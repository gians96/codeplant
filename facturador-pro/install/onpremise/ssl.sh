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
#   sudo ./ssl.sh --domain fe.consurtrading.org --repair-proxy
#   sudo ./ssl.sh --root /opt/proyectos
# =========================================================================

set -e

# La raiz es DONDE VIVE EL SCRIPT (no el directorio actual). Override: --root
ROOT="$(cd "$(dirname "$0")" && pwd)"
DOMAIN=""
EMAIL=""
REPAIR_PROXY="0"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --root)   ROOT="$2"; shift 2 ;;
        --domain) DOMAIN="$2"; shift 2 ;;
        --email)  EMAIL="$2";  shift 2 ;;
        --repair-proxy) REPAIR_PROXY="1"; shift ;;
        *) echo "Parametro desconocido: $1"; exit 1 ;;
    esac
done

# Si se ejecuta dentro de un proyecto (<dominio>/app), subir a la raiz.
if [ -f "$ROOT/docker-compose.yml" ] && [ -f "$ROOT/artisan" ]; then
    ROOT="$(cd "$ROOT/../.." && pwd)"
fi
CERTS_DIR="$ROOT/_infra/certs"
mkdir -p "$CERTS_DIR"

env_value() { grep -E "^$1=" "$2" 2>/dev/null | tail -1 | cut -d= -f2- | sed 's/^"//;s/"$//' || true; }
set_env_var() {
    local key="$1"; local value="$2"; local file="$3"
    if grep -q "^${key}=" "$file"; then sed -i "/^${key}=/c\\${key}=${value}" "$file"
    else echo "${key}=${value}" >> "$file"; fi
}

find_proxy() {
    local proxy

    proxy="$(docker ps --filter "ancestor=rash07/nginx-proxy:4.0" --format '{{.Names}}' | head -1)"
    [ -z "$proxy" ] && proxy="$(docker ps | grep -i proxy | awk '{print $NF}' | head -1)"
    echo "$proxy"
}

proxy_certs_dir() {
    local proxy="$1"
    local source

    [ -n "$proxy" ] || { echo "$CERTS_DIR"; return 0; }

    source="$(docker inspect "$proxy" --format '{{range .Mounts}}{{if eq .Destination "/etc/nginx/certs"}}{{.Source}}{{end}}{{end}}' 2>/dev/null || true)"
    if [ -n "$source" ]; then
        echo "$source"
    else
        echo "$CERTS_DIR"
    fi
}

copy_cert_files() {
    local target_dir="$1"

    mkdir -p "$target_dir"
    cp "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" "$target_dir/$DOMAIN.crt"
    cp "/etc/letsencrypt/live/$DOMAIN/privkey.pem"   "$target_dir/$DOMAIN.key"
    cp "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" "$target_dir/$SOKETI_HOST.crt"
    cp "/etc/letsencrypt/live/$DOMAIN/privkey.pem"   "$target_dir/$SOKETI_HOST.key"
}

ensure_proxy_env() {
    local compose_file="$PROJECT_DIR/docker-compose.yml"
    local result

    [ -f "$compose_file" ] || { echo "   ADVERTENCIA: no existe $compose_file"; return 1; }
    command -v python3 >/dev/null 2>&1 || { echo "   ADVERTENCIA: python3 no esta disponible; no se pudo reparar docker-compose.yml"; return 1; }

    echo "-> Verificando variables del proxy en docker-compose.yml ..."
    result="$(python3 - "$compose_file" "$DOMAIN" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
domain = sys.argv[2]
text = path.read_text()
lines = text.splitlines()

service_start = None
for i, line in enumerate(lines):
    if re.match(r"^    nginx_[0-9]+:\s*$", line):
        service_start = i
        break

if service_start is None:
    print("   ADVERTENCIA: no se encontro el servicio nginx_N.")
    print("CHANGED=0")
    sys.exit(0)

service_end = len(lines)
for i in range(service_start + 1, len(lines)):
    if re.match(r"^    [A-Za-z0-9_-]+:\s*$", lines[i]):
        service_end = i
        break

environment_index = None
for i in range(service_start + 1, service_end):
    if re.match(r"^        environment:\s*$", lines[i]):
        environment_index = i
        break

if environment_index is None:
    insert_at = service_start + 1
    for i in range(service_start + 1, service_end):
        if re.match(r"^        (container_name|working_dir):", lines[i]):
            insert_at = i + 1
    lines.insert(insert_at, "        environment:")
    environment_index = insert_at
    service_end += 1

environment_end = service_end
for i in range(environment_index + 1, service_end):
    if re.match(r"^        [A-Za-z0-9_-]+:", lines[i]):
        environment_end = i
        break

def clean(value: str) -> str:
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in ("'", '"'):
        return value[1:-1]
    return value

def read_env(key: str) -> str:
    for line in lines[environment_index + 1:environment_end]:
        match = re.match(rf"^            {re.escape(key)}:\s*(.*)$", line)
        if match:
            return clean(match.group(1))
        match = re.match(rf"^            - {re.escape(key)}=(.*)$", line)
        if match:
            return clean(match.group(1))
    return ""

hosts = [domain, f"*.{domain}"]
for raw_host in read_env("VIRTUAL_HOST").split(","):
    host = raw_host.strip()
    if not host or host in hosts:
        continue
    if host == f"*.{domain}" or host.endswith(f".{domain}"):
        continue
    hosts.append(host)

desired = {
    "VIRTUAL_HOST": ",".join(hosts),
    "VIRTUAL_PORT": "80",
    "VIRTUAL_PROTO": "http",
    "CERT_NAME": domain,
}

new_env_lines = []
for line in lines[environment_index + 1:environment_end]:
    is_managed = any(
        re.match(rf"^            ({re.escape(key)}:|- {re.escape(key)}=)", line)
        for key in desired
    )
    if not is_managed:
        new_env_lines.append(line)

managed_lines = [f'            {key}: "{value}"' for key, value in desired.items()]
lines[environment_index + 1:environment_end] = managed_lines + new_env_lines

new_text = "\n".join(lines) + ("\n" if text.endswith("\n") else "")
if new_text != text:
    path.write_text(new_text)
    print("   OK docker-compose.yml actualizado para HTTPS/proxy.")
    print("CHANGED=1")
else:
    print("   OK docker-compose.yml ya tenia la configuracion del proxy.")
    print("CHANGED=0")
PY
)" || { echo "   ADVERTENCIA: no se pudo reparar docker-compose.yml"; return 1; }

    echo "$result" | sed '/^CHANGED=/d'
    echo "$result" | grep -q '^CHANGED=1$'
}

restart_project_nginx() {
    local nginx_service
    nginx_service="$(grep -E '^[[:space:]]+nginx_[0-9]+:' "$PROJECT_DIR/docker-compose.yml" | head -1 | sed -E 's/^[[:space:]]+([^:]+):.*/\1/')"
    [ -n "$nginx_service" ] || { echo "   ADVERTENCIA: no se encontro servicio nginx_N para recrear."; return 0; }

    echo "-> Recreando $nginx_service para aplicar variables del proxy ..."
    ( cd "$PROJECT_DIR" && docker compose up -d --no-deps "$nginx_service" ) || \
        echo "   ADVERTENCIA: no se pudo recrear $nginx_service; revisa docker compose logs."
}

validate_local_proxy() {
    local output

    echo "-> Validando proxy local ..."
    if [ -n "${PROXY:-}" ]; then
        docker exec "$PROXY" nginx -t >/dev/null 2>&1 && \
            echo "   OK nginx -t dentro de $PROXY" || \
            echo "   ADVERTENCIA: nginx -t fallo dentro de $PROXY (revisa docker logs $PROXY)."

        docker exec "$PROXY" sh -c "test -s /etc/nginx/certs/$DOMAIN.crt && test -s /etc/nginx/certs/$DOMAIN.key" >/dev/null 2>&1 && \
            echo "   OK certificado visible dentro del proxy: /etc/nginx/certs/$DOMAIN.{crt,key}" || \
            echo "   ADVERTENCIA: el proxy no ve /etc/nginx/certs/$DOMAIN.{crt,key}; revisa el volumen de certificados."

        docker exec "$PROXY" sh -c "nginx -T 2>/dev/null | grep -q 'server_name .*${DOMAIN}'" >/dev/null 2>&1 && \
            echo "   OK nginx genero server_name para $DOMAIN" || \
            echo "   ADVERTENCIA: nginx no genero server_name para $DOMAIN; revisa VIRTUAL_HOST en el contenedor nginx del proyecto."
    fi

    if ! command -v curl >/dev/null 2>&1; then
        echo "   ADVERTENCIA: curl no esta instalado; omito prueba HTTPS local."
        return 0
    fi

    if output="$(curl -I --connect-timeout 5 --max-time 15 --resolve "$DOMAIN:80:127.0.0.1" "http://$DOMAIN" 2>&1)"; then
        echo "$output" | head -5
        echo "   OK HTTP local responde por 127.0.0.1:80"
    else
        echo "   ADVERTENCIA: HTTP local no respondio por 127.0.0.1:80"
        echo "$output" | head -20
        echo "   Si Cloudflare entra por HTTP, esto tambien puede producir 522."
    fi

    if output="$(curl -kI --connect-timeout 5 --max-time 15 --resolve "$DOMAIN:443:127.0.0.1" "https://$DOMAIN" 2>&1)"; then
        echo "$output" | head -5
        echo "   OK HTTPS local responde por 127.0.0.1:443"
    else
        echo "   ADVERTENCIA: HTTPS local no respondio por 127.0.0.1:443"
        echo "$output" | head -20
        echo "   Si esto falla aqui, Cloudflare mostrara 522 aunque DNS/SSL esten correctos."
    fi
}

# --- Elegir dominio ------------------------------------------------
if [ -z "$DOMAIN" ]; then
    PROJECTS=()
    for d in "$ROOT"/*/; do
        dom="$(basename "$d")"; case "$dom" in _*) continue ;; esac
        [ -f "${d}app/docker-compose.yml" ] && [ -f "${d}app/.env" ] && PROJECTS+=("$dom")
    done
    [ ${#PROJECTS[@]} -eq 0 ] && { echo "ERROR: no hay dominios instalados en $ROOT (usa --root o --domain)."; exit 1; }
    echo "Dominios instalados en $ROOT:"
    i=1; for p in "${PROJECTS[@]}"; do echo "  [$i] $p"; i=$((i+1)); done
    read -p "Numero del dominio (SSL emitir/renovar): " sel
    [[ "$sel" =~ ^[0-9]+$ ]] && [ "$sel" -ge 1 ] && [ "$sel" -le ${#PROJECTS[@]} ] || { echo "Seleccion invalida."; exit 1; }
    DOMAIN="${PROJECTS[$((sel-1))]}"
fi

PROJECT_DIR="$ROOT/$DOMAIN/app"
ENV_FILE="$PROJECT_DIR/.env"
SOKETI_HOST="ws.$DOMAIN"
LIVE_PEM="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"

# --- Detectar modo: emitir, renovar o reparar proxy ----------------
if [ "$REPAIR_PROXY" = "1" ]; then
    MODE="reparar-proxy"
    [ -f "$LIVE_PEM" ] || { echo "ERROR: no existe certificado en $LIVE_PEM. Primero emite SSL sin --repair-proxy."; exit 1; }
    [ -f "$ENV_FILE" ] || { echo "ERROR: no existe $ENV_FILE (el dominio no parece instalado)."; exit 1; }
elif [ -f "$LIVE_PEM" ]; then
    MODE="renovar"
else
    MODE="emitir"
    [ -f "$ENV_FILE" ] || { echo "ERROR: no existe $ENV_FILE (el dominio no parece instalado)."; exit 1; }
fi

if [ "$MODE" != "reparar-proxy" ]; then
    command -v certbot >/dev/null 2>&1 || { echo "-> Instalando certbot ..."; apt-get -y update && apt-get -y install certbot; }
fi

echo ""
echo "=================================================="
case "$MODE" in
    emitir) echo "  EMITIR WILDCARD SSL + ACTIVAR HTTPS" ;;
    renovar) echo "  RENOVAR WILDCARD SSL" ;;
    reparar-proxy) echo "  REPARAR PROXY HTTPS (SIN RENOVAR CERTIFICADO)" ;;
esac
echo "=================================================="
echo "  Dominio:  $DOMAIN  (+ *.$DOMAIN)"
echo "  Proyecto: $PROJECT_DIR"
echo "  Certs:    $CERTS_DIR"
echo "=================================================="
echo ""
if [ "$MODE" != "reparar-proxy" ]; then
    echo "REQUISITO UNICO para emitir/renovar (no hace falta IP publica ni NAT):"
    echo "  - Acceso al panel DNS del registrador para crear el TXT _acme-challenge.$DOMAIN"
    echo ""
else
    echo "Este modo NO pide TXT ni renueva Let's Encrypt; solo repara compose/proxy"
    echo "usando el certificado existente en /etc/letsencrypt/live/$DOMAIN."
    echo ""
fi
echo "Solo para ACCESO PUBLICO (lo configura el admin de red, puede ser despues):"
echo "  1. DNS registrador:  A $DOMAIN -> IP_PUBLICA   y   A *.$DOMAIN -> IP_PUBLICA"
echo "  2. FortiGate: VIP/NAT puertos 80 y 443 -> IP LAN del servidor."
echo "  3. LAN sigue resolviendo local (hosts o DNS FortiGate) = split-horizon."
echo ""
read -p "Continuar? [S/n]: " ok
[ "$ok" = "n" ] || [ "$ok" = "N" ] && { echo "Cancelado."; exit 0; }

echo ""
if [ "$MODE" != "reparar-proxy" ]; then
    echo "--- IMPORTANTE -----------------------------------"
    echo "Certbot mostrara uno o dos TXT _acme-challenge.$DOMAIN"
    echo "Crealos en el DNS del registrador y ESPERA la propagacion ANTES"
    echo "de presionar Enter (verifica: dig TXT _acme-challenge.$DOMAIN @8.8.8.8)."
    echo "NO uses Ctrl+C (cancela el proceso)."
    echo "--------------------------------------------------"
    echo ""
fi

EMAIL_ARG="--register-unsafely-without-email"
[ -n "$EMAIL" ] && EMAIL_ARG="-m $EMAIL"

RENEW_ARG=""
PEM_BEFORE="0"
if [ "$MODE" = "renovar" ]; then
    RENEW_ARG="--force-renewal"
    PEM_BEFORE="$(stat -c %Y "$LIVE_PEM" 2>/dev/null || echo 0)"
fi

if [ "$MODE" != "reparar-proxy" ]; then
    certbot certonly --manual --preferred-challenges dns-01 \
        -d "$DOMAIN" -d "*.$DOMAIN" \
        --agree-tos --no-eff-email $EMAIL_ARG $RENEW_ARG \
        --server https://acme-v02.api.letsencrypt.org/directory
fi

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

PROXY="$(find_proxy)"
PROXY_CERTS_DIR="$(proxy_certs_dir "$PROXY")"

echo "-> Copiando certificados a $CERTS_DIR ..."
copy_cert_files "$CERTS_DIR"

if [ "$PROXY_CERTS_DIR" != "$CERTS_DIR" ]; then
    echo "-> Copiando certificados al volumen real del proxy: $PROXY_CERTS_DIR ..."
    copy_cert_files "$PROXY_CERTS_DIR"
fi

COMPOSE_PROXY_CHANGED="0"
ensure_proxy_env && COMPOSE_PROXY_CHANGED="1"

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

# OPcache corre con validate_timestamps=0: los workers PHP siguen sirviendo
# la config VIEJA (http) aunque config:cache ya escribio la nueva. Hay que
# reiniciar fpm + scheduling + supervisor (workers de cola) para que tomen
# APP_URL https, FORCE_HTTPS y pusher 443.
N="${FPM#fpm_}"
echo "-> Reiniciando PHP y workers (fpm_$N, scheduling_$N, supervisor_$N) ..."
( cd "$PROJECT_DIR" && docker compose restart "fpm_$N" "scheduling_$N" "supervisor_$N" ) || \
    echo "   ADVERTENCIA: reinicia manualmente: docker compose restart fpm_$N scheduling_$N supervisor_$N"

[ "$COMPOSE_PROXY_CHANGED" = "1" ] && restart_project_nginx

echo "-> Reiniciando proxy ..."
[ -z "$PROXY" ] && PROXY="$(find_proxy)"
if [ -n "$PROXY" ]; then
    docker restart "$PROXY" && echo "   OK proxy reiniciado: $PROXY" || echo "   ADVERTENCIA: reinicia el proxy manualmente."
    sleep 3
else
    echo "   ADVERTENCIA: reinicia el proxy manualmente."
fi

validate_local_proxy

NEXT_RENEW="$(date -d '+75 days' '+%Y-%m-%d' 2>/dev/null || echo 'en ~75 dias')"
echo ""
echo "=================================================="
if [ "$MODE" = "emitir" ]; then
    echo "  OK SSL EMITIDO + HTTPS ACTIVADO - $DOMAIN"
    echo "=================================================="
    echo "  LAN:     https://$DOMAIN  (hosts/DNS FortiGate -> IP local)"
    echo "  Publico: https://$DOMAIN  (cuando el admin configure DNS + NAT)"
elif [ "$MODE" = "reparar-proxy" ]; then
    echo "  OK PROXY HTTPS REPARADO - $DOMAIN"
    echo "=================================================="
    echo "  Prueba local: curl -vkI --resolve $DOMAIN:443:127.0.0.1 https://$DOMAIN"
else
    echo "  OK SSL RENOVADO - $DOMAIN"
    echo "=================================================="
fi
echo "  Tenants: https://EMPRESA.$DOMAIN"
echo "  AGENDAR renovacion (mismo comando): $NEXT_RENEW"
echo "    sudo ./ssl.sh --domain $DOMAIN"
echo "=================================================="
