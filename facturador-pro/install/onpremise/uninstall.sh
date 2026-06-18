#!/bin/bash
# =========================================================================
# uninstall.sh - Eliminar por completo un dominio on-premise de Pro-8
# =========================================================================
# Borra de forma SEGURA y COMPLETA un dominio instalado por install.sh:
#   - contenedores del dominio (nginx_/fpm_/mariadb_/redis_/soketi_/...)
#   - VOLUMENES del dominio (mysqldata/redisdata)  <-- lo que `rm -rf` NO borra
#   - la carpeta  $ROOT/<dominio>
#
# Esta es la UNICA forma correcta de eliminar un dominio. Borrar la carpeta y
# los contenedores a mano deja los volumenes HUERFANOS; al reinstalar el mismo
# dominio, MariaDB conserva la password vieja del volumen y aparece:
#   SQLSTATE[HY000] [1045] Access denied for user 'root'
#
# NO toca el proxy compartido, los certificados ni los demas dominios.
# Tambien sirve para limpiar restos de un dominio ya borrado a mano
# (usa --domain aunque la carpeta ya no exista).
#
# Uso (desde la carpeta raiz, ej. /opt/proyectos):
#   sudo ./uninstall.sh                                  # menu selector
#   sudo ./uninstall.sh --domain fe.consurtrading.org
#   sudo ./uninstall.sh --domain fe.consurtrading.org --with-backup
#   sudo ./uninstall.sh --domain fe.consurtrading.org --keep-folder
#   sudo ./uninstall.sh --domain fe.consurtrading.org --yes   # sin confirmacion
# =========================================================================

set -e

ROOT="$(cd "$(dirname "$0")" && pwd)"
DOMAIN=""
KEEP_FOLDER=0
WITH_BACKUP=0
ASSUME_YES=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --root)        ROOT="$2"; shift 2 ;;
        --domain)      DOMAIN="$2"; shift 2 ;;
        --keep-folder) KEEP_FOLDER=1; shift ;;
        --with-backup) WITH_BACKUP=1; shift ;;
        --yes|-y)      ASSUME_YES=1; shift ;;
        *) echo "Parametro desconocido: $1"; exit 1 ;;
    esac
done

# Si se ejecuta DENTRO de un proyecto (<dominio>/app), subir a la raiz.
if [ -f "$ROOT/docker-compose.yml" ] && [ -f "$ROOT/artisan" ]; then
    ROOT="$(cd "$ROOT/../.." && pwd)"
fi

# --- Elegir dominio ------------------------------------------------
if [ -z "$DOMAIN" ]; then
    PROJECTS=()
    for d in "$ROOT"/*/; do
        dom="$(basename "$d")"; case "$dom" in _*) continue ;; esac
        [ -f "${d}app/docker-compose.yml" ] && PROJECTS+=("$dom")
    done
    if [ ${#PROJECTS[@]} -eq 0 ]; then
        echo "No hay dominios instalados en $ROOT."
        echo "  Para limpiar restos huerfanos de un dominio borrado a mano:"
        echo "    sudo ./uninstall.sh --domain <dominio>"
        exit 0
    fi
    echo "Dominios instalados en $ROOT:"
    i=1; for p in "${PROJECTS[@]}"; do echo "  [$i] $p"; i=$((i+1)); done
    read -p "Numero del dominio a ELIMINAR: " sel
    [[ "$sel" =~ ^[0-9]+$ ]] && [ "$sel" -ge 1 ] && [ "$sel" -le ${#PROJECTS[@]} ] || { echo "Seleccion invalida."; exit 1; }
    DOMAIN="${PROJECTS[$((sel-1))]}"
fi

DIR_MODIFIED="$(echo "$DOMAIN" | sed 's/\./_/g' | tr 'A-Z' 'a-z')"
PROJECT_HOME="$ROOT/$DOMAIN"
APP_DIR="$PROJECT_HOME/app"
ENV_FILE="$APP_DIR/.env"
# Coincidencia EXACTA (sin falsos positivos de otros dominios): contenedores por
# servicio+dominio; volumenes por prefijo nuevo (DIR_MODIFIED, ej.
# ceos-facturacion_com) o legacy (carpeta normalizada por Compose, solo sin
# puntos, ej. ceos-facturacioncom).
DOMSQUASH="$(echo "$DOMAIN" | tr 'A-Z' 'a-z' | tr -d '.')"
CT_RE="^(nginx|fpm|mariadb|redis|soketi|scheduling|supervisor)_${DIR_MODIFIED}\$"
VOL_RE="^(${DIR_MODIFIED}|${DOMSQUASH})_(mysqldata|redisdata)[0-9]+\$"

# --- Inventario de lo que se eliminara -----------------------------
CTS=()
while IFS= read -r c; do [ -n "$c" ] && CTS+=("$c"); done < <(
    docker ps -a --format '{{.Names}}' 2>/dev/null | grep -E "$CT_RE" || true)

VOLS=()
while IFS= read -r v; do [ -n "$v" ] && VOLS+=("$v"); done < <(
    docker volume ls --format '{{.Name}}' 2>/dev/null | grep -E "$VOL_RE" || true)

FOLDER_NOTE=""
[ -d "$PROJECT_HOME" ] || FOLDER_NOTE=" (no existe)"

echo ""
echo "=================================================="
echo "  ELIMINAR DOMINIO: $DOMAIN"
echo "=================================================="
echo "  Carpeta:      $PROJECT_HOME$FOLDER_NOTE"
echo "  Contenedores: ${CTS[*]:-(ninguno)}"
echo "  Volumenes:    ${VOLS[*]:-(ninguno)}"
echo "  Proxy/certs y otros dominios: NO se tocan."
echo "=================================================="

if [ ${#CTS[@]} -eq 0 ] && [ ${#VOLS[@]} -eq 0 ] && [ ! -d "$PROJECT_HOME" ]; then
    echo "Nada que eliminar para '$DOMAIN'."
    exit 0
fi

echo ""
echo "  ESTO BORRA LA BASE DE DATOS (system + todos los tenants) de este dominio."
if [ "$ASSUME_YES" != "1" ]; then
    read -p "  Escribe el dominio EXACTO para confirmar: " typed
    [ "$typed" = "$DOMAIN" ] || { echo "No coincide. Cancelado."; exit 1; }
fi

# --- Backup final opcional (antes de purgar; se guarda en la raiz) -
MARIADB="mariadb_${DIR_MODIFIED}"
if [ "$WITH_BACKUP" = "1" ]; then
    if docker ps --format '{{.Names}}' | grep -q "^${MARIADB}$"; then
        ROOT_PWD="$(grep -E '^MYSQL_ROOT_PASSWORD=' "$ENV_FILE" 2>/dev/null | tail -1 | cut -d= -f2- | sed 's/^"//;s/"$//' || true)"
        if [ -n "$ROOT_PWD" ]; then
            BK="$ROOT/${DOMAIN}-backup-final-$(date +%Y%m%d-%H%M%S).sql"
            echo "-> Backup final en $BK.gz ..."
            docker exec -e MYSQL_PWD="$ROOT_PWD" "$MARIADB" \
                sh -c 'mysqldump -uroot --single-transaction --routines --triggers --events --all-databases' > "$BK" || true
            if [ -s "$BK" ]; then
                command -v gzip >/dev/null 2>&1 && gzip -f "$BK"
                echo "   OK backup creado (fuera de la carpeta del dominio, se conserva)"
            else
                echo "   ADVERTENCIA: backup vacio/omitido"; rm -f "$BK"
            fi
        else
            echo "   ADVERTENCIA: sin MYSQL_ROOT_PASSWORD en .env; backup omitido."
        fi
    else
        echo "   ADVERTENCIA: MariaDB no esta corriendo; backup omitido."
    fi
fi

# --- Purga ---------------------------------------------------------
if [ -f "$APP_DIR/docker-compose.yml" ]; then
    echo "-> docker compose down -v (contenedores + volumenes del dominio) ..."
    ( cd "$APP_DIR" && docker compose down -v --remove-orphans ) || true
fi

# Fallback por nombre: restos no gestionados por compose (incl. nombres legacy)
LEFT_CTS=()
while IFS= read -r c; do [ -n "$c" ] && LEFT_CTS+=("$c"); done < <(
    docker ps -a --format '{{.Names}}' 2>/dev/null | grep -E "$CT_RE" || true)
if [ ${#LEFT_CTS[@]} -gt 0 ]; then
    echo "-> Eliminando contenedores restantes ..."
    docker rm -f "${LEFT_CTS[@]}" >/dev/null 2>&1 || true
fi

LEFT_VOLS=()
while IFS= read -r v; do [ -n "$v" ] && LEFT_VOLS+=("$v"); done < <(
    docker volume ls --format '{{.Name}}' 2>/dev/null | grep -E "$VOL_RE" || true)
if [ ${#LEFT_VOLS[@]} -gt 0 ]; then
    echo "-> Eliminando volumenes restantes ..."
    docker volume rm "${LEFT_VOLS[@]}" >/dev/null 2>&1 || true
fi

# --- Carpeta -------------------------------------------------------
if [ "$KEEP_FOLDER" = "1" ]; then
    echo "-> Carpeta conservada (--keep-folder): $PROJECT_HOME"
elif [ -d "$PROJECT_HOME" ]; then
    echo "-> Eliminando carpeta $PROJECT_HOME ..."
    rm -rf "$PROJECT_HOME"
fi

echo ""
echo "=================================================="
echo "  OK DOMINIO ELIMINADO - $DOMAIN"
echo "=================================================="
echo "  Reinstalar limpio:  sudo ./install.sh"
echo "  (El proxy compartido y los demas dominios siguen intactos.)"
echo "=================================================="
