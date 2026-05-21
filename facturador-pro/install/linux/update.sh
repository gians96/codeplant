#!/bin/bash
# =========================================================================
# update.sh    Actualizacion segura de un proyecto Pro-8 sobre Linux+Docker
# =========================================================================
# Equivalente a windows-server/03-update.sh pero para hosts Linux nativos.
# Ejecutar desde la carpeta del proyecto: /opt/proyectos/mi-empresa.com
#
# Uso:
#   sudo ./update.sh           # produccion (por defecto)
#   sudo ./update.sh dev       # desarrollo
# =========================================================================

set -euo pipefail

MODE="${1:-prod}"
FPM="fpm_1"
SUPERVISOR="supervisor_1"

gen_secret() {
    head /dev/urandom | tr -dc A-Za-z0-9 | head -c 20 ; echo ''
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

ensure_soketi_proxy_route() {
    local websocket_host="$1"
    local cert_name="$2"
    local compose_file="${COMPOSE_FILE:-docker-compose.yml}"

    if [ "$MODE" = "dev" ] || [ ! -f "$compose_file" ]; then
        return
    fi

    if ! grep -q "soketi_" "$compose_file" 2>/dev/null; then
        echo "  ADVERTENCIA: docker-compose fue generado antes de Soketi; reinstala/regenera el stack para Broadcasting en tiempo real."
        return
    fi
    if ! grep -q "SOKETI_DEFAULT_APP_SECRET=" "$compose_file" 2>/dev/null; then
        echo "  ADVERTENCIA: no se encontro el bloque environment de Soketi en $compose_file."
        return
    fi

    set_soketi_compose_env "$compose_file" "VIRTUAL_HOST" "$websocket_host"
    set_soketi_compose_env "$compose_file" "VIRTUAL_PORT" "6001"
    set_soketi_compose_env "$compose_file" "VIRTUAL_PROTO" "http"
    set_soketi_compose_env "$compose_file" "CERT_NAME" "$cert_name"

    echo "  WebSocket publico: wss://${websocket_host}/app/{key}"
    echo "  Subdominio reservado: ${websocket_host} (no crear tenant 'ws')"
}

set_soketi_compose_env() {
    local compose_file="$1"
    local key="$2"
    local value="$3"
    local tmp_file="${compose_file}.tmp.$$"

    if awk -v key="$key" -v value="$value" '
        /^[[:space:]]*soketi_[^:]*:/ { in_soketi=1 }
        in_soketi && /^[[:space:]]*[A-Za-z0-9_-]+_[0-9]+:/ && $0 !~ /^[[:space:]]*soketi_[^:]*:/ { in_soketi=0 }
        in_soketi && $0 ~ "^[[:space:]]*- " key "=" { print "            - " key "=" value; found=1; next }
        { print }
        END { exit found ? 0 : 1 }
    ' "$compose_file" > "$tmp_file"; then
        mv "$tmp_file" "$compose_file"
    else
        rm -f "$tmp_file"
        sed -i "/SOKETI_DEFAULT_APP_SECRET=/a\\            - ${key}=${value}" "$compose_file"
    fi
}

configure_broadcasting() {
    if [ ! -f .env ]; then
        return
    fi

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
        host_value="$(env_value APP_URL_BASE)"
        if [ -z "$host_value" ]; then
            host_value="$(basename "$(pwd)")"
        fi
        websocket_host="ws.${host_value}"
        dir_modified="$(echo "$host_value" | sed 's/\./_/g')"
        ensure_env_var "PUSHER_APP_ID" "vendemaster1"
        ensure_env_var "PUSHER_APP_KEY" "$(gen_secret)"
        ensure_env_var "PUSHER_APP_SECRET" "$(gen_secret)"
        set_env_var "PUSHER_HOST" "soketi_${dir_modified}"
        set_env_var "PUSHER_CLIENT_HOST" "$websocket_host"
        set_env_var "PUSHER_CLIENT_PORT" "443"
        set_env_var "PUSHER_CLIENT_SCHEME" "https"
        ensure_soketi_proxy_route "$websocket_host" "$host_value"
    fi

    set_env_var "BROADCAST_DRIVER" "pusher"
    set_env_var "PUSHER_APP_CLUSTER" "mt1"
    set_env_var "PUSHER_PORT" "6001"
    set_env_var "PUSHER_SCHEME" "http"

    if grep -q "soketi_" "${COMPOSE_FILE:-docker-compose.yml}" 2>/dev/null; then
        docker compose up -d soketi_1 2>/dev/null || true
    else
        echo "  ADVERTENCIA: docker-compose fue generado antes de Soketi; reinstala/regenera el stack para Broadcasting en tiempo real."
    fi
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

echo "-> configurar Broadcasting"
configure_broadcasting

echo "-> git pull"
git pull --ff-only

echo "-> composer install"
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

echo "-> composer dump-autoload -o  (clave para controllers/modulos nuevos)"
docker compose exec -T $FPM sh -c "cd /var/www/html && composer dump-autoload -o"

echo "-> php artisan module:discover"
docker compose exec -T $FPM sh -c "cd /var/www/html && CACHE_DRIVER=file php artisan module:discover" || true

echo "-> migrate + tenancy:migrate"
docker compose exec -T $FPM sh -c "cd /var/www/html && CACHE_DRIVER=file php artisan migrate --force"
docker compose exec -T $FPM sh -c "cd /var/www/html && CACHE_DRIVER=file php artisan tenancy:migrate --force" || true

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
