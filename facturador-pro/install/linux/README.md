# Facturador Pro-8 — Instalación en Linux (Ubuntu/Debian)

Scripts para instalar y mantener Pro-8 sobre Docker en hosts Linux nativos.

## Contenido

| Archivo | Propósito |
|---------|-----------|
| `install.sh` | Instalación inicial (proxy + tenant + MySQL + Redis) |
| `updateSSL.sh` | Renovación de certificados SSL |
| `update.sh` | **Actualizar código del proyecto tras `git pull`** ← nuevo |

## Instalación inicial

```bash
curl -O https://raw.githubusercontent.com/gians96/codeplant/master/facturador-pro/install/linux/install.sh
chmod +x install.sh
sudo ./install.sh
```

El script pide dominio, número de servicio y puerto MySQL.

## Actualizar el proyecto

Cuando hagas `git pull` y el commit incluye nuevos controllers, módulos, migraciones o rutas, el autoloader de Composer y las caches de Laravel quedan desactualizados. El síntoma típico es:

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
3. **`composer dump-autoload -o`** ← clave para clases nuevas
4. `php artisan module:discover`
5. `migrate` + `tenancy:migrate`
6. `route:clear` / `config:clear` / `cache:clear` / `view:clear`
7. `config:cache` (solo en prod)
8. `kill -USR2 1` sobre `fpm_1` (purga OPcache sin reiniciar el contenedor)
9. `supervisorctl restart all` sobre `supervisor_1` (reinicia colas)

> Todos los `php artisan` llevan `CACHE_DRIVER=file` para evitar el bug del driver `redis_tenancy`.

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

## Verificación post-actualización

```bash
# Endpoints nuevos deben responder 200/401 (no 500 con "Target class does not exist")
curl -I http://localhost:8080/api/offline/business-turns
curl -I http://localhost:8080/api/pro8/catalogs/ubigeo
```
