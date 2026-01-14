#!/bin/bash

# ================================================================
# SCRIPT DE SINCRONIZACIÓN INCREMENTAL DE REPOSITORIOS GIT - PRO8
# Con limpieza automática de archivos grandes >100MB
# ================================================================

# Configuración
REPO_DIR="/var/script_git/pro8/pro8-sync"
LOG_FILE="/var/script_git/pro8/log/git-sync.log"
BACKUP_DIR="/var/script_git/pro8/backups"
PROTECTED_BRANCHES="gians96"

# NUEVO: Límite de tamaño de archivo para GitLab Free
MAX_FILE_SIZE_MB=100
MAX_FILE_SIZE_BYTES=$((MAX_FILE_SIZE_MB * 1024 * 1024))

# CONFIGURACIÓN DE RAMAS ACTIVAS
DAYS_ACTIVE=30
DELETE_STALE_BRANCHES=false

# Función para URL-encode
urlencode() {
    local string="${1}"
    local strlen=${#string}
    local encoded=""
    local pos c o

    for (( pos=0 ; pos<strlen ; pos++ )); do
        c=${string:$pos:1}
        case "$c" in
            [-_.~a-zA-Z0-9] ) o="${c}" ;;
            * ) printf -v o '%%%02x' "'$c"
        esac
        encoded+="${o}"
    done
    echo "${encoded}"
}

# Credenciales ORIGEN
ORIGEN_USER="gians96@gmail.com"
ORIGEN_PASS="76251607GG#"
ORIGEN_USER_ENC=$(urlencode "$ORIGEN_USER")
ORIGEN_PASS_ENC=$(urlencode "$ORIGEN_PASS")
ORIGEN="https://${ORIGEN_USER_ENC}:${ORIGEN_PASS_ENC}@git.buho.la/facturaloperu/facturador/pro8.git"

# Credenciales DESTINO GITLAB
GITLAB_USER="gians96@gmail.com"
GITLAB_TOKEN="Gianmarcos96GG#"
GITLAB_USER_ENC=$(urlencode "$GITLAB_USER")
GITLAB_TOKEN_ENC=$(urlencode "$GITLAB_TOKEN")
DESTINO_GITLAB="https://${GITLAB_USER_ENC}:${GITLAB_TOKEN_ENC}@gitlab.com/gians96/pro-8.git"

# Crear directorios necesarios
mkdir -p "$(dirname "$REPO_DIR")"
mkdir -p "$(dirname "$LOG_FILE")"
mkdir -p "$BACKUP_DIR"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] ============================================" >> "$LOG_FILE"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Iniciando sincronización PRO8 con limpieza automática..." >> "$LOG_FILE"

# ================================================================
# FUNCIÓN: Verificar si una rama tiene archivos grandes
# ================================================================
has_large_files() {
    local branch=$1
    echo "    → Verificando archivos grandes en $branch..." >> "$LOG_FILE"
    
    # Buscar archivos >100MB en el historial de la rama
    local large_files=$(git rev-list --objects --all "$branch" 2>/dev/null | \
        git cat-file --batch-check='%(objecttype) %(objectname) %(objectsize) %(rest)' | \
        awk -v limit=$MAX_FILE_SIZE_BYTES '$1 == "blob" && $3 > limit {print $4, $3}')
    
    if [ -n "$large_files" ]; then
        echo "    ⚠ Archivos grandes encontrados:" >> "$LOG_FILE"
        echo "$large_files" | while read file size; do
            size_mb=$(echo "scale=2; $size / 1048576" | bc)
            echo "      - $file ($size_mb MiB)" >> "$LOG_FILE"
        done
        return 0  # Tiene archivos grandes
    else
        echo "    ✓ No se encontraron archivos >${MAX_FILE_SIZE_MB}MB" >> "$LOG_FILE"
        return 1  # No tiene archivos grandes
    fi
}

# ================================================================
# FUNCIÓN: Limpiar archivos grandes de una rama
# ================================================================
clean_branch() {
    local source_branch=$1
    local clean_branch="${source_branch}-clean"
    
    echo "  → Creando rama limpia: $clean_branch desde $source_branch" >> "$LOG_FILE"
    
    # Crear backup antes de modificar
    local backup_file="$BACKUP_DIR/backup-${source_branch}-$(date '+%Y%m%d_%H%M%S').bundle"
    echo "    → Creando backup: $backup_file" >> "$LOG_FILE"
    git bundle create "$backup_file" "$source_branch" >> "$LOG_FILE" 2>&1
    
    # Verificar si la rama clean ya existe localmente
    if git show-ref --verify --quiet "refs/heads/$clean_branch"; then
        echo "    → Rama $clean_branch ya existe localmente, actualizando..." >> "$LOG_FILE"
        git checkout "$clean_branch" >> "$LOG_FILE" 2>&1
    else
        echo "    → Creando nueva rama $clean_branch desde $source_branch..." >> "$LOG_FILE"
        git checkout -b "$clean_branch" "$source_branch" >> "$LOG_FILE" 2>&1
    fi
    
    if [ $? -ne 0 ]; then
        echo "    ✗ ERROR al crear/cambiar a rama $clean_branch" >> "$LOG_FILE"
        return 1
    fi
    
    # Instalar git-filter-repo si no está disponible
    USE_FILTER_REPO=false
    if ! command -v git-filter-repo &> /dev/null; then
        echo "    → Intentando instalar git-filter-repo via apt..." >> "$LOG_FILE"
        apt-get install -y git-filter-repo >> "$LOG_FILE" 2>&1
        
        if command -v git-filter-repo &> /dev/null; then
            USE_FILTER_REPO=true
            echo "    ✓ git-filter-repo instalado correctamente" >> "$LOG_FILE"
        else
            echo "    ⚠ git-filter-repo no disponible, usando git filter-branch" >> "$LOG_FILE"
            USE_FILTER_REPO=false
        fi
    else
        USE_FILTER_REPO=true
    fi
    
    # Hacer stash de cambios locales si existen
    git stash >> "$LOG_FILE" 2>&1
    
    # Método 1: Eliminar archivos específicos grandes usando filter-branch
    # (más lento pero funciona sin dependencias adicionales)
    echo "    → Eliminando archivos grandes del historial..." >> "$LOG_FILE"
    
    # Identificar archivos grandes específicos
    local large_files_list=$(git rev-list --objects --all | \
        git cat-file --batch-check='%(objecttype) %(objectname) %(objectsize) %(rest)' | \
        awk -v limit=$MAX_FILE_SIZE_BYTES '$1 == "blob" && $3 > limit {print $4}' | \
        sort -u)
    
    if [ -z "$large_files_list" ]; then
        echo "    ℹ No se encontraron archivos grandes" >> "$LOG_FILE"
        return 0
    fi
    
    # Mostrar archivos a eliminar
    echo "    → Archivos a eliminar del historial:" >> "$LOG_FILE"
    echo "$large_files_list" | while read file; do
        echo "      - $file" >> "$LOG_FILE"
    done
    
    # Usar filter-branch para eliminar cada archivo
    echo "$large_files_list" | while IFS= read -r file; do
        if [ -n "$file" ]; then
            echo "    → Eliminando: $file" >> "$LOG_FILE"
            git filter-branch -f --index-filter "git rm --cached --ignore-unmatch '$file'" --prune-empty --tag-name-filter cat -- --all >> "$LOG_FILE" 2>&1
        fi
    done
    
    # También eliminar todos los .map por si acaso
    echo "    → Eliminando archivos .map adicionales..." >> "$LOG_FILE"
    git filter-branch -f --index-filter "git rm -r --cached --ignore-unmatch '*.map' '**/*.map'" --prune-empty --tag-name-filter cat -- --all >> "$LOG_FILE" 2>&1
    
    # Limpiar referencias y objetos huérfanos
    echo "    → Limpiando repositorio..." >> "$LOG_FILE"
    git reflog expire --expire=now --all >> "$LOG_FILE" 2>&1
    git gc --prune=now --aggressive >> "$LOG_FILE" 2>&1
    
    # Verificar tamaño final
    local repo_size=$(du -sh .git | cut -f1)
    echo "    ✓ Rama limpia creada. Tamaño del repositorio: $repo_size" >> "$LOG_FILE"
    
    return 0
}

# ================================================================
# INICIALIZAR REPOSITORIO
# ================================================================
if [ ! -d "$REPO_DIR" ]; then
    echo "Clonando repositorio por primera vez..." >> "$LOG_FILE"
    git clone "$ORIGEN" "$REPO_DIR" >> "$LOG_FILE" 2>&1

    if [ $? -ne 0 ]; then
        echo "ERROR: Falló el clone inicial" >> "$LOG_FILE"
        exit 1
    fi

    cd "$REPO_DIR" || exit 1

    # Configurar tracking de todas las ramas remotas
    for branch in $(git branch -r | grep -v '\->' | sed 's/origin\///'); do
        git branch --track "$branch" "origin/$branch" 2>/dev/null || true
    done
else
    cd "$REPO_DIR" || exit 1
fi

# Configurar remote de GitLab
git remote add gitlab "$DESTINO_GITLAB" 2>/dev/null || git remote set-url gitlab "$DESTINO_GITLAB"

# ================================================================
# SINCRONIZACIÓN INCREMENTAL
# ================================================================
echo "Obteniendo cambios nuevos del origen..." >> "$LOG_FILE"
git fetch origin --prune >> "$LOG_FILE" 2>&1

if [ $? -ne 0 ]; then
    echo "ERROR: Falló el fetch del origen" >> "$LOG_FILE"
    exit 1
fi

echo "Obteniendo información de GitLab..." >> "$LOG_FILE"
git fetch gitlab --prune >> "$LOG_FILE" 2>&1

# Obtener lista de ramas del origen
ORIGIN_BRANCHES=$(git branch -r | grep 'origin/' | grep -v 'HEAD' | sed 's|origin/||' | xargs)

if [ -z "$ORIGIN_BRANCHES" ]; then
    echo "ERROR: No se encontraron ramas en el origen" >> "$LOG_FILE"
    exit 1
fi

echo "Ramas encontradas en origen: $ORIGIN_BRANCHES" >> "$LOG_FILE"

# Contadores
SYNCED_COUNT=0
CLEANED_COUNT=0
SKIPPED_COUNT=0
FAILED_COUNT=0

# Función para verificar si una rama está activa
is_branch_active() {
    local branch=$1
    local last_commit_date=$(git log -1 --format=%ct "origin/$branch" 2>/dev/null)

    if [ -z "$last_commit_date" ]; then
        return 1
    fi

    local current_date=$(date +%s)
    local days_diff=$(( (current_date - last_commit_date) / 86400 ))

    if [ $days_diff -le $DAYS_ACTIVE ]; then
        return 0
    else
        return 1
    fi
}

# ================================================================
# SINCRONIZAR CADA RAMA
# ================================================================
for branch in $ORIGIN_BRANCHES; do
    # Verificar si es rama protegida
    is_protected=false
    for protected in $PROTECTED_BRANCHES; do
        if [ "$branch" = "$protected" ]; then
            is_protected=true
            break
        fi
    done

    if [ "$is_protected" = true ]; then
        echo "  ⊘ Saltando rama protegida: $branch" >> "$LOG_FILE"
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        continue
    fi

    # Verificar si la rama está activa
    if ! is_branch_active "$branch"; then
        last_commit=$(git log -1 --format="%ci" "origin/$branch" 2>/dev/null | cut -d' ' -f1)
        echo "  ⏸ Rama inactiva: $branch (último commit: $last_commit)" >> "$LOG_FILE"
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        continue
    fi

    echo "  → Procesando rama: $branch" >> "$LOG_FILE"

    # Limpiar working directory
    git reset --hard >> "$LOG_FILE" 2>&1
    git clean -fd >> "$LOG_FILE" 2>&1

    # Cambiar a la rama
    git checkout "$branch" >> "$LOG_FILE" 2>&1 || git checkout -b "$branch" "origin/$branch" >> "$LOG_FILE" 2>&1

    if [ $? -ne 0 ]; then
        echo "    ✗ ERROR: No se pudo cambiar a la rama $branch" >> "$LOG_FILE"
        FAILED_COUNT=$((FAILED_COUNT + 1))
        continue
    fi

    # Actualizar rama con cambios del origen
    git merge "origin/$branch" --ff-only >> "$LOG_FILE" 2>&1 || git reset --hard "origin/$branch" >> "$LOG_FILE" 2>&1

    # Verificar si tiene archivos grandes
    if has_large_files "$branch"; then
        echo "    → Rama tiene archivos >100MB, creando versión limpia..." >> "$LOG_FILE"
        
        if clean_branch "$branch"; then
            clean_branch_name="${branch}-clean"
            
            # Push de la rama limpia
            echo "    → Sincronizando $clean_branch_name a GitLab..." >> "$LOG_FILE"
            git push gitlab "$clean_branch_name" --force >> "$LOG_FILE" 2>&1
            
            if [ $? -eq 0 ]; then
                echo "    ✓ Rama limpia $clean_branch_name sincronizada" >> "$LOG_FILE"
                CLEANED_COUNT=$((CLEANED_COUNT + 1))
                SYNCED_COUNT=$((SYNCED_COUNT + 1))
            else
                echo "    ✗ ERROR sincronizando $clean_branch_name" >> "$LOG_FILE"
                FAILED_COUNT=$((FAILED_COUNT + 1))
            fi
            
            # Volver a la rama original
            git checkout "$branch" >> "$LOG_FILE" 2>&1
        else
            echo "    ✗ ERROR al limpiar rama $branch" >> "$LOG_FILE"
            FAILED_COUNT=$((FAILED_COUNT + 1))
        fi
    else
        # No tiene archivos grandes, push normal
        echo "    → Sincronizando a GitLab..." >> "$LOG_FILE"
        
        git push gitlab "$branch" >> "$LOG_FILE" 2>&1
        
        if [ $? -eq 0 ]; then
            echo "    ✓ Rama $branch sincronizada correctamente" >> "$LOG_FILE"
            SYNCED_COUNT=$((SYNCED_COUNT + 1))
        else
            echo "    ✗ ERROR sincronizando rama $branch" >> "$LOG_FILE"
            FAILED_COUNT=$((FAILED_COUNT + 1))
        fi
    fi
done

# Sincronizar tags
echo "Sincronizando tags a GitLab..." >> "$LOG_FILE"
git push gitlab --tags >> "$LOG_FILE" 2>&1

# Resumen final
echo "" >> "$LOG_FILE"
echo "============================================" >> "$LOG_FILE"
echo "RESUMEN DE SINCRONIZACIÓN PRO8:" >> "$LOG_FILE"
echo "  • Ramas sincronizadas: $SYNCED_COUNT" >> "$LOG_FILE"
echo "  • Ramas limpias creadas: $CLEANED_COUNT" >> "$LOG_FILE"
echo "  • Ramas saltadas: $SKIPPED_COUNT" >> "$LOG_FILE"
echo "  • Errores: $FAILED_COUNT" >> "$LOG_FILE"
echo "============================================" >> "$LOG_FILE"

if [ $FAILED_COUNT -eq 0 ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Sincronización completada exitosamente" >> "$LOG_FILE"
    exit 0
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Sincronización completada con $FAILED_COUNT errores" >> "$LOG_FILE"
    exit 1
fi
