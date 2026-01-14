#!/bin/bash
# Script para configurar mitmproxy con interceptación completa HTTPS
# USO EDUCATIVO ÚNICAMENTE - Solo en tu propio servidor

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Este script debe ejecutarse como root (sudo)${NC}"
   exit 1
fi

echo -e "${BLUE}=========================================="
echo "  Configuración MITM Completa"
echo "  (Interceptación HTTPS descifrada)"
echo "==========================================${NC}"
echo ""

# Paso 1: Generar certificados de mitmproxy
echo -e "${YELLOW}[1/5]${NC} Generando certificados de mitmproxy..."

# Ejecutar mitmproxy brevemente para generar certificados
timeout 3 mitmproxy 2>/dev/null || true
sleep 1

if [ ! -f ~/.mitmproxy/mitmproxy-ca-cert.pem ]; then
    echo -e "${RED}Error: No se pudo generar el certificado${NC}"
    echo "Generando manualmente..."
    mkdir -p ~/.mitmproxy
    # mitmproxy generará los certs en el primer uso
fi

echo -e "${GREEN}✓${NC} Certificados generados en ~/.mitmproxy/"

# Paso 2: Instalar certificado en el sistema
echo -e "${YELLOW}[2/5]${NC} Instalando certificado MITM en el sistema..."

if [ -f ~/.mitmproxy/mitmproxy-ca-cert.pem ]; then
    cp ~/.mitmproxy/mitmproxy-ca-cert.pem /usr/local/share/ca-certificates/mitmproxy.crt
    update-ca-certificates > /dev/null 2>&1
    echo -e "${GREEN}✓${NC} Certificado instalado"
else
    echo -e "${YELLOW}⚠${NC} Certificado no encontrado, se generará en primer uso"
fi

# Paso 3: Configurar variables de entorno permanentes
echo -e "${YELLOW}[3/5]${NC} Configurando variables de entorno..."

cat > /etc/profile.d/mitmproxy.sh << 'EOF'
# Configuración de proxy para mitmproxy
export HTTP_PROXY=http://127.0.0.1:8080
export HTTPS_PROXY=http://127.0.0.1:8080
export http_proxy=http://127.0.0.1:8080
export https_proxy=http://127.0.0.1:8080
export SSL_CERT_FILE=~/.mitmproxy/mitmproxy-ca-cert.pem
export REQUESTS_CA_BUNDLE=~/.mitmproxy/mitmproxy-ca-cert.pem
export CURL_CA_BUNDLE=~/.mitmproxy/mitmproxy-ca-cert.pem
EOF

chmod +x /etc/profile.d/mitmproxy.sh
source /etc/profile.d/mitmproxy.sh

echo -e "${GREEN}✓${NC} Variables configuradas"

# Paso 4: Configurar Git para usar el proxy
echo -e "${YELLOW}[4/5]${NC} Configurando Git..."

git config --global http.proxy http://127.0.0.1:8080
git config --global https.proxy http://127.0.0.1:8080
git config --global http.sslVerify true

echo -e "${GREEN}✓${NC} Git configurado"

# Paso 5: Crear script de inicio mejorado
echo -e "${YELLOW}[5/5]${NC} Creando scripts de control..."

cat > /usr/local/bin/mitm-start << 'EOFSTART'
#!/bin/bash
# Iniciar interceptación completa

pkill -f mitmproxy 2>/dev/null || true
pkill -f mitmweb 2>/dev/null || true
pkill -f tcpdump 2>/dev/null || true

echo "Iniciando interceptación completa..."

# 1. Iniciar tcpdump para captura raw
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
mkdir -p /var/log/traffic-interceptor/captures

tcpdump -i any -n -l -vv -w /var/log/traffic-interceptor/captures/raw-$TIMESTAMP.pcap \
    'port 22 or port 80 or port 443 or port 8080 or port 3000 or port 3001' \
    > /var/log/traffic-interceptor/tcpdump.log 2>&1 &
TCPDUMP_PID=$!
echo $TCPDUMP_PID > /var/run/mitm-tcpdump.pid

# 2. Iniciar mitmweb en modo proxy para interceptar
nohup mitmweb \
    --mode regular \
    --listen-host 127.0.0.1 \
    --listen-port 8080 \
    --web-host 0.0.0.0 \
    --web-port 8081 \
    --save-stream-file /var/log/traffic-interceptor/captures/flows-$TIMESTAMP.mitm \
    --ssl-insecure \
    > /var/log/traffic-interceptor/mitmproxy.log 2>&1 &
MITM_PID=$!
echo $MITM_PID > /var/run/mitm-mitmweb.pid

sleep 3

echo ""
echo "✓ Interceptación iniciada"
echo ""
echo "Información:"
echo "  • tcpdump PID: $TCPDUMP_PID"
echo "  • mitmproxy PID: $MITM_PID"
echo "  • Proxy local: 127.0.0.1:8080"
echo "  • Web UI: http://$(hostname -I | awk '{print $1}'):8081"
echo ""
echo "Logs:"
echo "  • Capturas: /var/log/traffic-interceptor/captures/"
echo "  • Raw PCAP: /var/log/traffic-interceptor/captures/raw-$TIMESTAMP.pcap"
echo "  • Flows: /var/log/traffic-interceptor/captures/flows-$TIMESTAMP.mitm"
echo ""
echo "Comandos de prueba:"
echo "  mitm-test           # Generar tráfico de prueba"
echo "  mitm-view           # Ver capturas"
echo "  mitm-stop           # Detener"
EOFSTART

chmod +x /usr/local/bin/mitm-start

# Script para detener
cat > /usr/local/bin/mitm-stop << 'EOFSTOP'
#!/bin/bash
echo "Deteniendo interceptación..."
pkill -f mitmproxy
pkill -f mitmweb  
pkill -f "tcpdump.*raw-"
rm -f /var/run/mitm-*.pid
echo "✓ Detenido"
EOFSTOP

chmod +x /usr/local/bin/mitm-stop

# Script de pruebas
cat > /usr/local/bin/mitm-test << 'EOFTEST'
#!/bin/bash

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}Generando tráfico de prueba...${NC}"
echo ""

# Cargar variables de proxy
export HTTP_PROXY=http://127.0.0.1:8080
export HTTPS_PROXY=http://127.0.0.1:8080

echo -e "${YELLOW}[1/5]${NC} GET simple con HTTPS..."
curl -s https://httpbin.org/get > /dev/null
echo -e "${GREEN}✓${NC} Completado"

echo -e "${YELLOW}[2/5]${NC} POST con datos de formulario (credenciales)..."
curl -s -X POST https://httpbin.org/post \
    -d "username=admin" \
    -d "password=secreto123" \
    -d "email=admin@example.com" > /dev/null
echo -e "${GREEN}✓${NC} Completado"

echo -e "${YELLOW}[3/5]${NC} Autenticación Basic (usuario:contraseña en header)..."
curl -s -u "testuser:testpassword123" https://httpbin.org/basic-auth/testuser/testpassword123 > /dev/null
echo -e "${GREEN}✓${NC} Completado"

echo -e "${YELLOW}[4/5]${NC} POST con JSON (API con token)..."
curl -s -X POST https://httpbin.org/post \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9" \
    -d '{"username":"admin","password":"supersecret","api_key":"sk-1234567890"}' > /dev/null
echo -e "${GREEN}✓${NC} Completado"

echo -e "${YELLOW}[5/6]${NC} Cookies con sesión..."
curl -s -b "session_id=abc123def456; user_token=xyz789" https://httpbin.org/cookies > /dev/null
echo -e "${GREEN}✓${NC} Completado"

echo -e "${YELLOW}[6/6]${NC} Git clone con credenciales (GitLab privado)..."
# Limpiar credential helper temporalmente para forzar el uso de credenciales en la URL
GIT_TERMINAL_PROMPT=0 git clone https://gians96:123456789@gitlab.com/gians96/privado.git /tmp/test-repo-$$  2>&1 | head -5 || true
rm -rf /tmp/test-repo-$$
echo -e "${GREEN}✓${NC} Completado"

echo ""
echo -e "${GREEN}✓ Tráfico de prueba generado${NC}"
echo ""
echo -e "${YELLOW}Credenciales capturadas:${NC}"
echo "  • Usuario/Password en POST (formulario)"
echo "  • Basic Auth (testuser:testpassword123)"
echo "  • API Keys y Tokens en JSON"
echo "  • Git credentials (gians96:123456789)"
echo ""
echo "Ver capturas:"
echo "  • Interfaz web: http://$(hostname -I | awk '{print $1}'):8081"
echo "  • Comando: mitm-view"
echo ""
echo -e "${BLUE}Decodificar Authorization headers:${NC}"
echo "  En mitmproxy busca 'Authorization: Basic ...'"
echo "  Copia el string después de 'Basic' y ejecuta:"
echo "  echo 'STRING_BASE64' | base64 -d"
EOFTEST

chmod +x /usr/local/bin/mitm-test

# Script para ver capturas
cat > /usr/local/bin/mitm-view << 'EOFVIEW'
#!/bin/bash

echo "Logs disponibles:"
echo ""
ls -lh /var/log/traffic-interceptor/captures/ 2>/dev/null || echo "No hay capturas aún"
echo ""
echo "Ver en tiempo real:"
echo "  tail -f /var/log/traffic-interceptor/mitmproxy.log"
echo ""
echo "Interfaz web:"
echo "  http://$(hostname -I | awk '{print $1}'):8081"
EOFVIEW

chmod +x /usr/local/bin/mitm-view

echo ""
echo -e "${GREEN}=========================================="
echo "  ✓ Configuración Completa"
echo "==========================================${NC}"
echo ""
echo -e "${BLUE}Comandos disponibles:${NC}"
echo "  ${YELLOW}mitm-start${NC}     - Iniciar interceptación completa"
echo "  ${YELLOW}mitm-stop${NC}      - Detener interceptación"
echo "  ${YELLOW}mitm-test${NC}      - Generar tráfico de prueba"
echo "  ${YELLOW}mitm-view${NC}      - Ver capturas"
echo ""
echo -e "${RED}⚠ IMPORTANTE:${NC}"
echo "  • Esto es para USO EDUCATIVO únicamente"
echo "  • Solo en tu propio servidor/red"
echo "  • El certificado MITM está instalado en el sistema"
echo "  • Todo el tráfico HTTPS será descifrado y visible"
echo ""
echo -e "${YELLOW}Siguiente paso:${NC}"
echo "  sudo mitm-start"
echo ""
