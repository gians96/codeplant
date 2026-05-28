# `demo.localhost` devuelve HTTP 500 — `Access denied for user 'tenancy_demo'`

## Síntomas

- Al abrir `http://demo.localhost:8080/login` aparece `HTTP 500 Internal Server Error`.
- El log o la página de error muestra:
  ```text
  SQLSTATE[HY000] [1045] Access denied for user 'tenancy_demo'@'172.18.0.x'
  ```
- La base de datos `tenancy_demo` existe.
- El usuario MySQL `tenancy_demo` existe, normalmente como `tenancy_demo`@`%`.

## Causa raíz

En este proyecto, Hyn Multi Tenant genera la contraseña MySQL de cada tenant a
partir de datos del website y de la key de la aplicación.

Si `local-setup.sh` ejecuta `php artisan key:generate --force` sobre una
instalación local que ya tenía tenants, cambia `APP_KEY`. Desde ese momento
Laravel calcula una contraseña nueva para `tenancy_demo`, pero MariaDB conserva
la contraseña anterior del usuario `tenancy_demo`@`%`.

Resultado: el sistema conecta bien a la base principal `pro8_local`, encuentra
el hostname `demo.localhost`, intenta abrir la base tenant `tenancy_demo` y
MariaDB rechaza la autenticación.

## Solución rápida

Ejecutar desde el host WSL:

```bash
cd ~/proyectos/pro-8

docker exec fpm_pro8_local sh -c "cd /var/www/html && CACHE_DRIVER=file php artisan tenancy:key:update"
docker exec fpm_pro8_local sh -c "cd /var/www/html && CACHE_DRIVER=file php artisan config:cache"
docker exec fpm_pro8_local sh -c "cd /var/www/html && CACHE_DRIVER=file php artisan cache:clear"
docker exec fpm_pro8_local sh -c "cd /var/www/html && CACHE_DRIVER=file php artisan tenancy:migrate --force"
```

Validar:

```bash
curl -sS -o /tmp/pro8-demo-login.html -w 'HTTP %{http_code}\n' --max-time 20 http://demo.localhost:8080/login
grep -o '<title>[^<]*</title>' /tmp/pro8-demo-login.html | head -1
```

Esperado:

```text
HTTP 200
<title>Facturación Electrónica</title>
```

## Qué hace cada comando

- `tenancy:key:update`: recalcula y actualiza en MariaDB las contraseñas de los
  usuarios tenant usando la key actual de Laravel.
- `config:cache`: deja la configuración recacheada con el estado actual.
- `cache:clear`: elimina caché de aplicación que pueda conservar datos viejos.
- `tenancy:migrate --force`: confirma que Laravel ya puede conectar a las bases
  tenant y aplica migraciones pendientes.

## Diagnóstico usado

Comprobar que el login falla:

```bash
curl -sS -o /tmp/pro8-demo-login.html -w 'HTTP %{http_code}\n' --max-time 20 http://demo.localhost:8080/login
```

Comprobar que la base y el usuario tenant existen:

```bash
docker exec mariadb_pro8_local mysql -uroot -psecret -N -e "SELECT User, Host FROM mysql.user WHERE User = 'tenancy_demo'; SHOW DATABASES LIKE 'tenancy_demo';"
```

Comprobar que el tenant está registrado en la base principal:

```bash
docker exec mariadb_pro8_local mysql -uroot -psecret pro8_local -N -e "SELECT id, uuid, created_at FROM websites; SELECT fqdn, website_id FROM hostnames WHERE fqdn = 'demo.localhost';"
```

Comprobar que el comando oficial existe:

```bash
docker exec fpm_pro8_local sh -c "cd /var/www/html && CACHE_DRIVER=file php artisan list | grep -i -E 'tenant|pass|key'"
docker exec fpm_pro8_local sh -c "cd /var/www/html && CACHE_DRIVER=file php artisan help tenancy:key:update"
```

## Comandos ejecutados en la reparación

Estos fueron los comandos usados para reparar el entorno local:

```bash
cd /home/gg/proyectos/pro-8

docker exec fpm_pro8_local sh -c "cd /var/www/html && CACHE_DRIVER=file php artisan tenancy:key:update && CACHE_DRIVER=file php artisan config:cache && CACHE_DRIVER=file php artisan cache:clear"

curl -sS -o /tmp/pro8-demo-login.html -w 'HTTP %{http_code}\n' --max-time 20 http://demo.localhost:8080/login

docker exec fpm_pro8_local sh -c "cd /var/www/html && CACHE_DRIVER=file php artisan tenancy:migrate --force"
```

También se validó conexión directa a MariaDB como `tenancy_demo` usando la
contraseña derivada por Laravel, sin imprimirla en la terminal:

```bash
docker exec mariadb_pro8_local mysql -utenancy_demo -p$(docker exec fpm_pro8_local sh -c "cd /var/www/html && php -r 'require \"vendor/autoload.php\"; \$app=require \"bootstrap/app.php\"; \$kernel=\$app->make(Illuminate\\Contracts\\Console\\Kernel::class); \$kernel->bootstrap(); \$site=Hyn\\Tenancy\\Models\\Website::where(\"uuid\", \"tenancy_demo\")->firstOrFail(); echo md5(sprintf(\"%d.%s.%s.%s\", \$site->id, \$site->uuid, (string) \$site->created_at, config(\"tenancy.key\")));'" ) tenancy_demo -N -e "SELECT COUNT(*) FROM configurations;"
```

Salida esperada:

```text
1
```

## Prevención aplicada

Se corrigieron los scripts locales para reducir que vuelva a ocurrir:

- `pro-8/scripts/local-setup.sh` conserva `APP_KEY` si ya existe.
- `pro-8/scripts/local-setup.sh` ejecuta `tenancy:key:update` después de migrar
  la base principal.
- `pro-8/scripts/local-update.sh` también ejecuta `tenancy:key:update` antes de
  migrar tenants.

## Importante

No usar `docker compose down -v` para este problema. Ese comando borra volúmenes
y puede eliminar datos locales de MariaDB. La reparación correcta es sincronizar
las claves tenant con `tenancy:key:update`.