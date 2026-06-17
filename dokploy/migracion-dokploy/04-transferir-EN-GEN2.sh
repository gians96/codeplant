#!/usr/bin/env bash
# ============================================================================
#  04 - TRANSFERIR DATOS  (ejecutar EN GEN2, NUEVO)
# ----------------------------------------------------------------------------
#  Detiene Docker en GEN2 y copia desde GEN1 (en frío) las DOS rutas clave:
#    - /etc/dokploy            (config, traefik+acme.json, bind-mounts)
#    - /var/lib/docker/volumes (todos los volúmenes, incl. dokploy-postgres)
#  Usa rsync sobre SSH con sudo en ambos lados. Reanudable si se corta.
#  Requisito: en GEN1 ya se ejecutó 03 (Docker detenido).
# ============================================================================
set -uo pipefail

GEN1_USER="undc"
GEN1_IP="161.132.53.113"
SSH_PORT="22"

echo ">> Origen: ${GEN1_USER}@${GEN1_IP}:${SSH_PORT}"
echo ">> NOTA: ssh te pedirá la contraseña de ${GEN1_USER}@${GEN1_IP} (una vez por cada copia)."
echo ">>       Para evitarlo, configura primero una clave: ssh-keygen -t ed25519 && ssh-copy-id ${GEN1_USER}@${GEN1_IP}"
read -r -p "¿Confirmaste que en GEN1 ya corrió 03 (Docker detenido)? (SI): " ok
[ "$ok" = "SI" ] || { echo "Cancelado."; exit 1; }

# Asegurar rsync en GEN2 (Ubuntu suele traerlo)
command -v rsync >/dev/null 2>&1 || { echo ">> Instalando rsync..."; sudo apt-get update -qq && sudo apt-get install -y rsync; }

echo
echo ">> Deteniendo Docker en GEN2 para recibir datos en frío..."
sudo systemctl stop docker
sudo systemctl stop docker.socket 2>/dev/null || true

RS="sudo rsync -aHAX --numeric-ids --info=progress2"
SSHCMD="ssh -p ${SSH_PORT}"
REMOTE="${GEN1_USER}@${GEN1_IP}"

echo
echo ">> [1/2] Copiando /etc/dokploy  (~329 MB)..."
$RS --delete \
  --exclude='logs/' --exclude='traefik/dynamic/access.log' \
  --rsync-path="sudo rsync" -e "$SSHCMD" \
  "${REMOTE}:/etc/dokploy/" /etc/dokploy/

echo
echo ">> [2/2] Copiando /var/lib/docker/volumes  (~7.5 GB)..."
$RS --exclude='backingFsBlockDev' \
  --rsync-path="sudo rsync" -e "$SSHCMD" \
  "${REMOTE}:/var/lib/docker/volumes/" /var/lib/docker/volumes/

echo
echo ">> Comprobando que llegaron los datos críticos:"
sudo test -f /etc/dokploy/traefik/dynamic/acme.json && echo "   OK acme.json (certificados SSL)" || echo "   !! FALTA acme.json"
sudo test -d /var/lib/docker/volumes/dokploy-postgres-database && echo "   OK dokploy-postgres-database (config Dokploy)" || echo "   !! FALTA dokploy-postgres-database"

echo
echo "✅ Transferencia completa. Ahora ejecuta 05-arrancar-EN-GEN2.sh"
