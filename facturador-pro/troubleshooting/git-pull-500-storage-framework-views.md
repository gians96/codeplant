# Error 500 tras `git pull` — Vistas compiladas versionadas en `storage/framework/views/`

## Síntomas

- Al visitar el sitio (ej. `demo.nt-suite.pro`) aparece:
  ```
  Esta página no funciona
  HTTP ERROR 500
  ```
- En el servidor, al hacer `git pull origin <rama>` salta el error:
  ```
  error: Your local changes to the following files would be overwritten by merge:
      storage/framework/views/09acb46af4...php
      storage/framework/views/2499a16e3e...php
      ...
  Please commit your changes or stash them before you merge.
  ```
  o bien:
  ```
  error: The following untracked working tree files would be overwritten by merge:
      storage/framework/views/*.php
  ```

## Causa raíz

Los archivos `storage/framework/views/*.php` **son caché generado por Laravel**, no código fuente:

- Laravel los crea automáticamente a partir de los `.blade.php` en `resources/views/` y `modules/*/Resources/views/`.
- Sus nombres son hashes SHA1 derivados de la ruta del archivo Blade original.
- Se **regeneran solos** cuando alguien visita una página o se ejecuta `php artisan view:cache`.

Si estos archivos fueron **commiteados al repositorio por error**, aparecen tres problemas:

1. Cada entorno (local, staging, producción) genera su propia versión del caché → `git status` siempre muestra archivos modificados.
2. Al hacer `git pull` con cambios locales sin commitear en esa carpeta, git aborta el merge.
3. Si el `.blade.php` fuente cambió pero el `.php` compilado que está en el repo está desactualizado, Laravel ejecuta código viejo → **HTTP 500** con errores tipo "Undefined variable", "Class not found", etc.

## Solución (una sola vez, en el repositorio)

### 1. Agregar reglas al `.gitignore` raíz

```gitignore
# Laravel — caché de vistas compiladas (generado automáticamente)
/storage/framework/views/*
!/storage/framework/views/.gitignore
```

### 2. Crear `.gitignore` interno en la carpeta `views/`

`storage/framework/views/.gitignore`:
```gitignore
*
!.gitignore
```

Esto mantiene la carpeta en el repo pero ignora todo su contenido (convención estándar de Laravel).

### 3. Eliminar los archivos compilados del index de git

```bash
cd /ruta/al/proyecto
git rm --cached 'storage/framework/views/*.php'
git add .gitignore storage/framework/views/.gitignore
git commit -m "chore(gitignore): untrack compiled blade views in storage/framework/views"
git push origin <tu-rama>
```

> Nota: `git rm --cached` **solo** los quita del repo, no los borra del disco local.

### Si los archivos son propiedad de `www-data` (Docker) y no puedes escribir

```bash
sudo chown -R $(whoami):$(whoami) storage/framework/views
# ... realiza los pasos 1-3 ...
# Al terminar, devuelve la propiedad al usuario del contenedor PHP-FPM:
sudo chown -R www-data:www-data storage/framework/views
```

## Solución en el servidor de producción

Tras pushear el commit, en el servidor:

```bash
cd /var/nt-suite.pro   # o la ruta del proyecto

# Borrar las vistas compiladas antiguas que quedaron en el working tree
rm -f storage/framework/views/*.php

# Pull limpio
git pull origin <tu-rama>
```

Si la app corre en Docker (ej. contenedor `fpm_nt-suite_pro`, ruta interna `/var/www/html`):

```bash
# 1) Borrar vistas compiladas obsoletas
docker exec fpm_nt-suite_pro sh -c 'rm -f /var/www/html/storage/framework/views/*.php'

# 2) Corregir permisos
docker exec fpm_nt-suite_pro chown -R www-data:www-data \
    /var/www/html/storage /var/www/html/bootstrap/cache
docker exec fpm_nt-suite_pro chmod -R 775 \
    /var/www/html/storage /var/www/html/bootstrap/cache

# 3) Limpiar todas las cachés
docker exec fpm_nt-suite_pro php /var/www/html/artisan view:clear
docker exec fpm_nt-suite_pro php /var/www/html/artisan config:clear
docker exec fpm_nt-suite_pro php /var/www/html/artisan cache:clear
docker exec fpm_nt-suite_pro php /var/www/html/artisan route:clear

# 4) Regenerar autoload
docker exec fpm_nt-suite_pro composer dump-autoload -o --working-dir=/var/www/html
```

## Diagnóstico (si el 500 persiste)

Leer el log real de Laravel:

```bash
# Sin Docker
tail -100 storage/logs/laravel.log

# Con Docker (ruta típica /var/www/html)
docker exec fpm_nt-suite_pro tail -100 /var/www/html/storage/logs/laravel.log
```

Si no sabes dónde está el log:
```bash
docker exec fpm_nt-suite_pro find /var/www -name "laravel.log" 2>/dev/null
```

## Checklist rápido

- [ ] `.gitignore` raíz incluye `/storage/framework/views/*` + excepción de `.gitignore`
- [ ] Existe `storage/framework/views/.gitignore` con `*` y `!.gitignore`
- [ ] `git ls-files storage/framework/views/` devuelve **solo** `.gitignore`
- [ ] En producción, la carpeta `storage/framework/views/` es escribible por `www-data`
- [ ] `php artisan view:clear` ejecutado tras cada deploy

## ¿Por qué esto es lo correcto?

`storage/framework/views/*.php` es **caché derivado**, igual que `vendor/` o `node_modules/`:

- Se regenera solo en tiempo de ejecución.
- Depende del entorno (rutas absolutas, versión de PHP).
- No debe viajar por git.

La convención oficial de Laravel (ver `.gitignore` del skeleton `laravel/laravel`) ya excluye esta carpeta por defecto. Si aparece versionada, es un commit accidental del pasado que hay que limpiar.
