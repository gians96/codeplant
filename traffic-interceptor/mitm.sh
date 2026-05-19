#!/bin/bash
# MITM Traffic Interceptor - Script Todo-en-Uno
# Instalación, control, monitoreo y diagnóstico
# Uso: sudo ./mitm.sh [comando]

VERSION="1.0"
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

CAPTURE_DIR="/var/log/traffic-interceptor/captures"
LOG_FILE="/var/log/traffic-interceptor/mitmproxy.log"

# ============================================
# FUNCIONES DE INSTALACIÓN
# ============================================

install_mitm() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Debes ejecutar la instalación como root (sudo)${NC}"
        exit 1
    fi
    
    echo -e "${BLUE}=========================================="
    echo "  Instalando MITM Traffic Interceptor"
    echo "==========================================${NC}"
    echo ""
    
    echo -e "${YELLOW}[1/5]${NC} Instalando dependencias..."
    apt-get update -qq > /dev/null 2>&1
    apt-get install -y mitmproxy tcpdump curl net-tools -qq > /dev/null 2>&1
    
    echo -e "${YELLOW}[2/5]${NC} Creando directorios..."
    mkdir -p $CAPTURE_DIR
    chmod -R 777 /var/log/traffic-interceptor
    
    echo -e "${YELLOW}[3/5]${NC} Generando certificados MITM..."
    timeout 3 mitmproxy 2>/dev/null || true
    if [ -f ~/.mitmproxy/mitmproxy-ca-cert.pem ]; then
        cp ~/.mitmproxy/mitmproxy-ca-cert.pem /usr/local/share/ca-certificates/mitmproxy.crt
        update-ca-certificates > /dev/null 2>&1
    fi
    
    echo -e "${YELLOW}[4/5]${NC} Configurando Git..."
    git config --global http.proxy http://127.0.0.1:8080
    git config --global https.proxy http://127.0.0.1:8080
    git config --global --unset credential.helper 2>/dev/null || true
    
    echo -e "${YELLOW}[5/5]${NC} Creando comando global..."
    SCRIPT_PATH="$(readlink -f "$0")"
    ln -sf "$SCRIPT_PATH" /usr/local/bin/mitm
    chmod +x /usr/local/bin/mitm
    
    echo ""
    echo -e "${GREEN}✓ Instalación completada${NC}"
    echo ""
    echo -e "${BLUE}Comandos disponibles:${NC}"
    echo "  ${YELLOW}mitm start${NC}      - Iniciar interceptación"
    echo "  ${YELLOW}mitm stop${NC}       - Detener"
    echo "  ${YELLOW}mitm status${NC}     - Ver estado"
    echo "  ${YELLOW}mitm monitor${NC}    - Monitor en tiempo real"
    echo "  ${YELLOW}mitm test${NC}       - Generar tráfico de prueba"
    echo "  ${YELLOW}mitm view${NC}       - Ver capturas guardadas"
    echo "  ${YELLOW}mitm diagnose${NC}   - Diagnosticar problemas"
    echo ""
}

# ============================================
# FUNCIONES DE CONTROL
# ============================================

start_mitm() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Debes ejecutar como root: sudo mitm start${NC}"
        exit 1
    fi
    
    # Detener instancias previas
    pkill -f mitmproxy 2>/dev/null || true
    pkill -f mitmweb 2>/dev/null || true
    pkill -f "tcpdump.*raw-" 2>/dev/null || true
    sleep 1
    
    echo "Iniciando MITM..."
    
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    mkdir -p $CAPTURE_DIR
    
    # Iniciar tcpdump
    nohup tcpdump -i any -n -l -vv -w $CAPTURE_DIR/raw-$TIMESTAMP.pcap \
        'port 22 or port 80 or port 443 or port 8080 or port 3000 or port 3001' \
        > /var/log/traffic-interceptor/tcpdump.log 2>&1 &
    TCPDUMP_PID=$!
    
    # Iniciar mitmweb
    nohup mitmweb \
        --mode regular \
        --listen-host 127.0.0.1 \
        --listen-port 8080 \
        --web-host 0.0.0.0 \
        --web-port 8081 \
        --save-stream-file $CAPTURE_DIR/flows-$TIMESTAMP.mitm \
        --ssl-insecure \
        > $LOG_FILE 2>&1 &
    MITM_PID=$!
    
    sleep 3
    
    # Verificar que estén corriendo
    if ps -p $MITM_PID > /dev/null && ps -p $TCPDUMP_PID > /dev/null; then
        IP=$(hostname -I | awk '{print $1}')
        echo ""
        echo -e "${GREEN}✓ MITM iniciado correctamente${NC}"
        echo ""
        echo "Información:"
        echo "  • tcpdump PID: $TCPDUMP_PID"
        echo "  • mitmproxy PID: $MITM_PID"
        echo "  • Proxy: 127.0.0.1:8080"
        echo "  • Web UI: ${CYAN}http://$IP:8081${NC}"
        echo ""
        echo "Capturas en: $CAPTURE_DIR"
        echo ""
        echo "Ver estado: ${YELLOW}mitm status${NC}"
        echo "Monitor: ${YELLOW}mitm monitor${NC}"
    else
        echo -e "${RED}✗ Error al iniciar MITM${NC}"
        echo "Ver logs: tail -f $LOG_FILE"
        exit 1
    fi
}

stop_mitm() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Debes ejecutar como root: sudo mitm stop${NC}"
        exit 1
    fi
    
    echo "Deteniendo MITM..."
    pkill -f mitmproxy
    pkill -f mitmweb  
    pkill -f "tcpdump.*raw-"
    sleep 1
    echo -e "${GREEN}✓ Detenido${NC}"
}

status_mitm() {
    echo -e "${BLUE}========== Estado MITM ==========${NC}"
    echo ""
    
    MITM_PID=$(pgrep -f "mitmweb|mitmproxy" | head -1)
    TCPDUMP_PID=$(pgrep -f "tcpdump.*raw-" | head -1)
    
    # Procesos
    if [ -n "$MITM_PID" ]; then
        MEM=$(ps -p $MITM_PID -o %mem --no-headers | tr -d ' ')
        CPU=$(ps -p $MITM_PID -o %cpu --no-headers | tr -d ' ')
        TIME=$(ps -p $MITM_PID -o etime --no-headers | tr -d ' ')
        echo -e "${GREEN}✓${NC} mitmproxy: PID $MITM_PID (CPU: ${CPU}%, MEM: ${MEM}%, Tiempo: $TIME)"
    else
        echo -e "${RED}✗${NC} mitmproxy NO está corriendo"
    fi
    
    if [ -n "$TCPDUMP_PID" ]; then
        echo -e "${GREEN}✓${NC} tcpdump: PID $TCPDUMP_PID"
    else
        echo -e "${RED}✗${NC} tcpdump NO está corriendo"
    fi
    
    echo ""
    
    # Puertos
    if netstat -tlnp 2>/dev/null | grep -q :8080 || ss -tlnp 2>/dev/null | grep -q :8080; then
        echo -e "${GREEN}✓${NC} Puerto 8080 (proxy) activo"
    else
        echo -e "${RED}✗${NC} Puerto 8080 NO activo"
    fi
    
    if netstat -tlnp 2>/dev/null | grep -q :8081 || ss -tlnp 2>/dev/null | grep -q :8081; then
        IP=$(hostname -I | awk '{print $1}')
        echo -e "${GREEN}✓${NC} Interfaz web: ${CYAN}http://$IP:8081${NC}"
    else
        echo -e "${RED}✗${NC} Interfaz web NO activa"
    fi
    
    echo ""
    
    # Capturas
    if [ -d "$CAPTURE_DIR" ]; then
        LATEST_FLOW=$(ls -t $CAPTURE_DIR/flows-*.mitm 2>/dev/null | head -1)
        if [ -n "$LATEST_FLOW" ]; then
            FLOW_COUNT=$(mitmdump -r "$LATEST_FLOW" 2>/dev/null | wc -l)
            FILE_SIZE=$(du -h "$LATEST_FLOW" | awk '{print $1}')
            echo -e "${GREEN}✓${NC} Flows capturados: $FLOW_COUNT (tamaño: $FILE_SIZE)"
            echo "  Archivo: $(basename $LATEST_FLOW)"
        else
            echo -e "${YELLOW}⚠${NC} Sin capturas aún"
        fi
    fi
    
    echo ""
    
    # Git config
    GIT_HTTP=$(git config --global http.proxy 2>/dev/null)
    if [ "$GIT_HTTP" = "http://127.0.0.1:8080" ]; then
        echo -e "${GREEN}✓${NC} Git configurado correctamente"
    else
        echo -e "${RED}✗${NC} Git NO configurado (http.proxy: ${GIT_HTTP:-no configurado})"
    fi
    
    echo ""
}

monitor_mitm() {
    echo -e "${BLUE}Monitor en tiempo real (Ctrl+C para salir)${NC}"
    echo ""
    
    while true; do
        clear
        echo -e "${BLUE}========== Monitor MITM - $(date '+%H:%M:%S') ==========${NC}"
        echo ""
        
        MITM_PID=$(pgrep -f "mitmweb|mitmproxy" | head -1)
        
        if [ -n "$MITM_PID" ]; then
            MEM=$(ps -p $MITM_PID -o %mem --no-headers | tr -d ' ')
            CPU=$(ps -p $MITM_PID -o %cpu --no-headers | tr -d ' ')
            echo -e "${GREEN}✓ Activo${NC} - PID: $MITM_PID - CPU: ${CPU}% - MEM: ${MEM}%"
        else
            echo -e "${RED}✗ NO está corriendo${NC}"
        fi
        
        echo ""
        
        # Últimos flows
        LATEST_FLOW=$(ls -t $CAPTURE_DIR/flows-*.mitm 2>/dev/null | head -1)
        if [ -n "$LATEST_FLOW" ]; then
            FLOW_COUNT=$(mitmdump -r "$LATEST_FLOW" 2>/dev/null | wc -l)
            echo "Flows capturados: $FLOW_COUNT"
            echo ""
            echo "Últimos 5 flows:"
            mitmdump -r "$LATEST_FLOW" 2>/dev/null | tail -5
        fi
        
        echo ""
        echo -e "${CYAN}Actualizando cada 3s...${NC}"
        sleep 3
    done
}

test_mitm() {
    echo -e "${BLUE}Generando tráfico de prueba...${NC}"
    echo ""
    
    export HTTP_PROXY=http://127.0.0.1:8080
    export HTTPS_PROXY=http://127.0.0.1:8080
    
    echo -e "${YELLOW}[1/4]${NC} GET HTTPS..."
    curl -s https://httpbin.org/get > /dev/null && echo -e "${GREEN}✓${NC}"
    
    echo -e "${YELLOW}[2/4]${NC} POST con credenciales..."
    curl -s -X POST https://httpbin.org/post -d "username=admin&password=secret123" > /dev/null && echo -e "${GREEN}✓${NC}"
    
    echo -e "${YELLOW}[3/4]${NC} Basic Auth..."
    curl -s -u "testuser:testpass123" https://httpbin.org/basic-auth/testuser/testpass123 > /dev/null && echo -e "${GREEN}✓${NC}"
    
    echo -e "${YELLOW}[4/4]${NC} POST JSON con token..."
    curl -s -X POST https://httpbin.org/post \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer token123456" \
        -d '{"user":"admin","pass":"secret"}' > /dev/null && echo -e "${GREEN}✓${NC}"
    
    echo ""
    echo -e "${GREEN}✓ Tráfico generado${NC}"
    IP=$(hostname -I | awk '{print $1}')
    echo "Ver en: ${CYAN}http://$IP:8081${NC}"
}

view_mitm() {
    echo -e "${BLUE}========== Capturas MITM ==========${NC}"
    echo ""
    
    if [ ! -d "$CAPTURE_DIR" ]; then
        echo -e "${RED}No hay directorio de capturas${NC}"
        exit 1
    fi
    
    ls -lh $CAPTURE_DIR/
    echo ""
    
    FLOW_FILES=$(ls $CAPTURE_DIR/flows-*.mitm 2>/dev/null | wc -l)
    echo "Total archivos: $FLOW_FILES"
    echo ""
    
    if [ $FLOW_FILES -eq 0 ]; then
        echo -e "${YELLOW}Sin capturas aún${NC}"
        exit 0
    fi
    
    LATEST_FLOW=$(ls -t $CAPTURE_DIR/flows-*.mitm | head -1)
    echo -e "${YELLOW}Archivo más reciente:${NC} $(basename $LATEST_FLOW)"
    echo ""
    
    echo "Opciones:"
    echo "1. Ver lista de flows"
    echo "2. Buscar por dominio"
    echo "3. Buscar credenciales (Authorization)"
    echo "4. Ver dominios contactados"
    echo "5. Analizar interactivo"
    echo ""
    read -p "Selecciona [1-5]: " option
    
    case $option in
        1)
            mitmdump -r "$LATEST_FLOW" 2>/dev/null | less
            ;;
        2)
            read -p "Dominio: " domain
            mitmdump -r "$LATEST_FLOW" 2>/dev/null | grep -i "$domain"
            ;;
        3)
            echo ""
            echo "Buscando Authorization headers..."
            mitmdump -r "$LATEST_FLOW" 2>/dev/null | grep -i "authorization"
            echo ""
            echo "Para decodificar: echo 'BASE64_STRING' | base64 -d"
            ;;
        4)
            mitmdump -r "$LATEST_FLOW" 2>/dev/null | grep -oP 'https?://[^/]+' | sort -u
            ;;
        5)
            mitmproxy -r "$LATEST_FLOW"
            ;;
    esac
}

diagnose_mitm() {
    echo -e "${BLUE}========== Diagnóstico MITM ==========${NC}"
    echo ""
    
    ISSUES=0
    
    # 1. Proceso
    echo -n "1. Proceso mitmproxy: "
    if pgrep -f "mitmweb|mitmproxy" > /dev/null; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
        ((ISSUES++))
    fi
    
    # 2. Puerto
    echo -n "2. Puerto 8080: "
    if netstat -tlnp 2>/dev/null | grep -q :8080 || ss -tlnp 2>/dev/null | grep -q :8080; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
        ((ISSUES++))
    fi
    
    # 3. Git config
    echo -n "3. Git http.proxy: "
    if [ "$(git config --global http.proxy)" = "http://127.0.0.1:8080" ]; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
        ((ISSUES++))
    fi
    
    echo -n "4. Git https.proxy: "
    if [ "$(git config --global https.proxy)" = "http://127.0.0.1:8080" ]; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
        ((ISSUES++))
    fi
    
    # 5. Test conectividad
    echo -n "5. Test proxy: "
    if curl -s -x http://127.0.0.1:8080 --connect-timeout 2 https://httpbin.org/ip > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
        ((ISSUES++))
    fi
    
    echo ""
    
    if [ $ISSUES -eq 0 ]; then
        echo -e "${GREEN}✓ Todo funcionando correctamente${NC}"
    else
        echo -e "${RED}✗ Problemas encontrados: $ISSUES${NC}"
        echo ""
        echo "Soluciones:"
        echo "  ${YELLOW}sudo mitm stop${NC}    # Detener"
        echo "  ${YELLOW}sudo mitm start${NC}   # Iniciar"
    fi
}

uninstall_mitm() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Debes ejecutar como root: sudo mitm uninstall${NC}"
        exit 1
    fi
    
    echo -e "${RED}========== Desinstalar MITM ==========${NC}"
    echo ""
    read -p "¿Estás seguro? Esto eliminará todos los datos [y/N]: " confirm
    
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo "Cancelado"
        exit 0
    fi
    
    echo ""
    echo "Deteniendo servicios..."
    pkill -f mitmproxy 2>/dev/null
    pkill -f mitmweb 2>/dev/null
    pkill -f tcpdump 2>/dev/null
    
    echo "Eliminando archivos..."
    rm -rf /var/log/traffic-interceptor
    rm -f /usr/local/bin/mitm
    rm -f /etc/profile.d/mitmproxy.sh
    rm -f /usr/local/share/ca-certificates/mitmproxy.crt
    
    echo "Limpiando configuración Git..."
    git config --global --unset http.proxy 2>/dev/null
    git config --global --unset https.proxy 2>/dev/null
    
    update-ca-certificates > /dev/null 2>&1
    
    echo ""
    echo -e "${GREEN}✓ MITM desinstalado${NC}"
}

# ============================================
# MENÚ PRINCIPAL
# ============================================

show_help() {
    echo ""
    echo -e "${BLUE}MITM Traffic Interceptor v$VERSION${NC}"
    echo ""
    echo "Uso: mitm [comando]"
    echo ""
    echo "Comandos:"
    echo "  ${YELLOW}install${NC}     - Instalar MITM (solo primera vez)"
    echo "  ${YELLOW}start${NC}       - Iniciar interceptación"
    echo "  ${YELLOW}stop${NC}        - Detener interceptación"
    echo "  ${YELLOW}status${NC}      - Ver estado actual"
    echo "  ${YELLOW}monitor${NC}     - Monitor en tiempo real"
    echo "  ${YELLOW}test${NC}        - Generar tráfico de prueba"
    echo "  ${YELLOW}view${NC}        - Ver capturas guardadas"
    echo "  ${YELLOW}diagnose${NC}    - Diagnosticar problemas"
    echo "  ${YELLOW}uninstall${NC}   - Desinstalar completamente"
    echo "  ${YELLOW}help${NC}        - Mostrar esta ayuda"
    echo ""
    echo "Ejemplos:"
    echo "  sudo mitm install   # Primera instalación"
    echo "  sudo mitm start     # Iniciar"
    echo "  mitm status         # Ver estado"
    echo "  mitm monitor        # Monitorear en vivo"
    echo ""
}

# ============================================
# EJECUTAR COMANDO
# ============================================

case "${1:-help}" in
    install)
        install_mitm
        ;;
    start)
        start_mitm
        ;;
    stop)
        stop_mitm
        ;;
    status)
        status_mitm
        ;;
    monitor)
        monitor_mitm
        ;;
    test)
        test_mitm
        ;;
    view)
        view_mitm
        ;;
    diagnose)
        diagnose_mitm
    uninstall)
        uninstall_mitm
        ;;
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo -e "${RED}Comando desconocido: $1${NC}"
        show_help
        exit 1
        ;;
esac
