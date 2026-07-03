# Handoff soporte: ceos-facturacion.com, Cloudflare, FortiGate y Laravel 500

Fecha de corte: 2026-07-03  
Dominio: `ceos-facturacion.com`  
Wildcard/tenants: `*.ceos-facturacion.com`, ejemplo `demo.ceos-facturacion.com`  
IP publica origen: `143.0.248.236`  
Ruta productiva vista en el servidor: `/var/ceos-facturacion.com`  
Stack: Pro-8 / Laravel / hyn multi-tenant / Docker Compose / nginx-proxy / MariaDB / Redis / Soketi

Este documento resume todo el contexto para continuar desde otro dispositivo o
pasarlo a otro tecnico sin perder la linea de investigacion.

---

## 1. Resumen ejecutivo

El problema inicial no era el certificado ni Docker: cuando Cloudflare estaba
con proxy naranja, Cloudflare devolvia `522 Connection timed out`. Al quitar el
proxy naranja y dejar DNS en `Solo DNS`, el sitio llego al origen y empezo a
mostrar la pagina Laravel `500`.

Eso separa los problemas en dos capas:

1. **Cloudflare/FortiGate/red:** el `522` ocurre cuando Cloudflare no logra
   conectar al origen. El origen si responde cuando se prueba directo con
   `curl --resolve`.
2. **Laravel/base de datos:** una vez que el trafico llega al servidor, el
   `500` actual viene de Laravel por tablas del sistema faltantes:
   `websites` y `clients` en la BD `ceos-facturacion_com`.

Estado mas reciente conocido:

- SSL/proxy Docker local responde.
- Acceso directo al origen por `143.0.248.236:443` con SNI/Host correcto
  responde `302` hacia `/login`.
- `public/build/manifest.json` existe, asi que el `500` actual no es Vite.
- Logs Laravel muestran tablas faltantes en la BD system.
- Siguiente accion recomendada: correr `php artisan migrate --seed --force`
  en la BD system y luego `tenancy:migrate`.

---

## 2. Arquitectura del despliegue

Contenedores vistos en `docker ps`:

```text
nginx_ceos-facturacion_com        nginx interno de la app, puerto 80/tcp
fpm_ceos-facturacion_com          PHP-FPM / Laravel, puerto 9000/tcp
supervisor_ceos-facturacion_com   workers de cola
scheduling_ceos-facturacion_com   scheduler Laravel
redis_ceos-facturacion_com        Redis
soketi_ceos-facturacion_com       WebSocket/Broadcasting
mariadb_ceos-facturacion_com      MariaDB, host 3001 -> container 3306
proxy-proxy-1                     nginx-proxy compartido, host 80/443
```

Flujo esperado:

```text
Internet
  -> Cloudflare DNS/proxy
  -> IP publica 143.0.248.236
  -> FortiGate VIP/NAT 80/443
  -> servidor Docker
  -> proxy-proxy-1
  -> nginx_ceos-facturacion_com
  -> fpm_ceos-facturacion_com
  -> MariaDB/Redis
```

En LAN puede existir split-horizon: las PCs internas resuelven el dominio a la
IP LAN del servidor, y los clientes externos resuelven a la IP publica.

---

## 3. Cloudflare: que se vio y que significa

Configuracion vista en Cloudflare:

- Modo SSL/TLS: Automatico / Completo.
- Registros DNS:
  - `ceos-facturacion.com` A -> `143.0.248.236`
  - `*.ceos-facturacion.com` A -> `143.0.248.236`
  - `_acme-challenge...` TXT en `Solo DNS`
- En varios momentos el apex/wildcard estuvieron con proxy naranja.

Sintoma:

```text
https://ceos-facturacion.com
-> Cloudflare 522 Connection timed out
-> Browser Working / Cloudflare Working / Host Error
```

Interpretacion:

- `522` no es error de certificado de navegador.
- `522` significa que Cloudflare no pudo completar conexion TCP/HTTP contra el
  origen dentro de su timeout.
- Si el acceso directo al origen responde, el problema queda entre Cloudflare y
  el FortiGate/firewall/origen.

Por que `nt-suite.pro` puede funcionar con "la misma configuracion":

- La configuracion DNS/SSL puede verse igual, pero el camino de red no es el
  mismo si ese dominio esta en otro servidor, otra arquitectura o Elastika.
- Cloudflare sale desde sus rangos IP. Si FortiGate/IPS/DoS/GeoIP/NAT trata
  distinto esos origenes, un dominio puede funcionar y otro no.

---

## 4. Pruebas que aislaron Cloudflare/FortiGate

### 4.1 Prueba local en el servidor

Ejecutar en el servidor:

```bash
curl -vkI --resolve ceos-facturacion.com:443:127.0.0.1 https://ceos-facturacion.com
curl -vkI --resolve ceos-facturacion.com:80:127.0.0.1 http://ceos-facturacion.com
```

Resultado esperado si Docker/proxy local esta OK:

```text
HTTPS -> 302 /login, 200 o similar
HTTP  -> 301 hacia HTTPS
```

### 4.2 Prueba directa al origen desde una red externa

Ejecutar desde una laptop fuera de la LAN:

```powershell
curl.exe -vkI --resolve ceos-facturacion.com:443:143.0.248.236 https://ceos-facturacion.com
curl.exe -vI  --resolve ceos-facturacion.com:80:143.0.248.236 http://ceos-facturacion.com
```

Resultado visto:

```text
HTTPS directo -> HTTP/1.1 302 Found
Location: https://ceos-facturacion.com/login

HTTP directo -> HTTP/1.1 301 Moved Permanently
Location: https://ceos-facturacion.com/
```

Lectura:

- NAT/VIP hacia `443` funciona para un cliente externo normal.
- nginx-proxy y Laravel estan atendiendo.
- Si Cloudflare sigue devolviendo `522`, queda revisar FortiGate/firewall para
  trafico proveniente de Cloudflare.

### 4.3 Prueba por Cloudflare

Ejecutar sin `--resolve`:

```powershell
curl.exe -vkI https://ceos-facturacion.com
```

Resultado visto cuando el proxy naranja estaba activo:

```text
HTTP/1.1 522
Server: cloudflare
CF-RAY: ...-EZE
```

Lectura:

- La falla esta en el camino Cloudflare -> origen.
- Solucion rapida: poner los registros en `Solo DNS`.
- Solucion si se requiere proxy naranja: permitir IPs oficiales de Cloudflare
  hacia `80/443` en FortiGate/firewall y revisar IPS/DoS/GeoIP.

Link util: `https://www.cloudflare.com/ips/`

---

## 5. FortiGate / firewall: checklist si se quiere usar proxy naranja

Si se vuelve a activar el proxy naranja de Cloudflare:

1. Verificar VIP/NAT:
   - WAN `80` -> IP LAN del servidor `80`
   - WAN `443` -> IP LAN del servidor `443`
2. Permitir los rangos IP de Cloudflare hacia `80/443`.
3. Revisar perfiles de seguridad aplicados a la politica:
   - IPS
   - DoS policy
   - GeoIP
   - Web filter / SSL inspection
   - reglas de reputacion/bot si existen
4. Confirmar que no haya bloqueo por SNI/Host.
5. Confirmar que apex y wildcard tengan modo DNS coherente:
   - ambos `Solo DNS`, o
   - ambos proxied si FortiGate ya permite Cloudflare.
6. Si LAN usa split-horizon, confirmar que las PCs internas resuelvan al IP LAN
   y no necesariamente al IP publico.

Diagnostico rapido:

```text
Directo a IP publica con --resolve responde, Cloudflare 522:
  revisar FortiGate/firewall para origenes Cloudflare.

Directo a IP publica no responde:
  revisar VIP/NAT/puertos publicos.

Local 127.0.0.1 no responde:
  revisar Docker/proxy/certificados.
```

---

## 6. Error 400 al abrir IP:443

Se vio:

```text
143.0.248.236:443 -> 400 Bad Request
The plain HTTP request was sent to HTTPS port
```

Esto no es un fallo del proxy. Ocurre porque se escribio `143.0.248.236:443`
sin `https://`, entonces el navegador envio HTTP normal al puerto TLS.

Prueba correcta:

```text
https://143.0.248.236
```

Para Pro-8 la prueba realmente util es con Host/SNI:

```bash
curl -vkI --resolve ceos-facturacion.com:443:143.0.248.236 https://ceos-facturacion.com
```

---

## 7. Scripts usados para reparar SSL/proxy

### Linux legacy (`/var/...`) con `updateSSL.sh`

Descargar y ejecutar:

```bash
cd /var
sudo curl -fSL -o updateSSL.sh https://raw.githubusercontent.com/gians96/codeplant/master/facturador-pro/install/linux/updateSSL.sh
sudo chmod +x updateSSL.sh

sudo ./updateSSL.sh ceos-facturacion.com --repair-proxy
```

### Onpremise (`/opt/proyectos/...`) con `ssl.sh`

Descargar y ejecutar:

```bash
cd /opt/proyectos
sudo curl -fSL -o ssl.sh https://raw.githubusercontent.com/gians96/codeplant/master/facturador-pro/install/onpremise/ssl.sh
sudo chmod +x ssl.sh

sudo ./ssl.sh --domain ceos-facturacion.com --repair-proxy
```

Nota: si aparece `chmod: Operation not permitted`, usar `sudo chmod +x ...`.

### Que hace el modo repair

El modo `--repair-proxy` no renueva certificado ni borra datos. Hace:

1. Copia certificados existentes al volumen real del proxy.
2. Detecta el volumen/carpeta montada como `/etc/nginx/certs`.
3. Repara variables del servicio nginx:
   - `VIRTUAL_HOST`
   - `VIRTUAL_PORT`
   - `VIRTUAL_PROTO`
   - `CERT_NAME`
4. Agrega `www.<dominio>` como alias del panel central.
5. Agrega redirect de `www.<dominio>` hacia el dominio base.
6. Recachea Laravel si aplica.
7. Reinicia FPM/workers/proxy.
8. Valida localmente HTTP y HTTPS contra `127.0.0.1`.

---

## 8. `www.ceos-facturacion.com`

`www` no debe crearse como tenant. Debe ser alias del panel administrativo y
redirigir al dominio base.

Validacion:

```bash
curl -vkI --resolve www.ceos-facturacion.com:443:127.0.0.1 https://www.ceos-facturacion.com/login
```

Resultado esperado:

```text
301 -> https://ceos-facturacion.com/login
```

---

## 9. Laravel 500: errores vistos y significado

Cuando se quito el proxy naranja de Cloudflare, el trafico llego a Laravel y se
vio la pagina `500`. Esto ya no es un problema Cloudflare.

### 9.1 Errores viejos ya superados

Error:

```text
Class "Illuminate\Foundation\Application" not found
```

Significado:

- `vendor/` faltaba o Composer no termino.
- Se corrige con `composer install`.

Error:

```text
Class "Barryvdh\Debugbar\ServiceProvider" not found
```

Significado:

- Se instalo con `--no-dev`, pero la app intenta cargar Debugbar.
- Soluciones:
  - instalar sin `--no-dev`, o
  - quitar Debugbar del provider/config del proyecto.

Error:

```text
Please provide a valid cache path
```

Significado:

- Faltaban carpetas dentro de `storage/framework` o permisos.

Recuperacion de carpetas/permisos:

```bash
cd /var/ceos-facturacion.com

docker compose exec -T -u root fpm_1 sh -c "
cd /var/www/html
mkdir -p storage/logs storage/framework/views storage/framework/cache/data storage/framework/sessions bootstrap/cache
touch storage/logs/laravel.log
chown -R www-data:www-data storage bootstrap/cache
chmod -R 775 storage bootstrap/cache
"
```

### 9.2 Error actual: tablas system faltantes

Logs vistos:

```text
SQLSTATE[42S02]: Base table or view not found: 1146
Table 'ceos-facturacion_com.websites' doesn't exist

SQLSTATE[42S02]: Base table or view not found: 1146
Table 'ceos-facturacion_com.clients' doesn't exist
```

Lectura:

- La BD system `ceos-facturacion_com` existe, pero no tiene tablas base.
- Faltan migraciones del sistema o la instalacion quedo a medias.
- No es problema de Vite porque se confirmo:

```text
public/build/manifest.json existe
```

---

## 10. Comando recomendado para reparar el 500 actual

No usar `migrate:refresh` si hay datos que preservar.

Ejecutar:

```bash
cd /var/ceos-facturacion.com

docker compose stop supervisor_1 scheduling_1

docker compose exec -T fpm_1 sh -c "
cd /var/www/html
CACHE_DRIVER=file php artisan migrate --seed --force
CACHE_DRIVER=file php artisan tenancy:migrate --force || true
CACHE_DRIVER=file php artisan package:discover
CACHE_DRIVER=file php artisan config:clear
CACHE_DRIVER=file php artisan cache:clear
CACHE_DRIVER=file php artisan route:clear
CACHE_DRIVER=file php artisan view:clear
CACHE_DRIVER=file php artisan config:cache
"

docker compose restart fpm_1
docker compose start supervisor_1 scheduling_1
```

Validar:

```bash
curl -vkI --resolve ceos-facturacion.com:443:127.0.0.1 https://ceos-facturacion.com/login
```

Si vuelve a fallar:

```bash
cd /var/ceos-facturacion.com

docker compose exec -T fpm_1 sh -c "
cd /var/www/html
tail -180 storage/logs/laravel-2026-07-02.log
tail -180 storage/logs/laravel.log
"
```

Tambien revisar estado de migraciones:

```bash
docker compose exec -T fpm_1 sh -c "
cd /var/www/html
CACHE_DRIVER=file php artisan migrate:status | head -120
"
```

---

## 11. Comandos de diagnostico completos

### Ver servicios Compose

```bash
cd /var/ceos-facturacion.com
docker compose config --services
docker compose ps
docker ps
```

### Logs de nginx y FPM

```bash
cd /var/ceos-facturacion.com
docker compose logs --tail=120 nginx_1
docker compose logs --tail=160 fpm_1
```

### Logs Laravel

```bash
docker compose exec -T fpm_1 sh -c '
cd /var/www/html
echo "== logs =="
ls -lah storage/logs
for f in storage/logs/*.log; do
  [ -f "$f" ] && echo "### $f" && tail -120 "$f"
done
'
```

### Verificar assets Vite

```bash
docker compose exec -T fpm_1 sh -c '
cd /var/www/html
ls -lah public/build/manifest.json public/build 2>/dev/null || true
'
```

### Probar apex y tenant localmente

```bash
curl -vkI --resolve ceos-facturacion.com:443:127.0.0.1 https://ceos-facturacion.com/login
curl -vkI --resolve demo.ceos-facturacion.com:443:127.0.0.1 https://demo.ceos-facturacion.com/login
```

### Probar origen publico desde fuera de la LAN

```powershell
curl.exe -vkI --resolve ceos-facturacion.com:443:143.0.248.236 https://ceos-facturacion.com
curl.exe -vI  --resolve ceos-facturacion.com:80:143.0.248.236 http://ceos-facturacion.com
curl.exe -vkI --resolve demo.ceos-facturacion.com:443:143.0.248.236 https://demo.ceos-facturacion.com/login
```

### Probar camino real por Cloudflare

```powershell
curl.exe -vkI https://ceos-facturacion.com
curl.exe -vkI https://demo.ceos-facturacion.com/login
```

---

## 12. Decisiones importantes

- No borrar volumenes Docker.
- No usar `docker compose down -v`.
- No usar `migrate:refresh` salvo reinstalacion limpia sin datos.
- Para Cloudflare proxy naranja, resolver primero FortiGate/firewall.
- Mientras tanto, dejar DNS en `Solo DNS` permite operar directo contra el
  origen con SSL de Let's Encrypt.
- `www` debe redirigir a apex; no crear `www` como tenant.
- Si se reinstala, usar scripts oficiales; no borrar carpetas a mano.

---

## 13. Commits locales relacionados

En `codeplant`:

```text
19d3207 fix(onpremise): repair ssl proxy handling
afb5e3a fix(onpremise): detect proxy cert volume
d963b84 fix(onpremise): handle www admin alias
82712fb fix(linux): repair ssl proxy routing
85ead4c docs(facturador): add cloudflare ssl troubleshooting
```

En `pro-8`:

```text
39111e2 fix(onpremise): declare proxy ssl routing
ed186fb fix(onpremise): redirect www admin host
```

El push queda manual.

---

## 14. Estado final para continuar

Si se continua desde otro dispositivo, iniciar por aqui:

1. Entrar al servidor.
2. Ir a:

```bash
cd /var/ceos-facturacion.com
```

3. Confirmar que Cloudflare esta en `Solo DNS` mientras se repara FortiGate.
4. Ejecutar migraciones system sin borrar datos:

```bash
docker compose stop supervisor_1 scheduling_1
docker compose exec -T fpm_1 sh -c "
cd /var/www/html
CACHE_DRIVER=file php artisan migrate --seed --force
CACHE_DRIVER=file php artisan tenancy:migrate --force || true
CACHE_DRIVER=file php artisan config:clear
CACHE_DRIVER=file php artisan cache:clear
CACHE_DRIVER=file php artisan route:clear
CACHE_DRIVER=file php artisan view:clear
CACHE_DRIVER=file php artisan config:cache
"
docker compose restart fpm_1
docker compose start supervisor_1 scheduling_1
```

5. Probar:

```bash
curl -vkI --resolve ceos-facturacion.com:443:127.0.0.1 https://ceos-facturacion.com/login
```

6. Si funciona local y directo por IP publica, pero no con Cloudflare proxy
   naranja, volver al checklist FortiGate/Cloudflare de este documento.

