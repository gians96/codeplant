# Facturador Pro-8 Ã¢â‚¬â€ InstalaciÃƒÂ³n en Windows Server (WSL2)

## Ã‚Â¿Por quÃƒÂ© WSL2?

PHP/Laravel lee miles de archivos por request. En NTFS (C:\) vÃƒÂ­a 9P, el TTFB es de 4-8 segundos. Con el cÃƒÂ³digo en ext4 nativo dentro de WSL, el TTFB es < 1 segundo.

## Requisitos

| Requisito | MÃƒÂ­nimo | Recomendado |
|-----------|--------|-------------|
| **OS** | Windows Server 2019+ / Windows 10+ | Windows Server 2022 |
| **RAM** | 8 GB | 16 GB |
| **Disco** | SSD 50 GB | SSD 100 GB |
| **CPU** | 4 cores (VT-x/AMD-V habilitado) | 8 cores |
| **Red** | IP fija en LAN | IP fija + dominio |

## Proceso de instalaciÃƒÂ³n (2 fases)

### Fase 1 Ã¢â‚¬â€ Preparar entorno (PowerShell como Admin)

```powershell
# Descargar el script
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/gians96/codeplant/master/facturador-pro/install/windows-server/01-setup-wsl.ps1" -OutFile "01-setup-wsl.ps1"

# Ejecutar
powershell -ExecutionPolicy Bypass -File 01-setup-wsl.ps1
```

Este script:
1. Verifica virtualizaciÃƒÂ³n (VT-x/AMD-V)
2. Habilita WSL2 + Virtual Machine Platform
3. Instala Ubuntu 24.04
4. Crea usuario seguro (default: `pro8admin`)
5. Instala Docker Engine nativo
6. Abre puertos en Windows Firewall (80, 443, 8080)
7. Genera `data-config.txt` con credenciales

**ParÃƒÂ¡metros opcionales:**
```powershell
# Usuario personalizado
powershell -File 01-setup-wsl.ps1 -WslUser "miusuario"

# Forzar reinstalaciÃƒÂ³n
powershell -File 01-setup-wsl.ps1 -Force
```

### Fase 2 Ã¢â‚¬â€ Instalar proyecto (dentro de WSL)

Abrir WSL y descargar el script correspondiente:

```bash
wsl
```

#### OpciÃƒÂ³n A: ProducciÃƒÂ³n (dominio, proxy, SSL)

```bash
curl -O https://raw.githubusercontent.com/gians96/codeplant/master/facturador-pro/install/windows-server/02-install-prod.sh
chmod +x 02-install-prod.sh
sudo ./02-install-prod.sh
```

El script pide:
- **Dominio** (ej: `mi-empresa.com`)
- **NÃƒÂºmero de servicio** (1 para primera instalaciÃƒÂ³n, 2+ para multi-proyecto)
- **Puerto MySQL** (auto-detectado)
- **SSL** (certbot manual DNS challenge, opcional)

Incluye:
- Proxy reverso (`rash07/nginx-proxy:4.0`) para soporte multi-proyecto
- OPcache + JIT para mÃƒÂ¡ximo rendimiento
- MariaDB con tuning optimizado
- Redis con maxmemory 256MB
- Soketi para Laravel Broadcasting, publicado por el mismo dominio HTTPS (`wss://DOMINIO/app/...`)
- Headers de seguridad en nginx
- Credenciales aleatorias guardadas en `data-config.txt`

**Multi-proyecto:** Ejecutar de nuevo con service number 2, 3, etc. Solo el primer servicio instala el proxy.

#### OpciÃƒÂ³n B: Desarrollo (local, sin proxy ni SSL)

```bash
curl -O https://raw.githubusercontent.com/gians96/codeplant/master/facturador-pro/install/windows-server/02-install-dev.sh
chmod +x 02-install-dev.sh
./02-install-dev.sh
```

- Clona el repo en `~/proyectos/pro-8/`
- Ejecuta `scripts/local-setup.sh` del propio proyecto
- App en `http://localhost:8080`
- MySQL en `localhost:3308` (root / secret)

## DespuÃƒÂ©s de la instalaciÃƒÂ³n

### Acceso diario

```bash
# Entrar a WSL
wsl

# Ir al proyecto
cd ~/proyectos/mi-empresa.com    # producciÃƒÂ³n
cd ~/proyectos/pro-8             # desarrollo

# Iniciar Docker (si no arranca solo)
sudo service docker start

# Levantar containers
docker compose up -d

# Ver logs
docker compose logs -f
```

### Actualizar codigo (desarrollo local)

```bash
cd ~/proyectos/pro-8
bash scripts/local-update.sh
```

El update local valida que el contenedor FPM vea `composer.json` y `artisan` en
`/var/www/html`. Si WSL/Docker dejo el bind mount vacio despues de un reinicio,
el script recrea el stack con `docker compose down` + `up -d`, sin `-v`, y luego
continua con Composer, Bun y migraciones.

### Actualizar cÃƒÂ³digo (producciÃƒÂ³n)

**OpciÃƒÂ³n A Ã¢â‚¬â€ script todo-en-uno (recomendado):**

```bash
cd ~/proyectos/mi-empresa.com
curl -O https://raw.githubusercontent.com/gians96/codeplant/master/facturador-pro/install/windows-server/03-update.sh
chmod +x 03-update.sh
./03-update.sh prod
./03-update.sh prod --skip-backup   # solo si ya hiciste backup manual
```

El script ejecuta en orden: verifica Soketi y cancela si el compose es antiguo, crea backup previo en `storage/app/backups/pre-update/`, normaliza Broadcasting, levanta solo Soketi, `git pull --ff-only`, `composer install`, **`composer dump-autoload -o`** (clave para detectar controllers/modulos nuevos), `module:discover`, `migrate` + `tenancy:migrate`, limpieza de caches, `config:cache`, purga OPcache (`kill -USR2 1`) y reinicia colas.

Tambien normaliza Laravel Broadcasting: si el `.env` antiguo tenia `PUSHER_HOST=127.0.0.1`, lo cambia al contenedor `soketi_DOMINIO`. En instalaciones nuevas mantiene `PUSHER_CLIENT_HOST=DOMINIO`; si el compose antiguo se recupera con Soketi publicado por nginx-proxy, usa `PUSHER_CLIENT_HOST=ws.DOMINIO`.

> Si `docker-compose.yml` fue generado antes de Soketi, el update cancela antes de migrar y muestra el bloque YAML que debes agregar. Agrega solo ese servicio dentro de `services:` y conserva intactos `mariadb_*`, `redis_*`, `volumes` y `networks`. No uses `docker compose down -v`.

> Si alguna vez ves `"Target class [Modules\Offline\Http\Controllers\XxxController] does not exist"` es porque el autoloader de Composer estÃƒÂ¡ desactualizado. El paso `composer dump-autoload -o` del script lo arregla.

**OpciÃƒÂ³n B Ã¢â‚¬â€ comandos manuales:**

```bash
cd ~/proyectos/mi-empresa.com
git pull origin gians96
docker compose exec -T fpm_1 sh -c "cd /var/www/html && CACHE_DRIVER=file composer install --no-dev --optimize-autoloader"
docker compose exec -T fpm_1 sh -c "cd /var/www/html && composer dump-autoload -o"
docker compose exec -T fpm_1 sh -c "CACHE_DRIVER=file php artisan module:discover"
docker compose exec -T fpm_1 sh -c "CACHE_DRIVER=file php artisan migrate --force"
docker compose exec -T fpm_1 sh -c "CACHE_DRIVER=file php artisan tenancy:migrate --force"
docker compose exec -T fpm_1 sh -c "CACHE_DRIVER=file php artisan route:clear"
docker compose exec -T fpm_1 sh -c "CACHE_DRIVER=file php artisan config:cache"
docker compose exec -T fpm_1 sh -c "CACHE_DRIVER=file php artisan cache:clear"
docker compose exec -T fpm_1 sh -c "kill -USR2 1"   # purga OPcache
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

> **IMPORTANTE:** Todo comando `php artisan` en CLI debe llevar `CACHE_DRIVER=file` para evitar el bug del driver `redis_tenancy`.

### Renovar SSL

```bash
certbot certonly --manual -d *.mi-empresa.com -d mi-empresa.com --agree-tos --no-bootstrap --manual-public-ip-logging-ok --preferred-challenges dns-01 --server https://acme-v02.api.letsencrypt.org/directory

cp /etc/letsencrypt/live/mi-empresa.com/privkey.pem ~/proyectos/certs/mi-empresa.com.key
cp /etc/letsencrypt/live/mi-empresa.com/fullchain.pem ~/proyectos/certs/mi-empresa.com.crt

docker restart $(docker ps --filter "ancestor=rash07/nginx-proxy:4.0" --format "{{.Names}}" | head -1)
```

## Archivos generados

| Archivo | UbicaciÃƒÂ³n | PropÃƒÂ³sito |
|---------|-----------|-----------|
| `data-config.txt` | Junto al script | Credenciales WSL + proyecto |
| `DOMINIO.txt` | `~/proyectos/` | Credenciales del proyecto |
| `docker-compose.yml` | `~/proyectos/DOMINIO/` | Stack de containers |
| `.env` | `~/proyectos/DOMINIO/` | Config Laravel |

## Troubleshooting

### ERR_EMPTY_RESPONSE o "File not found"

Si el navegador devuelve respuesta vacÃƒÂ­a o PHP dice "File not found":

```bash
# Reconstruir Nginx y PHP-FPM (config ya estÃƒÂ¡ dentro de la imagen)
cd ~/proyectos/mi-empresa.com
docker compose up -d --build --force-recreate nginx_1 fpm_1
```

> La config de Nginx estÃƒÂ¡ horneada dentro de la imagen (build-time), **no depende de bind mounts**. Si necesitas cambiar la config, edita `proxy/fpms/DOMINIO/default` y reconstruye con `--build`.

### Composer no encuentra composer.json en /var/www/html

En desarrollo local con WSL2, el contenedor puede quedar con `/var/www/html`
vacio si Docker arranco antes de que WSL exponga el filesystem del usuario.

```bash
cd ~/proyectos/pro-8
bash scripts/local-update.sh
# o solo re-montar el stack:
bash scripts/pro8-restart.sh
```

No uses `docker compose down -v` para este caso; borraria datos locales.

### SQLSTATE 1045 con tenancy_demo en demo.localhost

Si despues de `bash scripts/local-setup.sh` ves `Access denied for user
'tenancy_demo'`, la `APP_KEY` cambio y la password MySQL derivada por Hyn quedo
desincronizada. El setup/update local actual conserva `APP_KEY` y sincroniza
tenants; para repararlo manual:

```bash
cd ~/proyectos/pro-8
docker exec fpm_pro8_local sh -c "cd /var/www/html && CACHE_DRIVER=file php artisan tenancy:key:update"
docker exec fpm_pro8_local sh -c "CACHE_DRIVER=file php artisan config:cache"
```

### Docker no arranca al reiniciar Windows

```bash
wsl -d Ubuntu-24.04
sudo service docker start
cd ~/proyectos/mi-empresa.com && docker compose up -d
```

### Healthchecks

Los servicios nginx y fpm tienen healthchecks configurados. Docker los reinicia automÃƒÂ¡ticamente si fallan. Para verificar:

```bash
docker ps --format "table {{.Names}}\t{{.Status}}"
# Debe mostrar "(healthy)" en nginx y fpm
```
