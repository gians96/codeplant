#!/usr/bin/env bash
# ============================================================================
#  06 - VERIFICAR  (ejecutar EN GEN2, NUEVO, tras hacer los Redeploy)
# ----------------------------------------------------------------------------
#  Chequeo rápido del estado post-migración.
# ============================================================================
set -uo pipefail

echo "=================== VERIFICACIÓN POST-MIGRACIÓN ==================="
echo
echo ">> Servicios y réplicas (compara con ~/servicios-antes-migracion.txt de GEN1):"
docker service ls
echo
echo ">> Servicios que NO están completos (réplicas no satisfechas):"
docker service ls --format '{{.Name}} {{.Replicas}}' | awk '{split($2,a,"/"); if(a[1]!=a[2]) print "   ⚠️  "$0}'
echo
echo ">> Contenedores corriendo: $(docker ps -q | wc -l)"
echo ">> Volúmenes: $(docker volume ls -q | wc -l)"
echo
echo ">> Datos críticos:"
sudo test -f /etc/dokploy/traefik/dynamic/acme.json && echo "   OK acme.json" || echo "   !! FALTA acme.json"
sudo test -d /var/lib/docker/volumes/dokploy-postgres-database && echo "   OK dokploy-postgres-database" || echo "   !! FALTA dokploy-postgres-database"
echo
echo ">> Puertos publicados:"
sudo ss -tlnp 2>/dev/null | grep -E ':(80|443|3000|3306|5432|6379) ' | awk '{print "   "$4}'
echo
cat <<'EOF'
CHECKLIST MANUAL FINAL:
  [ ] La UI de Dokploy (http://IP:3000) muestra todos los proyectos.
  [ ] Cada dominio responde por HTTPS con certificado válido.
  [ ] Conectar a cada BD y verificar que los datos están.
  [ ] Apps que estaban en 0 réplicas: decidir si reactivar.
  [ ] Dejar GEN1 encendido 3-7 días como respaldo (vence 22/07/2026).
  [ ] Rotar contraseña SSH de 'undc'.
  [ ] Cerrar puertos de BD públicos con firewall si no se usan remotamente.
EOF
echo "=================================================================="
