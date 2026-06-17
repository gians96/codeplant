#!/usr/bin/env bash
# ============================================================================
#  05 - ARRANCAR DOKPLOY  (ejecutar EN GEN2, NUEVO)
# ----------------------------------------------------------------------------
#  Levanta Docker con los datos ya restaurados. Dokploy leerá su Postgres
#  restaurado y mostrará TODOS tus proyectos. Los servicios de las apps aún
#  no corren: se recrean haciendo Redeploy desde la UI (ver paso siguiente).
# ============================================================================
set -uo pipefail

echo ">> Arrancando Docker..."
sudo systemctl start docker

echo ">> Esperando a que el Swarm/Dokploy se estabilice (30s)..."
sleep 30

echo
echo ">> Servicios del stack Dokploy:"
docker service ls | grep -E 'dokploy|traefik' || true

echo
echo ">> Estado general:"
docker service ls | wc -l
docker info --format 'Swarm: {{.Swarm.LocalNodeState}} | Nodes: {{.Swarm.Nodes}}'

IP=$(hostname -I | awk '{print $1}')
cat <<EOF

✅ Dokploy arrancado en GEN2.

SIGUIENTES PASOS MANUALES:
  1. Entra a http://${IP}:3000  -> deberías ver TODOS tus proyectos/apps/dominios/envs.
  2. Haz REDEPLOY de cada app desde la UI, EN ESTE ORDEN:
        a) Bases de datos primero (mysql, postgres, redis)
        b) Backends
        c) Frontends
     Esto recrea los servicios Swarm apuntando a los datos ya restaurados (no se pierde nada).
  3. DNS / IP:
       - Si conservaste la IP: nada que hacer, todo resuelve igual.
       - Si IP nueva: apunta los registros A a ${IP}. Traefik re-emite SSL al resolver.
  4. Ejecuta 06-verificar-EN-GEN2.sh para el chequeo final.
EOF
