# Reportes en `IN_PROCESS` en bandeja de descargas

## Sintomas

- En `https://<dominio>/reports/general-items` se solicita un reporte.
- En `https://<dominio>/reports/download-tray` el registro queda en estado `IN_PROCESS`.
- No aparece el boton `Descargar archivo`.
- Los reportes antiguos si muestran `FINISHED` y permiten descargar.

Caso validado en `cmecocasma.nt-suite.pro`.

## Causa probable

Los reportes dinamicos de `reports/general-items` no se generan durante la
peticion HTTP. Laravel crea un registro en `download_tray` y despacha jobs a
Redis para que los procese Supervisor.

El archivo aparece solo cuando el job termina y actualiza la bandeja a
`FINISHED`. Si los workers no estan procesando, o quedaron en un estado malo,
los registros nuevos permanecen en `IN_PROCESS`.

Para reportes PDF grandes con separacion por chunks, tambien se usan batches de
Laravel. Por eso deben existir las tablas `job_batches` y `job_batching_trays`.

## Diagnostico rapido

Ver contenedores:

```bash
docker ps
```

En una instalacion tipo `nt-suite.pro`, los contenedores esperados son:

```text
fpm_nt-suite_pro
supervisor_nt-suite_pro
redis_nt-suite_pro
mariadb_nt-suite_pro
nginx_nt-suite_pro
scheduling_nt-suite_pro
```

Verificar migraciones de batches:

```bash
docker exec fpm_nt-suite_pro php artisan migrate:status --path=database/migrations/2025_11_11_151513_create_job_batches_table.php
docker exec fpm_nt-suite_pro php artisan migrate:status --path=database/migrations/2025_11_11_171612_create_jobs_batching_tray.php
```

Salida esperada:

```text
2025_11_11_151513_create_job_batches_table ........ [N] Ran
2025_11_11_171612_create_jobs_batching_tray ....... [N] Ran
```

Verificar workers y Redis:

```bash
docker exec supervisor_nt-suite_pro supervisorctl status
docker exec redis_nt-suite_pro redis-cli ping
docker exec redis_nt-suite_pro redis-cli llen queues:default
```

Ver logs relevantes:

```bash
docker exec supervisor_nt-suite_pro tail -n 200 /var/www/html/storage/logs/supervisor.log
docker exec fpm_nt-suite_pro ls -lt /var/www/html/storage/logs | head
```

## Solucion aplicada

Si las migraciones estan en `Ran`, reiniciar Supervisor dentro del contenedor:

```bash
docker exec supervisor_nt-suite_pro sh -c "service supervisor start || true; supervisorctl reread; supervisorctl update; supervisorctl restart all"
```

Salida esperada:

```text
Starting supervisor: No config updates to processes
laravel-worker:laravel-worker_00: started
laravel-worker:laravel-worker_01: started
laravel-worker:laravel-worker_02: started
laravel-worker:laravel-worker_03: started
```

Confirmar estado:

```bash
docker exec supervisor_nt-suite_pro supervisorctl status
```

Debe mostrar los `laravel-worker` en `RUNNING`.

## Validacion funcional

1. Entrar a `https://<dominio>/reports/general-items`.
2. Generar un reporte nuevo, primero con rango pequeno.
3. Para PDF grande, seleccionar `Registros: 500`.
4. Abrir `https://<dominio>/reports/download-tray`.
5. Confirmar que el registro nuevo pasa a `FINISHED` y aparece `Descargar archivo`.

Los registros antiguos que ya quedaron en `IN_PROCESS` pueden no recuperarse si
el job original fallo o ya no existe en Redis. En ese caso, generar un reporte
nuevo despues de reiniciar los workers.

## Si vuelve a fallar

Revisar si hay jobs atorados o reservados:

```bash
docker exec redis_nt-suite_pro redis-cli llen queues:default
docker exec redis_nt-suite_pro redis-cli zcard queues:default:reserved
docker exec redis_nt-suite_pro redis-cli zcard queues:default:delayed
```

Si las migraciones de batches no estan aplicadas:

```bash
docker exec fpm_nt-suite_pro php artisan migrate --force
docker exec supervisor_nt-suite_pro supervisorctl restart all
```

Si `supervisorctl status` no muestra workers `RUNNING`, repetir el reinicio de
Supervisor y revisar `storage/logs/supervisor.log`.
