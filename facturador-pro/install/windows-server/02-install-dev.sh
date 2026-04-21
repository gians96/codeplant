#!/bin/bash
#
# 02-install-dev.sh — Facturador Pro-8: Instalacion de desarrollo en WSL2
#
# Fase 2 del proceso de instalacion en Windows Server/Desktop.
# Ejecutar DENTRO de WSL despues de completar 01-setup-wsl.ps1
#
# Uso:
#   curl -O https://raw.githubusercontent.com/gians96/codeplant/master/facturador-pro/install/windows-server/02-install-dev.sh
#   chmod +x 02-install-dev.sh
#   ./02-install-dev.sh
#
# Clona el repo y ejecuta local-setup.sh.
# Sin proxy, sin SSL, puertos dev (8080, 3308).
#

set -e

REPO_URL="https://gitlab.com/gians96/pro-8.git"
BRANCH="master"
PROJECT_DEST="$HOME/proyectos/pro-8"

echo ""
echo "============================================"
echo "  FACTURADOR PRO-8 — Instalacion Desarrollo"
echo "  (WSL2)"
echo "============================================"
echo ""

# ─── Verificar Docker ─────────────────────────────────────────
# En WSL2 con Docker Desktop, el cliente puede heredar el contexto
# 'desktop-linux' (endpoint npipe de Windows), que rompe dentro de Linux
# con: "Failed to initialize: protocol not available" o panic del CLI.
# Fix: forzar contexto 'default' que apunta a unix:///var/run/docker.sock.
if ! docker info >/dev/null 2>&1; then
    echo "Docker no responde. Probando arreglo de contexto WSL..."
    docker context use default >/dev/null 2>&1 || true
    sleep 1
    if ! docker info >/dev/null 2>&1; then
        echo "Docker no esta corriendo. Intentando iniciar servicio nativo..."
        sudo service docker start 2>/dev/null || true
        sleep 3
        if ! docker info >/dev/null 2>&1; then
            echo "ERROR: No se pudo conectar con Docker."
            echo "  - Si usas Docker Desktop: activa WSL Integration para Ubuntu-24.04"
            echo "    (Settings > Resources > WSL Integration) y reinicia Docker Desktop."
            echo "  - Si usas Docker Engine nativo: sudo service docker start"
            echo "  - Luego en WSL: docker context use default"
            exit 1
        fi
    fi
fi
echo "Docker OK (contexto: $(docker context show 2>/dev/null || echo default))"

# ─── Instalar Bun (runtime/bundler JS) ────────────────────────
# Se usa para compilar assets con Vite (bun run build) sin depender del
# Node.js de Windows (que en WSL no funciona para node-gyp/esbuild nativos).
# Idempotente: si ya existe, se omite.
if ! command -v bun >/dev/null 2>&1 && [ ! -x "$HOME/.bun/bin/bun" ]; then
    echo "Instalando Bun..."
    # unzip es requisito del instalador oficial
    if ! command -v unzip >/dev/null 2>&1; then
        sudo apt-get update -qq && sudo apt-get install -y unzip >/dev/null
    fi
    curl -fsSL https://bun.sh/install | bash >/dev/null
    export BUN_INSTALL="$HOME/.bun"
    export PATH="$BUN_INSTALL/bin:$PATH"
    echo "Bun instalado: $(bun --version)"
else
    export PATH="$HOME/.bun/bin:$PATH"
    echo "Bun ya instalado: $(bun --version 2>/dev/null || echo 'n/d')"
fi

# ─── Rama (opcional) ──────────────────────────────────────────
read -p "Rama a clonar [$BRANCH]: " input_branch
if [ ! -z "$input_branch" ]; then
    BRANCH="$input_branch"
fi

# ─── Clonar o actualizar ─────────────────────────────────────
if [ -f "$PROJECT_DEST/artisan" ]; then
    echo "El proyecto ya existe en $PROJECT_DEST"
    read -p "Actualizar con git pull? [S/n]: " do_pull
    if [ "$do_pull" != "n" ] && [ "$do_pull" != "N" ]; then
        cd "$PROJECT_DEST"
        git pull origin $BRANCH
        echo "Proyecto actualizado"
    fi
else
    echo "Clonando $REPO_URL (rama: $BRANCH)..."
    mkdir -p "$(dirname $PROJECT_DEST)"
    git clone -b $BRANCH "$REPO_URL" "$PROJECT_DEST"
    echo "Proyecto clonado en $PROJECT_DEST"
fi

# ─── Ejecutar local-setup.sh ─────────────────────────────────
echo ""
echo "Ejecutando local-setup.sh (levanta 6 containers)..."
echo ""
cd "$PROJECT_DEST"
bash scripts/local-setup.sh

# ─── Compilar assets con Bun (Vite) ──────────────────────────
# canvas (dependencia transitiva) necesita libs nativas para compilar.
# Para evitar fallos en entornos sin build-tools, se usa --ignore-scripts.
# Luego 'bun run build' genera public/build/* requerido por el layout.
echo ""
echo "Instalando dependencias JS con Bun (--ignore-scripts)..."
cd "$PROJECT_DEST"
bun install --ignore-scripts

echo "Compilando assets (vite build)..."
bun run build || echo "ADVERTENCIA: falló el build de assets; revisa errores arriba"

# ─── Corregir permisos de storage y bootstrap/cache ──────────
# El repo ya trae la estructura de carpetas (storage/app, storage/framework/*,
# storage/logs, storage/app/tenancy/tenants, etc.) con sus .gitignore.
# El problema es que al ejecutar comandos artisan dentro del contenedor como
# root, Laravel puede crear subdirectorios (ej: storage/framework/cache/data)
# con owner root y permisos 700, pero el worker php-fpm corre como www-data
# y no puede escribir ahi. Sintomas:
#   - "file_put_contents(.../storage/framework/views/XXX.php): Permission denied"
#   - "Unable to create a directory at /var/www/html/storage/app/tenancy/tenants"
# Fix: forzar ownership a www-data y modo 775 en todo storage y bootstrap/cache.
echo ""
echo "Corrigiendo permisos de storage y bootstrap/cache..."
if docker ps --format '{{.Names}}' | grep -q '^fpm_pro8_local$'; then
    docker exec fpm_pro8_local bash -c '
        chown -R www-data:www-data /var/www/html/storage /var/www/html/bootstrap/cache &&
        chmod -R 775 /var/www/html/storage /var/www/html/bootstrap/cache &&
        find /var/www/html/storage/framework/views -type f -delete 2>/dev/null || true
    ' && echo "Permisos OK" || echo "ADVERTENCIA: no se pudo ajustar permisos"
else
    echo "ADVERTENCIA: contenedor fpm_pro8_local no esta corriendo, omito fix de permisos"
fi

# ─── Generar data-config.txt fuera del proyecto ──────────────
DATA_CONFIG="$(dirname $PROJECT_DEST)/pro-8-dev.txt"
cat << EOF > $DATA_CONFIG
============================================
DATOS DE INSTALACION (DEV) - pro-8
Generado: $(date '+%Y-%m-%d %H:%M')
============================================
Ruta del proyecto: $PROJECT_DEST
Rama: $BRANCH
URL: http://localhost:8080
----------------------------------------------
Acceso remoto a MySQL
Puerto: 3308
Host: localhost
Usuario: root
Contrasena root: secret
----------------------------------------------
Redis
Host: pro8_local_redis
Puerto: 6379
Password: null
----------------------------------------------
Contenedor FPM: pro8_local_fpm
Contenedor MariaDB: pro8_local_mariadb
Contenedor Redis: pro8_local_redis
============================================

Para entrar al proyecto:
  wsl -d Ubuntu-24.04
  cd $PROJECT_DEST

Para levantar/reiniciar:
  cd $PROJECT_DEST
  docker compose -f docker-compose.local.yml up -d
EOF
echo "Credenciales guardadas en: $DATA_CONFIG"

# Append a data-config.txt de Fase 1 si existe
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PHASE1_CONFIG="$SCRIPT_DIR/data-config.txt"
if [ -f "$PHASE1_CONFIG" ]; then
    cat << EOF >> $PHASE1_CONFIG

# ============================================
# FASE 2 — Desarrollo
# Instalado: $(date '+%Y-%m-%d %H:%M')
# ============================================
Ruta: $PROJECT_DEST
Rama: $BRANCH
URL: http://localhost:8080
MySQL: localhost:3308 (root / secret)
Credenciales completas: $DATA_CONFIG
EOF
    echo "data-config.txt (Fase 1) actualizado"
fi

echo ""
echo "============================================"
echo "  INSTALACION DEV COMPLETADA"
echo "============================================"
echo ""
echo "  Proyecto: $PROJECT_DEST"
echo "  App:      http://localhost:8080"
echo "  MySQL:    localhost:3308 (root / secret)"
echo ""
echo "  Credenciales: $DATA_CONFIG"
echo ""
echo "  Para entrar al proyecto:"
echo "    wsl"
echo "    cd $PROJECT_DEST"
echo ""
