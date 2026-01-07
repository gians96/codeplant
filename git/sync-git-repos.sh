#!/bin/bash

# ================================================================
# SCRIPT DE SINCRONIZACIÓN INCREMENTAL DE REPOSITORIOS GIT
# Envía solo commits nuevos, no todo el historial
# ================================================================

# Configuración
REPO_DIR="/var/script_git/pro7-sync"
LOG_FILE="/var/script_git/log/git-sync.log"
BACKUP_DIR="/var/script_git/backups"
PROTECTED_BRANCHES="gians96"
SKIP_BRANCHES_GITLAB="Pro8 v7.2"  # Ramas con archivos >100MB que GitLab rechaza (pero sí van a Bitbucket)

# CONFIGURACIÓN DE COMMITS BASE PARA RAMAS CLEAN
# Último commit de cada rama que ya existe en GitLab (para evitar enviar historial completo)
V7_2_BASE_COMMIT="aa0e0ec59649b1277fb6101c09c966fe7d4e562f"   # Último commit de v7.2 sincronizado en GitLab (29 dic 2025)
PRO8_BASE_COMMIT="SKIP"  # SKIP = No procesar Pro8 (demasiado pesado, 768 commits)

# CONFIGURACIÓN DE RAMAS ACTIVAS
# Solo sincronizar ramas con commits en los últimos X días
DAYS_ACTIVE=30  # 1 mes (ajustar según necesidad: 30=1mes, 60=2meses, 180=6meses)
DELETE_STALE_BRANCHES=false  # true para eliminar ramas inactivas del destino

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
ORIGEN_USER="gg"
ORIGEN_PASS="pasword"
ORIGEN_USER_ENC=$(urlencode "$ORIGEN_USER")
ORIGEN_PASS_ENC=$(urlencode "$ORIGEN_PASS")
ORIGEN="https://${ORIGEN_USER_ENC}:${ORIGEN_PASS_ENC}@git.buho.la/facturaloperu/facturador/pro7.git"

# Credenciales DESTINO GITLAB
GITLAB_USER="gg"
GITLAB_TOKEN="pasword#"
GITLAB_USER_ENC=$(urlencode "$GITLAB_USER")
GITLAB_TOKEN_ENC=$(urlencode "$GITLAB_TOKEN")
DESTINO_GITLAB="https://${GITLAB_USER_ENC}:${GITLAB_TOKEN_ENC}@gitlab.com/gians96/pro-7.git"

# BITBUCKET DESHABILITADO - Requiere plan de pago
# Usando solo GitLab FREE (omite ramas >100MB)

# Crear directorios necesarios
mkdir -p "$(dirname "$REPO_DIR")"
mkdir -p "$(dirname "$LOG_FILE")"
mkdir -p "$BACKUP_DIR"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] ============================================" >> "$LOG_FILE"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Iniciando sincronización INCREMENTAL..." >> "$LOG_FILE"

# ================================================================
# CAMBIO CLAVE: Usar clone normal, NO --mirror
# ================================================================
if [ ! -d "$REPO_DIR" ]; then
    echo "Clonando repositorio por primera vez (clone normal)..." >> "$LOG_FILE"
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
# SINCRONIZACIÓN INCREMENTAL: Solo traer cambios nuevos
# ================================================================
echo "Obteniendo cambios nuevos del origen..." >> "$LOG_FILE"
git fetch origin --prune >> "$LOG_FILE" 2>&1

if [ $? -ne 0 ]; then
    echo "ERROR: Falló el fetch del origen" >> "$LOG_FILE"
    exit 1
fi

# Obtener información de GitLab
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
SKIPPED_COUNT=0
FAILED_COUNT=0
STALE_COUNT=0

echo "Iniciando sincronización de ramas..." >> "$LOG_FILE"
echo "Configuración: Solo ramas con actividad en últimos $DAYS_ACTIVE días" >> "$LOG_FILE"

# Función para verificar si una rama está activa
is_branch_active() {
    local branch=$1
    local last_commit_date=$(git log -1 --format=%ct "origin/$branch" 2>/dev/null)

    if [ -z "$last_commit_date" ]; then
        return 1  # No se pudo obtener fecha
    fi

    local current_date=$(date +%s)
    local days_diff=$(( (current_date - last_commit_date) / 86400 ))

    if [ $days_diff -le $DAYS_ACTIVE ]; then
        return 0  # Activa
    else
        return 1  # Inactiva
    fi
}

# ================================================================
# SINCRONIZAR CADA RAMA INCREMENTALMENTE
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

    # Verificar si es rama con archivos grandes
    skip_gitlab=false
    for skipped in $SKIP_BRANCHES_GITLAB; do
        if [ "$branch" = "$skipped" ]; then
            skip_gitlab=true
            break
        fi
    done
    
    # Si tiene archivos grandes, crear rama limpia (-clean)
    if [ "$skip_gitlab" = true ]; then
        echo "  → Rama $branch tiene archivos >100MB, creando versión limpia..." >> "$LOG_FILE"
        
        CLEAN_BRANCH="${branch}-clean"
        
        # Verificar si la rama clean ya existe en GitLab (para ser incremental)
        git fetch gitlab "$CLEAN_BRANCH" >> "$LOG_FILE" 2>&1
        CLEAN_EXISTS=$(git rev-parse --verify "gitlab/$CLEAN_BRANCH" 2>/dev/null)
        
        # Rama de seguimiento local para registrar el último commit procesado de origin/$branch
        TRACKING_REF="refs/heads/${CLEAN_BRANCH}-tracking"
        
        if [ -n "$CLEAN_EXISTS" ]; then
            # Rama clean ya existe - modo incremental
            echo "    → Rama $CLEAN_BRANCH ya existe, actualizando incrementalmente..." >> "$LOG_FILE"
            git checkout "$CLEAN_BRANCH" >> "$LOG_FILE" 2>&1 || git checkout -b "$CLEAN_BRANCH" "gitlab/$CLEAN_BRANCH" >> "$LOG_FILE" 2>&1
            git reset --hard "gitlab/$CLEAN_BRANCH" >> "$LOG_FILE" 2>&1
            
            # Obtener el último commit de origin/$branch que ya fue procesado
            LAST_PROCESSED=$(git rev-parse "$TRACKING_REF" 2>/dev/null)
            
            if [ -z "$LAST_PROCESSED" ]; then
                echo "    ⚠ No se encontró tracking ref, usando commit base" >> "$LOG_FILE"
                if [ "$branch" = "v7.2" ] && [ -n "$V7_2_BASE_COMMIT" ]; then
                    LAST_PROCESSED="$V7_2_BASE_COMMIT"
                elif [ "$branch" = "Pro8" ] && [ -n "$PRO8_BASE_COMMIT" ]; then
                    LAST_PROCESSED="$PRO8_BASE_COMMIT"
                else
                    # Si no hay referencia, obtener el primer commit de la rama
                    LAST_PROCESSED=$(git rev-list --max-parents=0 "origin/$branch" 2>/dev/null | head -1)
                fi
            fi
            
            # Obtener lista de commits NUEVOS desde el último procesado
            NEW_COMMITS=$(git rev-list --reverse "${LAST_PROCESSED}..origin/$branch" 2>/dev/null)
            
            # Contar commits de forma robusta
            if [ -z "$NEW_COMMITS" ]; then
                COMMIT_COUNT=0
            else
                COMMIT_COUNT=$(echo "$NEW_COMMITS" | wc -l | tr -d ' ')
            fi
            
            if [ "$COMMIT_COUNT" -eq 0 ]; then
                echo "    ℹ No hay commits nuevos para procesar (último: ${LAST_PROCESSED:0:8})" >> "$LOG_FILE"
                SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
                continue
            fi
            
            echo "    → Procesando $COMMIT_COUNT commits nuevos desde ${LAST_PROCESSED:0:8}..." >> "$LOG_FILE"
        else
            # Primera vez - determinar commit base
            echo "    → Creando rama $CLEAN_BRANCH por primera vez..." >> "$LOG_FILE"
            
            BASE_COMMIT=""
            if [ "$branch" = "v7.2" ] && [ -n "$V7_2_BASE_COMMIT" ]; then
                BASE_COMMIT="$V7_2_BASE_COMMIT"
            elif [ "$branch" = "Pro8" ] && [ -n "$PRO8_BASE_COMMIT" ]; then
                if [ "$PRO8_BASE_COMMIT" = "SKIP" ]; then
                    echo "    ℹ Pro8 configurado para SKIP - omitiendo procesamiento" >> "$LOG_FILE"
                    SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
                    continue
                fi
                BASE_COMMIT="$PRO8_BASE_COMMIT"
            fi
            
            if [ -n "$BASE_COMMIT" ]; then
                echo "    → Iniciando desde commit base: $BASE_COMMIT" >> "$LOG_FILE"
                git checkout -b "$CLEAN_BRANCH" "$BASE_COMMIT" >> "$LOG_FILE" 2>&1 || {
                    echo "    ✗ ERROR al crear rama desde $BASE_COMMIT" >> "$LOG_FILE"
                    FAILED_COUNT=$((FAILED_COUNT + 1))
                    git checkout main 2>/dev/null
                    continue
                }
                NEW_COMMITS=$(git rev-list --reverse "$BASE_COMMIT..origin/$branch" 2>/dev/null)
            else
                echo "    → Iniciando desde el primer commit de $branch" >> "$LOG_FILE"
                git checkout --orphan "$CLEAN_BRANCH" >> "$LOG_FILE" 2>&1
                git rm -rf . >> "$LOG_FILE" 2>&1 || true
                NEW_COMMITS=$(git rev-list --reverse "origin/$branch" 2>/dev/null)
            fi
            
            # Contar commits de forma robusta
            if [ -z "$NEW_COMMITS" ]; then
                COMMIT_COUNT=0
            else
                COMMIT_COUNT=$(echo "$NEW_COMMITS" | wc -l | tr -d ' ')
            fi
            echo "    → Procesando $COMMIT_COUNT commits..." >> "$LOG_FILE"
        fi
        
        # Cherry-pick cada commit eliminando archivos .map
        PROCESSED=0
        FAILED_CHERRIES=0
        
        for commit in $NEW_COMMITS; do
            COMMIT_MSG=$(git log -1 --format="%s" "$commit")
            COMMIT_AUTHOR=$(git log -1 --format="%an <%ae>" "$commit")
            COMMIT_DATE=$(git log -1 --format="%ad" "$commit")
            
            echo "    → Cherry-picking: $commit - $COMMIT_MSG" >> "$LOG_FILE"
            
            # Cherry-pick sin commitear
            git cherry-pick --no-commit "$commit" >> "$LOG_FILE" 2>&1
            
            if [ $? -ne 0 ]; then
                # Si falla el cherry-pick (conflictos), intentar resolverlos
                echo "    ⚠ Conflictos detectados, resolviendo..." >> "$LOG_FILE"
                git add -A >> "$LOG_FILE" 2>&1
            fi
            
            # Eliminar archivos .map del staging
            git rm -r --cached "**/*.map" >> "$LOG_FILE" 2>&1 || true
            git rm -r --cached "*.map" >> "$LOG_FILE" 2>&1 || true
            find . -name "*.map" -type f -delete 2>/dev/null || true
            
            # Commitear con el mensaje y autor original
            git add -A >> "$LOG_FILE" 2>&1
            
            if ! git diff --cached --quiet; then
                git commit --author="$COMMIT_AUTHOR" --date="$COMMIT_DATE" -m "$COMMIT_MSG" >> "$LOG_FILE" 2>&1
                
                if [ $? -eq 0 ]; then
                    PROCESSED=$((PROCESSED + 1))
                else
                    echo "    ✗ ERROR al commitear $commit" >> "$LOG_FILE"
                    FAILED_CHERRIES=$((FAILED_CHERRIES + 1))
                fi
            else
                # Commit vacío (solo tenía archivos .map)
                echo "    ℹ Commit $commit solo contenía archivos .map, omitiendo" >> "$LOG_FILE"
            fi
        done
        
        echo "    ✓ Procesados $PROCESSED commits ($FAILED_CHERRIES fallos)" >> "$LOG_FILE"
        
        if [ $FAILED_CHERRIES -gt 0 ]; then
            FAILED_COUNT=$((FAILED_COUNT + 1))
        fi
        
        # Actualizar la referencia de tracking con el último commit procesado de origin/$branch
        LATEST_ORIGIN_COMMIT=$(git rev-parse "origin/$branch" 2>/dev/null)
        if [ -n "$LATEST_ORIGIN_COMMIT" ]; then
            git update-ref "$TRACKING_REF" "$LATEST_ORIGIN_COMMIT" >> "$LOG_FILE" 2>&1
            echo "    ✓ Actualizada tracking ref a ${LATEST_ORIGIN_COMMIT:0:8}" >> "$LOG_FILE"
        fi
        
        # Pushear rama limpia a GitLab
        echo "    → Sincronizando $CLEAN_BRANCH a GitLab..." >> "$LOG_FILE"
        git push gitlab "$CLEAN_BRANCH" --force >> "$LOG_FILE" 2>&1
        
        if [ $? -eq 0 ]; then
            echo "    ✓ Rama limpia $CLEAN_BRANCH sincronizada a GitLab" >> "$LOG_FILE"
            SYNCED_COUNT=$((SYNCED_COUNT + 1))
        else
            echo "    ✗ ERROR sincronizando $CLEAN_BRANCH" >> "$LOG_FILE"
            FAILED_COUNT=$((FAILED_COUNT + 1))
        fi
        
        # Volver a la rama original
        git checkout "$branch" >> "$LOG_FILE" 2>&1
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        continue
    fi

    # Verificar si la rama está activa
    if ! is_branch_active "$branch"; then
        last_commit=$(git log -1 --format="%ci" "origin/$branch" 2>/dev/null | cut -d' ' -f1)
        days_ago=$(git log -1 --format=%ct "origin/$branch" 2>/dev/null)
        if [ ! -z "$days_ago" ]; then
            days_ago=$(( ($(date +%s) - days_ago) / 86400 ))
            echo "  ⏸ Rama inactiva: $branch (último commit: $last_commit, hace $days_ago días)" >> "$LOG_FILE"
        else
            echo "  ⏸ Rama inactiva: $branch (sin commits recientes)" >> "$LOG_FILE"
        fi

        # Opcionalmente eliminar rama inactiva de GitLab
        if [ "$DELETE_STALE_BRANCHES" = true ]; then
            if git ls-remote --exit-code --heads gitlab "$branch" > /dev/null 2>&1; then
                echo "    → Eliminando rama inactiva de GitLab..." >> "$LOG_FILE"
                git push gitlab --delete "$branch" >> "$LOG_FILE" 2>&1
            fi
        fi

        STALE_COUNT=$((STALE_COUNT + 1))
        continue
    fi

    echo "  → Procesando rama: $branch" >> "$LOG_FILE"

    # Limpiar working directory antes de cambiar de rama
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

    # ================================================================
    # PUSH A GITLAB (omitiendo ramas con archivos >100MB)
    # ================================================================
    if [ "$skip_gitlab" = false ]; then
        echo "    → Sincronizando a GitLab..." >> "$LOG_FILE"
        COMMITS_BEHIND_GITLAB=$(git rev-list --count "gitlab/$branch..HEAD" 2>/dev/null || echo "new")

        if [ "$COMMITS_BEHIND_GITLAB" = "new" ]; then
            echo "      ℹ Rama nueva en GitLab, enviando historial completo..." >> "$LOG_FILE"
        elif [ "$COMMITS_BEHIND_GITLAB" = "0" ]; then
            echo "      ✓ GitLab ya está actualizado" >> "$LOG_FILE"
            SYNCED_COUNT=$((SYNCED_COUNT + 1))
        else
            echo "      ℹ Enviando $COMMITS_BEHIND_GITLAB commits nuevos a GitLab..." >> "$LOG_FILE"
        fi

        if [ "$COMMITS_BEHIND_GITLAB" != "0" ]; then
            git push gitlab "$branch" >> "$LOG_FILE" 2>&1

            if [ $? -eq 0 ]; then
                echo "      ✓ Rama $branch sincronizada correctamente" >> "$LOG_FILE"
                SYNCED_COUNT=$((SYNCED_COUNT + 1))
            else
                echo "      ✗ ERROR sincronizando rama $branch" >> "$LOG_FILE"
                FAILED_COUNT=$((FAILED_COUNT + 1))
            fi
        fi
    else
        echo "    ⊘ Omitiendo GitLab para rama $branch (archivos >100MB)" >> "$LOG_FILE"
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
    fi

    # BITBUCKET deshabilitado (requiere plan de pago)
done

# Sincronizar tags a GitLab
echo "Sincronizando tags a GitLab..." >> "$LOG_FILE"
git push gitlab --tags >> "$LOG_FILE" 2>&1
if [ $? -eq 0 ]; then
    echo "  ✓ Tags sincronizados correctamente" >> "$LOG_FILE"
else
    echo "  ⚠ Algunos tags no se pudieron sincronizar" >> "$LOG_FILE"
fi

# Resumen final
echo "" >> "$LOG_FILE"
echo "============================================" >> "$LOG_FILE"
echo "RESUMEN DE SINCRONIZACIÓN A GITLAB:" >> "$LOG_FILE"
echo "  • Ramas sincronizadas: $SYNCED_COUNT" >> "$LOG_FILE"
echo "  • Ramas con versión limpia creada: $SKIPPED_COUNT (v7.2-clean, Pro8-clean)" >> "$LOG_FILE"
echo "  • Ramas protegidas (saltadas): $(echo $PROTECTED_BRANCHES | wc -w)" >> "$LOG_FILE"
echo "  • Ramas inactivas (>$DAYS_ACTIVE días): $STALE_COUNT" >> "$LOG_FILE"
echo "  • Errores totales: $FAILED_COUNT" >> "$LOG_FILE"
echo "  • NOTA: Pro8 y v7.2 no sincronizadas (archivos >100MB)" >> "$LOG_FILE"
echo "============================================" >> "$LOG_FILE"

if [ $FAILED_COUNT -eq 0 ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Sincronización completada exitosamente" >> "$LOG_FILE"
    exit 0
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Sincronización completada con $FAILED_COUNT errores" >> "$LOG_FILE"
    echo "NOTA: Si los errores son por límite de almacenamiento, es necesario:" >> "$LOG_FILE"
    echo "  1. Aumentar el límite en GitLab (plan premium/ultimate)" >> "$LOG_FILE"
    echo "  2. O limpiar el repositorio destino con: git reflog expire y git gc" >> "$LOG_FILE"
    exit 1
fi
