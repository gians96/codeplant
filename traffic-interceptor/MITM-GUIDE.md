# 🔍 Guía Completa de Interceptación MITM

## ⚠️ ADVERTENCIA LEGAL Y ÉTICA

**Este sistema es para USO EDUCATIVO únicamente:**
- ✅ Solo en tu propio servidor VPS
- ✅ Solo para entender cómo funciona el cifrado
- ✅ Solo con tu propio tráfico
- ❌ **NUNCA** interceptar tráfico de terceros sin consentimiento
- ❌ **ILEGAL** en muchos países si se usa maliciosamente

---

## 🚀 Instalación Rápida

### Paso 1: Subir y ejecutar el script

```bash
# En tu VPS
cd /var/scripts

# Dar permisos
chmod +x setup-mitm-full.sh

# Ejecutar instalación
sudo ./setup-mitm-full.sh
```

### Paso 2: Iniciar interceptación

```bash
sudo mitm-start
```

### Paso 3: Generar tráfico de prueba

```bash
# En otra terminal o con screen/tmux
mitm-test
```

### Paso 4: Ver capturas

```bash
# Opción 1: Interfaz web (recomendado)
# Abre en tu navegador:
http://64.23.255.238:8081

# Opción 2: Ver logs
mitm-view

# Opción 3: Ver en tiempo real
tail -f /var/log/traffic-interceptor/mitmproxy.log
```

---

## 📊 ¿Qué verás capturado?

### ✅ Tráfico HTTP (sin cifrar)
```
GET /api/users HTTP/1.1
Host: example.com
Authorization: Bearer token123
Cookie: session=abc123

POST /login
username=admin&password=secreto123
```

### ✅ Tráfico HTTPS (descifrado por mitmproxy)

**Ejemplo real capturado:**
```
POST https://api.github.com/user
Authorization: token ghp_xxxxxxxxxxxx
{"username": "admin", "password": "secreto"}
```

### ✅ Git Clone con credenciales (GitLab/GitHub)

**Comando ejecutado:**
```bash
git clone https://gians96:123456789@gitlab.com/gians96/privado.git
```

**Lo que captura mitmproxy:**
```
GET https://gitlab.com/gians96/privado.git/info/refs?service=git-upload-pack
Authorization: Basic Z2lhbnM5NjoxMjM0NTY3ODk=
User-Agent: git/2.43.0
```

**Decodificación:**
```bash
echo "Z2lhbnM5NjoxMjM0NTY3ODk=" | base64 -d
# Output: gians96:123456789
```

**✅ Capturado:** URL completa, usuario y contraseña en texto plano después de decodificar.

### ✅ Autenticación Basic HTTP
```
Authorization: Basic YWRtaW46c2VjcmV0bzEyMw==
# Decodificado: admin:secreto123
```

### ✅ POST con formularios (Login tradicional)
```
POST https://example.com/login
Content-Type: application/x-www-form-urlencoded

username=administrador&password=SuperSecreto2024&email=admin@test.com
```

### ✅ POST con JSON (APIs modernas)
```json
POST https://api.example.com/auth
Content-Type: application/json

{
  "email": "user@example.com",
  "password": "MiPasswordReal123",
  "api_key": "sk-live-abc123xyz789",
  "remember_me": true
}
```

### ✅ Tokens y API Keys en Headers
```
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
X-API-Key: sk-1234567890abcdef
X-Auth-Token: abc123def456ghi789
```

### ✅ Cookies de Sesión
```
Cookie: session_id=abc123def456; user_token=xyz789; auth=Bearer_token123
```

---

## 🛠️ Comandos Disponibles

| Comando | Descripción |
|---------|-------------|
| `sudo mitm-start` | Iniciar interceptación completa |
| `sudo mitm-stop` | Detener interceptación |
| `mitm-test` | Generar tráfico de prueba con credenciales |
| `mitm-view` | Ver lista de capturas |

---

## 📁 Ubicación de Archivos

```
/var/log/traffic-interceptor/captures/
├── raw-20260113-230000.pcap      # Captura tcpdump (crudo)
├── flows-20260113-230000.mitm    # Flows de mitmproxy
└── ...

~/.mitmproxy/
├── mitmproxy-ca-cert.pem         # Certificado CA
├── mitmproxy-ca-cert.p12         # Para navegadores
└── mitmproxy-ca.pem              # Clave privada
```

---

## 🔬 Ejemplos de Pruebas Educativas

### Ejemplo 1: Capturar git clone con credenciales (GitLab/GitHub)

```bash
# Terminal 1: Iniciar interceptación
sudo mitm-start

# Terminal 2: Ejecutar test automático (incluye git clone)
mitm-test

# O manualmente con tus credenciales reales:
export HTTPS_PROXY=http://127.0.0.1:8080
export GIT_TERMINAL_PROMPT=0
git clone https://usuario:contraseña@gitlab.com/usuario/repo-privado.git

# Ver en: http://64.23.255.238:8081
```

**Lo que verás capturado:**

1. **Request HTTP:**
```
GET https://gitlab.com/usuario/repo-privado.git/info/refs?service=git-upload-pack
```

2. **Authorization Header (Base64):**
```
Authorization: Basic Z2lhbnM5NjoxMjM0NTY3ODk=
```

3. **Decodificar credenciales:**
```bash
# Copia el string después de "Basic " y ejecuta:
echo "Z2lhbnM5NjoxMjM0NTY3ODk=" | base64 -d
# Resultado: usuario:contraseña
```

**✅ Captura exitosa:** URL, usuario y contraseña completamente visibles.

### Ejemplo 2: Capturar API con credenciales

```bash
export HTTPS_PROXY=http://127.0.0.1:8080

curl -X POST https://api.ejemplo.com/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"secreto123"}'

# En mitmproxy verás el JSON completo con la contraseña
```

**Cómo ver en mitmproxy web:**
1. Abre http://64.23.255.238:8081
2. Busca el flow `POST /login`
3. Haz clic en el flow
4. Ve a la pestaña **Request**
5. Verás el body completo con `{"username":"admin","password":"secreto123"}`

### Ejemplo 3: Capturar formulario de login

```bash
export HTTPS_PROXY=http://127.0.0.1:8080

curl -X POST https://example.com/login \
  -d "username=admin" \
  -d "password=MiPasswordSegura123" \
  -d "email=admin@test.com"

# Captura visible: username=admin&password=MiPasswordSegura123&email=admin@test.com
```

---

## 🔍 Análisis de Capturas

### Ver flows de mitmproxy (CLI)

```bash
# Cargar archivo de flows guardado
mitmproxy -r /var/log/traffic-interceptor/captures/flows-*.mitm

# Navegación en mitmproxy:
# ↑↓ : Navegar entre flows
# Enter: Ver detalles del flow seleccionado
# Tab: Cambiar entre Request/Response/Detail
# q: Salir
# /: Buscar (escribe "password" para buscar credenciales)
# f: Filtrar (ejemplo: ~m POST para ver solo POST)
```

### Ver flows en interfaz web (Recomendado)

1. **Abrir interfaz web:**
   ```
   http://64.23.255.238:8081
   ```

2. **Navegar por los flows:**
   - Lista de todos los requests capturados
   - Click en cualquier flow para ver detalles

3. **Ver credenciales en un flow:**
   - Click en un flow POST o GET
   - Ve a pestaña **Request**
   - Scroll down para ver el **body** (formularios, JSON)
   - Ve a **Headers** para ver Authorization

4. **Decodificar Authorization Basic:**
   ```bash
   # Si ves: Authorization: Basic Z2lhbnM5NjoxMjM0NTY3ODk=
   # Copia el string después de "Basic " y ejecuta:
   echo "Z2lhbnM5NjoxMjM0NTY3ODk=" | base64 -d
   ```

### Analizar PCAP con tcpdump

```bash
# Leer archivo PCAP y buscar credenciales
tcpdump -r /var/log/traffic-interceptor/captures/raw-*.pcap -A | grep -i "password\|authorization\|token"

# Ver solo tráfico HTTPS
tcpdump -r /var/log/traffic-interceptor/captures/raw-*.pcap 'port 443'

# Ver tráfico de un dominio específico
tcpdump -r /var/log/traffic-interceptor/captures/raw-*.pcap -n | grep "gitlab.com"
```

### Buscar credenciales específicas

```bash
# En logs de mitmproxy
grep -i "password\|token\|authorization" /var/log/traffic-interceptor/mitmproxy.log

# Ver solo POST requests (donde suelen estar las credenciales)
grep "POST" /var/log/traffic-interceptor/mitmproxy.log

# Buscar un usuario específico
grep -i "usuario\|username\|email" /var/log/traffic-interceptor/mitmproxy.log
```

### Exportar flows capturados

```bash
# Los flows se guardan automáticamente en:
ls -lh /var/log/traffic-interceptor/captures/

# Para revisar después sin el proxy activo:
mitmproxy -r /var/log/traffic-interceptor/captures/flows-20260113-230000.mitm

# Exportar a HAR (HTTP Archive) para análisis en otras herramientas:
mitmdump -r flows.mitm -w output.har
```

---

## 🛡️ Seguridad y Buenas Prácticas

### ⚠️ Después de las pruebas

```bash
# 1. Detener interceptación
sudo mitm-stop

# 2. Desinstalar certificado MITM
sudo rm /usr/local/share/ca-certificates/mitmproxy.crt
sudo update-ca-certificates --fresh

# 3. Eliminar configuración de proxy
sudo rm /etc/profile.d/mitmproxy.sh

# 4. Limpiar configuración de git
git config --global --unset http.proxy
git config --global --unset https.proxy

# 5. Eliminar capturas sensibles
sudo rm -rf /var/log/traffic-interceptor/captures/*
```

---

## 🎓 Entendiendo cómo funciona

### 1. Certificado MITM (Man-in-the-Middle)

- mitmproxy genera su propio certificado CA (Certificate Authority)
- Lo instalas en tu sistema para que confíe en él
- Cuando haces HTTPS, mitmproxy:
  1. **Intercepta** la conexión original
  2. **Crea un certificado falso** para el dominio (ej: gitlab.com)
  3. **Tu cliente confía** porque instalaste el CA de mitmproxy
  4. **mitmproxy ve el tráfico descifrado** (texto plano)
  5. **Re-cifra** el tráfico hacia el servidor real con el certificado legítimo
  6. El servidor no detecta nada porque recibe una conexión normal

```
Tu App → [Conexión cifrada con cert de mitmproxy] → mitmproxy → [Conexión cifrada con cert real] → Servidor
          ↑ Tu app confía porque instalaste el CA                ↑ Servidor ve conexión normal
                                    ↓
                        mitmproxy ve TODO en texto plano
```

### 2. Modo Proxy

- Configuras `HTTP_PROXY=http://127.0.0.1:8080`
- Todos los programas que respetan esta variable envían tráfico a través de ese proxy
- mitmproxy intercepta, descifra, registra y reenvía
- El servidor destino recibe una petición "normal"

**Ejemplo práctico:**

```bash
# Sin proxy:
curl https://gitlab.com/user/repo.git  # Conexión directa cifrada

# Con proxy (captura activa):
export HTTPS_PROXY=http://127.0.0.1:8080
curl https://gitlab.com/user/repo.git  # Pasa por mitmproxy → descifrado → visible
```

### 3. Base64 en Authorization Headers

Git y muchas APIs usan **Basic Authentication** que codifica las credenciales en Base64:

```
usuario:contraseña → Base64 → Z2lhbnM5NjoxMjM0NTY3ODk=
```

**NO es cifrado**, solo codificación. Se decodifica fácilmente:

```bash
echo "Z2lhbnM5NjoxMjM0NTY3ODk=" | base64 -d
# Output: usuario:contraseña
```

Por eso SIEMPRE debe usarse con HTTPS. Pero mitmproxy intercepta HTTPS, por eso se ve.

### 4. Por qué funciona con GitLab/GitHub

Cuando clonas con credenciales en la URL:
```bash
git clone https://usuario:contraseña@gitlab.com/repo.git
```

Git internamente hace:
1. Extrae `usuario:contraseña` de la URL
2. Codifica en Base64: `dXN1YXJpbzpjb250cmFzZcOxYQ==`
3. Envía header: `Authorization: Basic dXN1YXJpbzpjb250cmFzZcOxYQ==`
4. mitmproxy intercepta este header
5. Puedes decodificar y ver las credenciales

### 5. Limitaciones del sistema

#### ❌ NO funciona con:

- **Certificate Pinning:** Apps que solo aceptan certificados específicos
  - Ejemplo: Apps bancarias, algunas apps móviles
  - Detectan que el certificado es de mitmproxy y rechazan la conexión

- **SSH sin proxy:** SSH no usa HTTP, cifra todo de forma diferente
  - No puedes interceptar: `git clone git@gitlab.com:user/repo.git`
  - Solo funciona con HTTPS: `https://gitlab.com/user/repo.git`

- **TLS 1.3 con 0-RTT:** Algunas optimizaciones modernas dificultan la interceptación

- **Apps que no respetan HTTP_PROXY:** Algunas apps ignoran las variables de entorno

#### ✅ SÍ funciona con:

- **HTTP/HTTPS estándar:** Todo el tráfico web
- **REST APIs:** Prácticamente todas las APIs modernas
- **Git HTTPS:** GitHub, GitLab, Bitbucket
- **cURL, wget, navegadores:** Cuando usan el proxy
- **Python requests, Node.js fetch:** Cuando configuran proxy
- **WebSockets sobre HTTPS**

### 6. ¿Por qué es educativo?

Este sistema te enseña:

1. **Cómo NO enviar credenciales:**
   - Nunca en URLs (se quedan en logs)
   - Nunca en HTTP sin cifrar
   - Usar tokens en lugar de contraseñas cuando sea posible

2. **Importancia del HTTPS:**
   - Sin HTTPS, todo es visible para intermediarios
   - Con HTTPS, solo visible si instalan certificado MITM (ataque activo)

3. **Defense in depth:**
   - HTTPS es la primera capa
   - Certificate pinning es la segunda
   - Autenticación multi-factor es la tercera

4. **Cómo funcionan los proxies corporativos:**
   - Muchas empresas hacen exactamente esto
   - Instalan su CA en computadoras corporativas
   - Inspeccionan TODO el tráfico HTTPS de empleados

---

## 📚 Recursos Educativos

- [mitmproxy docs](https://docs.mitmproxy.org/)
- [TLS/SSL explained](https://tls.ulfheim.net/)
- [OWASP Testing Guide](https://owasp.org/www-project-web-security-testing-guide/)

---

## 🆘 Solución de Problemas

### El certificado no es confiable

```bash
# Reinstalar certificado
sudo cp ~/.mitmproxy/mitmproxy-ca-cert.pem /usr/local/share/ca-certificates/mitmproxy.crt
sudo update-ca-certificates

# Verificar
openssl x509 -in /usr/local/share/ca-certificates/mitmproxy.crt -text -noout
```

### El proxy no intercepta

```bash
# Verificar que las variables estén configuradas
echo $HTTPS_PROXY

# Recargar
source /etc/profile.d/mitmproxy.sh

# Probar manualmente
curl -x http://127.0.0.1:8080 https://httpbin.org/get
```

### mitmproxy no inicia

```bash
# Ver logs
cat /var/log/traffic-interceptor/mitmproxy.log

# Matar procesos zombies
pkill -9 mitmproxy
pkill -9 mitmweb

# Reiniciar
sudo mitm-start
```

---

**Recuerda: Usa este conocimiento de forma ética y legal. La seguridad informática es una responsabilidad seria.**
