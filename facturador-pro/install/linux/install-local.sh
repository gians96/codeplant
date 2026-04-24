#!/bin/bash
#
# install-local.sh — Facturador Pro-8: Instalacion de desarrollo LOCAL en Linux
#
# Equivalente a windows-server/02-install-dev.sh pero para Linux nativo
# (Ubuntu / Debian / derivados). Sin WSL, sin Docker Desktop.
#
# Uso:
#   curl -O https://raw.githubusercontent.com/gians96/codeplant/master/facturador-pro/install/linux/install-local.sh
#   chmod +x install-local.sh
#   ./install-local.sh
#
# Que hace:
#   1. Verifica/instala prerequisitos (git, curl, unzip, Docker Engine)
#   2. Instala Bun (runtime/bundler JS para Vite)
#   3. Clona el repo pro-8 en ~/proyectos/pro-8
#   4. Ejecuta scripts/local-setup.sh (levanta 6 containers)
#   5. Compila assets con bun run build
#   6. Corrige permisos de storage y bootstrap/cache
#   7. Genera archivo de credenciales fuera del proyecto
#
# Sin proxy, sin SSL, puertos dev (App 8080, MySQL 3308).
#

set -e

REPO_URL="https://gitlab.com/gians96/pro-8.git"
BRANCH="master"
PROJECT_DEST="$HOME/proyectos/pro-8"

echo ""
echo "============================================"
echo "  FACTURADOR PRO-8 — Instalacion Local"
echo "  (Linux nativo)"
echo "============================================"
echo ""

# ─── No correr como root ─────────────────────────────────────
# El proyecto se clona en $HOME del usuario actual. Si corres como root,
# queda en /root y luego docker no puede montar los volumes del usuario.
if [ "$(id -u)" -eq 0 ]; then
    echo "ERROR: No ejecutes este script como root / sudo."
    echo "  El script pedira sudo solo para los comandos que lo requieran"
    echo "  (instalar paquetes, docker, añadir tu usuario al grupo docker)."
    exit 1
fi

# ─── Detectar gestor de paquetes ─────────────────────────────
if command -v apt-get >/dev/null 2>&1; then
    PKG_UPDATE="sudo apt-get update -qq"
    PKG_INSTALL="sudo apt-get install -y"
elif command -v dnf >/dev/null 2>&1; then
    PKG_UPDATE="sudo dnf -y check-update || true"
    PKG_INSTALL="sudo dnf install -y"
elif command -v pacman >/dev/null 2>&1; then
    PKG_UPDATE="sudo pacman -Sy --noconfirm"
    PKG_INSTALL="sudo pacman -S --noconfirm --needed"
else
    echo "ADVERTENCIA: gestor de paquetes no reconocido (apt/dnf/pacman)."
    echo "  Instala manualmente: git curl unzip ca-certificates"
    PKG_UPDATE="true"
    PKG_INSTALL="true"
fi

# ─── Prerequisitos basicos ───────────────────────────────────
NEED_PKGS=""
command -v git   >/dev/null 2>&1 || NEED_PKGS="$NEED_PKGS git"
command -v curl  >/dev/null 2>&1 || NEED_PKGS="$NEED_PKGS curl"
command -v unzip >/dev/null 2>&1 || NEED_PKGS="$NEED_PKGS unzip"

if [ -n "$NEED_PKGS" ]; then
    echo "Instalando dependencias:$NEED_PKGS ..."
    $PKG_UPDATE
    $PKG_INSTALL $NEED_PKGS
fi

# ─── Docker Engine ───────────────────────────────────────────
# Idempotente: si docker responde, no se toca. Si no esta, se instala
# con el script oficial (get.docker.com) y se añade el usuario al grupo.
if ! command -v docker >/dev/null 2>&1; then
    echo "Docker no encontrado. Instalando con get.docker.com ..."
    curl -fsSL https://get.docker.com | sudo sh
    sudo usermod -aG docker "$USER" || true
    echo ""
    echo "IMPORTANTE: se añadio '$USER' al grupo docker."
    echo "  Cierra sesion y vuelve a entrar (o ejecuta 'newgrp docker')"
    echo "  para que el cambio surta efecto, luego vuelve a correr este script."
    exit 0
fi

# Arrancar el daemon si el servicio esta instalado pero parado
if ! docker info >/dev/null 2>&1; then
    echo "Docker instalado pero daemon no responde. Intentando arrancar..."
    sudo systemctl start docker 2>/dev/null || sudo service docker start 2>/dev/null || true
    sleep 2
    if ! docker info >/dev/null 2>&1; then
        echo "ERROR: no se pudo conectar con el daemon de Docker."
        echo "  Verifica con: sudo systemctl status docker"
        echo "  Y que tu usuario pertenezca al grupo docker: groups"
        exit 1
    fi
fi
echo "Docker OK ($(docker --version))"

# Verificar que docker compose (plugin v2) este disponible
if ! docker compose version >/dev/null 2>&1; then
    echo "ERROR: plugin 'docker compose' v2 no disponible."
    echo "  Instala 'docker-compose-plugin' o reinstala Docker con get.docker.com"
    exit 1
fi

# ─── Bun (runtime/bundler JS para Vite) ──────────────────────
# Idempotente: si ya existe, se omite.
if ! command -v bun >/dev/null 2>&1 && [ ! -x "$HOME/.bun/bin/bun" ]; then
    echo "Instalando Bun..."
    curl -fsSL https://bun.sh/install | bash >/dev/null
    export BUN_INSTALL="$HOME/.bun"
    export PATH="$BUN_INSTALL/bin:$PATH"
    echo "Bun instalado: $(bun --version)"
else
    export PATH="$HOME/.bun/bin:$PATH"
    echo "Bun ya instalado: $(bun --version 2>/dev/null || echo 'n/d')"
fi

# ─── Rama (opcional) ──────────────────────────────────────────
read -p "Rama a clonar [$BRANCH]: " input_branch
if [ ! -z "$input_branch" ]; then
    BRANCH="$input_branch"
fi

# ─── Clonar o actualizar ─────────────────────────────────────
if [ -f "$PROJECT_DEST/artisan" ]; then
    echo "El proyecto ya existe en $PROJECT_DEST"
    read -p "Actualizar con git pull? [S/n]: " do_pull
    if [ "$do_pull" != "n" ] && [ "$do_pull" != "N" ]; then
        cd "$PROJECT_DEST"
        git pull origin "$BRANCH"
        echo "Proyecto actualizado"
    fi
else
    echo "Clonando $REPO_URL (rama: $BRANCH)..."
    mkdir -p "$(dirname "$PROJECT_DEST")"
    git clone -b "$BRANCH" "$REPO_URL" "$PROJECT_DEST"
    echo "Proyecto clonado en $PROJECT_DEST"
fi

# ─── Ejecutar local-setup.sh ─────────────────────────────────
echo ""
echo "Ejecutando local-setup.sh (levanta 6 containers)..."
echo ""
cd "$PROJECT_DEST"
bash scripts/local-setup.sh

# ─── Compilar assets con Bun (Vite) ──────────────────────────
# canvas (dependencia transitiva) necesita libs nativas para compilar.
# --ignore-scripts evita fallos en entornos sin build-tools.
echo ""
echo "Instalando dependencias JS con Bun (--ignore-scripts)..."
cd "$PROJECT_DEST"
bun install --ignore-scripts

echo "Compilando assets (vite build)..."
bun run build || echo "ADVERTENCIA: fallo el build de assets; revisa errores arriba"

# ─── Corregir permisos de storage y bootstrap/cache ──────────
# artisan dentro del contenedor corre como root y puede crear subdirs con
# owner root / 700; php-fpm corre como www-data y no puede escribir ahi.
# Sintoma tipico:
#   "file_put_contents(.../storage/framework/views/XXX.php): Permission denied"
echo ""
echo "Corrigiendo permisos de storage y bootstrap/cache..."
if docker ps --format '{{.Names}}' | grep -q '^fpm_pro8_local$'; then
    docker exec fpm_pro8_local bash -c '
        chown -R www-data:www-data /var/www/html/storage /var/www/html/bootstrap/cache &&
        chmod -R 775 /var/www/html/storage /var/www/html/bootstrap/cache &&
        find /var/www/html/storage/framework/views -type f -delete 2>/dev/null || true
    ' && echo "Permisos OK" || echo "ADVERTENCIA: no se pudo ajustar permisos"
else
    echo "ADVERTENCIA: contenedor fpm_pro8_local no esta corriendo, omito fix de permisos"
fi

# ─── Alias pro8up (reinicio rapido del stack) ────────────────
# Util cuando quieres tirar y levantar todo el stack sin recordar la ruta.
# Idempotente: no duplica si ya existe.
BASHRC="${HOME}/.bashrc"
RESTART_SCRIPT="${PROJECT_DEST}/scripts/pro8-restart.sh"
if [ -f "$RESTART_SCRIPT" ]; then
    chmod +x "$RESTART_SCRIPT" 2>/dev/null || true
    if [ -f "$BASHRC" ] && ! grep -q "alias pro8up=" "$BASHRC"; then
        {
            echo ""
            echo "# pro-8: reinicio rapido del stack local"
            echo "alias pro8up='bash ${RESTART_SCRIPT}'"
        } >> "$BASHRC"
        echo "Alias 'pro8up' instalado en ~/.bashrc"
    fi
fi

# ─── Archivo de credenciales ─────────────────────────────────
DATA_CONFIG="$(dirname "$PROJECT_DEST")/pro-8-local.txt"
cat << EOF > "$DATA_CONFIG"
============================================
DATOS DE INSTALACION (LOCAL / DEV) - pro-8
Generado: $(date '+%Y-%m-%d %H:%M')
============================================
Ruta del proyecto: $PROJECT_DEST
Rama: $BRANCH
URL: http://localhost:8080
----------------------------------------------
Acceso remoto a MySQL
Puerto: 3308
Host: localhost
Usuario: root
Contrasena root: secret
----------------------------------------------
Redis
Host: redis_pro8_local
Puerto: 6379
Password: null
----------------------------------------------
Contenedor FPM:       fpm_pro8_local
Contenedor MariaDB:   mariadb_pro8_local
Contenedor Redis:     redis_pro8_local
Contenedor Nginx:     nginx_pro8_local
============================================

Para levantar / reiniciar el stack:
  cd $PROJECT_DEST
  docker compose -f docker-compose.local.yml up -d

O con el alias (requiere abrir nueva terminal):
  pro8up
EOF
echo "Credenciales guardadas en: $DATA_CONFIG"

echo ""
echo "============================================"
echo "  INSTALACION LOCAL COMPLETADA"
echo "============================================"
echo ""
echo "  Proyecto: $PROJECT_DEST"
echo "  App:      http://localhost:8080"
echo "  MySQL:    localhost:3308 (root / secret)"
echo ""
echo "  Credenciales: $DATA_CONFIG"
echo ""
echo "  Para entrar al proyecto:"
echo "    cd $PROJECT_DEST"
echo ""
echo "  Para reiniciar el stack (tras reboot o cambios):"
echo "    pro8up      # abre nueva terminal para activar el alias"
echo ""
