#!/bin/bash
# Desinstalar el Traffic Interceptor

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Este script debe ejecutarse como root (sudo)${NC}"
   exit 1
fi

echo ""
echo -e "${YELLOW}=========================================="
echo "  Desinstalador de Traffic Interceptor"
echo "==========================================${NC}"
echo ""
echo -e "${RED}ADVERTENCIA:${NC} Esto eliminará:"
echo "  - Todos los scripts de control"
echo "  - Configuraciones"
echo "  - Opcionalmente los logs capturados"
echo ""
echo -n "¿Estás seguro? (escribe 'SI' para confirmar): "
read confirmacion

if [ "$confirmacion" != "SI" ]; then
    echo ""
    echo "Desinstalación cancelada"
    exit 0
fi

echo ""
echo "Desinstalando..."

# Detener si está corriendo
echo "Deteniendo interceptor..."
traffic-stop 2>/dev/null

# Eliminar scripts
echo "Eliminando scripts..."
rm -f /usr/local/bin/traffic-start
rm -f /usr/local/bin/traffic-stop
rm -f /usr/local/bin/traffic-view
rm -f /usr/local/bin/traffic-status
rm -f /usr/local/bin/traffic-analyze
rm -f /usr/local/bin/traffic-enable-redirect
rm -f /usr/local/bin/traffic-disable-redirect

# Eliminar configuración
rm -f /etc/traffic-interceptor.conf

# Limpiar reglas iptables
echo "Limpiando reglas de firewall..."
iptables -t nat -D OUTPUT -p tcp --dport 80 -j REDIRECT --to-port 8080 2>/dev/null
iptables -t nat -D OUTPUT -p tcp --dport 443 -j REDIRECT --to-port 8080 2>/dev/null

# Preguntar sobre logs
echo ""
echo -n "¿Eliminar todos los logs capturados? (s/n): "
read delete_logs

if [ "$delete_logs" = "s" ] || [ "$delete_logs" = "S" ]; then
    rm -rf /var/log/traffic-interceptor
    echo "Logs eliminados"
else
    echo -e "${YELLOW}Logs conservados en /var/log/traffic-interceptor/${NC}"
fi

# Preguntar sobre mitmproxy
echo ""
echo -n "¿Desinstalar mitmproxy? (s/n): "
read uninstall_mitm

if [ "$uninstall_mitm" = "s" ] || [ "$uninstall_mitm" = "S" ]; then
    pip3 uninstall -y mitmproxy 2>/dev/null
    echo "mitmproxy desinstalado"
fi

echo ""
echo -e "${GREEN}✓ Desinstalación completada${NC}"
echo ""
