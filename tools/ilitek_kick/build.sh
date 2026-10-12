#!/usr/bin/env bash
# Compila ilitek_kick.ko para el kernel que corre en el teléfono conectado por adb
# (requiere root vía KernelSU/Magisk con permiso para "Shell").
#
# Toma del teléfono la versión exacta del kernel, su config (/proc/config.gz) y el
# CRC de module_layout (de tp_ilitek.ko), y baja solo la parte del árbol del
# kernel necesaria para compilar un módulo externo.
#
# Uso: tools/ilitek_kick/build.sh [directorio de trabajo]   (por defecto ~/.cache/lamu-kmod)
set -euo pipefail

MOD_DIR=$(cd "$(dirname "$0")" && pwd)
WORK=${1:-$HOME/.cache/lamu-kmod}
SRC=$WORK/src
mkdir -p "$WORK"

phone() { adb shell su <<<"$1" | tr -d '\r'; }
phone_raw() { adb exec-out su -c "$1"; }   # binarios: sin tocar los bytes

RELEASE=$(phone 'uname -r')
# El hash del commit va en la versión: 6.6.127-android15-8-g<hash>-...
COMMIT=$(sed -E 's/.*-g([0-9a-f]{12}).*/\1/' <<<"$RELEASE")
echo "kernel: $RELEASE (commit $COMMIT)"

if [ "$(git -C "$SRC" rev-parse --short=12 HEAD 2>/dev/null)" != "$COMMIT" ]; then
  rm -rf "$SRC"
  git init -q "$SRC"
  git -C "$SRC" sparse-checkout init --no-cone
  cat > "$SRC/.git/info/sparse-checkout" <<'EOF'
/*
!/*/
/scripts/
/include/
/arch/arm64/
/arch/arm/vdso/
/arch/arm/include/
/arch/x86/entry/syscalls/
/arch/x86/include/
/kernel/
/certs/
/usr/
/lib/
/security/
/tools/
**/Kconfig*
**/Makefile*
**/Kbuild*
EOF
  FULL=$(curl -s "https://android.googlesource.com/kernel/common/+/$COMMIT?format=JSON" |
         tail -n +2 | python3 -c 'import json,sys; print(json.load(sys.stdin)["commit"])')
  git -C "$SRC" fetch -q --depth 1 --filter=blob:none https://android.googlesource.com/kernel/common "$FULL"
  git -C "$SRC" checkout -q FETCH_HEAD
fi

phone_raw 'cat /proc/config.gz' > "$WORK/config.gz"
zcat "$WORK/config.gz" > "$SRC/.config"

# Con MODVERSIONS todo módulo lleva el CRC de module_layout; se toma de un
# módulo del propio teléfono (sección __versions: 8 bytes de CRC + 56 de nombre).
phone_raw 'cat /vendor_dlkm/lib/modules/tp_ilitek.ko' > "$WORK/tp_ilitek.ko"
llvm-objcopy -O binary --only-section=__versions "$WORK/tp_ilitek.ko" "$WORK/versions.bin"
CRC=$(python3 -I - "$WORK/versions.bin" <<'EOF'
import struct, sys
d = open(sys.argv[1], "rb").read()
for i in range(0, len(d), 64):
    if d[i+8:i+64].split(b"\0")[0] == b"module_layout":
        print(hex(struct.unpack_from("<Q", d, i)[0]))
EOF
)
printf '%s\tmodule_layout\tvmlinux\tEXPORT_SYMBOL\t\n' "$CRC" > "$WORK/vmlinux.symvers"
echo "module_layout: $CRC"

# CONFIG_DEBUG_INFO_BTF* se anulan solo en la línea de make (no en .config, que
# cambiaría struct module): evitan compilar resolve_btfids, que no hace falta
# para un módulo externo y no compila con clang moderno.
MAKE=(make -C "$SRC" ARCH=arm64 LLVM=1 KERNELRELEASE="$RELEASE"
      CONFIG_DEBUG_INFO_BTF= CONFIG_DEBUG_INFO_BTF_MODULES=)
"${MAKE[@]}" olddefconfig >/dev/null
"${MAKE[@]}" -j"$(nproc)" modules_prepare >/dev/null
"${MAKE[@]}" M="$MOD_DIR" KBUILD_EXTRA_SYMBOLS="$WORK/vmlinux.symvers" modules

# Debe coincidir con los módulos del teléfono o el kernel lo rechaza.
size() { llvm-readelf -S -W "$1" | awk '/gnu.linkonce.this_module/ {print $6}'; }
[ "$(size "$MOD_DIR/ilitek_kick.ko")" = "$(size "$WORK/tp_ilitek.ko")" ] ||
  { echo "ERROR: struct module no coincide con el kernel del teléfono"; exit 1; }
echo "listo: $MOD_DIR/ilitek_kick.ko"
