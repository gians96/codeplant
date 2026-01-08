#!/bin/bash
# Script de instalación del Interceptor de Tráfico HTTP/HTTPS
# Ejecutar con: sudo bash install.sh

# No usar set -e para evitar que se detenga

echo "=========================================="
echo "  Instalador de Traffic Interceptor"
echo "    (mitmproxy + tcpdump + análisis)"
echo "=========================================="
echo ""

# Colores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Verificar root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Este script debe ejecutarse como root (sudo)${NC}"
   exit 1
fi

# Guardar directorio actual
SCRIPT_DIR="$(pwd)"

echo -e "${YELLOW}[1/7]${NC} Actualizando sistema..."
apt-get update -qq > /dev/null 2>&1

echo -e "${YELLOW}[2/7]${NC} Instalando dependencias..."
apt-get install -y python3 python3-pip tcpdump iptables-persistent net-tools > /dev/null 2>&1

echo -e "${YELLOW}[3/7]${NC} Instalando mitmproxy..."
echo "  (esto puede tardar varios minutos...)"

# Intentar diferentes métodos de instalación
if pip3 install mitmproxy --break-system-packages 2>&1 | grep -q "error\|Error"; then
    echo "  Intentando método alternativo..."
    if pip3 install mitmproxy 2>&1 | grep -q "error\|Error"; then
        echo "  Instalando desde apt (versión estable)..."
        apt-get install -y mitmproxy 2>&1 | grep -v "^Get:" | grep -v "^Fetched"
    fi
fi

# Verificar instalación
if ! command -v mitmproxy &> /dev/null && ! command -v mitmweb &> /dev/null; then
    echo -e "${RED}Error: No se pudo instalar mitmproxy${NC}"
    echo "Instalando solo tcpdump (funcionará sin interfaz web)..."
    MITM_INSTALLED=false
else
    MITM_INSTALLED=true
fi

echo -e "${YELLOW}[4/7]${NC} Creando directorios para logs..."
mkdir -p /var/log/traffic-interceptor/pcap
mkdir -p /var/log/traffic-interceptor/mitmproxy
mkdir -p /var/log/traffic-interceptor/analysis
chmod 777 /var/log/traffic-interceptor
chmod 777 /var/log/traffic-interceptor/pcap
chmod 777 /var/log/traffic-interceptor/mitmproxy
chmod 777 /var/log/traffic-interceptor/analysis

# Desactivar AppArmor para tcpdump si está activo
if command -v aa-status &> /dev/null; then
    echo "  Desactivando AppArmor para tcpdump..."
    if [ -f /etc/apparmor.d/usr.bin.tcpdump ] || [ -f /etc/apparmor.d/usr.sbin.tcpdump ]; then
        ln -sf /etc/apparmor.d/usr.bin.tcpdump /etc/apparmor.d/disable/ 2>/dev/null
        ln -sf /etc/apparmor.d/usr.sbin.tcpdump /etc/apparmor.d/disable/ 2>/dev/null
        apparmor_parser -R /etc/apparmor.d/usr.bin.tcpdump 2>/dev/null
        apparmor_parser -R /etc/apparmor.d/usr.sbin.tcpdump 2>/dev/null
    fi
fi

# Dar capacidades a tcpdump
TCPDUMP_PATH=$(which tcpdump)
if [ -n "$TCPDUMP_PATH" ]; then
    setcap cap_net_raw,cap_net_admin=eip "$TCPDUMP_PATH" 2>/dev/null
fi

echo -e "${YELLOW}[5/7]${NC} Instalando scripts de control..."

# Verificar archivos
if [ ! -f "$SCRIPT_DIR/start.sh" ]; then
    echo -e "${RED}Error: No se encuentran los scripts en $SCRIPT_DIR${NC}"
    exit 1
fi

# Copiar scripts
cp "$SCRIPT_DIR/start.sh" /usr/local/bin/traffic-start
cp "$SCRIPT_DIR/stop.sh" /usr/local/bin/traffic-stop
cp "$SCRIPT_DIR/view.sh" /usr/local/bin/traffic-view
cp "$SCRIPT_DIR/status.sh" /usr/local/bin/traffic-status
cp "$SCRIPT_DIR/analyze.sh" /usr/local/bin/traffic-analyze

chmod +x /usr/local/bin/traffic-*

echo -e "${YELLOW}[6/7]${NC} Configurando reglas de firewall..."
# Crear script para reglas iptables
cat > /usr/local/bin/traffic-enable-redirect << 'EOF'
#!/bin/bash
# Redirigir HTTP/HTTPS a mitmproxy
iptables -t nat -A OUTPUT -p tcp --dport 80 -j REDIRECT --to-port 8080
iptables -t nat -A OUTPUT -p tcp --dport 443 -j REDIRECT --to-port 8080
echo "✓ Redirección de tráfico activada"
EOF

cat > /usr/local/bin/traffic-disable-redirect << 'EOF'
#!/bin/bash
# Eliminar redirecciones
iptables -t nat -D OUTPUT -p tcp --dport 80 -j REDIRECT --to-port 8080 2>/dev/null
iptables -t nat -D OUTPUT -p tcp --dport 443 -j REDIRECT --to-port 8080 2>/dev/null
echo "✓ Redirección de tráfico desactivada"
EOF

chmod +x /usr/local/bin/traffic-enable-redirect
chmod +x /usr/local/bin/traffic-disable-redirect

echo -e "${YELLOW}[7/7]${NC} Configuración final..."

# Crear archivo de configuración
cat > /etc/traffic-interceptor.conf << 'EOF'
# Configuración Traffic Interceptor
LOG_DIR="/var/log/traffic-interceptor"
PCAP_DIR="$LOG_DIR/pcap"
MITM_DIR="$LOG_DIR/mitmproxy"
ANALYSIS_DIR="$LOG_DIR/analysis"
MITM_PORT=8080
WEB_PORT=8081
EOF

echo ""
echo -e "${GREEN}=========================================="
echo "  ✓ Instalación completada exitosamente"
echo "==========================================${NC}"
echo ""

# Mostrar información según lo instalado
if [ "$MITM_INSTALLED" = true ]; then
    echo -e "${GREEN}✓ mitmproxy instalado correctamente${NC}"
    IP=$(hostname -I | awk '{print $1}')
    echo -e "${BLUE}  Interfaz Web: http://$IP:8081${NC}"
else
    echo -e "${YELLOW}⚠ mitmproxy no disponible (solo tcpdump)${NC}"
    echo -e "  Podrás capturar tráfico pero sin interfaz web"
fi

echo ""
echo -e "${BLUE}Comandos disponibles:${NC}"
echo ""
echo -e "${YELLOW}Gestión:${NC}"
echo "  sudo traffic-start           - Iniciar interceptor"
echo "  sudo traffic-stop            - Detener interceptor"
echo "  sudo traffic-status          - Ver estado"
echo "  sudo traffic-view            - Ver logs capturados"
echo "  sudo traffic-analyze         - Análisis de tráfico"
echo ""
echo -e "${YELLOW}Redirección (opcional):${NC}"
echo "  sudo traffic-enable-redirect  - Activar redirección transparente"
echo "  sudo traffic-disable-redirect - Desactivar redirección"
echo ""
echo -e "${YELLOW}Logs guardados en:${NC}"
echo "  /var/log/traffic-interceptor/"
echo ""
echo -e "${RED}IMPORTANTE:${NC} Esto es para uso educativo en tu servidor privado"
echo ""
