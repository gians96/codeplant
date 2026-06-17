#!/usr/bin/env bash
# ============================================================================
#  03 - DETENER SERVICIOS  (ejecutar EN GEN1, ORIGEN)  ⚠️ INICIA EL DOWNTIME
# ----------------------------------------------------------------------------
#  Escala todos los servicios a 0 (para consistencia de las BD) y detiene
#  Docker para poder copiar los datos en frío.
#  Ejecútalo SOLO cuando ya hayas hecho el backup (01) y preparado GEN2 (02).
# ============================================================================
set -uo pipefail

read -r -p "⚠️  Esto DETIENE TODOS los servicios de GEN1. ¿Continuar? (escribe SI): " ok
[ "$ok" = "SI" ] || { echo "Cancelado."; exit 1; }

echo ">> Guardando lista de servicios y sus réplicas (para referencia)..."
docker service ls > ~/servicios-antes-migracion.txt
cat ~/servicios-antes-migracion.txt

echo
echo ">> Escalando a 0 todos los servicios (excepto el stack de Dokploy y Traefik)..."
docker service ls --format '{{.Name}}' \
  | grep -vE '^(dokploy|dokploy-postgres|dokploy-redis|dokploy-traefik|traefik)$' \
  | xargs -r -I{} docker service scale {}=0

echo
echo ">> Esperando 15s a que terminen los contenedores..."
sleep 15
docker ps

echo
echo ">> Deteniendo Docker para copia en frío..."
sudo systemctl stop docker
sudo systemctl stop docker.socket 2>/dev/null || true

echo
echo "✅ GEN1 detenido. Ahora ve al GEN2 y ejecuta 04-transferir-EN-GEN2.sh"
echo "   (El acceso SSH sigue funcionando aunque Docker esté apagado.)"
