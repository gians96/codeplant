# Un cambio en código/Blade no se refleja en producción (stack de cachés + OPcache)

## Síntoma

Editaste o arreglaste un archivo (`.blade.php`, controlador, modelo) y tras desplegar:

- El cambio **no aparece**: sigue el label/precio/comportamiento viejo, o el PDF sale igual que antes.
- O peor: aparece un **HTTP 500** porque el código nuevo y el caché viejo dejaron de coincidir
  (`Undefined variable`, `Undefined property`, `Class not found`, etc.).

### Caso real (2026-07-21) — el que originó esta guía

Al editar un comprobante en `/documents/10/edit` saltaba un 500:

```
Undefined property: stdClass::$guarantee_fund
(View: .../app/CoreFacturalo/Templates/pdf/marca_de_agua/invoice_a4.blade.php)
```

Hay **dos problemas encadenados** — es importante no confundirlos:

1. **El bug de fondo (código).** El campo `guarantee_fund` (fondo de garantía) se agregó el
   `2026-06-04` (migración `tenant_add_enabled_guarantee_fund_to_configurations`). Los comprobantes
   creados antes —o guardados con `enabled_guarantee_fund` apagado— **no tienen esa clave** en el
   JSON de detracción/retención, que el modelo decodifica a `stdClass`. Las plantillas la accedían
   directo (`$value_ob->guarantee_fund`), así que al regenerar el PDF en `createPdf()` durante el
   `update()` reventaba con "Undefined property".
   **Fix:** `$value_ob->guarantee_fund ?? 0` en las 4 posiciones de `invoice_a4.blade.php`
   (plantillas `default` y `marca_de_agua`). Commit pro-8 `b136f31f`.

2. **Por qué "no se actualizaba" aunque cambies el `.blade.php` (cachés).** Aunque corrijas el
   fuente, el cambio **no se ve en prod** hasta limpiar la vista compilada **y** reiniciar PHP
   (OPcache). Ese es el verdadero "no se actualiza", y aplica a *cualquier* cambio de código, no
   solo a este bug.

## Causa raíz — hay 4 capas de caché, no una

En este stack (Laravel + Docker + OPcache con `validate_timestamps=0`) un cambio de código atraviesa
varias capas. Si no limpias la correcta, sigues sirviendo código/datos viejos:

| Capa | Qué cachea | Se ve como | Cómo se limpia |
|------|-----------|-----------|----------------|
| **Vistas compiladas** `storage/framework/views/*.php` | El Blade compilado a PHP | PDF/labels viejos; `Undefined variable/property` tras cambiar un `.blade.php` | `php artisan view:clear` |
| **OPcache** (PHP) | El bytecode de **cada** `.php` (incluida la vista Blade compilada) | **La más traicionera:** aunque borres el archivo o hagas `view:clear`, el proceso PHP sigue sirviendo el bytecode que cargó al arrancar | **Reiniciar los contenedores PHP** (`docker restart` de fpm + supervisor + scheduling) |
| **Cache de app** (`CACHE_DRIVER=file`) | Datos cacheados por la app (listados de items/documents, etc.) | Precios/datos viejos hasta ~10 min ("no se guarda el precio") | `php artisan cache:clear` |
| **config / route** | `config/*.php` y rutas compiladas | Cambios de config o rutas no aplican | `php artisan config:clear` / `route:clear` |

### La trampa del OPcache (`validate_timestamps=0`)

En prod/on-prem, OPcache corre con `opcache.validate_timestamps=0` (ver `scripts/onprem-setup.sh`).
Eso significa: **cada proceso PHP sirve el bytecode que cargó al arrancar, para siempre**, aunque el
archivo en disco cambie. Consecuencias:

- `view:clear` borra la vista compilada y Laravel la regenera en el próximo request… pero OPcache
  sigue sirviendo el bytecode viejo de **esa misma ruta** hasta reiniciar FPM. Por eso `view:clear`
  **solo** no basta en prod.
- Hay que reiniciar los **TRES** contenedores PHP: `fpm`, `supervisor` y `scheduling` (no solo fpm),
  porque los tres cargan bytecode en RAM.
- Y reiniciar **nginx**: resuelve `fastcgi_pass` por nombre una sola vez al arrancar; si fpm fue
  recreado con otra IP, nginx sigue mandando tráfico a la IP vieja (que puede pertenecer a otro
  contenedor con código viejo en RAM). Ver incidente ceos 2026-07-20.

> **Nota sobre la cache de app:** en prod `CACHE_DRIVER=file`. `CacheHelper::flush()` era **no-op**
> con el driver file (emulaba tags que `file` no soporta) → los listados quedaban con datos viejos
> aunque la BD sí guardara. Arreglado en pro-8 commit `45c7cca0`. Aun así conviene `cache:clear` en
> cada deploy.

> **En local es distinto:** `local-setup.sh` usa `opcache.validate_timestamps=1`, así que OPcache
> revalida por mtime y Blade recompila cuando el fuente cambia. Por eso en local casi nunca hace
> falta `view:clear` + restart; en prod **siempre**.

## Solución — receta de despliegue (el orden importa)

Dentro del contenedor FPM (`fpm_<dominio>`):

```bash
docker exec ${FPM} sh -c "cd /var/www/html && CACHE_DRIVER=file php artisan config:clear"
docker exec ${FPM} sh -c "cd /var/www/html && CACHE_DRIVER=file php artisan route:clear"
# view:clear OBLIGATORIO: sin él quedan vistas compiladas viejas -> PDFs/labels antiguos
# y 'Undefined variable/property' cuando el código nuevo ya cambió.
docker exec ${FPM} sh -c "cd /var/www/html && CACHE_DRIVER=file php artisan view:clear"
docker exec ${FPM} sh -c "cd /var/www/html && CACHE_DRIVER=file php artisan cache:clear"

# OPcache: reiniciar los TRES contenedores PHP + nginx (sin esto se sigue sirviendo bytecode viejo)
docker exec ${FPM} sh -c "CACHE_DRIVER=file php artisan queue:restart"
docker restart ${FPM} ${SUPERVISOR} ${SCHEDULING}
docker restart ${NGINX}
```

> **NO usar `route:cache`** — hyn/multi-tenant necesita rutas dinámicas; `route:cache` las rompe.

### Hotfix rápido (solo cambié un Blade, sin re-desplegar todo)

```bash
docker exec fpm_<dominio> sh -c "cd /var/www/html && php artisan view:clear"
docker restart fpm_<dominio> supervisor_<dominio> scheduling_<dominio>
```

## Estado de los scripts de deploy (verificado 2026-07-21)

Los scripts de **producción / on-prem ya están actualizados** con `view:clear` + restart de los
contenedores PHP. El único con hueco es `local-update.sh`, y en local el impacto es mínimo
(OPcache revalida por mtime).

| Script | `view:clear` | restart PHP (OPcache) | Estado |
|--------|:-----------:|:---------------------:|--------|
| `pro-8/scripts/prod-update.sh` | ✅ (L456) | ✅ fpm+supervisor+scheduling + nginx (L477-478) | OK |
| `pro-8/scripts/onprem-update.sh` | ✅ loop L109 | ✅ (maneja OPcache, L121) | OK |
| `codeplant install/onpremise/update.sh` | ✅ delega en `onprem-update.sh` | ✅ | OK (wrapper multi-dominio) |
| `codeplant install/linux/update.sh` | ✅ loop L441 | ✅ | OK |
| `codeplant install/windows-server/03-update.sh` | ✅ loop L421 | ✅ | OK |
| `pro-8/scripts/local-update.sh` | ⚠️ **falta** | ⚠️ solo supervisor (L224) | Bajo riesgo — local usa `validate_timestamps=1` |

> Pendiente menor: agregar `view:clear` a `local-update.sh` por consistencia (opcional; en local
> Blade recompila por mtime).

## Checklist "mi cambio no aparece en prod"

- [ ] ¿Corrí `view:clear` tras cambiar un `.blade.php`?
- [ ] ¿Reinicié fpm **+ supervisor + scheduling** (no solo fpm) por OPcache?
- [ ] ¿Reinicié nginx (puede apuntar a IP vieja de fpm)?
- [ ] ¿`cache:clear` si eran datos/listados (no código)?
- [ ] ¿`config:clear` / `route:clear` si toqué config o rutas?
- [ ] ¿Qué dice el log real?
      `docker exec fpm_<dominio> tail -100 /var/www/html/storage/logs/laravel.log`

## Lección para el futuro (al tocar plantillas PDF o campos opcionales)

- Todo campo agregado por migración reciente es **opcional** en registros viejos. En Blade/PDF
  accédelo defensivo: `$obj->campo ?? <default>` (igual que hace el backend en `DocumentInput`,
  que usa `isset(...) ? ... : 0`). Nunca asumas que un JSON viejo tiene claves nuevas.
- Un fix de plantilla en prod **no se ve** hasta `view:clear` + restart de los contenedores PHP.

## Relacionado

- [Error 500 tras `git pull` — vistas compiladas versionadas en `storage/framework/views/`](git-pull-500-storage-framework-views.md)
- [`ceos-facturacion.com`: Cloudflare 522, FortiGate, SSL/proxy y Laravel 500 (OPcache sirviendo código viejo)](ceos-facturacion-cloudflare-fortigate-laravel-500.md)
