#!/bin/bash
# Ver logs capturados del interceptor

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Este comando debe ejecutarse como root (sudo)${NC}"
   exit 1
fi

LOG_DIR="/var/log/traffic-interceptor"
PCAP_DIR="$LOG_DIR/pcap"
MITM_DIR="$LOG_DIR/mitmproxy"

show_menu() {
    clear
    echo ""
    echo -e "${BLUE}=========================================="
    echo "    Visor de Logs - Traffic Interceptor"
    echo "==========================================${NC}"
    echo ""
    echo "1) Ver tráfico en tiempo real (tcpdump)"
    echo "2) Listar archivos PCAP capturados"
    echo "3) Analizar archivo PCAP específico"
    echo "4) Ver últimas 50 conexiones"
    echo "5) Buscar por dominio/IP"
    echo "6) Ver estadísticas generales"
    echo "7) Abrir interfaz web mitmproxy"
    echo "0) Salir"
    echo ""
}

view_realtime() {
    echo -e "${GREEN}Tráfico en tiempo real (Ctrl+C para salir):${NC}"
    echo "=========================================="
    tcpdump -i any -n 'port 80 or port 443' -A
}

list_pcap_files() {
    echo ""
    echo -e "${YELLOW}Archivos PCAP capturados:${NC}"
    echo ""
    if [ -d "$PCAP_DIR" ]; then
        ls -lh "$PCAP_DIR"/*.pcap 2>/dev/null | awk '{print NR") " $9 " (" $5 ")"}'
    else
        echo -e "${RED}No hay archivos PCAP${NC}"
    fi
}

analyze_pcap() {
    list_pcap_files
    echo ""
    echo -n "Ingresa el número del archivo (0 para cancelar): "
    read file_num
    
    if [ "$file_num" != "0" ] && [ -n "$file_num" ]; then
        selected=$(ls "$PCAP_DIR"/*.pcap 2>/dev/null | sed -n "${file_num}p")
        if [ -n "$selected" ]; then
            echo ""
            echo -e "${GREEN}Analizando: $selected${NC}"
            echo "=========================================="
            echo ""
            echo "Mostrando primeras 100 líneas (usa less para navegación completa)"
            echo ""
            tcpdump -r "$selected" -n -A | head -100
            echo ""
            echo -e "${YELLOW}Para ver completo:${NC} tcpdump -r $selected -A | less"
        fi
    fi
}

last_connections() {
    echo ""
    echo -e "${GREEN}Últimas 50 conexiones:${NC}"
    echo "=========================================="
    latest=$(ls -t "$PCAP_DIR"/*.pcap 2>/dev/null | head -1)
    if [ -n "$latest" ]; then
        tcpdump -r "$latest" -n | tail -50
    else
        echo -e "${RED}No hay archivos PCAP disponibles${NC}"
    fi
}

search_domain() {
    echo -n "Ingresa dominio o IP a buscar: "
    read search_term
    if [ -n "$search_term" ]; then
        echo ""
        echo -e "${YELLOW}Buscando '$search_term'...${NC}"
        echo "=========================================="
        for pcap in "$PCAP_DIR"/*.pcap; do
            if [ -f "$pcap" ]; then
                echo ""
                echo "En: $(basename $pcap)"
                tcpdump -r "$pcap" -n | grep -i "$search_term" | head -20
            fi
        done
    fi
}

show_statistics() {
    echo ""
    echo -e "${GREEN}Estadísticas generales:${NC}"
    echo "=========================================="
    latest=$(ls -t "$PCAP_DIR"/*.pcap 2>/dev/null | head -1)
    if [ -n "$latest" ]; then
        echo ""
        echo "Archivo más reciente: $(basename $latest)"
        echo ""
        echo "Top 10 IPs de destino:"
        tcpdump -r "$latest" -n | awk '{print $5}' | cut -d':' -f1 | sort | uniq -c | sort -rn | head -10
        echo ""
        echo "Conteo por puerto:"
        tcpdump -r "$latest" -n | awk '{print $5}' | cut -d':' -f2 | cut -d'.' -f1 | sort | uniq -c | sort -rn
    else
        echo -e "${RED}No hay archivos PCAP disponibles${NC}"
    fi
}

open_web_interface() {
    IP=$(hostname -I | awk '{print $1}')
    echo ""
    echo -e "${BLUE}Interfaz web de mitmproxy:${NC}"
    echo "  http://$IP:8081"
    echo ""
    echo "Abre esta URL en tu navegador"
    echo "(El interceptor debe estar corriendo)"
}

# Verificar si hay logs
if [ ! -d "$LOG_DIR" ]; then
    echo -e "${RED}No hay logs disponibles${NC}"
    echo "Inicia el interceptor primero: sudo traffic-start"
    exit 1
fi

# Menú interactivo
while true; do
    show_menu
    echo -n "Selecciona una opción: "
    read opcion
    
    case $opcion in
        1) view_realtime ;;
        2) list_pcap_files ;;
        3) analyze_pcap ;;
        4) last_connections ;;
        5) search_domain ;;
        6) show_statistics ;;
        7) open_web_interface ;;
        0) echo ""; echo "¡Hasta luego!"; exit 0 ;;
        *) echo -e "${RED}Opción inválida${NC}" ;;
    esac
    
    echo ""
    echo -n "Presiona Enter para continuar..."
    read
done
