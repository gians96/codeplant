#!/bin/bash
# =========================================================================
# install.sh - Instalacion ON-PREMISE multi-dominio de Facturador Pro-8
# =========================================================================
# Despliega Pro-8 multi-tenant en un servidor LOCAL (VMware ESXi / bare-metal).
# Funciona HOY por LAN (IP + archivos hosts, HTTP) y luego se activa el acceso
# publico con SSL via ssl.sh, SIN migrar base de datos.
#
# REUTILIZABLE: se puede ejecutar varias veces para instalar VARIOS dominios
# en el mismo servidor sin que choquen entre si:
#   - Cada proyecto vive en su propia carpeta  $ROOT/<dominio>
#   - Contenedores nombrados por dominio:  nginx_<dom>, fpm_<dom>, mariadb_<dom>...
#   - Puerto MySQL del host asignado automaticamente a uno libre
#   - Proxy nginx (80/443) y red proxynet COMPARTIDOS por todos los dominios
#   - Misma IP publica sirve para todos (el proxy enruta por VIRTUAL_HOST)
#
# Uso:
#   mkdir -p /opt/proyectos && cd /opt/proyectos
#   curl -O https://raw.githubusercontent.com/gians96/codeplant/master/facturador-pro/install/onpremise/install.sh
#   chmod +x install.sh
#   sudo ./install.sh
# =========================================================================

set -e

REPO_URL="${REPO_URL:-https://gitlab.com/gians96/pro-8.git}"
DEFAULT_BRANCH="${DEFAULT_BRANCH:-master}"
PATH_INSTALL="$(pwd)"

# --- Helpers de puertos -------------------------------------------
find_free_mysql_port() {
    local start_port=${1:-3001}
    local port
    for port in $(seq "$start_port" 3999); do
        if ! ss -tuln 2>/dev/null | grep -q ":$port " && ! docker ps -a --format '{{.Ports}}' | grep -q "$port->3306"; then
            echo "$port"; return 0
        fi
    done
    return 1
}

port_busy() {
    local p="$1"
    ss -tuln 2>/dev/null | grep -q ":$p " || docker ps -a --format '{{.Ports}}' | grep -q "$p->3306"
}

# --- Listar instalaciones existentes ------------------------------
list_installed() {
    local found=0
    echo "=== Dominios ya instalados en $PATH_INSTALL ==="
    for d in "$PATH_INSTALL"/*/; do
        [ -f "${d}docker-compose.yml" ] && [ -f "${d}.env" ] || continue
        local dom; dom="$(basename "$d")"
        [ "$dom" = "proxy" ] && continue
        local port; port="$(grep -E '^MYSQL_PORT_HOST=' "${d}.env" 2>/dev/null | cut -d= -f2)"
        printf "  - %-30s (MySQL host: %s)\n" "$dom" "${port:-?}"
        found=1
    done
    [ "$found" = "0" ] && echo "  (ninguno todavia)"
    echo "==============================================="
}

echo ""
echo "=================================================="
echo "  FACTURADOR PRO-8 - Instalacion ON-PREMISE (LAN)"
echo "  Multi-dominio / reutilizable"
echo "=================================================="
echo ""
list_installed
echo ""

# --- 1. Dominio base (OBLIGATORIO, generico) ----------------------
read -p "Dominio base para esta instalacion (ej: fe.consurtrading.org): " BASE_DOMAIN
if [ -z "$BASE_DOMAIN" ]; then
    echo "ERROR: no ingresaste un dominio. Vuelve a ejecutar el script."
    exit 1
fi
if [[ "$BASE_DOMAIN" == ws.* ]]; then
    echo "ERROR: el dominio base no puede empezar con ws. (queda reservado para WebSocket)."
    exit 1
fi

DIR="$BASE_DOMAIN"
PROJECT_DIR="$PATH_INSTALL/$DIR"
if [ -f "$PROJECT_DIR/docker-compose.yml" ]; then
    echo "ADVERTENCIA: '$BASE_DOMAIN' ya parece instalado en $PROJECT_DIR."
    echo "  - Para actualizar CODIGO usa:  sudo ./update.sh"
    echo "  - Continuar aqui RE-GENERA compose/config REUSANDO los secretos del .env"
    echo "    existente (no borra datos, volumenes ni passwords)."
    read -p "  Continuar (re-generar config)? [s/N]: " cont
    [ "$cont" = "s" ] || [ "$cont" = "S" ] || { echo "Cancelado."; exit 0; }
fi

# --- 2. IP LAN del servidor (autodetectada) -----------------------
DETECTED_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
read -p "IP LAN del servidor [$DETECTED_IP]: " SERVER_IP
SERVER_IP="${SERVER_IP:-$DETECTED_IP}"
[ -z "$SERVER_IP" ] && { echo "ERROR: no se determino la IP del servidor."; exit 1; }

# --- 3. Numero de servicio (sugerido por # de instalados) ---------
EXISTING_COUNT="$(find "$PATH_INSTALL" -maxdepth 2 -name docker-compose.yml 2>/dev/null | grep -v "/proxy/" | wc -l | tr -d ' ')"
SUGGESTED_SN=$((EXISTING_COUNT + 1))
read -p "Numero de servicio [$SUGGESTED_SN]: " SERVICE_NUMBER
SERVICE_NUMBER="${SERVICE_NUMBER:-$SUGGESTED_SN}"

# --- 4. Puerto MySQL del host (libre, automatico) -----------------
SUGGESTED_PORT=$((3000 + SERVICE_NUMBER))
if port_busy "$SUGGESTED_PORT"; then
    echo "  Puerto $SUGGESTED_PORT ocupado, buscando libre ..."
    FREE_PORT="$(find_free_mysql_port "$SUGGESTED_PORT")" || { echo "ERROR: sin puertos MySQL libres 3001-3999"; exit 1; }
    MYSQL_PORT_HOST="$FREE_PORT"
else
    MYSQL_PORT_HOST="$SUGGESTED_PORT"
fi
read -p "Puerto MySQL para el host [$MYSQL_PORT_HOST]: " in_port
MYSQL_PORT_HOST="${in_port:-$MYSQL_PORT_HOST}"
if port_busy "$MYSQL_PORT_HOST"; then
    echo "ERROR: el puerto $MYSQL_PORT_HOST esta ocupado. Aborto."
    exit 1
fi

# --- 5. Rama -------------------------------------------------------
read -p "Rama del repositorio [$DEFAULT_BRANCH]: " BRANCH
BRANCH="${BRANCH:-$DEFAULT_BRANCH}"

echo ""
echo "  Dominio:    $BASE_DOMAIN"
echo "  IP LAN:     $SERVER_IP"
echo "  Servicio:   $SERVICE_NUMBER"
echo "  MySQL host: $MYSQL_PORT_HOST"
echo "  Destino:    $PROJECT_DIR"
echo "  Rama:       $BRANCH"
echo ""
read -p "Continuar? [S/n]: " ok
[ "$ok" = "n" ] || [ "$ok" = "N" ] && { echo "Cancelado."; exit 0; }

# --- 6. Docker -----------------------------------------------------
if ! command -v docker >/dev/null 2>&1; then
    echo "-> Instalando Docker ..."
    apt-get -y update
    apt-get -y install apt-transport-https ca-certificates curl gnupg-agent software-properties-common gnupg lsb-release git-core
    mkdir -p /etc/apt/keyrings
    curl -fsSL "https://download.docker.com/linux/$(. /etc/os-release; echo "$ID")/gpg" | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$(. /etc/os-release; echo "$ID") $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
    apt-get -y update
    apt-get -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    systemctl enable --now docker
else
    echo "-> Docker OK ($(docker --version))"
fi
command -v certbot >/dev/null 2>&1 || apt-get -y install certbot 2>/dev/null || true

# --- 7. Red + nginx-proxy compartido (una sola vez) ----------------
echo "-> Configurando proxy compartido (80/443) ..."
docker network inspect proxynet >/dev/null 2>&1 || docker network create proxynet
mkdir -p "$PATH_INSTALL/certs" "$PATH_INSTALL/proxy"
PROXY_RUNNING="$(docker ps --filter "ancestor=rash07/nginx-proxy:4.0" --format '{{.Names}}' | head -1)"
if [ -z "$PROXY_RUNNING" ]; then
    cat > "$PATH_INSTALL/proxy/docker-compose.yml" << 'EOFPROXY'
services:
    proxy:
        image: rash07/nginx-proxy:4.0
        ports:
            - "80:80"
            - "443:443"
        volumes:
            - ./../certs:/etc/nginx/certs
            - /var/run/docker.sock:/tmp/docker.sock:ro
        restart: always
networks:
    default:
        external:
            name: proxynet
EOFPROXY
    ( cd "$PATH_INSTALL/proxy" && docker compose up -d )
else
    echo "   proxy ya esta corriendo (compartido entre dominios)"
fi

# --- 8. Clonar pro-8 ----------------------------------------------
if [ -f "$PROJECT_DIR/artisan" ]; then
    echo "-> El proyecto ya existe; git pull ($BRANCH) ..."
    ( cd "$PROJECT_DIR" && git pull origin "$BRANCH" ) || true
else
    echo "-> Clonando $REPO_URL ($BRANCH) ..."
    rm -rf "$PROJECT_DIR"
    git clone -b "$BRANCH" "$REPO_URL" "$PROJECT_DIR"
fi

# --- 9. Motor de despliegue (en el repo pro-8) --------------------
echo "-> Ejecutando motor onprem-setup.sh ..."
cd "$PROJECT_DIR"
BASE_DOMAIN="$BASE_DOMAIN" \
SERVER_IP="$SERVER_IP" \
SERVICE_NUMBER="$SERVICE_NUMBER" \
MYSQL_PORT_HOST="$MYSQL_PORT_HOST" \
    bash scripts/onprem-setup.sh

# --- 10. Resumen ---------------------------------------------------
DIR_MODIFIED="$(echo "$BASE_DOMAIN" | sed 's/\./_/g')"
CRED_FILE="$PATH_INSTALL/${DIR}-onprem.txt"

echo ""
echo "=================================================="
echo "  SERVICIOS LEVANTADOS ($BASE_DOMAIN)"
echo "=================================================="
docker compose ps 2>/dev/null || true

echo ""
echo "=================================================="
echo "  ENTRADAS HOSTS PARA LAS PCs"
echo "=================================================="
SERVER_IP="$SERVER_IP" BASE_DOMAIN="$BASE_DOMAIN" bash scripts/list-tenant-hosts.sh || true

echo ""
echo "=================================================="
echo "  OK INSTALACION COMPLETADA - $BASE_DOMAIN"
echo "=================================================="
echo "  Panel central: http://$SERVER_IP   |   http://$BASE_DOMAIN"
echo "  Tenants:       http://EMPRESA.$BASE_DOMAIN"
echo "  Credenciales:  $CRED_FILE"
echo "    (incluye seccion PENDIENTES ADMIN DE RED: DNS registrador,"
echo "     VIP/NAT FortiGate y zona DNS local FortiGate)"
echo "  Contenedores:  nginx_$DIR_MODIFIED fpm_$DIR_MODIFIED mariadb_$DIR_MODIFIED redis_$DIR_MODIFIED soketi_$DIR_MODIFIED ..."
echo ""
echo "  Instalar OTRO dominio: vuelve a ejecutar  sudo ./install.sh"
echo "  SSL (emitir o renovar wildcard):          sudo ./ssl.sh"
echo "  Actualizar un dominio instalado:          sudo ./update.sh"
echo "=================================================="
