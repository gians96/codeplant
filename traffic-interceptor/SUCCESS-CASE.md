# 🎯 Ejemplo Real Exitoso - Captura de Credenciales GitLab

## Caso de Prueba Verificado

**Fecha:** 13 de enero de 2026  
**Sistema:** Ubuntu VPS con mitmproxy 8.1  
**Objetivo:** Capturar credenciales de git clone en GitLab

---

## ✅ Configuración Exitosa

### 1. Sistema instalado
```bash
sudo ./setup-mitm-full.sh
```

### 2. Interceptación iniciada
```bash
sudo mitm-start
```

**Estado del sistema:**
- ✅ tcpdump capturando en puerto 22, 80, 443, 8080
- ✅ mitmproxy escuchando en 127.0.0.1:8080 (proxy)
- ✅ mitmweb interfaz en 0.0.0.0:8081 (web UI)
- ✅ Certificado CA instalado en el sistema

---

## 🧪 Prueba Ejecutada

### Comando ejecutado:
```bash
export HTTPS_PROXY=http://127.0.0.1:8080
export GIT_TERMINAL_PROMPT=0
git clone https://gians96:123456789@gitlab.com/gians96/privado.git
```

### También funciona con el test automático:
```bash
mitm-test
```

---

## 📊 Resultados Capturados

### 1. En la interfaz web (http://64.23.255.238:8081)

**Flow capturado:**
```
GET https://gitlab.com/gians96/privado.git/info/refs?service=git-upload-pack
```

**Headers capturados:**
```http
GET /gians96/privado.git/info/refs?service=git-upload-pack HTTP/2.0
Host: gitlab.com
User-Agent: git/2.43.0
Authorization: Basic Z2lhbnM5NjoxMjM0NTY3ODk=
Accept: */*
Accept-Encoding: deflate, gzip, br, zstd
Pragma: no-cache
```

### 2. Decodificación del Authorization Header

**En el servidor:**
```bash
echo "Z2lhbnM5NjoxMjM0NTY3ODk=" | base64 -d
```

**Salida:**
```
gians96:123456789
```

---

## 🎯 Información Capturada Exitosamente

| Dato | Valor Capturado | Ubicación |
|------|----------------|-----------|
| **URL** | `https://gitlab.com/gians96/privado.git` | Flow path en mitmproxy |
| **Usuario** | `gians96` | Authorization header (decodificado) |
| **Contraseña** | `123456789` | Authorization header (decodificado) |
| **Protocolo** | Git sobre HTTPS | User-Agent: git/2.43.0 |
| **Tipo de Auth** | Basic Authentication | Authorization: Basic ... |

---

## 📸 Evidencia Visual

### Vista en mitmproxy web:

1. **Lista de flows:**
   - ✅ `GET https://gitlab.com/gians96/privado.git/info/refs`
   - ✅ Status: 401 (primera intento) → 200 (con credenciales)

2. **Detalles del Request:**
   - Pestaña **Request** muestra todos los headers
   - Authorization header visible con Base64
   - User-Agent confirma que es Git

3. **Decodificación confirmada:**
   - Base64 decode revela: `usuario:contraseña`
   - Credenciales en texto plano después de decodificar

---

## 🔬 Análisis Técnico

### ¿Por qué funcionó?

1. **mitmproxy interceptó HTTPS:**
   - Sistema confía en el certificado CA de mitmproxy
   - Descifró la conexión SSL/TLS

2. **Git usó credenciales de la URL:**
   - `https://usuario:contraseña@gitlab.com`
   - Git las codificó en Base64
   - Las envió en el header Authorization

3. **mitmproxy capturó el header:**
   - Todo el tráfico pasa por el proxy
   - Headers visibles en texto plano
   - Almacenado en flows para análisis posterior

### ¿Por qué no siempre funciona?

En el primer intento con GitHub:
- Git usó un **token almacenado** (`ghp_kcsfwE...`)
- NO usó la contraseña escrita
- Credential helper de Git guardó el token previamente

**Solución:** Usar `GIT_TERMINAL_PROMPT=0` y credenciales en la URL fuerza el uso directo.

---

## 🛡️ Lecciones de Seguridad Aprendidas

### ❌ Malas Prácticas Detectadas

1. **Credenciales en URLs:**
   ```bash
   # MAL: Las credenciales quedan en logs, historial, proxies
   git clone https://user:pass@gitlab.com/repo.git
   ```

2. **HTTPS sin certificate pinning:**
   - Vulnerable a MITM si instalan certificado malicioso
   - Exactamente lo que hicimos aquí

3. **Basic Authentication sobre HTTPS:**
   - Solo Base64, no es cifrado real
   - Depende completamente del HTTPS

### ✅ Buenas Prácticas

1. **Usar SSH en lugar de HTTPS:**
   ```bash
   # MEJOR: SSH con clave, no interceptable así
   git clone git@gitlab.com:user/repo.git
   ```

2. **Tokens en lugar de contraseñas:**
   - Tokens tienen alcance limitado
   - Pueden revocarse sin cambiar contraseña
   - Expiran automáticamente

3. **Autenticación multi-factor:**
   - Incluso si capturan contraseña, necesitan segundo factor
   - Tokens de un solo uso

4. **Certificate pinning en apps críticas:**
   - Apps bancarias, corporativas
   - Rechazan certificados que no sean los esperados

---

## 📝 Comandos para Reproducir

```bash
# 1. Instalar sistema
sudo ./setup-mitm-full.sh

# 2. Iniciar interceptación
sudo mitm-start

# 3. Ejecutar test con GitLab (o tu repo)
mitm-test

# 4. Ver capturas en web
# Abrir: http://TU_IP:8081

# 5. Decodificar credenciales
# Copiar string Base64 del Authorization header y ejecutar:
echo "STRING_BASE64" | base64 -d

# 6. Revisar flows guardados
ls -lh /var/log/traffic-interceptor/captures/

# 7. Detener cuando termines
sudo mitm-stop
```

---

## 🎓 Conclusión Educativa

Este experimento demuestra:

1. **HTTPS protege contra espías pasivos** (solo escuchan red)
2. **NO protege contra MITM activo** (si instalan certificado)
3. **Las credenciales en URLs son visibles** en proxies corporativos
4. **La seguridad depende de múltiples capas**, no solo cifrado
5. **Por eso las empresas pueden monitorear** empleados legalmente

**Uso ético:** Este conocimiento es para protegerse mejor, nunca para atacar sistemas de terceros.

---

## 🔗 Archivos Relacionados

- [MITM-GUIDE.md](MITM-GUIDE.md) - Guía completa
- [setup-mitm-full.sh](setup-mitm-full.sh) - Script de instalación
- [README.md](README.md) - Documentación general del interceptor

---

**⚠️ Recordatorio Legal:** Este sistema es únicamente para uso educativo en tu propio servidor/red. Interceptar tráfico de terceros sin consentimiento es ilegal en la mayoría de jurisdicciones.
