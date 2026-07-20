#!/bin/bash
# =========================================================================
# 03-update.sh    Actualizacion segura de un proyecto Pro-8 sobre WSL2+Docker
# =========================================================================
# Ejecutar DENTRO de la carpeta del proyecto (~/proyectos/mi-empresa.com)
# o en desarrollo (~/proyectos/pro-8).
#
# Hace, en orden:
#   1. git pull
#   2. composer install (dentro de fpm)   produccion: --no-dev
#   3. composer dump-autoload -o          CLAVE! resuelve "Target class does not exist"
#   4. php artisan module:discover        re-escanea modules/<Modulo>/module.json
#   5. migrate + tenancy:migrate
#   6. route:clear / config:clear / cache:clear / view:clear
#   7. docker compose exec fpm_1 kill -USR2 1  (purga OPcache sin restart)
#   8. supervisorctl restart all  (si el contenedor existe)
# =========================================================================

set -euo pipefail

MODE="prod"               # prod | dev
SKIP_BACKUP=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        prod|dev) MODE="$1"; shift ;;
        --skip-backup) SKIP_BACKUP=1; shift ;;
        *) echo "Parametro desconocido: $1"; exit 1 ;;
    esac
done

FPM="fpm_1"
SUPERVISOR="supervisor_1"

gen_secret() {
    local value
    value="$(LC_ALL=C tr -dc A-Za-z0-9 </dev/urandom | head -c 20 || true)"
    printf '%s\n' "$value"
}

env_value() {
    local key="$1"
    if [ -f .env ]; then
        grep -E "^${key}=" .env | tail -1 | cut -d= -f2- | sed 's/^"//;s/"$//' || true
    fi
}

set_env_var() {
    local key="$1"
    local value="$2"
    if [ ! -f .env ]; then
        return
    fi
    if grep -q "^${key}=" .env; then
        sed -i "/^${key}=/c\\${key}=${value}" .env
    else
        echo "${key}=${value}" >> .env
    fi
}

ensure_env_var() {
    local key="$1"
    local value="$2"
    local current
    current="$(env_value "$key")"
    if [ -z "$current" ]; then
        set_env_var "$key" "$value"
    fi
}

compose_file() {
    echo "${COMPOSE_FILE:-docker-compose.yml}"
}

sanitize_host() {
    echo "$1" | sed -E 's#^https?://##; s#/.*$##; s/[[:space:]]//g'
}

infer_compose_service() {
    local prefix="$1"
    local compose
    local service
    compose="$(compose_file)"
    service="$(grep -E "^[[:space:]]+${prefix}_[0-9]+:" "$compose" 2>/dev/null | head -1 | sed -E 's/^[[:space:]]+([^:]+):.*/\1/' || true)"
    echo "${service:-${prefix}_1}"
}

infer_service_number() {
    local fpm_service
    fpm_service="$(infer_compose_service fpm)"
    echo "${fpm_service#fpm_}"
}

compose_has_soketi() {
    local compose
    compose="$(compose_file)"
    grep -Eq '^[[:space:]]+soketi_[0-9]+:' "$compose" 2>/dev/null
}

print_soketi_compose_hint() {
    local websocket_host="$1"
    local cert_name="$2"
    local service_number
    local soketi_service
    local soketi_container
    service_number="$(infer_service_number)"
    soketi_service="soketi_${service_number}"
    soketi_container="soketi_$(echo "$cert_name" | sed 's/\./_/g')"

    cat << EOF
   Agrega este servicio dentro de services: en docker-compose.yml y vuelve a ejecutar el update:

    ${soketi_service}:
        image: quay.io/soketi/soketi:1.6-16-debian
        container_name: ${soketi_container}
        environment:
            - SOKETI_DEBUG=0
            - SOKETI_DEFAULT_APP_ID=\${PUSHER_APP_ID:-vendemaster-prod}
            - SOKETI_DEFAULT_APP_KEY=\${PUSHER_APP_KEY}
            - SOKETI_DEFAULT_APP_SECRET=\${PUSHER_APP_SECRET}
            - VIRTUAL_HOST=${websocket_host}
            - VIRTUAL_PORT=6001
            - VIRTUAL_PROTO=http
            - CERT_NAME=${cert_name}
        restart: always

    No ejecutes docker compose down -v ni borres volumenes mysqldata*/redisdata*.
    No levantes Soketi manualmente antes; vuelve a ejecutar este script y el creara PUSHER_*.
EOF
}

preflight_broadcasting() {
    local compose
    compose="$(compose_file)"

    if [ ! -f .env ]; then
        echo "ERROR: No existe .env en $(pwd). Aborto."
        exit 1
    fi
    if [ ! -f "$compose" ]; then
        echo "ERROR: No existe $compose en $(pwd). Aborto."
        exit 1
    fi

    if compose_has_soketi; then
        if ! grep -q "SOKETI_DEFAULT_APP_SECRET=" "$compose" 2>/dev/null; then
            echo "ERROR: El servicio Soketi no tiene SOKETI_DEFAULT_APP_SECRET. Aborto."
            exit 1
        fi
        return
    fi

    if [ "$MODE" = "dev" ]; then
        echo "ERROR: $compose fue generado antes de Soketi."
        echo "  Actualiza el stack local sin borrar datos:"
        echo "    docker compose -f docker-compose.local.yml down"
        echo "    bash scripts/local-setup.sh"
        echo "  Importante: no uses down -v."
        exit 1
    fi

    local host_value
    host_value="$(sanitize_host "$(env_value APP_URL_BASE)")"
    if [ -z "$host_value" ]; then
        host_value="$(basename "$(pwd)")"
    fi
    if [[ "$host_value" == ws.* ]]; then
        echo "ERROR: APP_URL_BASE debe ser el dominio raiz, no $host_value."
        exit 1
    fi

    echo "ERROR: docker-compose.yml fue generado antes de Soketi."
    print_soketi_compose_hint "ws.${host_value}" "$host_value"
    exit 1
}

set_soketi_compose_env() {
    local key="$1"
    local value="$2"
    local compose
    compose="$(compose_file)"
    if grep -q "${key}=" "$compose" 2>/dev/null; then
        sed -i "/${key}=/c\\            - ${key}=${value}" "$compose"
    fi
}

ensure_soketi_proxy_route() {
    local websocket_host="$1"
    local cert_name="$2"
    local compose
    compose="$(compose_file)"
    if grep -q "VIRTUAL_HOST=" "$compose" 2>/dev/null; then
        set_soketi_compose_env "VIRTUAL_HOST" "$websocket_host"
        set_soketi_compose_env "VIRTUAL_PORT" "6001"
        set_soketi_compose_env "VIRTUAL_PROTO" "http"
        set_soketi_compose_env "CERT_NAME" "$cert_name"
    fi
}

backup_production_state() {
    if [ "$MODE" != "prod" ]; then
        return
    fi
    if [ "$SKIP_BACKUP" = "1" ]; then
        echo "ADVERTENCIA: backup previo omitido por --skip-backup."
        return
    fi

    local mysql_root_password
    local mariadb_service
    local timestamp
    local backup_dir
    local sql_file
    mysql_root_password="$(env_value MYSQL_ROOT_PASSWORD)"
    if [ -z "$mysql_root_password" ]; then
        echo "ERROR: No se encontro MYSQL_ROOT_PASSWORD en .env; no se puede crear backup seguro."
        exit 1
    fi

    mariadb_service="$(infer_compose_service mariadb)"
    if ! docker compose exec -T "$mariadb_service" sh -c 'true' >/dev/null 2>&1; then
        echo "ERROR: MariaDB no responde via docker compose exec: $mariadb_service"
        exit 1
    fi

    timestamp="$(date +%Y%m%d-%H%M%S)"
    backup_dir="$(pwd)/storage/app/backups/pre-update/${timestamp}"
    sql_file="${backup_dir}/all-databases.sql"
    mkdir -p "$backup_dir"
    chmod 700 "$backup_dir"
    [ -f docker-compose.yml ] && cp -p docker-compose.yml "${backup_dir}/docker-compose.yml"
    [ -f .env ] && cp -p .env "${backup_dir}/.env"
    [ -f supervisor.conf ] && cp -p supervisor.conf "${backup_dir}/supervisor.conf"

    echo "-> backup completo de MariaDB antes del update"
    docker compose exec -T -e MYSQL_PWD="$mysql_root_password" "$mariadb_service" sh -c 'mysqldump -uroot --single-transaction --routines --triggers --events --all-databases' > "$sql_file"

    if [ ! -s "$sql_file" ]; then
        echo "ERROR: el backup SQL quedo vacio. Aborto."
        exit 1
    fi
    if command -v gzip >/dev/null 2>&1; then
        gzip -f "$sql_file"
        sql_file="${sql_file}.gz"
    fi
    echo "OK backup creado en: $backup_dir"
    echo "   SQL: $sql_file"
}

configure_broadcasting() {
    preflight_broadcasting

    if [ "$MODE" = "dev" ]; then
        ensure_env_var "PUSHER_APP_ID" "vendemaster-local"
        ensure_env_var "PUSHER_APP_KEY" "vendemaster-key"
        ensure_env_var "PUSHER_APP_SECRET" "vendemaster-secret"
        set_env_var "PUSHER_HOST" "soketi_pro8_local"
        set_env_var "PUSHER_CLIENT_HOST" "127.0.0.1"
        set_env_var "PUSHER_CLIENT_PORT" "6001"
        set_env_var "PUSHER_CLIENT_SCHEME" "http"
    else
        local host_value
        local dir_modified
        local websocket_host
        local compose
        host_value="$(sanitize_host "$(env_value APP_URL_BASE)")"
        if [ -z "$host_value" ]; then
            host_value="$(basename "$(pwd)")"
        fi
        if [[ "$host_value" == ws.* ]]; then
            echo "ERROR: APP_URL_BASE debe ser el dominio raiz, no $host_value."
            exit 1
        fi
        compose="$(compose_file)"
        websocket_host="$host_value"
        if grep -q "VIRTUAL_HOST=" "$compose" 2>/dev/null; then
            websocket_host="ws.${host_value}"
            ensure_soketi_proxy_route "$websocket_host" "$host_value"
        fi
        dir_modified="$(echo "$host_value" | sed 's/\./_/g')"
        ensure_env_var "PUSHER_APP_ID" "vendemaster-prod"
        ensure_env_var "PUSHER_APP_KEY" "$(gen_secret)"
        ensure_env_var "PUSHER_APP_SECRET" "$(gen_secret)"
        set_env_var "PUSHER_HOST" "soketi_${dir_modified}"
        set_env_var "PUSHER_CLIENT_HOST" "$websocket_host"
        set_env_var "PUSHER_CLIENT_PORT" "443"
        set_env_var "PUSHER_CLIENT_SCHEME" "https"
    fi

    set_env_var "BROADCAST_DRIVER" "pusher"
    set_env_var "PUSHER_APP_CLUSTER" "mt1"
    set_env_var "PUSHER_PORT" "6001"
    set_env_var "PUSHER_SCHEME" "http"

    docker compose up -d "$(infer_compose_service soketi)"
}

persist_bun_path() {
    for shell_file in "$HOME/.profile" "$HOME/.bashrc"; do
        if [ -f "$shell_file" ] && ! grep -q 'BUN_INSTALL=.*/.bun' "$shell_file"; then
            {
                echo ""
                echo "# Bun runtime/bundler"
                echo "export BUN_INSTALL=\"\$HOME/.bun\""
                echo "export PATH=\"\$BUN_INSTALL/bin:\$PATH\""
            } >> "$shell_file"
        fi
    done
}

ensure_bun() {
    export BUN_INSTALL="${BUN_INSTALL:-$HOME/.bun}"
    case ":$PATH:" in
        *":$BUN_INSTALL/bin:"*) ;;
        *) export PATH="$BUN_INSTALL/bin:$PATH" ;;
    esac

    if command -v bun >/dev/null 2>&1; then
        echo "Bun OK: $(bun --version)"
        return 0
    fi

    if [ -x "$BUN_INSTALL/bin/bun" ]; then
        echo "Bun OK: $($BUN_INSTALL/bin/bun --version)"
        return 0
    fi

    echo "Instalando Bun..."
    if ! command -v unzip >/dev/null 2>&1; then
        sudo apt-get update -qq && sudo apt-get install -y unzip >/dev/null
    fi
    if ! command -v curl >/dev/null 2>&1; then
        sudo apt-get update -qq && sudo apt-get install -y curl ca-certificates >/dev/null
    fi
    curl -fsSL https://bun.sh/install | bash >/dev/null
    export PATH="$BUN_INSTALL/bin:$PATH"
    hash -r 2>/dev/null || true

    persist_bun_path

    echo "Bun instalado: $(bun --version)"
}

echo "=================================================="
echo " Pro-8  Update script ($MODE)"
echo " $(pwd)"
echo "=================================================="

if [ ! -f docker-compose.yml ] && [ ! -f docker-compose.local.yml ]; then
    echo "ERROR: No se encontro docker-compose.yml en $(pwd). Aborto."
    exit 1
fi

# Detectar archivo compose local vs prod
if [ -f docker-compose.local.yml ] && [ "$MODE" = "dev" ]; then
    export COMPOSE_FILE=docker-compose.local.yml
fi

FPM="$(infer_compose_service fpm)"
SUPERVISOR="$(infer_compose_service supervisor)"

echo "-> 0/8 verificar Broadcasting/Soketi"
preflight_broadcasting

echo "-> 0b/8 backup previo"
backup_production_state

echo "-> 0/8 configurar Broadcasting"
configure_broadcasting

echo "-> 1/8 git pull"
git pull --ff-only

echo "-> 2/8 composer install"
if [ "$MODE" = "prod" ]; then
    docker compose exec -T $FPM sh -c "cd /var/www/html && CACHE_DRIVER=file composer install --no-dev --optimize-autoloader" || {
        echo "-> composer lock desactualizado; actualizando solo pusher/pusher-php-server"
        docker compose exec -T $FPM sh -c "cd /var/www/html && CACHE_DRIVER=file composer update pusher/pusher-php-server --with-dependencies --no-dev --optimize-autoloader"
    }
else
    docker compose exec -T $FPM sh -c "cd /var/www/html && CACHE_DRIVER=file composer install" || {
        echo "-> composer lock desactualizado; actualizando solo pusher/pusher-php-server"
        docker compose exec -T $FPM sh -c "cd /var/www/html && CACHE_DRIVER=file composer update pusher/pusher-php-server --with-dependencies"
    }
fi

echo "-> 2b/8 Bun + assets JS"
if [ -f scripts/ensure-bun.sh ]; then
    source scripts/ensure-bun.sh
else
    ensure_bun
fi
bun install --ignore-scripts
bun run build || echo "  ADVERTENCIA: bun run build fallo; revisa errores arriba"

echo "-> 3/8 composer dump-autoload (CLAVE para clases nuevas)"
docker compose exec -T $FPM sh -c "cd /var/www/html && composer dump-autoload -o"

# mPDF/dompdf escriben cache y fuentes DENTRO de vendor; tras composer (como root)
# quedan root:root y fpm (www-data) no puede escribir -> "mkdir(): Permission denied"
# al generar PDF (incidente 2026-07-20). Se les da owner www-data.
echo "-> permisos de escritura de mpdf/dompdf"
docker compose exec -T -u root $FPM sh -c "mkdir -p /var/www/html/vendor/mpdf/mpdf/tmp /var/www/html/vendor/mpdf/mpdf/ttfontdata; chown -R www-data:www-data /var/www/html/vendor/mpdf/mpdf/tmp /var/www/html/vendor/mpdf/mpdf/ttfontdata /var/www/html/vendor/dompdf/dompdf/lib/fonts 2>/dev/null; chmod -R ug+rwX /var/www/html/vendor/mpdf/mpdf/tmp /var/www/html/vendor/mpdf/mpdf/ttfontdata /var/www/html/vendor/dompdf/dompdf/lib/fonts 2>/dev/null; true"

echo "-> 4/8 php artisan module:discover"
docker compose exec -T $FPM sh -c "cd /var/www/html && CACHE_DRIVER=file php artisan module:discover" || true

echo "-> 5/8 migraciones"
docker compose exec -T $FPM sh -c "cd /var/www/html && CACHE_DRIVER=file php artisan migrate --force"
# --path OBLIGATORIO: config/tenancy.php tiene tenant-migrations-path=false y sin el
# hyn lanza InvalidArgumentException y NO migra ningun tenant (incidente 2026-07-13).
docker compose exec -T $FPM sh -c "cd /var/www/html && CACHE_DRIVER=file php artisan tenancy:migrate --path=database/migrations/tenant --force" || {
    echo "=========================================================="
    echo "ADVERTENCIA: tenancy:migrate FALLO. Los tenants pueden haber"
    echo "quedado a medio migrar. Revisar el error de arriba ANTES de"
    echo "dar el update por bueno (el backup pre-update es el rollback)."
    echo "=========================================================="
}

echo "-> 6/8 clear caches"
for cmd in route:clear config:clear cache:clear view:clear; do
    docker compose exec -T $FPM sh -c "cd /var/www/html && CACHE_DRIVER=file php artisan $cmd" || true
done

if [ "$MODE" = "prod" ]; then
    echo "-> 6b  config:cache (solo prod)"
    docker compose exec -T $FPM sh -c "cd /var/www/html && CACHE_DRIVER=file php artisan config:cache" || true
fi

echo "-> 7/8 purgar OPcache (sin reiniciar fpm)"
docker compose exec -T $FPM sh -c "kill -USR2 1" || true

echo "-> 8/8 reiniciar colas"
docker compose exec -T $SUPERVISOR supervisorctl restart all 2>/dev/null || \
    echo "  (supervisor no esta activo  OK en dev)"

# Auto-start (WSL2 only): lo instala el script de instalacion.
if grep -qi microsoft /proc/version 2>/dev/null && [ ! -f /etc/systemd/system/pro8-autostart.service ]; then
    echo ""
    echo "ADVERTENCIA: pro8-autostart no esta instalado. Re-ejecuta el script de instalacion actualizado."
fi

echo ""
echo "OK Actualizacion completada."
echo ""
echo "Prueba con:"
echo "  curl -I http://localhost:8080/api/offline/business-turns"
