# Traffic Interceptor - Monitor de Tráfico HTTP/HTTPS

Sistema completo para interceptar, capturar y analizar tráfico HTTP/HTTPS en tu servidor usando tcpdump.

## 🎯 Características

- ✅ **tcpdump** - Captura todo el tráfico de red en tiempo real
- ✅ **Monitoreo multi-puerto** - HTTP (80), HTTPS (443), Docker (3001), Apps (8080)
- ✅ **Análisis automático** - Reportes de dominios, puertos, conexiones
- ✅ **Logs en texto plano** - Fácil de leer y procesar
- ✅ **Organizado** - Todo guardado en `/var/log/traffic-interceptor`
- 🔧 **mitmproxy** - Opcional, interfaz web (si está instalado)

## 🚀 Instalación

```bash
# 1. Dar permisos
chmod +x *.sh

# 2. Instalar
sudo ./install.sh
```

## 📋 Uso Básico

### Iniciar el interceptor

```bash
sudo traffic-start
```

Esto inicia tcpdump capturando en background tráfico en los puertos:
- **80** - HTTP
- **443** - HTTPS  
- **3001** - Docker/MariaDB
- **8080** - Aplicaciones

Los logs se guardan en `/var/log/traffic-interceptor/traffic-TIMESTAMP.txt`

### Ver estado

```bash
sudo traffic-status
```

### Ver logs capturados

```bash
sudo traffic-view
```

Menú interactivo con opciones:
1. Ver últimas 50 líneas
2. Ver últimas 100 líneas
3. Ver en tiempo real (tail -f)
4. Buscar por texto
5. Ver logs antiguos
6. Limpiar logs
7. Salir

### Análisis avanzado

```bash
sudo traffic-analyze
```

Genera reporte con:
- Top IPs contactadas
- Distribución por puertos
- Conexiones activas
- Estadísticas generales

### Detener

```bash
sudo traffic-stop
```

## 🌐 Visualización en Tiempo Real

Puedes ver el tráfico capturado en tiempo real con:

```bash
sudo tail -f /var/log/traffic-interceptor/traffic-*.txt
```

O usando el visor interactivo:

```bash
sudo traffic-view
# Opción 3: Ver en tiempo real
```

**Nota:** Si mitmproxy está instalado, también podrás acceder a la interfaz web en `http://TU-IP:8081`

## 📁 Ubicación de Logs

```
/var/log/traffic-interceptor/
├── traffic-YYYYMMDD-HHMMSS.txt  # Capturas de tcpdump en texto
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
