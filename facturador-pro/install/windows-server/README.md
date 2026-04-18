# Facturador Pro-8 — Instalación en Windows Server (WSL2)

## ¿Por qué WSL2?

PHP/Laravel lee miles de archivos por request. En NTFS (C:\) vía 9P, el TTFB es de 4-8 segundos. Con el código en ext4 nativo dentro de WSL, el TTFB es < 1 segundo.

## Requisitos

| Requisito | Mínimo | Recomendado |
|-----------|--------|-------------|
| **OS** | Windows Server 2019+ / Windows 10+ | Windows Server 2022 |
| **RAM** | 8 GB | 16 GB |
| **Disco** | SSD 50 GB | SSD 100 GB |
| **CPU** | 4 cores (VT-x/AMD-V habilitado) | 8 cores |
| **Red** | IP fija en LAN | IP fija + dominio |

## Proceso de instalación (2 fases)

### Fase 1 — Preparar entorno (PowerShell como Admin)

```powershell
# Descargar el script
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/gians96/codeplant/master/facturador-pro/install/windows-server/01-setup-wsl.ps1" -OutFile "01-setup-wsl.ps1"

# Ejecutar
powershell -ExecutionPolicy Bypass -File 01-setup-wsl.ps1
```

Este script:
1. Verifica virtualización (VT-x/AMD-V)
2. Habilita WSL2 + Virtual Machine Platform
3. Instala Ubuntu 24.04
4. Crea usuario seguro (default: `pro8admin`)
5. Instala Docker Engine nativo
6. Abre puertos en Windows Firewall (80, 443, 8080)
7. Genera `data-config.txt` con credenciales

**Parámetros opcionales:**
```powershell
# Usuario personalizado
powershell -File 01-setup-wsl.ps1 -WslUser "miusuario"

# Forzar reinstalación
powershell -File 01-setup-wsl.ps1 -Force
```

### Fase 2 — Instalar proyecto (dentro de WSL)

Abrir WSL y descargar el script correspondiente:

```bash
wsl
```

#### Opción A: Producción (dominio, proxy, SSL)

```bash
curl -O https://raw.githubusercontent.com/gians96/codeplant/master/facturador-pro/install/windows-server/02-install-prod.sh
chmod +x 02-install-prod.sh
sudo ./02-install-prod.sh
```

El script pide:
- **Dominio** (ej: `mi-empresa.com`)
- **Número de servicio** (1 para primera instalación, 2+ para multi-proyecto)
- **Puerto MySQL** (auto-detectado)
- **SSL** (certbot manual DNS challenge, opcional)

Incluye:
- Proxy reverso (`rash07/nginx-proxy:4.0`) para soporte multi-proyecto
- OPcache + JIT para máximo rendimiento
- MariaDB con tuning optimizado
- Redis con maxmemory 256MB
- Headers de seguridad en nginx
- Credenciales aleatorias guardadas en `data-config.txt`

**Multi-proyecto:** Ejecutar de nuevo con service number 2, 3, etc. Solo el primer servicio instala el proxy.

#### Opción B: Desarrollo (local, sin proxy ni SSL)

```bash
curl -O https://raw.githubusercontent.com/gians96/codeplant/master/facturador-pro/install/windows-server/02-install-dev.sh
chmod +x 02-install-dev.sh
./02-install-dev.sh
```

- Clona el repo en `~/proyectos/pro-8/`
- Ejecuta `scripts/local-setup.sh` del propio proyecto
- App en `http://localhost:8080`
- MySQL en `localhost:3308` (root / secret)

## Después de la instalación

### Acceso diario

```bash
# Entrar a WSL
wsl

# Ir al proyecto
cd ~/proyectos/mi-empresa.com    # producción
cd ~/proyectos/pro-8             # desarrollo

# Iniciar Docker (si no arranca solo)
sudo service docker start

# Levantar containers
docker compose up -d

# Ver logs
docker compose logs -f
```

### Actualizar código (producción)

```bash
cd ~/proyectos/mi-empresa.com
git pull origin master
docker compose exec -T fpm_1 sh -c "cd /var/www/html && CACHE_DRIVER=file composer install --no-dev --optimize-autoloader"
docker compose exec -T fpm_1 sh -c "CACHE_DRIVER=file php artisan migrate --force"
docker compose exec -T fpm_1 sh -c "CACHE_DRIVER=file php artisan tenancy:migrate --force"
docker compose exec -T fpm_1 sh -c "CACHE_DRIVER=file php artisan config:cache"
docker compose exec -T fpm_1 sh -c "CACHE_DRIVER=file php artisan cache:clear"
docker compose exec -T supervisor_1 supervisorctl restart all
```

> **IMPORTANTE:** Todo comando `php artisan` en CLI debe llevar `CACHE_DRIVER=file` para evitar el bug del driver `redis_tenancy`.

### Renovar SSL

```bash
certbot certonly --manual -d *.mi-empresa.com -d mi-empresa.com --agree-tos --no-bootstrap --manual-public-ip-logging-ok --preferred-challenges dns-01 --server https://acme-v02.api.letsencrypt.org/directory

cp /etc/letsencrypt/live/mi-empresa.com/privkey.pem ~/proyectos/certs/mi-empresa.com.key
cp /etc/letsencrypt/live/mi-empresa.com/fullchain.pem ~/proyectos/certs/mi-empresa.com.crt

docker restart $(docker ps --filter "ancestor=rash07/nginx-proxy:4.0" --format "{{.Names}}" | head -1)
```

## Archivos generados

| Archivo | Ubicación | Propósito |
|---------|-----------|-----------|
| `data-config.txt` | Junto al script | Credenciales WSL + proyecto |
| `DOMINIO.txt` | `~/proyectos/` | Credenciales del proyecto |
| `docker-compose.yml` | `~/proyectos/DOMINIO/` | Stack de containers |
| `.env` | `~/proyectos/DOMINIO/` | Config Laravel |

## Troubleshooting

### ERR_EMPTY_RESPONSE o "File not found"

Si el navegador devuelve respuesta vacía o PHP dice "File not found":

```bash
# Reconstruir Nginx y PHP-FPM (config ya está dentro de la imagen)
cd ~/proyectos/mi-empresa.com
docker compose up -d --build --force-recreate nginx_1 fpm_1
```

> La config de Nginx está horneada dentro de la imagen (build-time), **no depende de bind mounts**. Si necesitas cambiar la config, edita `proxy/fpms/DOMINIO/default` y reconstruye con `--build`.

### Docker no arranca al reiniciar Windows

```bash
wsl -d Ubuntu-24.04
sudo service docker start
cd ~/proyectos/mi-empresa.com && docker compose up -d
```

### Healthchecks

Los servicios nginx y fpm tienen healthchecks configurados. Docker los reinicia automáticamente si fallan. Para verificar:

```bash
docker ps --format "table {{.Names}}\t{{.Status}}"
# Debe mostrar "(healthy)" en nginx y fpm
```
