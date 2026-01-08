#!/bin/bash
# Ver el estado del interceptor

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Este comando debe ejecutarse como root (sudo)${NC}"
   exit 1
fi

echo ""
echo -e "${BLUE}=========================================="
echo "     Estado del Traffic Interceptor"
echo "==========================================${NC}"
echo ""

# Estado de tcpdump
echo -e "${BLUE}tcpdump:${NC}"
if [ -f /var/run/traffic-tcpdump.pid ]; then
    PID=$(cat /var/run/traffic-tcpdump.pid)
    if ps -p $PID > /dev/null 2>&1; then
        echo -e "  Estado: ${GREEN}✓ Ejecutándose${NC}"
        echo "  PID: $PID"
        MEM=$(ps -p $PID -o rss= 2>/dev/null)
        if [ -n "$MEM" ]; then
            MEM_MB=$(echo "scale=2; $MEM/1024" | bc)
            echo "  Memoria: ${MEM_MB} MB"
        fi
    else
        echo -e "  Estado: ${RED}✗ Detenido${NC}"
    fi
else
    echo -e "  Estado: ${RED}✗ No iniciado${NC}"
fi

echo ""

# Estado de mitmproxy
echo -e "${BLUE}mitmproxy:${NC}"
if [ -f /var/run/traffic-mitmweb.pid ]; then
    PID=$(cat /var/run/traffic-mitmweb.pid)
    if ps -p $PID > /dev/null 2>&1; then
        echo -e "  Estado: ${GREEN}✓ Ejecutándose${NC}"
        echo "  PID: $PID"
        MEM=$(ps -p $PID -o rss= 2>/dev/null)
        if [ -n "$MEM" ]; then
            MEM_MB=$(echo "scale=2; $MEM/1024" | bc)
            echo "  Memoria: ${MEM_MB} MB"
        fi
        IP=$(hostname -I | awk '{print $1}')
        echo -e "  Web UI: ${YELLOW}http://$IP:8081${NC}"
    else
        echo -e "  Estado: ${RED}✗ Detenido${NC}"
    fi
else
    echo -e "  Estado: ${RED}✗ No iniciado${NC}"
fi

echo ""

# Estado de redirección iptables
echo -e "${BLUE}Redirección iptables:${NC}"
REDIRECT_80=$(iptables -t nat -L OUTPUT -n | grep "REDIRECT.*dpt:80.*redir ports 8080" 2>/dev/null)
REDIRECT_443=$(iptables -t nat -L OUTPUT -n | grep "REDIRECT.*dpt:443.*redir ports 8080" 2>/dev/null)

if [ -n "$REDIRECT_80" ] || [ -n "$REDIRECT_443" ]; then
    echo -e "  Estado: ${GREEN}✓ Activa${NC}"
    [ -n "$REDIRECT_80" ] && echo "    • HTTP (80) → 8080"
    [ -n "$REDIRECT_443" ] && echo "    • HTTPS (443) → 8080"
else
    echo -e "  Estado: ${YELLOW}✗ Inactiva${NC}"
    echo "    Ejecuta: sudo traffic-enable-redirect"
fi

echo ""

# Información de logs
echo -e "${BLUE}Logs capturados:${NC}"
LOG_DIR="/var/log/traffic-interceptor"

if [ -d "$LOG_DIR" ]; then
    PCAP_COUNT=$(find "$LOG_DIR/pcap" -name "*.pcap" 2>/dev/null | wc -l)
    PCAP_SIZE=$(du -sh "$LOG_DIR/pcap" 2>/dev/null | awk '{print $1}')
    MITM_COUNT=$(find "$LOG_DIR/mitmproxy" -name "*.mitm" 2>/dev/null | wc -l)
    
    echo "  • Archivos PCAP: $PCAP_COUNT ($PCAP_SIZE)"
    echo "  • Flows mitmproxy: $MITM_COUNT"
    echo "  • Directorio: $LOG_DIR"
else
    echo -e "  ${YELLOW}No hay logs disponibles${NC}"
fi

echo ""
echo -e "${BLUE}Comandos:${NC}"
echo "  sudo traffic-start    - Iniciar"
echo "  sudo traffic-stop     - Detener"
echo "  sudo traffic-view     - Ver logs"
echo "  sudo traffic-analyze  - Análisis"
echo ""
