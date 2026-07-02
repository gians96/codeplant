# Facturador Pro-8 Ã¢â‚¬â€ InstalaciÃƒÂ³n en Linux (Ubuntu/Debian)

Scripts para instalar y mantener Pro-8 sobre Docker en hosts Linux nativos.

## Contenido

| Archivo | PropÃƒÂ³sito |
|---------|-----------|
| `install.sh` | InstalaciÃƒÂ³n **producciÃƒÂ³n** (proxy + tenant + MySQL + Redis + SSL) |
| `install-local.sh` | InstalaciÃƒÂ³n **local / desarrollo** (sin proxy, sin SSL) Ã¢â€ Â nuevo |
| `updateSSL.sh` | RenovaciÃƒÂ³n de certificados SSL y reparacion de proxy HTTPS |
| `update.sh` | Actualizar cÃƒÂ³digo del proyecto tras `git pull` |

## InstalaciÃƒÂ³n producciÃƒÂ³n

```bash
curl -O https://raw.githubusercontent.com/gians96/codeplant/master/facturador-pro/install/linux/install.sh
chmod +x install.sh
sudo ./install.sh
```

El script pide dominio, nÃƒÂºmero de servicio y puerto MySQL.

La instalaciÃƒÂ³n de producciÃƒÂ³n incluye Soketi para Laravel Broadcasting. Pro-8 publica internamente a `soketi_DOMINIO:6001` y VendeMaster se conecta por el mismo dominio HTTPS (`wss://DOMINIO/app/...`), sin abrir un puerto WebSocket adicional.

## Reparar SSL/proxy sin reinstalar

Si el servidor responde localmente pero Cloudflare muestra `522`, o si `www`
esta cayendo como tenant en vez de panel administrativo, actualiza y ejecuta:

```bash
cd /opt/proyectos                  # o la raiz donde esta nt-suite.pro/
sudo curl -fSL -o updateSSL.sh https://raw.githubusercontent.com/gians96/codeplant/master/facturador-pro/install/linux/updateSSL.sh
sudo chmod +x updateSSL.sh

sudo ./updateSSL.sh nt-suite.pro --repair-proxy
```

El script no borra volumenes ni toca base de datos. Solo:

1. Copia el certificado al volumen real de `nginx-proxy`.
2. Repara `VIRTUAL_HOST`, `VIRTUAL_PORT`, `VIRTUAL_PROTO` y `CERT_NAME`.
3. Agrega `www.<dominio>` como alias y redirect al dominio base.
4. Reconstruye solo `nginx_N`.
5. Reinicia el proxy y valida `http://` / `https://` contra `127.0.0.1`.

Para renovar certificado y reparar proxy en el mismo flujo:

```bash
sudo ./updateSSL.sh nt-suite.pro
```

## Troubleshooting SSL / Cloudflare / Laravel

### Cloudflare muestra 522 pero el origen directo responde

Sintoma:

```text
https://ceos-facturacion.com        -> 522 desde Cloudflare
curl --resolve dominio:443:IP_ORIGEN https://dominio -> 302 /login
```

Diagnostico:

- Docker, `nginx-proxy`, SSL y Laravel estan bien si el origen directo responde
  `301`, `302` o `200`.
- El `522` queda entre Cloudflare y la red del origen: FortiGate, firewall,
  IPS/DoS/GeoIP, NAT o allowlist de IPs.
- Si un tenant funcionaba y luego falla, revisar si el registro paso de
  `Solo DNS` a proxy naranja.

Pruebas:

```bash
# En el servidor
curl -vkI --resolve ceos-facturacion.com:443:127.0.0.1 https://ceos-facturacion.com
curl -vkI --resolve ceos-facturacion.com:80:127.0.0.1 http://ceos-facturacion.com
```

```powershell
# Desde fuera de la red
curl.exe -vkI --resolve ceos-facturacion.com:443:143.0.248.236 https://ceos-facturacion.com
curl.exe -vI  --resolve ceos-facturacion.com:80:143.0.248.236 http://ceos-facturacion.com
curl.exe -vkI https://ceos-facturacion.com
```

Interpretacion:

| Resultado | Causa probable |
|---|---|
| Directo a `IP_ORIGEN` responde, Cloudflare da `522` | Firewall/NAT bloquea Cloudflare o perfiles de seguridad cortan ese trafico. |
| Local `127.0.0.1:443` falla | Problema de proxy/certificados en Docker; ejecutar `updateSSL.sh DOMINIO --repair-proxy`. |
| Directo a `IP_ORIGEN` falla | NAT/VIP/puertos publicos no llegan al servidor. |

Solucion rapida:

1. Poner `ceos-facturacion.com`, `*.ceos-facturacion.com` y
   `www.ceos-facturacion.com` en `Solo DNS`.
2. Si se necesita proxy naranja, permitir los rangos oficiales de Cloudflare
   hacia `80/443` en FortiGate/firewall y revisar IPS/DoS/GeoIP.

### `400 Bad Request: plain HTTP request was sent to HTTPS port`

Sintoma al abrir en navegador:

```text
143.0.248.236:443 -> 400 Bad Request
The plain HTTP request was sent to HTTPS port
```

Causa: se escribio `143.0.248.236:443` sin `https://`; el navegador mando HTTP
normal al puerto TLS. No es fallo del proxy.

Prueba correcta:

```text
https://143.0.248.236
```

Para Pro-8, la prueba real debe preservar `Host`/SNI:

```bash
curl -vkI --resolve ceos-facturacion.com:443:143.0.248.236 https://ceos-facturacion.com
```

### `www.<dominio>` devuelve 404 o cae como tenant

`www` no debe crearse como tenant. Debe ser alias del panel central y redirigir
al dominio base. Ejecutar:

```bash
cd /var
sudo ./updateSSL.sh ceos-facturacion.com --repair-proxy
```

Validacion:

```bash
curl -vkI --resolve www.ceos-facturacion.com:443:127.0.0.1 https://www.ceos-facturacion.com/login
```

Debe responder `301` hacia `https://ceos-facturacion.com/login`.

### Laravel 500 despues de reparar proxy

Una vez que el proxy funciona, puede aparecer `500` de Laravel. Revisar FPM y
logs:

```bash
cd /var/ceos-facturacion.com
docker compose logs --tail=120 fpm_1
docker compose exec -T fpm_1 sh -c "tail -120 /var/www/html/storage/logs/laravel.log"
```

Errores vistos y solucion:

| Error | Causa | Solucion |
|---|---|---|
| `Class "Illuminate\Foundation\Application" not found` | Falta `vendor/` o Composer no termino. | Ejecutar `composer install` dentro de `fpm_1`. |
| `Class "Barryvdh\Debugbar\ServiceProvider" not found` | Se instalo con `--no-dev`, pero la app intenta cargar Debugbar. | Instalar sin `--no-dev` o quitar el provider de Debugbar del proyecto. |
| `Please provide a valid cache path` | Faltan carpetas de `storage/framework` o permisos. | Crear carpetas y permisos de Laravel. |

Comandos de recuperacion:

```bash
cd /var/ceos-facturacion.com

docker compose exec -T -u root fpm_1 sh -c "
mkdir -p storage/logs storage/framework/views storage/framework/cache/data storage/framework/sessions bootstrap/cache
touch storage/logs/laravel.log
chown -R www-data:www-data storage bootstrap/cache
chmod -R 775 storage bootstrap/cache
"

docker compose exec -T fpm_1 sh -c "cd /var/www/html && composer install --optimize-autoloader"
docker compose exec -T fpm_1 sh -c "cd /var/www/html && composer dump-autoload -o"
docker compose exec -T fpm_1 sh -c "CACHE_DRIVER=file php artisan package:discover"
docker compose exec -T fpm_1 sh -c "CACHE_DRIVER=file php artisan config:clear"
docker compose exec -T fpm_1 sh -c "CACHE_DRIVER=file php artisan cache:clear"
docker compose exec -T fpm_1 sh -c "CACHE_DRIVER=file php artisan route:clear"
docker compose exec -T fpm_1 sh -c "CACHE_DRIVER=file php artisan view:clear"
docker compose exec -T fpm_1 sh -c "CACHE_DRIVER=file php artisan config:cache"
docker compose restart fpm_1 supervisor_1 scheduling_1
```

## InstalaciÃƒÂ³n local / desarrollo

Equivalente Linux nativo del `02-install-dev.sh` de Windows Server. Monta el stack con `scripts/local-setup.sh` del propio proyecto: 7 containers, sin proxy ni SSL.

```bash
curl -O https://raw.githubusercontent.com/gians96/codeplant/master/facturador-pro/install/linux/install-local.sh
chmod +x install-local.sh
./install-local.sh          # NO usar sudo; el script pide sudo solo cuando hace falta
```

El script:

1. Verifica/instala prerequisitos (`git`, `curl`, `unzip`, Docker Engine con `get.docker.com`).
2. Instala **Bun** (runtime JS para compilar assets con Vite).
3. Clona `pro-8` en `~/proyectos/pro-8` (pregunta rama, default `gians96`).
4. Ejecuta `scripts/local-setup.sh` del repo Ã¢â‚¬â€ levanta nginx + fpm + mariadb + redis + soketi + scheduling + supervisor.
5. `bun install --ignore-scripts` + `bun run build`.
6. Corrige permisos de `storage/` y `bootstrap/cache` dentro del contenedor `fpm_pro8_local`.
7. Instala alias `pro8up` en `~/.bashrc` para reiniciar el stack rÃƒÂ¡pido.
8. Genera `~/proyectos/pro-8-local.txt` con credenciales.

Tras la instalaciÃƒÂ³n:

| Recurso | Valor |
|---------|-------|
| App | <http://localhost:8080> |
| MySQL | `localhost:3308` (`root` / `secret`) |
| Redis | `redis_pro8_local:6379` sin password |
| FPM | `fpm_pro8_local` |

> **Primer arranque y Docker:** si Docker acaba de instalarse, el script aÃƒÂ±ade tu usuario al grupo `docker` y termina. Cierra sesiÃƒÂ³n (o ejecuta `newgrp docker`) y vuelve a lanzarlo.

Para actualizar el entorno local/desarrollo:

```bash
cd ~/proyectos/pro-8
bash scripts/local-update.sh
```

El update local verifica que FPM vea `composer.json` y `artisan` en
`/var/www/html`. Si el bind mount quedo vacio tras reiniciar Docker/WSL,
recrea el stack con `docker compose down` + `up -d`, sin `-v`, y conserva los
datos locales.

Si `demo.localhost:8080/login` devuelve `SQLSTATE[HY000] [1045] Access denied
for user 'tenancy_demo'`, sincroniza las claves derivadas de Hyn:

```bash
cd ~/proyectos/pro-8
docker exec fpm_pro8_local sh -c "cd /var/www/html && CACHE_DRIVER=file php artisan tenancy:key:update"
docker exec fpm_pro8_local sh -c "CACHE_DRIVER=file php artisan config:cache"
```

## Estructura productiva y datos persistentes

La actualizacion se ejecuta siempre desde la carpeta real del proyecto en produccion, por ejemplo:

```text
/var/nt-suite.pro
/opt/proyectos/mi-empresa.com
```

Dentro de esa carpeta deben existir estos archivos y carpetas clave:

```text
.env
docker-compose.yml
supervisor.conf
storage/
vendor/
public/
```

El `docker-compose.yml` queda estructurado con servicios numerados por instalacion:

| Servicio | Funcion |
|----------|---------|
| `nginx_N` | Entrada HTTP interna de la app. |
| `fpm_N` | PHP-FPM con Laravel montado en `/var/www/html`. |
| `mariadb_N` | Base de datos principal. |
| `redis_N` | Redis persistente. |
| `soketi_N` | WebSocket/Broadcasting. |
| `scheduling_N` | Scheduler de Laravel. |
| `supervisor_N` | Colas y workers. |

La data importante no vive solamente en los contenedores. La base de datos y Redis viven en volumenes Docker:

```text
mysqldataN    Data fisica de MariaDB.
redisdataN    Data persistente de Redis.
```

Por eso el update seguro nunca elimina volumenes y nunca debe ejecutarse con `docker compose down -v`.

## Pasos para actualizar sin perder informacion

El script que debes ejecutar en produccion es `update.sh` en modo `prod`, sin `--skip-backup`:

```bash
cd /var/nt-suite.pro                         # o la carpeta real del proyecto
curl -fsSLo update.sh https://raw.githubusercontent.com/gians96/codeplant/master/facturador-pro/install/linux/update.sh
chmod +x update.sh
sudo ./update.sh prod
```

Ese comando es el flujo seguro porque el script hace backup antes de `git pull`, Composer y migraciones. Si tu proyecto esta en otra ruta, cambia solo el `cd`:

```bash
cd /opt/proyectos/mi-empresa.com
sudo ./update.sh prod
```

Antes de ejecutar puedes verificar que estas en la carpeta correcta:

```bash
pwd
test -f .env && test -f docker-compose.yml && echo "OK estructura base"
docker compose config --services
docker compose ps
docker volume ls | grep -E 'mysqldata|redisdata'
```

El script protege la informacion asi:

1. Verifica `.env` y `docker-compose.yml`.
2. Verifica que el compose tenga `soketi_N` antes de tocar Composer o migraciones.
3. Crea backup completo en `storage/app/backups/pre-update/FECHA/`.
4. Copia `.env`, `docker-compose.yml` y `supervisor.conf` al backup.
5. Genera dump completo de MariaDB con `mysqldump --all-databases`.
6. Comprime el SQL con `gzip` si esta disponible.
7. Levanta solo Soketi con `docker compose up -d soketi_N`.
8. Ejecuta el update de codigo y migraciones.
9. Limpia caches, purga OPcache y reinicia workers.

El backup queda con esta estructura:

```text
storage/app/backups/pre-update/20260526-153000/
+-- .env
+-- docker-compose.yml
+-- supervisor.conf
+-- all-databases.sql.gz
```

No uses estos comandos en produccion si quieres conservar data:

```bash
docker compose down -v
docker volume rm mysqldata1 redisdata1
docker system prune --volumes
rm -rf docker/data/mysql
```

Si necesitas detener contenedores, usa solo `docker compose down`, sin `-v`. Para actualizar normalmente no hace falta detener toda la stack.

## Actualizar el proyecto

Cuando hagas `git pull` y el commit incluye nuevos controllers, mÃƒÂ³dulos, migraciones o rutas, el autoloader de Composer y las caches de Laravel quedan desactualizados. El sÃƒÂ­ntoma tÃƒÂ­pico es:

```
Target class [Modules\Offline\Http\Controllers\BusinessTurnController] does not exist.
Target class [App\Http\Controllers\Tenant\Api\CatalogApiController] does not exist.
```

Usa el script `update.sh` para regenerar todo en un solo paso:

```bash
cd /opt/proyectos/mi-empresa.com           # o donde tengas el proyecto
curl -O https://raw.githubusercontent.com/gians96/codeplant/master/facturador-pro/install/linux/update.sh
chmod +x update.sh
sudo ./update.sh prod                       # "dev" para desarrollo
# No uses --skip-backup en produccion si quieres el flujo con backup automatico.
```

El script hace, en orden:

1. Verifica que el compose tenga Soketi y cancela antes de tocar nada si falta.
2. Crea backup previo en `storage/app/backups/pre-update/` (SQL completo + `.env` + compose + supervisor).
3. Normaliza Laravel Broadcasting y levanta solo el servicio Soketi.
4. `git pull --ff-only`.
5. `composer install` (con `--no-dev --optimize-autoloader` en prod).
6. **`composer dump-autoload -o`** clave para clases nuevas.
7. `php artisan module:discover`.
8. `migrate` + `tenancy:migrate`.
9. `route:clear` / `config:clear` / `cache:clear` / `view:clear`.
10. `config:cache` (solo en prod).
11. `kill -USR2 1` sobre `fpm_1` o el servicio FPM detectado.
12. `supervisorctl restart all` sobre el servicio supervisor detectado.

Ademas normaliza Laravel Broadcasting: si el `.env` antiguo tenia `PUSHER_HOST=127.0.0.1`, lo cambia al contenedor `soketi_DOMINIO`. En instalaciones nuevas mantiene `PUSHER_CLIENT_HOST=DOMINIO`; si el compose antiguo se recupera con Soketi publicado por nginx-proxy, usa `PUSHER_CLIENT_HOST=ws.DOMINIO`.

> Si `docker-compose.yml` fue generado antes de Soketi, el update agrega automaticamente solo el servicio `soketi_N` dentro de `services:`, crea un respaldo `docker-compose.yml.backup-before-soketi-FECHA`, valida el compose con `docker compose config --services` y continua con el backup SQL normal. Conserva intactos `mariadb_*`, `redis_*`, `volumes` y `networks`. No uses `docker compose down -v`.

> Todos los `php artisan` llevan `CACHE_DRIVER=file` para evitar el bug del driver `redis_tenancy`.

Si `composer install` falla porque `composer.lock` existe pero no contiene un paquete nuevo requerido por `composer.json` (por ejemplo `pusher/pusher-php-server` para Laravel Broadcasting), **no uses `composer update` global**. El script hace fallback a:

```bash
composer update pusher/pusher-php-server --with-dependencies
```

Esto actualiza solo el paquete nuevo y sus dependencias directas, evitando mover decenas de dependencias no relacionadas.

### Comandos manuales (si prefieres no usar el script)

```bash
cd /opt/proyectos/mi-empresa.com
git pull origin gians96
docker compose exec -T fpm_1 sh -c "cd /var/www/html && CACHE_DRIVER=file composer install --no-dev --optimize-autoloader"
docker compose exec -T fpm_1 sh -c "cd /var/www/html && composer dump-autoload -o"
docker compose exec -T fpm_1 sh -c "CACHE_DRIVER=file php artisan module:discover"
docker compose exec -T fpm_1 sh -c "CACHE_DRIVER=file php artisan migrate --force"
docker compose exec -T fpm_1 sh -c "CACHE_DRIVER=file php artisan tenancy:migrate --force"
docker compose exec -T fpm_1 sh -c "CACHE_DRIVER=file php artisan route:clear"
docker compose exec -T fpm_1 sh -c "CACHE_DRIVER=file php artisan config:cache"
docker compose exec -T fpm_1 sh -c "CACHE_DRIVER=file php artisan cache:clear"
docker compose exec -T fpm_1 sh -c "kill -USR2 1"
docker compose exec -T supervisor_1 supervisorctl restart all
```

Para instalaciones con VendeMaster/Restaurant, revisa que `.env` tenga:

```env
BROADCAST_DRIVER=pusher
PUSHER_HOST=soketi_mi-empresa_com
PUSHER_PORT=6001
PUSHER_SCHEME=http
PUSHER_CLIENT_HOST=mi-empresa.com
PUSHER_CLIENT_PORT=443
PUSHER_CLIENT_SCHEME=https
```

En servidores antiguos recuperados con el subdominio directo de nginx-proxy, el cliente externo queda como `PUSHER_CLIENT_HOST=ws.mi-empresa.com`.

## VerificaciÃƒÂ³n post-actualizaciÃƒÂ³n

```bash
# Endpoints nuevos deben responder 200/401 (no 500 con "Target class does not exist")
curl -I http://localhost:8080/api/offline/business-turns
curl -I http://localhost:8080/api/pro8/catalogs/ubigeo
```
