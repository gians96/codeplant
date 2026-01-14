# Traffic Interceptor - Monitor de Tráfico HTTP/HTTPS/SSH

Sistema completo para interceptar, capturar y analizar tráfico HTTP/HTTPS/SSH en tu servidor usando tcpdump y mitmproxy.

## 🎯 Características

### Modo Básico (tcpdump)
- ✅ **tcpdump** - Captura todo el tráfico de red en tiempo real
- ✅ **Monitoreo multi-puerto** - SSH (22), HTTP (80), HTTPS (443), Docker (3001), Apps (8080)
- ✅ **Análisis automático** - Reportes de dominios, puertos, conexiones
- ✅ **Logs en texto plano** - Fácil de leer y procesar
- ✅ **Organizado** - Todo guardado en `/var/log/traffic-interceptor`

### Modo Avanzado (MITM con mitmproxy)
- 🔓 **Interceptación HTTPS** - Descifra tráfico HTTPS con certificado MITM
- 🌐 **Interfaz Web** - Vista gráfica en http://IP:8081
- 🔍 **Captura de credenciales** - Ve usuarios, contraseñas, tokens en texto plano
- 📊 **Análisis detallado** - Headers, body, cookies, todo visible
- ✅ **Probado exitosamente** - Captura credenciales de Git, APIs, formularios

## ⚠️ Advertencia Legal

**USO EDUCATIVO ÚNICAMENTE:**
- ✅ Solo en tu propio servidor/VPS
- ✅ Solo para entender cómo funciona la seguridad
- ✅ Solo con tu propio tráfico
- ❌ **NUNCA** interceptar tráfico de terceros sin consentimiento
- ❌ **ILEGAL** en muchos países si se usa maliciosamente

## 🚀 Instalación

### Modo Básico (Solo captura)

```bash
# 1. Dar permisos
chmod +x *.sh

# 2. Instalar
sudo ./install.sh
```

### Modo Avanzado (MITM completo)

```bash
# 1. Dar permisos
chmod +x setup-mitm-full.sh

# 2. Instalar sistema completo con interceptación HTTPS
sudo ./setup-mitm-full.sh

# Esto instala: tcpdump, mitmproxy, certificado CA, scripts de control
```

## 📋 Uso

### Modo Básico (Monitoreo Pasivo)

#### Iniciar el interceptor

```bash
sudo traffic-start
```

Captura tráfico en los puertos:
- **22** - SSH
- **80** - HTTP
- **443** - HTTPS  
- **3001** - Docker/MariaDB
- **8080** - Aplicaciones

Logs en `/var/log/traffic-interceptor/traffic-TIMESTAMP.txt`

#### Ver estado

```bash
sudo traffic-status
```

#### Ver logs capturados

```bash
sudo traffic-view
```

Menú interactivo:
1. Ver últimas 50 líneas
2. Ver últimas 100 líneas
3. Ver en tiempo real (tail -f)
4. Buscar por texto
5. Ver logs antiguos
6. Limpiar logs

#### Análisis avanzado

```bash
sudo traffic-analyze
```

Genera reporte con:
- Top IPs contactadas
- Distribución por puertos
- Conexiones activas
- Estadísticas generales

#### Detener

```bash
sudo traffic-stop
```

---

### Modo Avanzado (MITM - Interceptación HTTPS)

**Ver guía completa:** [MITM-GUIDE.md](MITM-GUIDE.md)

#### Iniciar interceptación completa

```bash
sudo mitm-start
```

Esto inicia:
- ✅ tcpdump capturando tráfico raw
- ✅ mitmproxy en modo proxy (puerto 8080)
- ✅ mitmweb interfaz en http://IP:8081
- ✅ Redirección automática de tráfico

#### Generar tráfico de prueba

```bash
mitm-test
```

Ejecuta pruebas automáticas:
- GET/POST HTTPS
- Formularios con credenciales
- Basic Authentication
- Tokens y API keys
- **Git clone con credenciales** (GitLab/GitHub)

#### Ver capturas en interfaz web

```bash
# Abre en tu navegador:
http://TU_IP:8081
```

Verás:
- Lista de todos los flows HTTP/HTTPS
- Detalles de cada request/response
- Headers, body, cookies
- **Credenciales en texto plano** (después de descifrar)

#### Ver credenciales capturadas

```bash
# Ver flows guardados
ls -lh /var/log/traffic-interceptor/captures/

# Analizar con mitmproxy CLI
mitmproxy -r /var/log/traffic-interceptor/captures/flows-*.mitm

# Decodificar Authorization headers
echo "BASE64_STRING" | base64 -d
```

#### Detener

```bash
sudo mitm-stop
```

## 📚 Documentación

- **[README.md](README.md)** - Este archivo (guía rápida)
- **[MITM-GUIDE.md](MITM-GUIDE.md)** - Guía completa de interceptación HTTPS
- **[SUCCESS-CASE.md](SUCCESS-CASE.md)** - Caso real exitoso con GitLab
- **[setup-mitm-full.sh](setup-mitm-full.sh)** - Script de instalación MITM

## 🎓 Ejemplo Real Verificado

**Captura exitosa de credenciales Git:**

```bash
# 1. Instalar
sudo ./setup-mitm-full.sh

# 2. Iniciar
sudo mitm-start

# 3. Ejecutar test
mitm-test

# 4. Ver en navegador
http://TU_IP:8081
```

**Resultado:** ✅ Captura exitosa de:
- URL: `https://gitlab.com/usuario/repo.git`
- Usuario: `gians96`
- Contraseña: `123456789`

**Cómo:** Authorization header decodificado de Base64.

Ver detalles completos en [SUCCESS-CASE.md](SUCCESS-CASE.md)

## 📁 Estructura de Archivos

```
traffic-interceptor/
├── README.md                  # Guía rápida (este archivo)
├── MITM-GUIDE.md             # Guía completa MITM
├── SUCCESS-CASE.md           # Caso de éxito documentado
├── install.sh                # Instalación básica
├── setup-mitm-full.sh        # Instalación MITM completa
├── start.sh                  # Script de inicio básico
├── stop.sh                   # Script de detención
├── status.sh                 # Ver estado
├── view.sh                   # Ver logs
├── analyze.sh                # Análisis de tráfico
└── uninstall.sh             # Desinstalar

Logs y capturas:
/var/log/traffic-interceptor/
├── traffic-*.txt             # Logs de tcpdump (básico)
├── captures/
│   ├── raw-*.pcap           # Capturas tcpdump raw
│   └── flows-*.mitm         # Flows de mitmproxy
└── mitmproxy.log            # Log de mitmproxy
```

## 🔧 Comandos Disponibles

### Modo Básico
| Comando | Descripción |
|---------|-------------|
| `sudo traffic-start` | Iniciar captura básica |
| `sudo traffic-stop` | Detener captura |
| `sudo traffic-status` | Ver estado |
| `sudo traffic-view` | Ver logs interactivo |
| `sudo traffic-analyze` | Análisis de tráfico |

### Modo MITM
| Comando | Descripción |
|---------|-------------|
| `sudo mitm-start` | Iniciar interceptación completa |
| `sudo mitm-stop` | Detener interceptación |
| `mitm-test` | Generar tráfico de prueba |
| `mitm-view` | Ver lista de capturas |
├── analysis/                     # Reportes de análisis
└── *.pid                         # IDs de proceso activos
```

Cada archivo de captura incluye:
- Timestamp de cada paquete
- IP origen y destino
- Puertos
- Protocolo
- Flags TCP
- Datos del payload

## 🔧 Comandos Disponibles

| Comando | Descripción |
|---------|-------------|
| `sudo traffic-start` | Iniciar captura de tráfico |
| `sudo traffic-stop` | Detener captura |
| `sudo traffic-status` | Ver estado (PID, memoria, archivo actual) |
| `sudo traffic-view` | Visor interactivo de logs |
| `sudo traffic-analyze` | Generar reporte de análisis |

## 📊 Ejemplos de Análisis Manual

### Ver tráfico en tiempo real

```bash
sudo tail -f /var/log/traffic-interceptor/traffic-*.txt
```

### Buscar tráfico a un dominio específico

```bash
grep "google.com" /var/log/traffic-interceptor/traffic-*.txt
```

### Ver solo conexiones al puerto 443 (HTTPS)

```bash
grep "443" /var/log/traffic-interceptor/traffic-*.txt
```

### Contar conexiones por puerto

```bash
grep -oP ':\d{2,5}' /var/log/traffic-interceptor/traffic-*.txt | sort | uniq -c | sort -rn
```

### Ver conexiones a Docker (puerto 3001)

```bash
grep "3001" /var/log/traffic-interceptor/traffic-*.txt
```

### Buscar por IP específica

```bash
grep "38.187.3.129" /var/log/traffic-interceptor/traffic-*.txt
```

## 🔒 Captura de Tráfico HTTPS

El sistema captura **metadata** de conexiones HTTPS:
- IPs origen y destino
- Puertos
- Timestamps
- Tamaño de paquetes
- Flags TCP (SYN, ACK, FIN, etc.)

**No se captura el contenido cifrado** (es HTTPS). Para ver el contenido necesitarías:
1. Instalar mitmproxy (opcional en install.sh)
2. Configurar certificados CA
3. Activar modo proxy transparente

Para la mayoría de casos de monitoreo, la metadata es suficiente para:
- Identificar servicios contactados
- Detectar patrones de tráfico
- Monitorear actividad sospechosa
- Debug de conectividad

## 🎓 Casos de Uso

### 1. Monitoreo de APIs y servicios web

Ver exactamente qué conexiones hace tu servidor:

```bash
sudo traffic-start
# El servidor opera normalmente
sudo traffic-view
# Opción 1: Ver últimas 50 líneas
```

### 2. Análisis de seguridad

Detectar qué IPs y puertos contacta tu servidor:

```bash
sudo traffic-start
# Espera unos minutos mientras el servidor opera
sudo traffic-analyze
```

### 3. Debug de contenedores Docker

Monitorear tráfico entre contenedores:

```bash
sudo traffic-start
# Observa el tráfico al puerto 3001 (MariaDB)
grep "3001" /var/log/traffic-interceptor/traffic-*.txt
```

### 4. Verificar conexiones salientes

Ver a qué servicios externos se conecta tu aplicación:

```bash
sudo traffic-start
# Ejecuta tu aplicación
grep -oP '\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}' /var/log/traffic-interceptor/traffic-*.txt | sort -u
```

## ⚠️ Notas Importantes

- **Solo para uso educativo** en tu servidor privado
- Requiere permisos de root para capturar tráfico de red
- Los archivos de log pueden crecer rápidamente en servidores con mucho tráfico
- tcpdump usa muy pocos recursos (~5-10MB RAM)
- La captura incluye TODO el tráfico de los puertos especificados
- Para entornos de producción, considera usar soluciones más robustas como:
  - **Suricata** - IDS/IPS completo
  - **Zeek** (antes Bro) - Análisis de seguridad de red
  - **Wireshark** - Para análisis detallado offline

## 🐛 Solución de Problemas

### No se captura tráfico

```bash
# Verificar que esté corriendo
sudo traffic-status

# Ver el archivo de log actual
sudo tail -f /var/log/traffic-interceptor/traffic-*.txt

# Reiniciar
sudo traffic-stop
sudo traffic-start
```

### Ver qué puertos se están monitoreando

```bash
ps aux | grep tcpdump
# Verás algo como: tcpdump -i any -n -l 'port 80 or port 443 or port 3001 or port 8080'
```

### Error de permisos

```bash
# tcpdump requiere permisos especiales
sudo setcap cap_net_raw,cap_net_admin=eip $(which tcpdump)
```

### Logs crecen demasiado

```bash
# Ver tamaño actual
du -sh /var/log/traffic-interceptor/

# Limpiar logs antiguos (opción 6 en traffic-view)
sudo traffic-view
# Seleccionar opción 6: Limpiar logs

# O manualmente
sudo rm /var/log/traffic-interceptor/traffic-*.txt
```

### Ver uso de recursos

```bash
# Ver memoria y CPU de tcpdump
ps aux | grep tcpdump
```

## 🗑️ Desinstalar

```bash
sudo ./uninstall.sh
```

## 📚 Recursos

- [tcpdump man page](https://www.tcpdump.org/manpages/tcpdump.1.html)
- [tcpdump tutorial por Daniel Miessler](https://danielmiessler.com/study/tcpdump/)
- [Guía de filtros de captura](https://wiki.wireshark.org/CaptureFilters)
- [Análisis de tráfico de red](https://www.networkdefenseblog.com/post/packet-analysis-for-network-forensics)

## 💡 Tips Adicionales

### Capturar solo paquetes grandes (posible transferencia de archivos)

```bash
tcpdump -i any 'greater 1000' -w /tmp/large-packets.txt
```

### Ver solo inicio de conexiones (SYN packets)

```bash
grep "Flags \[S\]" /var/log/traffic-interceptor/traffic-*.txt
```

### Monitorear un contenedor Docker específico

```bash
# Si tienes contenedor en puerto específico
grep "port_del_contenedor" /var/log/traffic-interceptor/traffic-*.txt | tail -f
```

### Exportar logs para análisis externo

```bash
# Copiar a tu máquina local
scp root@tu-servidor:/var/log/traffic-interceptor/traffic-*.txt ./
# Luego analizar con herramientas como Wireshark
```

---

**Autor:** Para aprendizaje de seguridad en servidores  
**Fecha:** Enero 2026  
**Licencia:** Uso educativo
