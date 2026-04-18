# MITM Traffic Interceptor

Sistema todo-en-uno para interceptar y analizar tráfico HTTPS en tu servidor. Captura credenciales, tokens, cookies y headers en texto plano.

## ✨ Características

- 🔓 **Interceptación HTTPS** - Descifra tráfico HTTPS con certificado MITM
- 🌐 **Interfaz Web** - Vista gráfica en http://IP:8081  
- 🔍 **Captura credenciales** - Usuarios, contraseñas, tokens en texto plano
- 📊 **Todo en uno** - Un solo script para todo (mitm.sh)
- 💾 **Guarda todo** - Flows permanentes en `/var/log/traffic-interceptor/captures/`
- 🎯 **Fácil de usar** - Comandos simples y claros
- ✅ **Probado** - Captura credenciales de Git, APIs, formularios

## ⚠️ Advertencia Legal

**USO EDUCATIVO ÚNICAMENTE:**
- ✅ Solo en tu propio servidor/VPS
- ✅ Solo para entender cómo funciona la seguridad
- ✅ Solo con tu propio tráfico
- ❌ **NUNCA** interceptar tráfico de terceros sin consentimiento
- ❌ **ILEGAL** en muchos países si se usa maliciosamente

## 🚀 Instalación (Un solo comando)

```bash
# 1. Dar permisos
chmod +x mitm.sh

# 2. Instalar
sudo ./mitm.sh install

# ¡Listo! Ya puedes usar el comando "mitm" desde cualquier lugar
```

## 📋 Uso

### Comandos principales

```bash
# Iniciar interceptación
sudo mitm start

# Ver estado
mitm status

# Monitor en tiempo real (actualiza cada 3s)
mitm monitor

# Generar tráfico de prueba
mitm test

# Ver capturas guardadas
mitm view

# Diagnosticar problemas
mitm diagnose

# Detener
sudo mitm stop

# Desinstalar
sudo mitm uninstall
```

### Ver capturas en interfaz web

```bash
# Abre en tu navegador (mientras mitm está corriendo):
http://TU_IP:8081
```

Verás:
- ✅ Lista de todos los flows HTTP/HTTPS
- ✅ Detalles de cada request/response  
- ✅ Headers, body, cookies
- ✅ **Credenciales en texto plano**

### Capturas permanentes

```bash
# Ver archivos guardados
ls -lh /var/log/traffic-interceptor/captures/

# Analizar con mitmproxy CLI
mitmproxy -r /var/log/traffic-interceptor/captures/flows-*.mitm

# Buscar credenciales
mitmdump -r /var/log/traffic-interceptor/captures/flows-*.mitm | grep -i "authorization\|password"

# Decodificar Authorization header (Base64)
echo "BASE64_STRING" | base64 -d
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

## 📁 Estructura (Simplificada)

```
traffic-interceptor/
├── mitm.sh                   # ⭐ Script TODO-EN-UNO (único necesario)
├── README.md                 # Esta guía
├── MITM-GUIDE.md            # Guía detallada
└── SUCCESS-CASE.md          # Caso de éxito

Capturas en servidor:
/var/log/traffic-interceptor/
├── captures/
│   ├── raw-*.pcap           # Capturas tcpdump
│   └── flows-*.mitm         # Flows mitmproxy (permanentes)
└── mitmproxy.log            # Logs de mitmproxy
```

## 🔧 Comandos Disponibles

### Modo Básico
| Comando | Descripción |
|---------|-------------|a guía (inicio rápido)
- **[MITM-GUIDE.md](MITM-GUIDE.md)** - Guía detallada de interceptación HTTPS
- **[SUCCESS-CASE.md](SUCCESS-CASE.md)** - Caso real exitoso con GitLab
- **[mitm.sh](mitm.sh)** - Script todo-en-uno (único archivo necesario)
| `sudTodos los Comandos

| Comando | Descripción |
|---------|-------------|
| `sudo mitm install` | Instalar (solo primera vez) |
| `sudo mitm start` | Iniciar interceptación |
| `sudo mitm stop` | Detener |
| `mitm status` | Ver estado actual |
| `mitm monitor` | Monitor en tiempo real |
| `mitm test` | Generar tráfico de prueba |
| `mitm view` | Ver capturas guardadas |
| `mitm diagnose` | Diagnosticar problemas |
| `sudo mitm uninstall` | Desinstalar completamente |
| `mitm help` | Ayuda
**Resultado verificado:** ✅ Captura exitosa de:
- Credenciales Git (usuario:contraseña)
- API tokens y Bearer tokens
- Cookies de sesión
- Basic Authentication
- POST con passwords

Ver caso real | Iniciar captura de tráfico |
| `sudo traffic-stop` | Detener captura |
| `sudo traffic-status` | Ver estado (PID, memoria, archivo actual) |
| `sudo traffic-view` | Visor interactivo de logs |
| `sudo traffic-analyze` | Generar reporte de análisis |



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
