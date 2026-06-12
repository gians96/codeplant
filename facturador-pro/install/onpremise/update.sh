#!/bin/bash
# =========================================================================
# update.sh - Actualizar un dominio instalado (selector multi-dominio)
# =========================================================================
# Lista los dominios instalados en el servidor, deja elegir cual actualizar y
# la rama, y ejecuta el motor scripts/onprem-update.sh del proyecto elegido:
# backup + git pull + composer + migrate/tenancy:migrate + recache + workers.
# Nunca borra volumenes.
#
# Uso (desde la carpeta raiz donde instalaste, ej. /opt/proyectos):
#   sudo ./update.sh
#   sudo ./update.sh --root /opt/proyectos
#   sudo ./update.sh --domain fe.consurtrading.org --branch master
# =========================================================================

set -e

ROOT="$(pwd)"
DOMAIN=""
BRANCH=""
EXTRA=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --root)   ROOT="$2"; shift 2 ;;
        --domain) DOMAIN="$2"; shift 2 ;;
        --branch) BRANCH="$2"; shift 2 ;;
        --skip-backup) EXTRA+=("--skip-backup"); shift ;;
        *) echo "Parametro desconocido: $1"; exit 1 ;;
    esac
done

# Si se ejecuta DENTRO de un proyecto, subir a la raiz para listar hermanos
if [ -f "$ROOT/docker-compose.yml" ] && [ -f "$ROOT/artisan" ]; then
    ROOT="$(dirname "$ROOT")"
fi

# --- Recolectar dominios instalados -------------------------------
PROJECTS=()
for d in "$ROOT"/*/; do
    dom="$(basename "$d")"
    [ "$dom" = "proxy" ] && continue
    [ -f "${d}docker-compose.yml" ] && [ -f "${d}artisan" ] && PROJECTS+=("$dom")
done

if [ ${#PROJECTS[@]} -eq 0 ]; then
    echo "ERROR: no se encontraron dominios instalados en $ROOT"
    echo "  Ejecuta este script desde la carpeta raiz de instalacion o usa --root."
    exit 1
fi

# --- Elegir dominio ------------------------------------------------
if [ -z "$DOMAIN" ]; then
    echo "Dominios instalados en $ROOT:"
    i=1
    for p in "${PROJECTS[@]}"; do echo "  [$i] $p"; i=$((i+1)); done
    read -p "Numero del dominio a actualizar: " sel
    [[ "$sel" =~ ^[0-9]+$ ]] && [ "$sel" -ge 1 ] && [ "$sel" -le ${#PROJECTS[@]} ] || { echo "Seleccion invalida."; exit 1; }
    DOMAIN="${PROJECTS[$((sel-1))]}"
fi

PROJECT_DIR="$ROOT/$DOMAIN"
if [ ! -f "$PROJECT_DIR/scripts/onprem-update.sh" ]; then
    echo "ERROR: no encuentro scripts/onprem-update.sh en $PROJECT_DIR"
    exit 1
fi

# --- Rama ----------------------------------------------------------
if [ -z "$BRANCH" ]; then
    CUR_BRANCH="$(cd "$PROJECT_DIR" && git rev-parse --abbrev-ref HEAD 2>/dev/null || echo master)"
    read -p "Rama a actualizar [$CUR_BRANCH]: " in_branch
    BRANCH="${in_branch:-$CUR_BRANCH}"
fi

echo ""
echo "-> Actualizando '$DOMAIN' (rama $BRANCH) ..."
cd "$PROJECT_DIR"
exec bash scripts/onprem-update.sh --branch "$BRANCH" "${EXTRA[@]}"
