#!/bin/bash
# =========================================================================
# ssl.sh - Instalar o renovar el wildcard SSL de un dominio (multi-dominio)
# =========================================================================
# UN solo script para todo el ciclo SSL. Detecta automaticamente el modo:
#   - Si el dominio NO tiene certificado -> lo EMITE (Let's Encrypt DNS-01
#     manual) y activa HTTPS en el .env del proyecto (FORCE_HTTPS, pusher 443).
#   - Si el dominio YA tiene certificado -> lo RENUEVA (--force-renewal).
#
# IMPORTANTE: emitir/renovar NO requiere IP publica ni NAT del FortiGate.
# El reto DNS-01 solo pide crear un TXT _acme-challenge en el DNS PUBLICO del
# registrador. El mismo cert wildcard sirve para la LAN (hosts / DNS FortiGate)
# y para el acceso publico cuando el FortiGate este configurado.
#
# Como el DNS del registrador no tiene API, el proceso es MANUAL cada ~90 dias
# (certbot pide crear/recrear el TXT y esperar propagacion).
#
# Uso (desde la carpeta raiz, ej. /opt/proyectos):
#   sudo ./ssl.sh
#   sudo ./ssl.sh --domain fe.consurtrading.org
#   sudo ./ssl.sh --domain fe.consurtrading.org --email admin@consurtrading.org
#   sudo ./ssl.sh --root /opt/proyectos
# =========================================================================

set -e

ROOT="$(pwd)"
DOMAIN=""
EMAIL=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --root)   ROOT="$2"; shift 2 ;;
        --domain) DOMAIN="$2"; shift 2 ;;
        --email)  EMAIL="$2";  shift 2 ;;
        *) echo "Parametro desconocido: $1"; exit 1 ;;
    esac
done

# Si se ejecuta dentro de un proyecto, subir a la raiz para listar
if [ -f "$ROOT/docker-compose.yml" ] && [ -f "$ROOT/artisan" ]; then
    ROOT="$(dirname "$ROOT")"
fi
CERTS_DIR="$ROOT/certs"
mkdir -p "$CERTS_DIR"

env_value() { grep -E "^$1=" "$2" 2>/dev/null | tail -1 | cut -d= -f2- | sed 's/^"//;s/"$//' || true; }
set_env_var() {
    local key="$1"; local value="$2"; local file="$3"
    if grep -q "^${key}=" "$file"; then sed -i "/^${key}=/c\\${key}=${value}" "$file"
    else echo "${key}=${value}" >> "$file"; fi
}

# --- Elegir dominio ------------------------------------------------
if [ -z "$DOMAIN" ]; then
    PROJECTS=()
    for d in "$ROOT"/*/; do
        dom="$(basename "$d")"; [ "$dom" = "proxy" ] && continue
        [ -f "${d}docker-compose.yml" ] && [ -f "${d}.env" ] && PROJECTS+=("$dom")
    done
    [ ${#PROJECTS[@]} -eq 0 ] && { echo "ERROR: no hay dominios instalados en $ROOT (usa --root o --domain)."; exit 1; }
    echo "Dominios instalados en $ROOT:"
    i=1; for p in "${PROJECTS[@]}"; do echo "  [$i] $p"; i=$((i+1)); done
    read -p "Numero del dominio (SSL emitir/renovar): " sel
    [[ "$sel" =~ ^[0-9]+$ ]] && [ "$sel" -ge 1 ] && [ "$sel" -le ${#PROJECTS[@]} ] || { echo "Seleccion invalida."; exit 1; }
    DOMAIN="${PROJECTS[$((sel-1))]}"
fi

PROJECT_DIR="$ROOT/$DOMAIN"
ENV_FILE="$PROJECT_DIR/.env"
SOKETI_HOST="ws.$DOMAIN"
LIVE_PEM="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"

# --- Detectar modo: emitir o renovar -------------------------------
if [ -f "$LIVE_PEM" ]; then
    MODE="renovar"
else
    MODE="emitir"
    [ -f "$ENV_FILE" ] || { echo "ERROR: no existe $ENV_FILE (el dominio no parece instalado)."; exit 1; }
fi

command -v certbot >/dev/null 2>&1 || { echo "-> Instalando certbot ..."; apt-get -y update && apt-get -y install certbot; }

echo ""
echo "=================================================="
if [ "$MODE" = "emitir" ]; then
    echo "  EMITIR WILDCARD SSL + ACTIVAR HTTPS"
else
    echo "  RENOVAR WILDCARD SSL"
fi
echo "=================================================="
echo "  Dominio:  $DOMAIN  (+ *.$DOMAIN)"
echo "  Proyecto: $PROJECT_DIR"
echo "  Certs:    $CERTS_DIR"
echo "=================================================="
echo ""
echo "REQUISITO UNICO para emitir/renovar (no hace falta IP publica ni NAT):"
echo "  - Acceso al panel DNS del registrador para crear el TXT _acme-challenge.$DOMAIN"
echo ""
echo "Solo para ACCESO PUBLICO (lo configura el admin de red, puede ser despues):"
echo "  1. DNS registrador:  A $DOMAIN -> IP_PUBLICA   y   A *.$DOMAIN -> IP_PUBLICA"
echo "  2. FortiGate: VIP/NAT puertos 80 y 443 -> IP LAN del servidor."
echo "  3. LAN sigue resolviendo local (hosts o DNS FortiGate) = split-horizon."
echo ""
read -p "Continuar? [S/n]: " ok
[ "$ok" = "n" ] || [ "$ok" = "N" ] && { echo "Cancelado."; exit 0; }

echo ""
echo "--- IMPORTANTE -----------------------------------"
echo "Certbot mostrara uno o dos TXT _acme-challenge.$DOMAIN"
echo "Crealos en el DNS del registrador y ESPERA la propagacion ANTES"
echo "de presionar Enter (verifica: dig TXT _acme-challenge.$DOMAIN @8.8.8.8)."
echo "NO uses Ctrl+C (cancela el proceso)."
echo "--------------------------------------------------"
echo ""

EMAIL_ARG="--register-unsafely-without-email"
[ -n "$EMAIL" ] && EMAIL_ARG="-m $EMAIL"

RENEW_ARG=""
PEM_BEFORE="0"
if [ "$MODE" = "renovar" ]; then
    RENEW_ARG="--force-renewal"
    PEM_BEFORE="$(stat -c %Y "$LIVE_PEM" 2>/dev/null || echo 0)"
fi

certbot certonly --manual --preferred-challenges dns-01 \
    -d "$DOMAIN" -d "*.$DOMAIN" \
    --agree-tos --no-eff-email $EMAIL_ARG $RENEW_ARG \
    --server https://acme-v02.api.letsencrypt.org/directory

if [ ! -f "$LIVE_PEM" ]; then
    echo "ERROR: no se genero el certificado para $DOMAIN. Revisa el reto DNS y reintenta."
    exit 1
fi
if [ "$MODE" = "renovar" ]; then
    PEM_AFTER="$(stat -c %Y "$LIVE_PEM" 2>/dev/null || echo 0)"
    if [ "$PEM_AFTER" = "$PEM_BEFORE" ]; then
        echo "ERROR: el certificado no cambio (la renovacion no se completo). Revisa el reto DNS y reintenta."
        exit 1
    fi
fi

echo "-> Copiando certificados a $CERTS_DIR ..."
cp "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" "$CERTS_DIR/$DOMAIN.crt"
cp "/etc/letsencrypt/live/$DOMAIN/privkey.pem"   "$CERTS_DIR/$DOMAIN.key"
cp "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" "$CERTS_DIR/$SOKETI_HOST.crt"
cp "/etc/letsencrypt/live/$DOMAIN/privkey.pem"   "$CERTS_DIR/$SOKETI_HOST.key"

if [ "$MODE" = "emitir" ]; then
    echo "-> Cambiando .env a HTTPS ..."
    sed -i '/^APP_URL=/c\APP_URL=https://${APP_URL_BASE}' "$ENV_FILE"
    set_env_var "FORCE_HTTPS" "true" "$ENV_FILE"
    set_env_var "PUSHER_CLIENT_HOST" "$SOKETI_HOST" "$ENV_FILE"
    set_env_var "PUSHER_CLIENT_PORT" "443" "$ENV_FILE"
    set_env_var "PUSHER_CLIENT_SCHEME" "https" "$ENV_FILE"

    FPM="$(grep -E '^[[:space:]]+fpm_[0-9]+:' "$PROJECT_DIR/docker-compose.yml" | head -1 | sed -E 's/^[[:space:]]+([^:]+):.*/\1/')"
    FPM="${FPM:-fpm_1}"
    echo "-> Recacheando config ($FPM) ..."
    ( cd "$PROJECT_DIR" && docker compose exec -T "$FPM" sh -c "CACHE_DRIVER=file php artisan config:cache" ) || true
    ( cd "$PROJECT_DIR" && docker compose exec -T "$FPM" sh -c "CACHE_DRIVER=file php artisan cache:clear" ) || true
fi

echo "-> Reiniciando proxy ..."
PROXY="$(docker ps --filter "ancestor=rash07/nginx-proxy:4.0" --format '{{.Names}}' | head -1)"
[ -z "$PROXY" ] && PROXY="$(docker ps | grep -i proxy | awk '{print $NF}' | head -1)"
[ -n "$PROXY" ] && docker restart "$PROXY" && echo "   OK proxy reiniciado: $PROXY" || echo "   ADVERTENCIA: reinicia el proxy manualmente."

NEXT_RENEW="$(date -d '+75 days' '+%Y-%m-%d' 2>/dev/null || echo 'en ~75 dias')"
echo ""
echo "=================================================="
if [ "$MODE" = "emitir" ]; then
    echo "  OK SSL EMITIDO + HTTPS ACTIVADO - $DOMAIN"
    echo "=================================================="
    echo "  LAN:     https://$DOMAIN  (hosts/DNS FortiGate -> IP local)"
    echo "  Publico: https://$DOMAIN  (cuando el admin configure DNS + NAT)"
else
    echo "  OK SSL RENOVADO - $DOMAIN"
    echo "=================================================="
fi
echo "  Tenants: https://EMPRESA.$DOMAIN"
echo "  AGENDAR renovacion (mismo comando): $NEXT_RENEW"
echo "    sudo ./ssl.sh --domain $DOMAIN"
echo "=================================================="
