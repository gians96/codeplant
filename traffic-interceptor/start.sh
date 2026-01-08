#!/bin/bash
# Iniciar el interceptor de tráfico

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Este comando debe ejecutarse como root (sudo)${NC}"
   exit 1
fi

source /etc/traffic-interceptor.conf 2>/dev/null || {
    LOG_DIR="/var/log/traffic-interceptor"
    PCAP_DIR="$LOG_DIR/pcap"
    MITM_DIR="$LOG_DIR/mitmproxy"
}

# Matar procesos anteriores si existen
pkill -f "tcpdump.*traffic-interceptor" 2>/dev/null
pkill -f "tcpdump.*$PCAP_DIR" 2>/dev/null

mkdir -p "$PCAP_DIR" "$MITM_DIR" "$LOG_DIR"
chmod 755 "$LOG_DIR" "$PCAP_DIR" "$MITM_DIR" 2>/dev/null

echo -e "${BLUE}=========================================="
echo "   Iniciando Traffic Interceptor"
echo "==========================================${NC}"
echo ""

# Verificar si mitmproxy está instalado
MITM_AVAILABLE=false
if command -v mitmweb &> /dev/null; then
    MITM_AVAILABLE=true
fi

# Iniciar tcpdump en background
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
OUTPUT_FILE="/tmp/traffic-$TIMESTAMP.txt"

echo -e "${YELLOW}[1/2]${NC} Iniciando captura tcpdump..."
echo "  Archivo: $OUTPUT_FILE"

# Capturar directo a archivo en /tmp (siempre funciona)
tcpdump -i any -n -l 'port 80 or port 443 or port 3000 or port 3001 or port 8080' \
    2>&1 | tee "$OUTPUT_FILE" > /dev/null &
TCPDUMP_PID=$!
echo $TCPDUMP_PID > /tmp/traffic-pid.txt

sleep 2

if ! ps -p $TCPDUMP_PID > /dev/null 2>&1; then
    echo -e "${RED}✗ Error al iniciar tcpdump${NC}"
    echo "Intenta manualmente: sudo tcpdump -i any -n 'port 80 or port 443'"
    exit 1
fi

echo -e "${GREEN}✓${NC} tcpdump iniciado correctamente"

# Iniciar mitmproxy solo si está disponible
MITM_PID=""
if [ "$MITM_AVAILABLE" = true ]; then
    echo -e "${YELLOW}[2/2]${NC} Iniciando mitmproxy web..."
    nohup mitmweb \
        --mode transparent \
        --showhost \
        --web-port 8081 \
        --flow-detail 3 \
        --save-stream-file "$MITM_DIR/flows-$TIMESTAMP.mitm" \
        > "$LOG_DIR/mitmproxy.log" 2>&1 &
    MITM_PID=$!
    echo $MITM_PID > /var/run/traffic-mitmweb.pid
    sleep 1
else
    echo -e "${YELLOW}[2/2]${NC} mitmproxy no disponible (solo tcpdump)"
fi

echo ""
echo -e "${GREEN}✓ Interceptor iniciado correctamente${NC}"
echo ""
echo -e "${BLUE}Información:${NC}"
echo "  • tcpdump PID: $TCPDUMP_PID"
echo "  • Archivo: $OUTPUT_FILE"

if [ "$MITM_AVAILABLE" = true ] && [ -n "$MITM_PID" ] && ps -p $MITM_PID > /dev/null; then
    echo "  • mitmproxy PID: $MITM_PID"
    echo "  • Flows: $MITM_DIR/flows-$TIMESTAMP.mitm"
    echo ""
    echo -e "${YELLOW}Interfaz Web:${NC}"
    IP=$(hostname -I | awk '{print $1}')
    echo "  http://$IP:8081"
fi

echo ""
echo -e "${YELLOW}Comandos útiles:${NC}"
echo "  sudo traffic-status    # Ver estado"
echo "  sudo traffic-view      # Ver logs"
echo "  sudo traffic-analyze   # Análisis detallado"
echo "  sudo traffic-stop      # Detener"
echo ""
