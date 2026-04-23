#!/bin/bash
# =========================================================================
# 03-update.sh  —  Actualización segura de un proyecto Pro-8 sobre WSL2+Docker
# =========================================================================
# Ejecutar DENTRO de la carpeta del proyecto (~/proyectos/mi-empresa.com)
# o en desarrollo (~/proyectos/pro-8).
#
# Hace, en orden:
#   1. git pull
#   2. composer install (dentro de fpm)  — produccion: --no-dev
#   3. composer dump-autoload -o         — ¡CLAVE! resuelve "Target class does not exist"
#   4. php artisan module:discover       — re-escanea modules/<Modulo>/module.json
#   5. migrate + tenancy:migrate
#   6. route:clear / config:clear / cache:clear / view:clear
#   7. docker compose exec fpm_1 kill -USR2 1  (purga OPcache sin restart)
#   8. supervisorctl restart all  (si el contenedor existe)
# =========================================================================

set -euo pipefail

MODE="${1:-prod}"         # prod | dev
FPM="fpm_1"
SUPERVISOR="supervisor_1"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Pro-8 · Update script ($MODE)"
echo " $(pwd)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ ! -f docker-compose.yml ] && [ ! -f docker-compose.local.yml ]; then
    echo "✗ No se encontró docker-compose.yml en $(pwd). Aborto."
    exit 1
fi

# Detectar archivo compose local vs prod
if [ -f docker-compose.local.yml ] && [ "$MODE" = "dev" ]; then
    export COMPOSE_FILE=docker-compose.local.yml
fi

echo "→ 1/8 git pull"
git pull --ff-only

echo "→ 2/8 composer install"
if [ "$MODE" = "prod" ]; then
    docker compose exec -T $FPM sh -c "cd /var/www/html && CACHE_DRIVER=file composer install --no-dev --optimize-autoloader"
else
    docker compose exec -T $FPM sh -c "cd /var/www/html && composer install"
fi

echo "→ 3/8 composer dump-autoload (CLAVE para clases nuevas)"
docker compose exec -T $FPM sh -c "cd /var/www/html && composer dump-autoload -o"

echo "→ 4/8 php artisan module:discover"
docker compose exec -T $FPM sh -c "cd /var/www/html && CACHE_DRIVER=file php artisan module:discover" || true

echo "→ 5/8 migraciones"
docker compose exec -T $FPM sh -c "cd /var/www/html && CACHE_DRIVER=file php artisan migrate --force"
docker compose exec -T $FPM sh -c "cd /var/www/html && CACHE_DRIVER=file php artisan tenancy:migrate --force" || true

echo "→ 6/8 clear caches"
for cmd in route:clear config:clear cache:clear view:clear; do
    docker compose exec -T $FPM sh -c "cd /var/www/html && CACHE_DRIVER=file php artisan $cmd" || true
done

if [ "$MODE" = "prod" ]; then
    echo "→ 6b  config:cache (solo prod)"
    docker compose exec -T $FPM sh -c "cd /var/www/html && CACHE_DRIVER=file php artisan config:cache" || true
fi

echo "→ 7/8 purgar OPcache (sin reiniciar fpm)"
docker compose exec -T $FPM sh -c "kill -USR2 1" || true

echo "→ 8/8 reiniciar colas"
docker compose exec -T $SUPERVISOR supervisorctl restart all 2>/dev/null || \
    echo "  (supervisor no está activo — OK en dev)"

# Auto-start (WSL2 only)
if grep -qi microsoft /proc/version 2>/dev/null && [ ! -f /etc/systemd/system/pro8-autostart.service ]; then
    AUTOSTART_URL="https://raw.githubusercontent.com/gians96/codeplant/master/facturador-pro/install/windows-server/enable-autostart.sh"
    if curl -fsSL -o /tmp/enable-autostart.sh "$AUTOSTART_URL" 2>/dev/null; then
        echo ""
        echo "⚙️  Configurando arranque automatico del stack (requiere sudo)..."
        sudo SUDO_USER="${USER}" bash /tmp/enable-autostart.sh || \
            echo "   ⚠ No se pudo activar auto-start. Ejecuta manualmente: sudo bash /tmp/enable-autostart.sh"
    fi
fi

echo ""
echo "✓ Actualización completada."
echo ""
echo "Prueba con:"
echo "  curl -I http://localhost:8080/api/offline/business-turns"
