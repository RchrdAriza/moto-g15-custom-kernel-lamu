#!/system/bin/sh
# touchfix: parche para el touch ILITEK (ILI9883) con pantalla de repuesto en lamu.
#
# Al apagar la pantalla, el driver del panel BOE corta la energía y el touch pierde
# su firmware (vive en RAM). Al encender, el driver solo lo recupera si llega una
# interrupción a tiempo ("FW upgrade pass" ~160 ms después de "Sleep Mode = 2").
# Si no llega, el touch queda muerto. Este script detecta ese caso en el log del
# kernel y fuerza la recuperación:
#   1. Con el módulo ilitek_kick.ko: simula la interrupción (sin parpadeo).
#   2. Si no hay módulo o no funcionó: apaga y enciende la pantalla.

ESPERA=0.5      # segundos a esperar la recuperación tras encender
KICKS=2         # interrupciones simuladas antes de recurrir a apagar/encender
MAX=8           # reintentos seguidos como máximo
DIR=/data/local/tmp/touchfix
LOG=$DIR/touchfix.log
MODULO=$(dirname "$0")/ilitek_kick.ko
KICK=/sys/module/ilitek_kick/parameters/kick

mkdir -p $DIR
rm -f $DIR/pendiente
echo 0 > $DIR/reintentos
log() { echo "$(date '+%F %T') $*" >> $LOG; }

cargar_modulo() {
  [ -e $KICK ] && return 0
  [ -f "$MODULO" ] || return 1
  # La dirección de generic_handle_irq_safe solo es visible con kptr_restrict=0.
  k=$(cat /proc/sys/kernel/kptr_restrict)
  echo 0 > /proc/sys/kernel/kptr_restrict
  addr=$(awk '$3 == "generic_handle_irq_safe" { print $1; exit }' /proc/kallsyms)
  echo $k > /proc/sys/kernel/kptr_restrict
  [ -n "$addr" ] && [ "$addr" != 0000000000000000 ] || return 1
  insmod "$MODULO" handler=0x$addr
}

revisar() {
  /system/bin/sleep $ESPERA
  [ -f $DIR/pendiente ] || return
  n=$(cat $DIR/reintentos)
  if [ "$n" -ge $MAX ]; then
    rm -f $DIR/pendiente
    log "touch sin recuperar tras $MAX reintentos, me rindo hasta el próximo encendido"
    echo 0 > $DIR/reintentos
    return
  fi
  echo $((n+1)) > $DIR/reintentos
  irq=$(awk '/ilitek/ { sub(":", "", $1); print $1; exit }' /proc/interrupts)
  if [ $n -lt $KICKS ] && [ -e $KICK ] && [ -n "$irq" ]; then
    log "touch sin firmware tras encender, simulo interrupción (reintento $((n+1)))"
    echo $irq > $KICK
    revisar &
  else
    rm -f $DIR/pendiente
    log "touch sin firmware tras encender, apago y enciendo (reintento $((n+1)))"
    input keyevent 223
    /system/bin/sleep 1
    input keyevent 224
  fi
}

if cargar_modulo; then
  log "módulo ilitek_kick cargado"
else
  log "sin módulo ilitek_kick: solo apagar/encender"
fi

MARCA="touchfix: inicio $$"
log "iniciado (pid $$)"
echo "$MARCA" > /dev/kmsg
listo=0
# Rutas explícitas: bajo KernelSU/Magisk el script corre con BusyBox, cuyo
# dmesg no soporta -w.
/system/bin/dmesg -w | while read -r l; do
  # dmesg -w repite primero el buffer viejo: ignorarlo hasta ver nuestra marca
  if [ $listo = 0 ]; then
    case "$l" in *"$MARCA"*) listo=1 ;; esac
    continue
  fi
  case "$l" in
    *"ili_sleep_handler"*"Sleep Mode = 2"*)
      touch $DIR/pendiente
      revisar &
      ;;
    *"FW upgrade pass"*)
      rm -f $DIR/pendiente
      n=$(cat $DIR/reintentos)
      [ "$n" != 0 ] && log "touch recuperado tras $n reintento(s)"
      echo 0 > $DIR/reintentos
      ;;
  esac
done
