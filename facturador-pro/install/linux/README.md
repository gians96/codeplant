# Facturador Pro-8 Ã¢â‚¬â€ InstalaciÃƒÂ³n en Linux (Ubuntu/Debian)

Scripts para instalar y mantener Pro-8 sobre Docker en hosts Linux nativos.

## Contenido

| Archivo | PropÃƒÂ³sito |
|---------|-----------|
| `install.sh` | InstalaciÃƒÂ³n **producciÃƒÂ³n** (proxy + tenant + MySQL + Redis + SSL) |
| `install-local.sh` | InstalaciÃƒÂ³n **local / desarrollo** (sin proxy, sin SSL) Ã¢â€ Â nuevo |
| `updateSSL.sh` | RenovaciÃƒÂ³n de certificados SSL |
| `update.sh` | Actualizar cÃƒÂ³digo del proyecto tras `git pull` |

## InstalaciÃƒÂ³n producciÃƒÂ³n

```bash
curl -O https://raw.githubusercontent.com/gians96/codeplant/master/facturador-pro/install/linux/install.sh
chmod +x install.sh
sudo ./install.sh
```

El script pide dominio, nÃƒÂºmero de servicio y puerto MySQL.

La instalaciÃƒÂ³n de producciÃƒÂ³n incluye Soketi para Laravel Broadcasting. Pro-8 publica internamente a `soketi_DOMINIO:6001` y VendeMaster se conecta por el mismo dominio HTTPS (`wss://DOMINIO/app/...`), sin abrir un puerto WebSocket adicional.

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
3. Clona `pro-8` en `~/proyectos/pro-8` (pregunta rama, default `master`).
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
```

El script hace, en orden:

1. `git pull`
2. `composer install` (con `--no-dev --optimize-autoloader` en prod)
3. **`composer dump-autoload -o`** Ã¢â€ Â clave para clases nuevas
4. `php artisan module:discover`
5. `migrate` + `tenancy:migrate`
6. `route:clear` / `config:clear` / `cache:clear` / `view:clear`
7. `config:cache` (solo en prod)
8. `kill -USR2 1` sobre `fpm_1` (purga OPcache sin reiniciar el contenedor)
9. `supervisorctl restart all` sobre `supervisor_1` (reinicia colas)

AdemÃƒÂ¡s normaliza Laravel Broadcasting: si el `.env` antiguo tenÃƒÂ­a `PUSHER_HOST=127.0.0.1`, lo cambia al contenedor `soketi_DOMINIO`; para clientes mÃƒÂ³viles deja `PUSHER_CLIENT_HOST=DOMINIO`, `PUSHER_CLIENT_PORT=443` y `PUSHER_CLIENT_SCHEME=https`.

> Si `docker-compose.yml` fue generado antes de Soketi, el update mostrarÃƒÂ¡ una advertencia. Para activar tiempo real en ese servidor hay que regenerar el stack con el instalador actualizado o agregar manualmente el servicio `soketi_1` y el proxy `/app`.

> Todos los `php artisan` llevan `CACHE_DRIVER=file` para evitar el bug del driver `redis_tenancy`.

Si `composer install` falla porque `composer.lock` existe pero no contiene un paquete nuevo requerido por `composer.json` (por ejemplo `pusher/pusher-php-server` para Laravel Broadcasting), **no uses `composer update` global**. El script hace fallback a:

```bash
composer update pusher/pusher-php-server --with-dependencies
```

Esto actualiza solo el paquete nuevo y sus dependencias directas, evitando mover decenas de dependencias no relacionadas.

### Comandos manuales (si prefieres no usar el script)

```bash
cd /opt/proyectos/mi-empresa.com
git pull origin master
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

## VerificaciÃƒÂ³n post-actualizaciÃƒÂ³n

```bash
# Endpoints nuevos deben responder 200/401 (no 500 con "Target class does not exist")
curl -I http://localhost:8080/api/offline/business-turns
curl -I http://localhost:8080/api/pro8/catalogs/ubigeo
```
