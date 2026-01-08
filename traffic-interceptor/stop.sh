#!/bin/bash
# Detener el interceptor de tráfico

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Este comando debe ejecutarse como root (sudo)${NC}"
   exit 1
fi

echo -e "${YELLOW}Deteniendo Traffic Interceptor...${NC}"
echo ""

# Detener tcpdump
if [ -f /var/run/traffic-tcpdump.pid ]; then
    TCPDUMP_PID=$(cat /var/run/traffic-tcpdump.pid)
    if ps -p $TCPDUMP_PID > /dev/null; then
        kill $TCPDUMP_PID 2>/dev/null
        echo -e "${GREEN}✓${NC} tcpdump detenido (PID: $TCPDUMP_PID)"
    fi
    rm -f /var/run/traffic-tcpdump.pid
fi

# Detener mitmproxy
if [ -f /var/run/traffic-mitmweb.pid ]; then
    MITM_PID=$(cat /var/run/traffic-mitmweb.pid)
    if ps -p $MITM_PID > /dev/null; then
        kill $MITM_PID 2>/dev/null
        echo -e "${GREEN}✓${NC} mitmproxy detenido (PID: $MITM_PID)"
    fi
    rm -f /var/run/traffic-mitmweb.pid
fi

# Matar cualquier proceso restante
pkill -f "tcpdump.*traffic-interceptor" 2>/dev/null
pkill -f "mitmweb" 2>/dev/null

# Desactivar redirección si estaba activa
iptables -t nat -D OUTPUT -p tcp --dport 80 -j REDIRECT --to-port 8080 2>/dev/null
iptables -t nat -D OUTPUT -p tcp --dport 443 -j REDIRECT --to-port 8080 2>/dev/null

echo ""
echo -e "${GREEN}✓ Interceptor detenido completamente${NC}"
