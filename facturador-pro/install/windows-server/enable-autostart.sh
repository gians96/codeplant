#!/bin/bash
#
# enable-autostart.sh — Arranque automatico del stack pro-8 tras cada reinicio
# (WSL2 + Docker Desktop + systemd).
#
# Que hace:
#   1. Activa systemd en WSL (/etc/wsl.conf: [boot] systemd=true).
#   2. Instala un script en /usr/local/bin que:
#        - espera a que Docker responda (hasta 5 min),
#        - espera a que el filesystem del usuario este montado,
#        - ejecuta el script de reinicio apropiado (dev o prod).
#   3. Registra un servicio systemd oneshot que se dispara al arrancar WSL.
#
# Como funciona el flujo tras cada reinicio de Windows:
#   Windows arranca → Docker Desktop auto-inicia → WSL Integration levanta
#   Ubuntu → systemd arranca → pro8-autostart.service corre → espera Docker
#   → ejecuta pro8up → nginx sirve correctamente.
#
# Requisitos:
#   - Docker Desktop configurado para iniciar con Windows
#     (Settings → General → Start Docker Desktop when you sign in).
#   - WSL Integration activa para esta distro
#     (Settings → Resources → WSL Integration → Ubuntu-xx).
#   - Ejecutar UNA VEZ con sudo:   sudo bash enable-autostart.sh
#   - Tras ejecutarlo:   wsl --shutdown   en PowerShell
#     (obligatorio la primera vez para que systemd quede habilitado).
#

set -e

if [ "$EUID" -ne 0 ]; then
    echo "ERROR: este script necesita sudo."
    echo "Ejecuta:   sudo bash $0"
    exit 1
fi

# Usuario real (no root) — propietario de ~/proyectos
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)

if [ -z "$TARGET_HOME" ] || [ "$TARGET_USER" = "root" ]; then
    echo "ERROR: no se pudo determinar el usuario no-root."
    echo "Ejecuta con:   sudo bash $0   (no como root directo)"
    exit 1
fi

echo ""
echo "============================================"
echo "  pro-8: Arranque automatico en WSL2"
echo "============================================"
echo "Usuario: $TARGET_USER"
echo "HOME:    $TARGET_HOME"
echo ""

# ─── 1. Verificar que estamos en WSL ─────────────────────────
if ! grep -qi microsoft /proc/version 2>/dev/null; then
    echo "ERROR: este script solo aplica a WSL2."
    exit 1
fi

# ─── 2. Activar systemd en /etc/wsl.conf ─────────────────────
WSL_CONF="/etc/wsl.conf"
if [ ! -f "$WSL_CONF" ] || ! grep -q "^\[boot\]" "$WSL_CONF" 2>/dev/null; then
    echo "→ Activando systemd en $WSL_CONF ..."
    {
        echo ""
        echo "[boot]"
        echo "systemd=true"
    } >> "$WSL_CONF"
    SYSTEMD_JUST_ENABLED=1
elif ! grep -Eq "^\s*systemd\s*=\s*true" "$WSL_CONF"; then
    echo "→ Habilitando systemd=true bajo [boot] en $WSL_CONF ..."
    sed -i '/^\[boot\]/a systemd=true' "$WSL_CONF"
    SYSTEMD_JUST_ENABLED=1
else
    echo "✓ systemd ya activo en $WSL_CONF"
    SYSTEMD_JUST_ENABLED=0
fi

# ─── 3. Escribir waiter en /usr/local/bin ────────────────────
WAITER="/usr/local/bin/pro8-autostart.sh"
echo "→ Instalando $WAITER ..."
cat > "$WAITER" << 'EOF_WAITER'
#!/bin/bash
#
# pro8-autostart.sh — Esperar a Docker + FS del usuario y disparar pro8up.
# Invocado por el servicio systemd pro8-autostart.service.
#
set -e

TARGET_USER="__TARGET_USER__"
TARGET_HOME="__TARGET_HOME__"

LOG="/var/log/pro8-autostart.log"
exec >> "$LOG" 2>&1
echo ""
echo "============================================"
echo "[$(date -Is)] pro8-autostart.sh iniciado"
echo "============================================"

# ─── Esperar a que Docker responda (hasta 5 min) ─────────────
for i in $(seq 1 60); do
    if docker info >/dev/null 2>&1; then
        echo "[$(date -Is)] Docker responde (intento $i)"
        break
    fi
    echo "[$(date -Is)] Docker no responde aun... (intento $i/60)"
    sleep 5
done
if ! docker info >/dev/null 2>&1; then
    echo "[$(date -Is)] ERROR: Docker no respondio en 5 min, abortando"
    exit 1
fi

# ─── Esperar a que el HOME del usuario este accesible ────────
for i in $(seq 1 30); do
    if [ -d "$TARGET_HOME/proyectos" ]; then
        echo "[$(date -Is)] $TARGET_HOME/proyectos accesible"
        break
    fi
    echo "[$(date -Is)] Esperando $TARGET_HOME/proyectos... ($i/30)"
    sleep 2
done
if [ ! -d "$TARGET_HOME/proyectos" ]; then
    echo "[$(date -Is)] ERROR: $TARGET_HOME/proyectos no existe, abortando"
    exit 1
fi

# ─── Elegir script de reinicio (prod o dev) ──────────────────
PROD_SCRIPT="$TARGET_HOME/proyectos/pro8-prod-restart.sh"
DEV_SCRIPT="$TARGET_HOME/proyectos/pro-8/scripts/pro8-restart.sh"

if [ -x "$PROD_SCRIPT" ]; then
    TARGET_SCRIPT="$PROD_SCRIPT"
    echo "[$(date -Is)] Modo PROD detectado: $TARGET_SCRIPT"
elif [ -x "$DEV_SCRIPT" ]; then
    TARGET_SCRIPT="$DEV_SCRIPT"
    echo "[$(date -Is)] Modo DEV detectado: $TARGET_SCRIPT"
else
    echo "[$(date -Is)] ERROR: no se encontro script de reinicio en:"
    echo "  - $PROD_SCRIPT"
    echo "  - $DEV_SCRIPT"
    exit 1
fi

# ─── Ejecutar como usuario no-root ───────────────────────────
echo "[$(date -Is)] Ejecutando como $TARGET_USER: $TARGET_SCRIPT"
sudo -u "$TARGET_USER" -H bash "$TARGET_SCRIPT"
EXIT_CODE=$?
echo "[$(date -Is)] Finalizado con exit code $EXIT_CODE"
exit $EXIT_CODE
EOF_WAITER

# Sustituir placeholders
sed -i "s|__TARGET_USER__|$TARGET_USER|g" "$WAITER"
sed -i "s|__TARGET_HOME__|$TARGET_HOME|g" "$WAITER"
chmod +x "$WAITER"

# ─── 4. Escribir unit de systemd ─────────────────────────────
UNIT="/etc/systemd/system/pro8-autostart.service"
echo "→ Instalando $UNIT ..."
cat > "$UNIT" << EOF_UNIT
[Unit]
Description=pro-8: recrear stack Docker al arrancar WSL
After=network-online.target
Wants=network-online.target
# No depende de docker.service porque Docker Desktop expone el socket
# via WSL Integration, no como servicio systemd nativo.

[Service]
Type=oneshot
ExecStart=$WAITER
RemainAfterExit=no
# Sin restart: si falla, se revisa el log manualmente.
StandardOutput=append:/var/log/pro8-autostart.log
StandardError=append:/var/log/pro8-autostart.log

[Install]
WantedBy=multi-user.target
EOF_UNIT

# ─── 5. Habilitar servicio ───────────────────────────────────
touch /var/log/pro8-autostart.log
chmod 644 /var/log/pro8-autostart.log

# Si systemd acaba de activarse, 'systemctl' todavia no esta operativo
# hasta que se haga 'wsl --shutdown'. Intentar, y si falla avisar.
if systemctl daemon-reload 2>/dev/null && systemctl enable pro8-autostart.service 2>/dev/null; then
    echo "✓ Servicio habilitado (enable)"
else
    echo "⚠ systemd no esta corriendo aun en esta sesion de WSL."
    echo "  El servicio se habilitara automaticamente en el proximo arranque"
    echo "  (ya esta registrado como WantedBy=multi-user.target)."
fi

echo ""
echo "============================================"
echo "  INSTALACION COMPLETADA"
echo "============================================"
echo ""
echo "Archivos instalados:"
echo "  $WAITER"
echo "  $UNIT"
echo "  /var/log/pro8-autostart.log   (log de cada arranque)"
echo ""
if [ "$SYSTEMD_JUST_ENABLED" = "1" ]; then
    echo "⚠ IMPORTANTE: systemd se acaba de activar. Ejecuta en POWERSHELL:"
    echo ""
    echo "    wsl --shutdown"
    echo ""
    echo "Y en el proximo arranque de Windows, todo funcionara solo."
else
    echo "Todo listo. En el proximo reinicio de Windows, el stack arrancara solo."
fi
echo ""
echo "Requisitos en Windows (verifica una vez):"
echo "  • Docker Desktop → Settings → General →"
echo "    ☑ Start Docker Desktop when you sign in"
echo "  • Docker Desktop → Settings → Resources → WSL Integration →"
echo "    ☑ Enable integration with my default WSL distro"
echo ""
echo "Verificar el arranque automatico manualmente:"
echo "  sudo systemctl status pro8-autostart"
echo "  tail -f /var/log/pro8-autostart.log"
echo ""
