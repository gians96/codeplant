#!/bin/bash
# =========================================================================
# set-hosts.sh - Agrega/actualiza las entradas hosts en una PC Linux/Mac
# =========================================================================
# Apunta el dominio base y los subdominios de empresas a la IP LAN del
# servidor pro-8, para acceder por nombre mientras no haya DNS publico.
#
# Uso:
#   sudo ./set-hosts.sh 192.168.1.100 fe.consurtrading.org empresa1 empresa2
#   sudo ./set-hosts.sh 192.168.1.100 fe.consurtrading.org   # solo base + ws
#
# Idempotente: reemplaza el bloque gestionado entre marcadores BEGIN/END.
# =========================================================================

set -e

SERVER_IP="$1"
BASE_DOMAIN="$2"
shift 2 || true
EMPRESAS=("$@")

if [ -z "$SERVER_IP" ] || [ -z "$BASE_DOMAIN" ]; then
    echo "Uso: sudo $0 <SERVER_IP> <BASE_DOMAIN> [empresa1 empresa2 ...]"
    echo "Ej:  sudo $0 192.168.1.100 fe.consurtrading.org empresa1 empresa2"
    exit 1
fi

HOSTS_FILE="/etc/hosts"
BEGIN="# >>> pro-8 ($BASE_DOMAIN) >>>"
END="# <<< pro-8 ($BASE_DOMAIN) <<<"

BLOCK="$BEGIN
$SERVER_IP    $BASE_DOMAIN
$SERVER_IP    ws.$BASE_DOMAIN"
for e in "${EMPRESAS[@]}"; do
    BLOCK="$BLOCK
$SERVER_IP    $e.$BASE_DOMAIN"
done
BLOCK="$BLOCK
$END"

# Quitar bloque previo (si existe) y anexar el nuevo
TMP="$(mktemp)"
awk -v b="$BEGIN" -v e="$END" '
    $0==b {skip=1}
    skip && $0==e {skip=0; next}
    !skip {print}
' "$HOSTS_FILE" > "$TMP"

printf '%s\n' "$BLOCK" >> "$TMP"
cat "$TMP" > "$HOSTS_FILE"
rm -f "$TMP"

echo "OK $HOSTS_FILE actualizado:"
printf '%s\n' "$BLOCK"
