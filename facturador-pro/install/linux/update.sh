#!/bin/bash
# =========================================================================
# update.sh    Actualizacion segura de un proyecto Pro-8 sobre Linux+Docker
# =========================================================================
# Equivalente a windows-server/03-update.sh pero para hosts Linux nativos.
# Ejecutar desde la carpeta del proyecto: /opt/proyectos/mi-empresa.com
#
# Uso:
#   sudo ./update.sh                  # produccion (por defecto)
#   sudo ./update.sh dev              # desarrollo
#   sudo ./update.sh prod --skip-backup
# =========================================================================

set -euo pipefail

MODE="prod"
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

render_soketi_compose_service() {
    local websocket_host="$1"
    local cert_name="$2"
    local service_number
    local soketi_service
    local soketi_container
    service_number="$(infer_service_number)"
    soketi_service="soketi_${service_number}"
    soketi_container="soketi_$(echo "$cert_name" | sed 's/\./_/g')"

    cat << EOF
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
EOF
}

print_soketi_compose_hint() {
    local websocket_host="$1"
    local cert_name="$2"

    cat << EOF
   Agrega este servicio dentro de services: en docker-compose.yml y vuelve a ejecutar el update:

$(render_soketi_compose_service "$websocket_host" "$cert_name")

    No ejecutes docker compose down -v ni borres volumenes mysqldata*/redisdata*.
    No levantes Soketi manualmente antes; vuelve a ejecutar este script y el creara PUSHER_*.
EOF
}

insert_soketi_compose_service() {
    local websocket_host="$1"
    local cert_name="$2"
    local compose
    local backup
    local tmp
    local timestamp
    local soketi_service
    local block

    compose="$(compose_file)"
    soketi_service="soketi_$(infer_service_number)"

    if ! grep -q '^services:[[:space:]]*$' "$compose" 2>/dev/null; then
        echo "ERROR: $compose no tiene una seccion services: valida. Aborto."
        print_soketi_compose_hint "$websocket_host" "$cert_name"
        exit 1
    fi

    timestamp="$(date +%Y%m%d-%H%M%S)"
    backup="${compose}.backup-before-soketi-${timestamp}"
    tmp="${compose}.tmp.$$"
    cp -p "$compose" "$backup"

    block="$(render_soketi_compose_service "$websocket_host" "$cert_name")"

    awk -v block="$block" '
        /^services:[[:space:]]*$/ { in_services=1; print; next }
        in_services && !inserted && /^[^[:space:]#][^:]*:[[:space:]]*$/ {
            print block "\n"
            inserted=1
            in_services=0
        }
        { print }
        END {
            if (in_services && !inserted) {
                print block
            }
        }
    ' "$compose" > "$tmp"

    mv "$tmp" "$compose"

    if ! docker compose config --services >/tmp/pro8-compose-services.$$ 2>/tmp/pro8-compose-config-error.$$; then
        cp -p "$backup" "$compose"
        echo "ERROR: no se pudo validar $compose despues de agregar Soketi."
        cat /tmp/pro8-compose-config-error.$$ 2>/dev/null || true
        rm -f /tmp/pro8-compose-services.$$ /tmp/pro8-compose-config-error.$$
        echo "Se restauro el compose original desde $backup. Aborto."
        exit 1
    fi

    if ! grep -qx "$soketi_service" /tmp/pro8-compose-services.$$; then
        cp -p "$backup" "$compose"
        rm -f /tmp/pro8-compose-services.$$ /tmp/pro8-compose-config-error.$$
        echo "ERROR: $compose valido, pero no registra el servicio $soketi_service."
        echo "Se restauro el compose original desde $backup. Aborto."
        exit 1
    fi

    rm -f /tmp/pro8-compose-services.$$ /tmp/pro8-compose-config-error.$$
    echo "OK se agrego $soketi_service a $compose."
    echo "   Backup previo del compose: $backup"
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

    echo "ADVERTENCIA: docker-compose.yml fue generado antes de Soketi."
    echo "-> agregando servicio Soketi sin tocar volumenes ni servicios existentes"
    insert_soketi_compose_service "ws.${host_value}" "$host_value"
}

set_soketi_compose_env() {
    local key="$1"
    local value="$2"
    local compose
    local service
    local tmp
    compose="$(compose_file)"
    service="$(infer_compose_service soketi)"
    tmp="${compose}.tmp.$$"
    awk -v service="$service" -v key="$key" -v value="$value" '
        $0 ~ "^[[:space:]]+" service ":[[:space:]]*$" { in_soketi=1; print; next }
        in_soketi && /^[^[:space:]#][^:]*:[[:space:]]*$/ { in_soketi=0 }
        in_soketi && $0 ~ "^[[:space:]]+[A-Za-z0-9_-]+_[0-9]+:[[:space:]]*$" { in_soketi=0 }
        in_soketi && index($0, "- " key "=") > 0 { print "            - " key "=" value; next }
        { print }
    ' "$compose" > "$tmp" && mv "$tmp" "$compose"
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

echo "=================================================="
echo " Pro-8  Update script ($MODE)  $(pwd)"
echo "=================================================="

if [ ! -f docker-compose.yml ] && [ ! -f docker-compose.local.yml ]; then
    echo "ERROR: No se encontro docker-compose.yml en $(pwd). Aborto."
    exit 1
fi

if [ -f docker-compose.local.yml ] && [ "$MODE" = "dev" ]; then
    export COMPOSE_FILE=docker-compose.local.yml
fi

FPM="$(infer_compose_service fpm)"
SUPERVISOR="$(infer_compose_service supervisor)"

echo "-> verificar Broadcasting/Soketi"
preflight_broadcasting

echo "-> backup previo"
backup_production_state

echo "-> configurar Broadcasting"
configure_broadcasting

echo "-> git pull"
git pull --ff-only

echo "-> composer install"
if [ "$MODE" = "prod" ]; then
    docker compose exec -T $FPM sh -c "cd /var/www/html && CACHE_DRIVER=file composer install" || {
        echo "-> composer lock desactualizado; actualizando solo pusher/pusher-php-server"
        docker compose exec -T $FPM sh -c "cd /var/www/html && CACHE_DRIVER=file composer update pusher/pusher-php-server --with-dependencies --no-dev --optimize-autoloader"
    }
else
    docker compose exec -T $FPM sh -c "cd /var/www/html && CACHE_DRIVER=file composer install" || {
        echo "-> composer lock desactualizado; actualizando solo pusher/pusher-php-server"
        docker compose exec -T $FPM sh -c "cd /var/www/html && CACHE_DRIVER=file composer update pusher/pusher-php-server --with-dependencies"
    }
fi

echo "-> composer dump-autoload -o  (clave para controllers/modulos nuevos)"
docker compose exec -T $FPM sh -c "cd /var/www/html && composer dump-autoload -o"

echo "-> php artisan module:discover"
docker compose exec -T $FPM sh -c "cd /var/www/html && CACHE_DRIVER=file php artisan module:discover" || true

echo "-> migrate + tenancy:migrate"
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

echo "-> clear caches"
for cmd in route:clear config:clear cache:clear view:clear; do
    docker compose exec -T $FPM sh -c "cd /var/www/html && CACHE_DRIVER=file php artisan $cmd" || true
done

if [ "$MODE" = "prod" ]; then
    docker compose exec -T $FPM sh -c "cd /var/www/html && CACHE_DRIVER=file php artisan config:cache" || true
fi

echo "-> purgar OPcache (sin reiniciar fpm)"
docker compose exec -T $FPM sh -c "kill -USR2 1" || true

echo "-> reiniciar colas"
docker compose exec -T $SUPERVISOR supervisorctl restart all 2>/dev/null || true

echo ""
echo "OK Actualizacion completada."
