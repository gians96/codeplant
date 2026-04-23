# Contenedor `fpm_*` queda `unhealthy` tras reiniciar — `nc: not found`

## Síntomas

- Tras reiniciar la PC / Docker Desktop / servidor, el sitio no responde.
- `docker ps` muestra:
  ```
  fpm_pro8_local    Up X seconds (unhealthy)    9000/tcp
  nginx_pro8_local  Created                     0.0.0.0:8080->80/tcp
  ```
- `nginx_*` nunca pasa a `Started` porque depende de que `fpm_*` esté *healthy*.
- `docker compose up -d` se queda en:
  ```
  ⠼ Container fpm_pro8_local  Waiting  76.7s
  ...
  dependency failed to start: container fpm_pro8_local is unhealthy
  ```

## Diagnóstico

Inspeccionar el healthcheck del contenedor fpm:

```bash
docker inspect --format='{{json .State.Health}}' fpm_pro8_local | head -c 500
```

Salida típica:
```json
{"Status":"unhealthy","FailingStreak":6,"Log":[
  {"ExitCode":127,"Output":"/bin/sh: 1: nc: not found\n"},
  ...
]}
```

## Causa raíz

El `docker-compose.local.yml` / `docker-compose.yml` generado por los scripts de
instalación definía el healthcheck así:

```yaml
test: ["CMD-SHELL", "kill -0 1 && test -S /var/run/php-fpm.sock || nc -z 127.0.0.1 9000"]
```

Dos problemas:

1. **`nc` (netcat) no está instalado** en la imagen oficial `php-fpm`. El comando
   devuelve siempre exit code `127`.
2. **Precedencia incorrecta**: `kill -0 1 && test -S sock || nc -z 9000` se
   evalúa como `(A && B) || C`. Como no existe el socket UNIX (fpm usa TCP), la
   parte `B` falla y se ejecuta `C` → `nc` → exit 127 → healthcheck falla.

Consecuencia: fpm arranca y atiende en `:9000` correctamente, pero el healthcheck
no lo sabe. Docker lo marca `unhealthy`, y nginx (con
`depends_on: fpm: condition: service_healthy`) no arranca nunca.

Por qué aparece solo tras reiniciar: en el primer `up` Docker espera
`start_period` antes de considerar fallos, y algunas versiones toleran un
healthcheck inicial erróneo. Al recrear contenedores (reinicio de host, Docker
Desktop, `down && up`), el `depends_on` bloquea estrictamente.

## Solución

Reemplazar el healthcheck por uno sin dependencias externas que lea
`/proc/net/tcp*` directamente (puerto 9000 en hex = `2328`):

```yaml
healthcheck:
    test: ["CMD-SHELL", "kill -0 1 2>/dev/null && grep -q ':2328' /proc/net/tcp /proc/net/tcp6 2>/dev/null"]
    interval: 30s
    timeout: 5s
    retries: 3
    start_period: 15s
```

- `kill -0 1` → verifica que el proceso maestro de php-fpm (PID 1) siga vivo.
- `grep ':2328' /proc/net/tcp*` → confirma que algo escucha en el puerto 9000.
  Se consulta `tcp6` porque la imagen oficial escucha en IPv6 por defecto.
- No requiere `nc`, `curl`, ni instalar paquetes.

## Aplicación

### 1. Fuentes corregidas (ya en master)

- `pro-8/scripts/local-setup.sh` — genera `docker-compose.local.yml` (dev)
- `codeplant/facturador-pro/install/linux/install.sh` — instalación prod Linux
- `codeplant/facturador-pro/install/windows-server/02-install-prod.sh` — prod WSL

Nuevas instalaciones ya no sufren el bug.

### 2. Instalaciones existentes (servidores ya desplegados)

Parche en caliente por dominio, sin pérdida de datos:

```bash
cd /ruta/al/proyecto/<dominio>   # donde vive el docker-compose.yml del sitio

# Backup
cp docker-compose.yml docker-compose.yml.bak

# Reemplazo
sed -i 's|kill -0 1 && test -S /var/run/php-fpm.sock || nc -z 127.0.0.1 9000|kill -0 1 2>/dev/null \&\& grep -q '\'':2328'\'' /proc/net/tcp /proc/net/tcp6 2>/dev/null|' docker-compose.yml

# Verificar
grep 'CMD-SHELL' docker-compose.yml

# Recrear fpm y nginx (no toca mariadb/redis)
docker compose up -d --force-recreate fpm_1 nginx_1

# Validar
sleep 20 && docker compose ps
```

Para múltiples dominios:

```bash
for f in $(find ~ -name "docker-compose.yml" 2>/dev/null); do
    grep -q 'nc -z 127.0.0.1 9000' "$f" || continue
    sed -i 's|kill -0 1 && test -S /var/run/php-fpm.sock || nc -z 127.0.0.1 9000|kill -0 1 2>/dev/null \&\& grep -q '\'':2328'\'' /proc/net/tcp /proc/net/tcp6 2>/dev/null|' "$f"
    (cd "$(dirname "$f")" && docker compose up -d --force-recreate fpm_1 nginx_1)
    echo "✓ Parcheado: $f"
done
```

## Verificación

```bash
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "fpm|nginx"
```

Esperado: todos los `fpm_*` y `nginx_*` con `(healthy)`.

```bash
curl -sI http://localhost:8080/ | head -5
# HTTP/1.1 200 (o 302 si redirige a login)
```

## Referencias

- Fecha del bug: detectado 2026-04-23 tras reinicio de WSL en entorno dev.
- Imagen afectada: `docker/php-fpm/Dockerfile` basada en `php:8.2-fpm`.
- FPM escucha en `[::]:9000` (IPv6) por `listen = 9000` en `zz-docker.conf`.

---

# Bonus: bind mount vacío en nginx tras reinicio (WSL2 + Docker Desktop)

## Síntomas

- Tras reiniciar el PC, los contenedores están `healthy` pero nginx responde **404 Not Found**.
- `docker exec nginx_pro8_local ls /var/www/html/public/` → *No such file or directory*.
- `docker exec nginx_pro8_local ls -la /var/www/html/` → solo `.` y `..` (vacío).
- En el host, `ls /home/gg/proyectos/pro-8/public/` muestra todos los archivos correctamente.
- `docker inspect` confirma el bind: `bind /home/gg/proyectos/pro-8 -> /var/www/html`.

## Causa

Con `restart: always` + Docker Desktop iniciando al arrancar Windows, Docker
levanta los contenedores **antes de que WSL haya montado `$HOME`**. Docker
encuentra la ruta inexistente, la crea como directorio vacío en el host de
Docker y bindea ese directorio vacío dentro del contenedor. Cuando WSL expone
los archivos reales segundos después, el mount del contenedor ya quedó
"congelado" apuntando al vacío.

## Solución

Recrear los contenedores una vez que el filesystem del host esté disponible:

```bash
cd ~/proyectos/pro-8
docker compose -f docker-compose.local.yml down
docker compose -f docker-compose.local.yml up -d
```

## Prevención

- **Opción A**: Desactivar el autoinicio de Docker Desktop en Windows y
  levantarlo manualmente después de login.
- **Opción B**: Alias en `~/.bashrc` de WSL para recrear el stack post-reboot:
  ```bash
  alias pro8up='cd ~/proyectos/pro-8 && docker compose -f docker-compose.local.yml down && docker compose -f docker-compose.local.yml up -d'
  ```
- **Opción C**: Cambiar `restart: always` → `restart: unless-stopped` y detener
  el stack con `down` antes de apagar el PC.
