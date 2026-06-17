#!/usr/bin/env bash
# ============================================================================
#  02 - INSTALAR DOKPLOY  (ejecutar EN GEN2, el servidor NUEVO)
# ----------------------------------------------------------------------------
#  Prepara el GEN2: verifica SO, instala Docker + Dokploy y FIJA la versión
#  EXACTA del origen (v0.29.8). Esto inicializa un Swarm nuevo. No configures
#  nada en la UI después: lo vamos a sobrescribir con los datos de GEN1.
# ============================================================================
set -euo pipefail

DOKPLOY_VERSION="0.29.8"   # debe coincidir con GEN1

echo ">> SO del GEN2:"; grep PRETTY_NAME /etc/os-release
echo ">> Recomendado: Ubuntu 24.04 (igual que GEN1)."
echo

# --- Docker (el instalador de Dokploy lo pone, pero por si acaso) ---
if ! command -v docker >/dev/null 2>&1; then
  echo ">> Instalando Docker..."
  curl -sSL https://get.docker.com | sudo sh
fi

# --- Dokploy (el instalador REQUIERE root -> sudo) ---
if ! docker service ls 2>/dev/null | grep -q '\bdokploy\b'; then
  echo ">> Instalando Dokploy..."
  curl -sSL https://dokploy.com/install.sh | sudo sh
else
  echo ">> Dokploy ya está instalado."
fi

echo
echo ">> Fijando Dokploy a la versión $DOKPLOY_VERSION (igual que GEN1)..."
docker service update --image "dokploy/dokploy:v${DOKPLOY_VERSION}" dokploy || true

echo
echo ">> Versión activa de Dokploy:"
docker service inspect dokploy --format '{{.Spec.TaskTemplate.ContainerSpec.Image}}' || true
echo
echo ">> Estado Swarm:"
docker info --format 'Swarm: {{.Swarm.LocalNodeState}} | Nodes: {{.Swarm.Nodes}}'
echo
echo "✅ GEN2 listo. Entra UNA vez a http://$(hostname -I | awk '{print $1}'):3000 para confirmar que carga,"
echo "   y NO configures nada más (se sobrescribe con la transferencia)."
