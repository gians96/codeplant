#!/bin/bash
# Análisis avanzado de tráfico capturado

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
ANALYSIS_DIR="$LOG_DIR/analysis"

mkdir -p "$ANALYSIS_DIR"

echo ""
echo -e "${BLUE}=========================================="
echo "    Análisis de Tráfico Interceptado"
echo "==========================================${NC}"
echo ""

# Buscar último archivo PCAP
LATEST_PCAP=$(ls -t "$PCAP_DIR"/*.pcap 2>/dev/null | head -1)

if [ -z "$LATEST_PCAP" ]; then
    echo -e "${RED}No hay archivos PCAP para analizar${NC}"
    exit 1
fi

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
REPORT_FILE="$ANALYSIS_DIR/report-$TIMESTAMP.txt"

echo -e "${YELLOW}Analizando:${NC} $(basename $LATEST_PCAP)"
echo ""

{
    echo "=========================================="
    echo "  REPORTE DE ANÁLISIS DE TRÁFICO"
    echo "  Generado: $(date)"
    echo "=========================================="
    echo ""
    echo "Archivo analizado: $LATEST_PCAP"
    echo ""
    
    echo "=========================================="
    echo "1. TOP 20 DOMINIOS/IPs CONTACTADOS"
    echo "=========================================="
    tcpdump -r "$LATEST_PCAP" -n 2>/dev/null | \
        awk '{print $5}' | \
        cut -d':' -f1 | \
        sort | uniq -c | sort -rn | head -20
    
    echo ""
    echo "=========================================="
    echo "2. DISTRIBUCIÓN POR PUERTOS"
    echo "=========================================="
    tcpdump -r "$LATEST_PCAP" -n 2>/dev/null | \
        grep -oE '(:[0-9]+)' | \
        cut -d':' -f2 | \
        sort | uniq -c | sort -rn | head -10
    
    echo ""
    echo "=========================================="
    echo "3. PETICIONES HTTP (Host headers)"
    echo "=========================================="
    tcpdump -r "$LATEST_PCAP" -A 2>/dev/null | \
        grep -i "Host:" | \
        sort | uniq -c | sort -rn | head -20
    
    echo ""
    echo "=========================================="
    echo "4. USER AGENTS DETECTADOS"
    echo "=========================================="
    tcpdump -r "$LATEST_PCAP" -A 2>/dev/null | \
        grep -i "User-Agent:" | \
        sort | uniq | head -10
    
    echo ""
    echo "=========================================="
    echo "5. MÉTODOS HTTP"
    echo "=========================================="
    tcpdump -r "$LATEST_PCAP" -A 2>/dev/null | \
        grep -oE '(GET|POST|PUT|DELETE|HEAD|OPTIONS|PATCH)' | \
        sort | uniq -c | sort -rn
    
    echo ""
    echo "=========================================="
    echo "6. ESTADÍSTICAS GENERALES"
    echo "=========================================="
    TOTAL_PACKETS=$(tcpdump -r "$LATEST_PCAP" 2>&1 | tail -1 | awk '{print $1}')
    FILE_SIZE=$(du -h "$LATEST_PCAP" | awk '{print $1}')
    
    echo "Total de paquetes: $TOTAL_PACKETS"
    echo "Tamaño del archivo: $FILE_SIZE"
    
    echo ""
    echo "=========================================="
    echo "7. CONEXIONES HTTPS (puerto 443)"
    echo "=========================================="
    tcpdump -r "$LATEST_PCAP" -n 'port 443' 2>/dev/null | \
        awk '{print $3, "->", $5}' | \
        head -20
    
} | tee "$REPORT_FILE"

echo ""
echo -e "${GREEN}✓ Análisis completado${NC}"
echo -e "${YELLOW}Reporte guardado en:${NC} $REPORT_FILE"
echo ""
echo -e "${BLUE}Comandos adicionales útiles:${NC}"
echo "  # Ver URLs completas"
echo "  tcpdump -r $LATEST_PCAP -A | grep -i 'GET\\|POST\\|Host:'"
echo ""
echo "  # Extraer solo tráfico de un dominio"
echo "  tcpdump -r $LATEST_PCAP -n 'host google.com'"
echo ""
echo "  # Ver solo headers HTTP"
echo "  tcpdump -r $LATEST_PCAP -A | grep -E '^(GET|POST|Host:|Cookie:)'"
echo ""
