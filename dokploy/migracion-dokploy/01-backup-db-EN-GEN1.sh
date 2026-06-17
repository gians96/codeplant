#!/usr/bin/env bash
# ============================================================================
#  01 - BACKUP DE BASES DE DATOS  (ejecutar EN GEN1, el servidor ORIGEN)
# ----------------------------------------------------------------------------
#  Red de seguridad: dumps lógicos de todas las BD (MySQL/MariaDB/Postgres)
#  por si un volumen no levanta bien en GEN2. NO detiene nada (sin downtime).
#  Auto-detecta el motor y la contraseña desde las variables de entorno del
#  contenedor. Guarda los .sql en ~/dumps-migracion.
# ============================================================================
set -uo pipefail

OUT=~/dumps-migracion
mkdir -p "$OUT"
echo ">> Guardando dumps en $OUT"
echo ">> Fecha: $(date)"
echo

fail=0
for c in $(docker ps --format '{{.Names}}'); do
  # ---- MySQL / MariaDB ----
  if docker exec "$c" sh -c 'command -v mysqldump' >/dev/null 2>&1; then
    pw="$(docker exec "$c" printenv MYSQL_ROOT_PASSWORD 2>/dev/null || true)"
    [ -z "$pw" ] && pw="$(docker exec "$c" printenv MARIADB_ROOT_PASSWORD 2>/dev/null || true)"
    echo "-- [MySQL]   $c"
    if docker exec "$c" sh -c "exec mysqldump -uroot -p'$pw' --all-databases --single-transaction --quick" \
         > "$OUT/mysql_${c}.sql" 2>/dev/null && [ -s "$OUT/mysql_${c}.sql" ]; then
      echo "   OK -> mysql_${c}.sql ($(du -h "$OUT/mysql_${c}.sql" | cut -f1))"
    else
      echo "   !! FALLÓ (revisa usuario/clave en Dokploy > Environment)"; fail=1; rm -f "$OUT/mysql_${c}.sql"
    fi

  # ---- PostgreSQL ----
  elif docker exec "$c" sh -c 'command -v pg_dumpall' >/dev/null 2>&1; then
    user="$(docker exec "$c" printenv POSTGRES_USER 2>/dev/null || true)"; user="${user:-postgres}"
    echo "-- [Postgres] $c (user=$user)"
    if docker exec "$c" sh -c "exec pg_dumpall -U '$user'" \
         > "$OUT/pg_${c}.sql" 2>/dev/null && [ -s "$OUT/pg_${c}.sql" ]; then
      echo "   OK -> pg_${c}.sql ($(du -h "$OUT/pg_${c}.sql" | cut -f1))"
    else
      echo "   !! FALLÓ (revisa POSTGRES_USER/clave en Dokploy > Environment)"; fail=1; rm -f "$OUT/pg_${c}.sql"
    fi
  fi
done

echo
echo ">> Dumps generados:"
ls -lh "$OUT" 2>/dev/null || true
echo
echo ">> Comprimiendo todo en un solo archivo..."
tar czf ~/dumps-migracion.tar.gz -C "$OUT" . && echo "   -> ~/dumps-migracion.tar.gz ($(du -h ~/dumps-migracion.tar.gz | cut -f1))"
echo
if [ "$fail" -ne 0 ]; then
  echo "⚠️  Algún dump falló. No es bloqueante (el rsync copia los volúmenes igual),"
  echo "    pero revisa esos contenedores si esas BD son importantes."
fi
echo "✅ Backup de seguridad terminado."
