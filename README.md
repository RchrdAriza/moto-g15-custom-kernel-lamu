# Moto G15 (lamu) — Custom Kernel para DroidSpaces

Custom kernel (GKI) para el **Motorola Moto G15** (`lamu`, MediaTek, kernel tree `kernel-6.6`) que habilita las funciones de **DroidSpaces** en Android: **chroot nativo**, **Docker nativo**, mejor rendimiento, etc.

Basado en LineageOS 23.2 (`android_kernel_motorola_lamu_manifest`, rama `lineage-23.2`) y compilado con la toolchain oficial de Android (Clang/Bazel Kleaf).

## Releases

| Release | Archivo | Descripción |
|---|---|---|
| v1.0 | `boot-lamu-custom.img` (descargable desde la pestaña **Releases** de GitHub) | Boot image flasheable (header v4, GKI) con el kernel custom |

### Características del kernel (GKI-Exclusive de la doc de Droidspaces)

Alternativas habilitadas en `gki_defconfig`:

- `CONFIG_SYSVIPC=y`
- `CONFIG_POSIX_MQUEUE=y`
- `CONFIG_IPC_NS=y`
- `CONFIG_PID_NS=y`
- `CONFIG_DEVTMPFS=y`
- `CONFIG_NETFILTER_XT_MATCH_ADDRTYPE=y`

Opciones de Docker Swarm (`VXLAN`, `IP_VS`, `IP_VS_RR`, `BRIDGE_NETFILTER`) **revertidas**: no presentes en la doc de Droidspaces y arriesgan kABI.

> **Nota kABI:** en kernels < 6.12, habilitar `CONFIG_SYSVIPC`/`CONFIG_IPC_NS` desplaza offsets de `task_struct` y puede bootlooper si se rompe la kABI. Por eso se aplica el parche oficial `001.GKI-below-6.12-fix_sysvipc_kabi_6_7_8.patch` (ver notebook).

## Version del kernel compilado

```
Linux version 6.6.127-android15-8-g98e7be363fe2-dirty-4k
#1 SMP PREEMPT Fri Aug  7 01:33:44 UTC 2026
```

El hash `98e7be363` identifica de forma única la config de este build (se puede verificar después de flashear vía `uname`/pstore).

## Capturas

Kernel custom visible en Configuración del dispositivo:

<img src="Screenshot_20260731-123844_Configuración.png" alt="Configuración del sistema con el kernel custom" width="340">

Requisitos de DroidSpaces verificados, todos en verde:

<img src="Screenshot_20260815-004328_Droidspaces.png" alt="Requisitos de DroidSpaces todos en verde" width="340">

Contenedores de Droidspaces corriendo:

<img src="Screenshot_20260815-004850_Droidspaces.png" alt="Contenedores de Droidspaces corriendo" width="340">

## Instalación

### Requisitos
- Bootloader desbloqueado.
- LineageOS 23.2 (o ROM compatible con GKI de este dispositivo) instalada.
- `fastboot` en la PC.

### Flashear

```bash
# Opción A: recovery/instalador (añadir a una ROM zip)
# Opción B: fastboot (necesarias particiones boot)
fastboot flash boot boot-lamu-custom.img
fastboot reboot
```

> Solo reemplaza la imagen `boot`. El ramdisk real vive en `vendor_boot.img` (ramdisk size 0, normal en GKI de este dispositivo).

## Compilar desde cero

1. Sincronizar el árbol:
   ```bash
   mkdir -p ~/lamu-kernel && cd ~/lamu-kernel
   yes | repo init -u https://github.com/moto-mediatek-devs/android_kernel_motorola_lamu_manifest -b lineage-23.2 --depth=1
   repo sync -c -j24 --force-sync --no-clone-bundle --optimized-fetch
   ```
2. Aplicar el parche kABI (`001.GKI-below-6.12-fix_sysvipc_kabi_6_7_8.patch`) en `kernel-6.6`.
3. Aplicar los cambios de `gki_defconfig` (ver notebook `kernel_droidspaces_lamu_clear.ipynb`).
4. Compilar:
   ```bash
   ./build_mgk_64_k66.sh
   ```
5. Empaquetar boot.img con las herramientas de mkbootimg:
   - Descargar el boot.img stock de LineageOS (`boot.img`, 64 MB).
   - `unpack_bootimg.py` → sustituir `kernel` por `out/mgk_64_k66/dist/Image.gz`.
   - `mkbootimg.py --header_version 4` + `avbtool add_hash_footer --partition_name boot --algorithm NONE`.
6. Verificar que los hashes del kernel dentro del boot.img coincidan con los del build (`sha1sum verify/kernel out/mgk_64_k66/dist/Image.gz`).

El paso a paso completo está documentado en [`kernel_droidspaces_lamu_clear.ipynb`](kernel_droidspaces_lamu_clear.ipynb).

## Advertencia

- Flashear un kernel custom puede romper la kABI de tu ROM si no es compatible. Usa este build con LineageOS 23.2 para `lamu`.
- Esto es un proyecto de desarrollo; úsalo bajo tu propio riesgo.