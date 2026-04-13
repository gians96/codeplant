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
if ! docker info >/dev/null 2>&1; then
    echo "Docker no esta corriendo. Intentando iniciar..."
    sudo service docker start
    sleep 3
    if ! docker info >/dev/null 2>&1; then
        echo "ERROR: No se pudo iniciar Docker."
        echo "Ejecuta: sudo service docker start"
        exit 1
    fi
fi
echo "Docker OK"

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

# ─── Append a data-config.txt si existe ──────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DATA_CONFIG="$SCRIPT_DIR/data-config.txt"
if [ -f "$DATA_CONFIG" ]; then
    cat << EOF >> $DATA_CONFIG

# ============================================
# FASE 2 — Desarrollo
# Instalado: $(date '+%Y-%m-%d %H:%M')
# ============================================
Ruta: $PROJECT_DEST
Rama: $BRANCH
URL: http://localhost:8080
MySQL: localhost:3308 (root / secret)
EOF
    echo "data-config.txt actualizado"
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
echo "  Para entrar al proyecto:"
echo "    wsl"
echo "    cd $PROJECT_DEST"
echo ""
