#!/system/bin/sh
# touchfix: parche para el touch ILITEK (ILI9883) con pantalla de repuesto en lamu.
#
# Al apagar la pantalla, el driver del panel BOE corta la energía y el touch pierde
# su firmware (vive en RAM). Al encender, el driver solo lo recupera si llega una
# interrupción a tiempo ("FW upgrade pass" ~160 ms después de "Sleep Mode = 2").
# Si no llega, el touch queda muerto. Este script detecta ese caso en el log del
# kernel y vuelve a apagar/encender la pantalla hasta que la recuperación ocurra.

ESPERA=0.8      # segundos a esperar la recuperación tras encender
MAX=5           # reintentos seguidos como máximo
DIR=/data/local/tmp/touchfix
LOG=$DIR/touchfix.log

mkdir -p $DIR
rm -f $DIR/pendiente
echo 0 > $DIR/reintentos
log() { echo "$(date '+%F %T') $*" >> $LOG; }

revisar() {
  /system/bin/sleep $ESPERA
  [ -f $DIR/pendiente ] || return
  rm -f $DIR/pendiente
  n=$(cat $DIR/reintentos)
  if [ "$n" -ge $MAX ]; then
    log "touch sin recuperar tras $MAX reintentos, me rindo hasta el próximo encendido"
    echo 0 > $DIR/reintentos
    return
  fi
  echo $((n+1)) > $DIR/reintentos
  log "touch sin firmware tras encender, reintento $((n+1))"
  input keyevent 223
  sleep 1
  input keyevent 224
}

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
