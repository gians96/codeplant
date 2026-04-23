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

# ─── 1. Verificar filesystem ──────────────────────────────────
if [ ! -d "$ROOT" ]; then
    echo "ERROR: $ROOT no existe."
    echo "El filesystem de WSL puede no estar listo todavia. Espera unos segundos y reintenta."
    exit 1
fi

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

# ─── 6. Esperar fpm healthy y validar mounts ─────────────────
echo ""
echo "Esperando que los contenedores esten listos..."
sleep 10

EXIT_CODE=0
for proj in "${PROJECTS[@]}"; do
    DIR_MOD=$(echo "$proj" | sed 's/\./_/g')
    NGINX="nginx_${DIR_MOD}"
    FPM="fpm_${DIR_MOD}"

    # Esperar fpm healthy (hasta 60s)
    for i in $(seq 1 30); do
        status=$(docker inspect --format='{{.State.Health.Status}}' "$FPM" 2>/dev/null || echo "missing")
        if [ "$status" = "healthy" ]; then break; fi
        sleep 2
    done

    # Validar que nginx vea el webroot
    if docker exec "$NGINX" test -f /var/www/html/public/index.php 2>/dev/null; then
        echo "✓ $proj — nginx ve /var/www/html/public/index.php"
    else
        echo "✗ $proj — nginx NO ve el webroot (bind mount vacio)"
        EXIT_CODE=1
    fi
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
