#!/bin/bash
# =========================================================================
# install.sh - Instalacion ON-PREMISE multi-dominio de Facturador Pro-8
# =========================================================================
# Despliega Pro-8 multi-tenant en un servidor LOCAL (VMware ESXi / bare-metal).
# Funciona HOY por LAN (IP + archivos hosts, HTTP) y luego se activa el acceso
# publico con SSL via ssl.sh, SIN migrar base de datos.
#
# REUTILIZABLE: instala VARIOS dominios en el mismo servidor sin que choquen:
#   - Cada proyecto vive en su carpeta:  $ROOT/<dominio>/app  (repo) + credenciales
#   - Infra COMPARTIDA (proxy 80/443 + certs) en  $ROOT/_infra
#   - Contenedores nombrados por dominio:  nginx_<dom>, fpm_<dom>, mariadb_<dom>...
#   - Volumenes deterministas:  <dominio>_mysqldata<N> / <dominio>_redisdata<N>
#   - Puerto MySQL del host asignado automaticamente a uno libre
#
# Estructura resultante:
#   /opt/proyectos/
#   |-- install.sh update.sh ssl.sh set-hosts.sh uninstall.sh
#   |-- _infra/{proxy,certs}                  (compartido)
#   `-- <dominio>/
#       |-- app/                              (repo pro-8: compose, .env, ...)
#       `-- <dominio>-onprem.txt              (credenciales)
#
# Uso:
#   mkdir -p /opt/proyectos && cd /opt/proyectos
#   curl -O https://raw.githubusercontent.com/gians96/codeplant/master/facturador-pro/install/onpremise/install.sh
#   curl -O https://raw.githubusercontent.com/gians96/codeplant/master/facturador-pro/install/onpremise/update.sh
#   curl -O https://raw.githubusercontent.com/gians96/codeplant/master/facturador-pro/install/onpremise/ssl.sh
#   curl -O https://raw.githubusercontent.com/gians96/codeplant/master/facturador-pro/install/onpremise/uninstall.sh
#   curl -O https://raw.githubusercontent.com/gians96/codeplant/master/facturador-pro/install/onpremise/set-hosts.sh
#   chmod +x *.sh
#   sudo ./install.sh
# =========================================================================

set -e

REPO_URL="${REPO_URL:-https://gitlab.com/gians96/pro-8.git}"
DEFAULT_BRANCH="${DEFAULT_BRANCH:-gians96}"

# La raiz es DONDE VIVEN LOS SCRIPTS (no el directorio actual): evita el doble
# anidamiento <dominio>/<dominio> si se ejecuta desde otra carpeta. Override: --root
ROOT="$(cd "$(dirname "$0")" && pwd)"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --root) ROOT="$2"; shift 2 ;;
        *) echo "Parametro desconocido: $1"; exit 1 ;;
    esac
done
INFRA_DIR="$ROOT/_infra"
PROXY_DIR="$INFRA_DIR/proxy"
CERTS_DIR="$INFRA_DIR/certs"

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
    local found=0 d dom port
    echo "=== Dominios ya instalados en $ROOT ==="
    for d in "$ROOT"/*/; do
        dom="$(basename "$d")"
        case "$dom" in _*) continue ;; esac          # _infra y otras carpetas internas
        [ -f "${d}app/docker-compose.yml" ] && [ -f "${d}app/.env" ] || continue
        port="$(grep -E '^MYSQL_PORT_HOST=' "${d}app/.env" 2>/dev/null | cut -d= -f2)"
        printf "  - %-30s (MySQL host: %s)\n" "$dom" "${port:-?}"
        found=1
    done
    [ "$found" = "0" ] && echo "  (ninguno todavia)"
    echo "==============================================="
}

# --- Preflight: requisitos del sistema (SE EJECUTA PRIMERO) -------
preflight() {
    echo "-> Comprobando requisitos (Docker, compose, git) ..."

    if [ "$(id -u)" -ne 0 ]; then
        echo "ERROR: ejecuta como root:  sudo ./install.sh"
        exit 1
    fi

    # Docker Engine
    if ! command -v docker >/dev/null 2>&1; then
        echo "   Docker no esta instalado. Instalando Docker Engine ..."
        apt-get -y update
        apt-get -y install apt-transport-https ca-certificates curl gnupg-agent software-properties-common gnupg lsb-release git-core
        mkdir -p /etc/apt/keyrings
        curl -fsSL "https://download.docker.com/linux/$(. /etc/os-release; echo "$ID")/gpg" | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$(. /etc/os-release; echo "$ID") $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
        apt-get -y update
        apt-get -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        systemctl enable --now docker
    fi

    # Daemon activo
    if ! docker info >/dev/null 2>&1; then
        echo "ERROR: Docker esta instalado pero el daemon no responde."
        echo "  Inicialo:  sudo systemctl start docker   (revisa: systemctl status docker)"
        exit 1
    fi

    # Plugin compose v2
    if ! docker compose version >/dev/null 2>&1; then
        echo "   Plugin 'docker compose' ausente. Instalando docker-compose-plugin ..."
        apt-get -y update && apt-get -y install docker-compose-plugin || {
            echo "ERROR: no se pudo instalar el plugin 'docker compose'."; exit 1; }
    fi

    # git / curl
    command -v git  >/dev/null 2>&1 || { echo "   Instalando git ...";  apt-get -y install git-core 2>/dev/null || apt-get -y install git; }
    command -v curl >/dev/null 2>&1 || { echo "   Instalando curl ..."; apt-get -y install curl; }

    # python3 / gzip: los usan scripts/onprem-setup.sh (seeder) y el backup del update
    command -v python3 >/dev/null 2>&1 || { echo "   Instalando python3 ..."; apt-get -y install python3; }
    command -v gzip    >/dev/null 2>&1 || { echo "   Instalando gzip ...";    apt-get -y install gzip; }

    # certbot (opcional, Fase 2 SSL)
    command -v certbot >/dev/null 2>&1 || apt-get -y install certbot 2>/dev/null || true

    echo "   OK Docker $(docker --version | awk '{print $3}' | tr -d ',') + compose $(docker compose version --short 2>/dev/null)"
}

# --- Guarda anti-huerfanos ----------------------------------------
# Causa raiz del error 'Access denied for user root' al reinstalar: borrar la
# carpeta y los contenedores NO borra los volumenes Docker. MariaDB conserva la
# password vieja del volumen y rechaza la nueva del .env. Aqui detectamos esos
# restos y ofrecemos purgarlos antes de reinstalar.
check_orphans() {
    local dom="$1" dirmod="$2" domsquash c v ct_re vol_re
    local cts=() vols=()
    # Dos esquemas de prefijo de volumen para este dominio EXACTO (sin falsos
    # positivos de otros dominios): nuevo = DIR_MODIFIED (puntos->_, ej.
    # ceos-facturacion_com); legacy = nombre de carpeta normalizado por Compose
    # (solo quita puntos, ej. ceos-facturacioncom).
    domsquash="$(echo "$dom" | tr 'A-Z' 'a-z' | tr -d '.')"
    ct_re="^(nginx|fpm|mariadb|redis|soketi|scheduling|supervisor)_${dirmod}\$"
    vol_re="^(${dirmod}|${domsquash})_(mysqldata|redisdata)[0-9]+\$"

    while IFS= read -r c; do [ -n "$c" ] && cts+=("$c"); done < <(
        docker ps -a --format '{{.Names}}' 2>/dev/null | grep -E "$ct_re" || true)
    while IFS= read -r v; do [ -n "$v" ] && vols+=("$v"); done < <(
        docker volume ls --format '{{.Name}}' 2>/dev/null | grep -E "$vol_re" || true)

    [ ${#cts[@]} -eq 0 ] && [ ${#vols[@]} -eq 0 ] && return 0

    echo ""
    echo "ADVERTENCIA: hay restos Docker de una instalacion previa de '$dom'"
    echo "  (la carpeta ya no existe, pero los contenedores/volumenes si)."
    [ ${#cts[@]}  -gt 0 ] && printf '    contenedor: %s\n' "${cts[@]}"
    [ ${#vols[@]} -gt 0 ] && printf '    volumen:    %s\n' "${vols[@]}"
    echo ""
    echo "  Si reinstalas sin limpiarlos, MariaDB conserva la password vieja del"
    echo "  volumen y la app fallara con:  Access denied for user 'root'."
    echo ""
    echo "  [P] Purgar estos restos y reinstalar LIMPIO (se PIERDEN esos datos)"
    echo "  [C] Cancelar (para conservarlos, usa el .env original o restaura backup)"
    read -p "  Opcion [P/C]: " opt
    case "$opt" in
        P|p)
            [ ${#cts[@]}  -gt 0 ] && docker rm -f "${cts[@]}" >/dev/null 2>&1 || true
            [ ${#vols[@]} -gt 0 ] && docker volume rm "${vols[@]}" >/dev/null 2>&1 || true
            echo "  -> Restos purgados. Continuando con instalacion limpia."
            ;;
        *) echo "Cancelado."; exit 0 ;;
    esac
}

echo ""
echo "=================================================="
echo "  FACTURADOR PRO-8 - Instalacion ON-PREMISE (LAN)"
echo "  Multi-dominio / reutilizable"
echo "=================================================="
echo ""

# --- 0. Requisitos PRIMERO ----------------------------------------
preflight
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

DIR_MODIFIED="$(echo "$BASE_DOMAIN" | sed 's/\./_/g' | tr 'A-Z' 'a-z')"
PROJECT_HOME="$ROOT/$BASE_DOMAIN"
APP_DIR="$PROJECT_HOME/app"
CRED_FILE="$PROJECT_HOME/$BASE_DOMAIN-onprem.txt"

if [ -f "$APP_DIR/docker-compose.yml" ]; then
    echo "ADVERTENCIA: '$BASE_DOMAIN' ya parece instalado en $APP_DIR."
    echo "  - Para actualizar CODIGO usa:   sudo ./update.sh"
    echo "  - Para ELIMINARLO por completo: sudo ./uninstall.sh --domain $BASE_DOMAIN"
    echo "  - Continuar aqui RE-GENERA compose/config REUSANDO los secretos del .env"
    echo "    existente (no borra datos, volumenes ni passwords). Util p.ej. para"
    echo "    cambiar la IP del servidor sin perder la base de datos."
    read -p "  Continuar (re-generar config)? [s/N]: " cont
    [ "$cont" = "s" ] || [ "$cont" = "S" ] || { echo "Cancelado."; exit 0; }
else
    check_orphans "$BASE_DOMAIN" "$DIR_MODIFIED"
fi

# --- 2. IP LAN del servidor (autodetectada) -----------------------
DETECTED_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
read -p "IP LAN del servidor [$DETECTED_IP]: " SERVER_IP
SERVER_IP="${SERVER_IP:-$DETECTED_IP}"
[ -z "$SERVER_IP" ] && { echo "ERROR: no se determino la IP del servidor."; exit 1; }

# --- 3. Numero de servicio (sugerido por # de instalados) ---------
EXISTING_COUNT="$(find "$ROOT" -maxdepth 3 -path '*/app/docker-compose.yml' 2>/dev/null | wc -l | tr -d ' ')"
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
echo "  Dominio:      $BASE_DOMAIN"
echo "  IP LAN:       $SERVER_IP"
echo "  Servicio:     $SERVICE_NUMBER"
echo "  MySQL host:   $MYSQL_PORT_HOST"
echo "  Destino:      $APP_DIR"
echo "  Credenciales: $CRED_FILE"
echo "  Rama:         $BRANCH"
echo ""
read -p "Continuar? [S/n]: " ok
[ "$ok" = "n" ] || [ "$ok" = "N" ] && { echo "Cancelado."; exit 0; }

# --- 6. Red + nginx-proxy compartido (en _infra, una sola vez) ----
echo "-> Configurando proxy compartido (80/443) ..."
docker network inspect proxynet >/dev/null 2>&1 || docker network create proxynet
mkdir -p "$CERTS_DIR" "$PROXY_DIR"
PROXY_RUNNING="$(docker ps --filter "ancestor=rash07/nginx-proxy:4.0" --format '{{.Names}}' | head -1)"
if [ -z "$PROXY_RUNNING" ]; then
    cat > "$PROXY_DIR/docker-compose.yml" << 'EOFPROXY'
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
        name: proxynet
        external: true
EOFPROXY
    ( cd "$PROXY_DIR" && docker compose up -d )
else
    echo "   proxy ya esta corriendo (compartido entre dominios)"
fi

# --- 7. Clonar pro-8 en <dominio>/app -----------------------------
mkdir -p "$PROJECT_HOME"
if [ -f "$APP_DIR/artisan" ]; then
    echo "-> El proyecto ya existe; git pull ($BRANCH) ..."
    ( cd "$APP_DIR" && git pull origin "$BRANCH" ) || true
else
    echo "-> Clonando $REPO_URL ($BRANCH) ..."
    rm -rf "$APP_DIR"
    git clone -b "$BRANCH" "$REPO_URL" "$APP_DIR"
fi

# --- 8. Motor de despliegue (en el repo pro-8) --------------------
echo "-> Ejecutando motor onprem-setup.sh ..."
cd "$APP_DIR"
BASE_DOMAIN="$BASE_DOMAIN" \
SERVER_IP="$SERVER_IP" \
SERVICE_NUMBER="$SERVICE_NUMBER" \
MYSQL_PORT_HOST="$MYSQL_PORT_HOST" \
CRED_FILE="$CRED_FILE" \
SCRIPTS_ROOT="$ROOT" \
    bash scripts/onprem-setup.sh

# --- 9. Resumen ---------------------------------------------------
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
echo "  Proyecto:      $APP_DIR"
echo "  Credenciales:  $CRED_FILE"
echo "    (incluye seccion PENDIENTES ADMIN DE RED: DNS registrador,"
echo "     VIP/NAT FortiGate y zona DNS local FortiGate)"
echo "  Contenedores:  nginx_$DIR_MODIFIED fpm_$DIR_MODIFIED mariadb_$DIR_MODIFIED redis_$DIR_MODIFIED soketi_$DIR_MODIFIED ..."
echo "  Volumenes:     ${DIR_MODIFIED}_mysqldata${SERVICE_NUMBER} ${DIR_MODIFIED}_redisdata${SERVICE_NUMBER}"
echo ""
echo "  Instalar OTRO dominio:  sudo ./install.sh"
echo "  Emitir/renovar SSL:     sudo ./ssl.sh"
echo "  Actualizar un dominio:  sudo ./update.sh"
echo "  ELIMINAR un dominio:    sudo ./uninstall.sh --domain $BASE_DOMAIN"
echo "=================================================="
