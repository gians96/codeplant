#!/bin/bash
# =========================================================================
# update.sh  —  Actualización segura de un proyecto Pro-8 sobre Linux+Docker
# =========================================================================
# Equivalente a windows-server/03-update.sh pero para hosts Linux nativos.
# Ejecutar desde la carpeta del proyecto: /opt/proyectos/mi-empresa.com
#
# Uso:
#   sudo ./update.sh           # producción (por defecto)
#   sudo ./update.sh dev       # desarrollo
# =========================================================================

set -euo pipefail

MODE="${1:-prod}"
FPM="fpm_1"
SUPERVISOR="supervisor_1"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Pro-8 · Update script ($MODE) · $(pwd)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ ! -f docker-compose.yml ] && [ ! -f docker-compose.local.yml ]; then
    echo "✗ No se encontró docker-compose.yml en $(pwd). Aborto."
    exit 1
fi

if [ -f docker-compose.local.yml ] && [ "$MODE" = "dev" ]; then
    export COMPOSE_FILE=docker-compose.local.yml
fi

echo "→ git pull"
git pull --ff-only

echo "→ composer install"
if [ "$MODE" = "prod" ]; then
    docker compose exec -T $FPM sh -c "cd /var/www/html && CACHE_DRIVER=file composer install --no-dev --optimize-autoloader"
else
    docker compose exec -T $FPM sh -c "cd /var/www/html && composer install"
fi

echo "→ composer dump-autoload -o  (clave para controllers/módulos nuevos)"
docker compose exec -T $FPM sh -c "cd /var/www/html && composer dump-autoload -o"

echo "→ php artisan module:discover"
docker compose exec -T $FPM sh -c "cd /var/www/html && CACHE_DRIVER=file php artisan module:discover" || true

echo "→ migrate + tenancy:migrate"
docker compose exec -T $FPM sh -c "cd /var/www/html && CACHE_DRIVER=file php artisan migrate --force"
docker compose exec -T $FPM sh -c "cd /var/www/html && CACHE_DRIVER=file php artisan tenancy:migrate --force" || true

echo "→ clear caches"
for cmd in route:clear config:clear cache:clear view:clear; do
    docker compose exec -T $FPM sh -c "cd /var/www/html && CACHE_DRIVER=file php artisan $cmd" || true
done

if [ "$MODE" = "prod" ]; then
    docker compose exec -T $FPM sh -c "cd /var/www/html && CACHE_DRIVER=file php artisan config:cache" || true
fi

echo "→ purgar OPcache (sin reiniciar fpm)"
docker compose exec -T $FPM sh -c "kill -USR2 1" || true

echo "→ reiniciar colas"
docker compose exec -T $SUPERVISOR supervisorctl restart all 2>/dev/null || true

echo ""
echo "✓ Actualización completada."
