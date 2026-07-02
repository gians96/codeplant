#!/bin/bash
# updateSSL.sh - Renovar o reparar SSL/proxy en instalaciones Linux clasicas.
#
# Uso:
#   sudo ./updateSSL.sh nt-suite.pro
#   sudo ./updateSSL.sh nt-suite.pro --repair-proxy
#
# --repair-proxy no ejecuta certbot: reutiliza el certificado existente,
# repara docker-compose/nginx, reconstruye nginx y valida HTTP/HTTPS local.

set -e

DOMAIN="${1:-dominio}"
REPAIR_PROXY="0"

shift || true
while [[ $# -gt 0 ]]; do
    case "$1" in
        --repair-proxy) REPAIR_PROXY="1"; shift ;;
        *) echo "Parametro desconocido: $1"; exit 1 ;;
    esac
done

if [ "$DOMAIN" = "dominio" ] || [ -z "$DOMAIN" ]; then
    echo "No ha ingresado dominio. Ejemplo: sudo ./updateSSL.sh nt-suite.pro --repair-proxy"
    exit 1
fi

ROOT="$(pwd)"
PROJECT_DIR=""
if [ -f "$ROOT/docker-compose.yml" ] && [ -f "$ROOT/.env" ]; then
    PROJECT_DIR="$ROOT"
    ROOT="$(cd "$PROJECT_DIR/.." && pwd)"
elif [ -f "$ROOT/$DOMAIN/docker-compose.yml" ] && [ -f "$ROOT/$DOMAIN/.env" ]; then
    PROJECT_DIR="$ROOT/$DOMAIN"
elif [ -f "/var/$DOMAIN/docker-compose.yml" ] && [ -f "/var/$DOMAIN/.env" ]; then
    PROJECT_DIR="/var/$DOMAIN"
    ROOT="/var"
else
    echo "ERROR: no encuentro el proyecto para $DOMAIN."
    echo "Ejecuta desde la raiz donde vive $DOMAIN/ o desde la carpeta del proyecto."
    exit 1
fi

SOKETI_HOST="ws.$DOMAIN"
LIVE_PEM="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
DEFAULT_CERTS_DIR="$ROOT/certs"

find_proxy() {
    local proxy
    proxy="$(docker ps --filter "ancestor=rash07/nginx-proxy:4.0" --format '{{.Names}}' | head -1)"
    [ -z "$proxy" ] && proxy="$(docker ps | grep -i proxy | awk '{print $NF}' | head -1)"
    echo "$proxy"
}

proxy_certs_dir() {
    local proxy="$1"
    local source

    [ -n "$proxy" ] || { echo "$DEFAULT_CERTS_DIR"; return 0; }
    source="$(docker inspect "$proxy" --format '{{range .Mounts}}{{if eq .Destination "/etc/nginx/certs"}}{{.Source}}{{end}}{{end}}' 2>/dev/null || true)"
    [ -n "$source" ] && echo "$source" || echo "$DEFAULT_CERTS_DIR"
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

    command -v python3 >/dev/null 2>&1 || { echo "   ADVERTENCIA: python3 no disponible; no se pudo reparar compose."; return 1; }
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
    print("   ADVERTENCIA: no se encontro servicio nginx_N.")
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

hosts = [domain, f"www.{domain}", f"*.{domain}"]
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
    print("   OK docker-compose.yml actualizado.")
    print("CHANGED=1")
else:
    print("   OK docker-compose.yml ya estaba correcto.")
    print("CHANGED=0")
PY
)" || { echo "   ADVERTENCIA: no se pudo reparar compose."; return 1; }

    echo "$result" | sed '/^CHANGED=/d'
    echo "$result" | grep -q '^CHANGED=1$'
}

nginx_default_file() {
    local default_path

    default_path="$(python3 - "$PROJECT_DIR/docker-compose.yml" "$PROJECT_DIR" <<'PY'
import re
import sys
from pathlib import Path

compose = Path(sys.argv[1])
project = Path(sys.argv[2])
lines = compose.read_text().splitlines()
service_start = None
for i, line in enumerate(lines):
    if re.match(r"^    nginx_[0-9]+:\s*$", line):
        service_start = i
        break
if service_start is None:
    sys.exit(0)
service_end = len(lines)
for i in range(service_start + 1, len(lines)):
    if re.match(r"^    [A-Za-z0-9_-]+:\s*$", lines[i]):
        service_end = i
        break
context = ""
for i in range(service_start + 1, service_end):
    m = re.match(r"^            context:\s*(.*)$", lines[i])
    if m:
        context = m.group(1).strip().strip('"').strip("'")
        break
if context:
    path = Path(context)
    if not path.is_absolute():
        path = project / path
    print(path / "default")
PY
)"

    if [ -n "$default_path" ] && [ -f "$default_path" ]; then
        echo "$default_path"
    elif [ -f "$ROOT/proxy/fpms/$DOMAIN/default" ]; then
        echo "$ROOT/proxy/fpms/$DOMAIN/default"
    elif [ -f "$PROJECT_DIR/docker/nginx/default" ]; then
        echo "$PROJECT_DIR/docker/nginx/default"
    else
        echo ""
    fi
}

ensure_www_redirect() {
    local nginx_file
    local result
    nginx_file="$(nginx_default_file)"

    [ -n "$nginx_file" ] || { echo "   ADVERTENCIA: no encontre nginx default para reparar www."; return 1; }
    echo "-> Verificando redirect www.$DOMAIN -> $DOMAIN ..."

    result="$(python3 - "$nginx_file" "$DOMAIN" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
domain = sys.argv[2]
text = path.read_text()
block = f'''    set $redirect_scheme $http_x_forwarded_proto;
    if ($redirect_scheme = "") {{ set $redirect_scheme $scheme; }}
    if ($host = "www.{domain}") {{
        return 301 $redirect_scheme://{domain}$request_uri;
    }}
'''

if f'www.{domain}' in text and f'{domain}$request_uri' in text:
    print("   OK redirect www ya existe.")
    print("CHANGED=0")
    sys.exit(0)

marker = "    server_tokens off;\n"
if marker not in text:
    print("   ADVERTENCIA: no se encontro server_tokens off; en nginx default.")
    print("CHANGED=0")
    sys.exit(0)

path.write_text(text.replace(marker, marker + block, 1))
print("   OK nginx default actualizado con redirect www.")
print("CHANGED=1")
PY
)" || { echo "   ADVERTENCIA: no se pudo reparar nginx default."; return 1; }

    echo "$result" | sed '/^CHANGED=/d'
    echo "$result" | grep -q '^CHANGED=1$'
}

restart_nginx_service() {
    local nginx_service
    nginx_service="$(grep -E '^[[:space:]]+nginx_[0-9]+:' "$PROJECT_DIR/docker-compose.yml" | head -1 | sed -E 's/^[[:space:]]+([^:]+):.*/\1/')"
    [ -n "$nginx_service" ] || { echo "   ADVERTENCIA: no se encontro servicio nginx_N."; return 0; }

    echo "-> Reconstruyendo/recreando $nginx_service ..."
    ( cd "$PROJECT_DIR" && docker compose up -d --build --no-deps "$nginx_service" ) || \
        echo "   ADVERTENCIA: no se pudo reconstruir $nginx_service."
}

validate_local_proxy() {
    local proxy="$1"
    local output

    echo "-> Validando proxy local ..."
    if [ -n "$proxy" ]; then
        docker exec "$proxy" nginx -t >/dev/null 2>&1 && echo "   OK nginx -t dentro de $proxy" || echo "   ADVERTENCIA: nginx -t fallo."
        docker exec "$proxy" sh -c "test -s /etc/nginx/certs/$DOMAIN.crt && test -s /etc/nginx/certs/$DOMAIN.key" >/dev/null 2>&1 && \
            echo "   OK certificado visible dentro del proxy" || \
            echo "   ADVERTENCIA: el proxy no ve el certificado $DOMAIN."
        docker exec "$proxy" sh -c "nginx -T 2>/dev/null | grep -q 'server_name .*${DOMAIN}'" >/dev/null 2>&1 && \
            echo "   OK nginx genero server_name para $DOMAIN" || \
            echo "   ADVERTENCIA: nginx no genero server_name para $DOMAIN."
    fi

    if output="$(curl -I --connect-timeout 5 --max-time 15 --resolve "$DOMAIN:80:127.0.0.1" "http://$DOMAIN" 2>&1)"; then
        echo "$output" | head -5
        echo "   OK HTTP local responde por 127.0.0.1:80"
    else
        echo "   ADVERTENCIA: HTTP local no respondio"
        echo "$output" | head -20
    fi

    if output="$(curl -kI --connect-timeout 5 --max-time 15 --resolve "$DOMAIN:443:127.0.0.1" "https://$DOMAIN" 2>&1)"; then
        echo "$output" | head -5
        echo "   OK HTTPS local responde por 127.0.0.1:443"
    else
        echo "   ADVERTENCIA: HTTPS local no respondio"
        echo "$output" | head -20
    fi
}

echo ""
echo "=================================================="
if [ "$REPAIR_PROXY" = "1" ]; then
    echo "  REPARAR PROXY SSL LINUX (SIN RENOVAR CERT)"
else
    echo "  RENOVAR SSL LINUX + REPARAR PROXY"
fi
echo "=================================================="
echo "  Dominio:  $DOMAIN (+ *.$DOMAIN)"
echo "  Proyecto: $PROJECT_DIR"
echo "=================================================="
echo ""

if [ "$REPAIR_PROXY" != "1" ]; then
    certbot certonly --manual -d "*.$DOMAIN" -d "$DOMAIN" \
        --agree-tos --no-bootstrap --manual-public-ip-logging-ok \
        --preferred-challenges dns-01 \
        --server https://acme-v02.api.letsencrypt.org/directory
fi

[ -f "$LIVE_PEM" ] || { echo "ERROR: no existe $LIVE_PEM. Primero emite el certificado."; exit 1; }

PROXY="$(find_proxy)"
PROXY_CERTS_DIR="$(proxy_certs_dir "$PROXY")"

echo "-> Copiando certificados a $DEFAULT_CERTS_DIR ..."
copy_cert_files "$DEFAULT_CERTS_DIR"

if [ "$PROXY_CERTS_DIR" != "$DEFAULT_CERTS_DIR" ]; then
    echo "-> Copiando certificados al volumen real del proxy: $PROXY_CERTS_DIR ..."
    copy_cert_files "$PROXY_CERTS_DIR"
fi

COMPOSE_CHANGED="0"
ensure_proxy_env && COMPOSE_CHANGED="1"
NGINX_CHANGED="0"
ensure_www_redirect && NGINX_CHANGED="1"

if [ "$COMPOSE_CHANGED" = "1" ] || [ "$NGINX_CHANGED" = "1" ]; then
    restart_nginx_service
fi

echo "-> Reiniciando proxy ..."
[ -z "$PROXY" ] && PROXY="$(find_proxy)"
if [ -n "$PROXY" ]; then
    docker restart "$PROXY" && echo "   OK proxy reiniciado: $PROXY"
    sleep 3
else
    echo "   ADVERTENCIA: no se encontro proxy."
fi

validate_local_proxy "$PROXY"

echo ""
echo "=================================================="
echo "  OK SSL/PROXY LINUX - $DOMAIN"
echo "=================================================="
echo "  Prueba directa:"
echo "    curl -vkI --resolve $DOMAIN:443:127.0.0.1 https://$DOMAIN"
echo "=================================================="
