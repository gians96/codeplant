#!/bin/bash
#
# pro8-prod-restart.sh — Recrea el stack de produccion completo en WSL2
# para forzar que los bind mounts se re-resuelvan contra el filesystem actual.
#
# Caso de uso: tras reiniciar Windows, Docker Desktop puede levantar los
# contenedores (restart: always) ANTES de que WSL termine de montar $HOME,
# dejando /var/www/html vacio dentro de nginx → 502/404 en todos los dominios.
#
# Este script hace, en orden:
#   1. Verifica que $HOME/proyectos exista y tenga contenido.
#   2. `down` de cada proyecto encontrado en $HOME/proyectos/<dominio>.
#   3. `down` del proxy.
#   4. `up -d` del proxy (primero — crea la red proxynet).
#   5. `up -d` de cada proyecto.
#   6. Verifica que nginx de cada proyecto vea /var/www/html/public/index.php.
#
# Uso: pro8up   (si tienes el alias en ~/.bashrc)
#      o: bash ~/proyectos/pro8-prod-restart.sh
#

set -e

ROOT="$HOME/proyectos"
PROXY_DIR="$ROOT/proxy"

wait_for_docker() {
    echo "→ Esperando Docker..."
    for i in $(seq 1 60); do
        if docker info >/dev/null 2>&1; then
            echo "✓ Docker responde"
            return 0
        fi
        echo "  Docker aun no responde ($i/60)"
        sleep 5
    done

    echo "ERROR: Docker no respondio en 5 minutos."
    exit 1
}

wait_for_root() {
    echo "→ Verificando filesystem de WSL..."
    for i in $(seq 1 30); do
        if [ -d "$ROOT" ]; then
            echo "✓ $ROOT accesible"
            return 0
        fi
        echo "  Esperando $ROOT ($i/30)"
        sleep 2
    done

    echo "ERROR: $ROOT no existe."
    echo "El filesystem de WSL puede no estar listo todavia. Espera unos segundos y reintenta."
    exit 1
}

compose_service() {
    local project_dir="$1"
    local prefix="$2"
    (cd "$project_dir" && docker compose config --services | grep -E "^${prefix}_[0-9]+$" | head -1)
}

wait_for_project_mount() {
    local proj="$1"
    local project_dir="$ROOT/$proj"
    local fpm_service
    local probe_image

    fpm_service=$(compose_service "$project_dir" "fpm")
    if [ -z "$fpm_service" ]; then
        echo "ERROR: no se encontro servicio fpm_* en $project_dir/docker-compose.yml"
        exit 1
    fi
    probe_image=$(cd "$project_dir" && docker compose images -q "$fpm_service" 2>/dev/null | head -1)
    if [ -z "$probe_image" ]; then
        probe_image="rash07/php-fpm:8.2"
    fi

    echo "→ Verificando bind mount Docker para $proj..."
    for i in $(seq 1 30); do
        if docker run --rm -v "$project_dir:/probe:ro" --entrypoint sh "$probe_image" -c 'test -f /probe/public/index.php && test -f /probe/artisan' >/dev/null 2>&1; then
            echo "✓ Docker puede montar $proj"
            return 0
        fi
        echo "  Docker todavía no ve $proj montado ($i/30)"
        sleep 2
    done

    echo "ERROR: Docker no pudo montar $project_dir dentro de /var/www/html."
    exit 1
}

wait_for_health() {
    local container="$1"
    local label="$2"

    echo "→ Esperando $label healthy..."
    for i in $(seq 1 30); do
        status=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}no-healthcheck{{end}}' "$container" 2>/dev/null || echo "missing")
        if [ "$status" = "healthy" ]; then
            echo "✓ $label healthy"
            return 0
        fi
        echo "  $label estado: $status ($i/30)"
        sleep 2
    done

    echo "✗ $label no llego a healthy. Revisa: docker logs $container --tail 80"
    return 1
}

ensure_supervisor() {
    local container="$1"
    local label="$2"

    echo "→ Verificando supervisor de $label..."
    docker exec "$container" sh -c "service supervisor start >/dev/null 2>&1 || true; supervisorctl reread >/dev/null 2>&1 || true; supervisorctl update >/dev/null 2>&1 || true; supervisorctl start all >/dev/null 2>&1 || true" >/dev/null 2>&1 || true
    for i in $(seq 1 20); do
        if docker exec "$container" sh -c "test -f /var/www/html/artisan && supervisorctl status | grep -Eq 'laravel-worker.*RUNNING'" >/dev/null 2>&1; then
            echo "✓ $label supervisor RUNNING"
            return 0
        fi
        sleep 2
    done

    echo "✗ $label supervisor sin workers RUNNING"
    docker exec "$container" supervisorctl status 2>/dev/null || true
    return 1
}

ensure_scheduler() {
    local container="$1"
    local label="$2"

    echo "→ Verificando scheduler de $label..."
    for i in $(seq 1 20); do
        if docker exec "$container" sh -c "test -f /var/www/html/artisan && ps aux | grep -Eq '[c]ron|[c]rond|schedule:(work|run)'" >/dev/null 2>&1; then
            echo "✓ $label scheduler activo"
            return 0
        fi
        sleep 2
    done

    echo "✗ $label scheduler no parece activo"
    docker exec "$container" ps aux 2>/dev/null || true
    return 1
}

# ─── 1. Verificar filesystem ──────────────────────────────────
wait_for_docker
wait_for_root

# ─── 2. Listar proyectos (carpetas con docker-compose.yml) ───
PROJECTS=()
for d in "$ROOT"/*/; do
    name=$(basename "$d")
    # Excluir proxy, certs, y cualquier carpeta sin compose
    if [ "$name" = "proxy" ] || [ "$name" = "certs" ]; then
        continue
    fi
    if [ -f "$d/docker-compose.yml" ] && [ -f "$d/public/index.php" ]; then
        PROJECTS+=("$name")
    fi
done

if [ ${#PROJECTS[@]} -eq 0 ]; then
    echo "ADVERTENCIA: no se encontraron proyectos en $ROOT"
    echo "Esperaba carpetas como $ROOT/mi-empresa.com/ con docker-compose.yml"
fi

echo "Proyectos detectados: ${PROJECTS[*]:-<ninguno>}"

for proj in "${PROJECTS[@]}"; do
    wait_for_project_mount "$proj"
done

# ─── 3. Down de todo ──────────────────────────────────────────
for proj in "${PROJECTS[@]}"; do
    echo "→ Deteniendo $proj ..."
    (cd "$ROOT/$proj" && docker compose down 2>/dev/null) || true
done

if [ -f "$PROXY_DIR/docker-compose.yml" ]; then
    echo "→ Deteniendo proxy ..."
    (cd "$PROXY_DIR" && docker compose down 2>/dev/null) || true
fi

# ─── 4. Up del proxy primero (crea la red proxynet) ──────────
if [ -f "$PROXY_DIR/docker-compose.yml" ]; then
    echo "→ Levantando proxy ..."
    (cd "$PROXY_DIR" && docker compose up -d)
fi

# ─── 5. Up de cada proyecto ──────────────────────────────────
for proj in "${PROJECTS[@]}"; do
    echo "→ Levantando $proj ..."
    (cd "$ROOT/$proj" && docker compose up -d)
done

# ─── 6. Esperar fpm healthy y validar servicios ──────────────
echo ""
echo "Esperando que los contenedores esten listos..."

EXIT_CODE=0
for proj in "${PROJECTS[@]}"; do
    DIR_MOD=$(echo "$proj" | sed 's/\./_/g')
    NGINX="nginx_${DIR_MOD}"
    FPM="fpm_${DIR_MOD}"
    SUPERVISOR="supervisor_${DIR_MOD}"
    SCHEDULING="scheduling_${DIR_MOD}"

    wait_for_health "$FPM" "$proj/fpm" || EXIT_CODE=1

    if docker exec "$NGINX" test -f /var/www/html/public/index.php 2>/dev/null; then
        echo "✓ $proj — nginx ve /var/www/html/public/index.php"
    else
        echo "✗ $proj — nginx NO ve el webroot (bind mount vacio)"
        EXIT_CODE=1
    fi

    ensure_supervisor "$SUPERVISOR" "$proj" || EXIT_CODE=1
    ensure_scheduler "$SCHEDULING" "$proj" || EXIT_CODE=1
done

echo ""
if [ $EXIT_CODE -eq 0 ] && [ ${#PROJECTS[@]} -gt 0 ]; then
    echo "✓ Todos los proyectos estan sirviendo correctamente."
else
    if [ $EXIT_CODE -ne 0 ]; then
        echo "✗ Alguno de los proyectos tiene bind mount vacio. Revisa:"
        echo "   docker exec <nginx_container> ls /var/www/html/"
    fi
fi

exit $EXIT_CODE
