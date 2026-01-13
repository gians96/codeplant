# 🔧 Solución de Problemas - Facturador Pro

## 📋 Índice
- [Problema de Scheduling con Alto CPU](#problema-de-scheduling-con-alto-cpu)
- [Monitoreo con Telescope](#monitoreo-con-telescope)
- [Análisis de Tráfico y Requests](#análisis-de-tráfico-y-requests)
- [Herramientas de Monitoreo](#herramientas-de-monitoreo)

---

## 🚨 Problema de Scheduling con Alto CPU

### Síntoma
El contenedor `scheduling_nt-suite_pro` consume 90-95% de CPU constantemente.

### Causa
El crontab dentro del contenedor tenía **dos tareas duplicadas** ejecutándose cada minuto:
```cron
* * * * * php artisan schedule:run
* * * * * php artisan tenancy:run schedule:run  ← DUPLICADO (ejecuta en 48 tenants)
```

Esto causaba que el sistema ejecutara las tareas programadas **48 + (48 × 48) = 2,352 ejecuciones** por minuto.

### ✅ Solución Aplicada

1. **Editar el crontab del contenedor:**
```bash
docker exec -it scheduling_nt-suite_pro crontab -e
```

2. **Eliminar la segunda línea**, dejando SOLO:
```cron
* * * * * /usr/local/bin/php /var/www/html/artisan schedule:run >> /var/log/cron.log 2>&1
```

3. **Reiniciar el contenedor:**
```bash
docker restart scheduling_nt-suite_pro
```

### Resultado
- **Antes:** 94-95% CPU
- **Después:** 0.01% CPU ✅

### Verificación
```bash
# Ver el crontab actual
docker exec -it scheduling_nt-suite_pro crontab -l

# Monitorear CPU
docker stats --no-stream | grep scheduling
```

---

## 📊 Monitoreo con Telescope

### ¿Qué es Telescope?
Laravel Telescope es una herramienta de debugging que permite monitorear en tiempo real:
- Requests HTTP (endpoints, duración, memoria)
- Queries de base de datos
- Jobs en cola
- Excepciones y logs
- Cache hits/misses
- Emails enviados

### Instalación (ya instalado en tu sistema)
```bash
composer require laravel/telescope --dev
php artisan telescope:install
php artisan migrate
```

### Acceso
```
https://nt-suite.pro/telescope
```

### Pausar Telescope (reduce carga)
```bash
docker exec -it fpm_nt-suite_pro php artisan telescope:pause
```

### Reactivar Telescope
```bash
docker exec -it fpm_nt-suite_pro php artisan telescope:continue
```

### Usos principales

#### 1. Ver requests más lentos
- Ir a: `/telescope/requests`
- Ordenar por columna **Duration**
- Identificar endpoints problemáticos

#### 2. Ver queries pesadas
- Ir a: `/telescope/queries`
- Ordenar por **Duration** o **Rows**
- Optimizar las queries lentas

#### 3. Ver errores recientes
- Ir a: `/telescope/exceptions`
- Ver stack traces completos

---

## 🔍 Análisis de Tráfico y Requests

### Problema
Los comandos de análisis de logs con `awk` son muy lentos porque procesan archivos grandes línea por línea.

### ❌ Comandos Lentos (NO usar)
```bash
# Estos se demoran mucho con logs grandes
docker exec nginx_nt-suite_pro tail -1000 /var/log/nginx/access.log | awk '{print $7}' | sort | uniq -c | sort -rn | head -20
```

### ✅ Soluciones Rápidas

#### Opción 1: Script de Monitoreo Optimizado
```bash
# Crear script rápido (CORREGIDO para logs en stdout)
cat > /var/scripts/analyze-traffic.sh << 'EOF'
#!/bin/bash
echo "=== TOP 10 ENDPOINTS MÁS LLAMADOS ==="
docker logs --tail 500 nginx_nt-suite_pro 2>&1 | grep -o '"[A-Z]* [^"]*' | cut -d' ' -f2 | sort | uniq -c | sort -rn | head -10

echo ""
echo "=== TOP 5 IPs CON MÁS TRÁFICO ==="
docker logs --tail 500 nginx_nt-suite_pro 2>&1 | awk '{print $1}' | sort | uniq -c | sort -rn | head -5

echo ""
echo "=== REQUESTS POR CÓDIGO DE ESTADO ==="
docker logs --tail 500 nginx_nt-suite_pro 2>&1 | awk '{print $9}' | sort | uniq -c | sort -rn

echo ""
echo "=== ÚLTIMAS 10 REQUESTS ==="
docker logs --tail 10 nginx_nt-suite_pro 2>&1
EOF

chmod +x /var/scripts/analyze-traffic.sh
```

**Uso:**
```bash
/var/scripts/analyze-traffic.sh
```

#### Opción 2: Monitoreo en Tiempo Real (más eficiente)
```bash
# Ver requests en vivo (LOGS EN STDOUT)
docker logs -f nginx_nt-suite_pro 2>&1

# Ver solo errores 500
docker logs -f nginx_nt-suite_pro 2>&1 | grep " 5[0-9][0-9] "

# Ver requests lentas (más de 1 segundo)
docker logs -f nginx_nt-suite_pro 2>&1 | awk '$NF > 1.0'
```

#### Opción 3: Usar GoAccess (Análisis visual rápido)
```bash
# Instalar GoAccess
apt-get install goaccess -y

# Analizar logs desde docker logs (CORREGIDO)
docker logs --tail 10000 nginx_nt-suite_pro 2>&1 | goaccess --log-format=COMBINED -o /tmp/report.html

# Ver el reporte
# Copiar /tmp/report.html y abrirlo en navegador
```

#### Opción 4: Rotar logs periódicamente
Si los logs son muy grandes, implementar rotación:

```bash
# Crear configuración de logrotate
cat > /etc/logrotate.d/nginx-docker << 'EOF'
/var/log/nginx/*.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 0640 nginx adm
    sharedscripts
}
EOF
```

---

## 🛠️ Herramientas de Monitoreo

### 1. Sysstat - ¿Para qué sirve?

**Sysstat** es un conjunto de utilidades para monitorear el rendimiento del sistema Linux.

#### Herramientas incluidas:

- **`iostat`**: Monitorea CPU y disco I/O
- **`mpstat`**: Estadísticas por procesador
- **`pidstat`**: Monitorea procesos específicos
- **`sar`**: Recolecta y reporta actividad del sistema
- **`sadf`**: Visualiza datos en diferentes formatos

#### Uso en tu servidor:

```bash
# Ver CPU por core
mpstat -P ALL 1

# Ver procesos que más consumen
pidstat 1 5

# Monitorear I/O de disco
iostat -x 2

# Ver histórico del sistema (si está habilitado)
sar -u 1 10  # CPU usage
sar -r 1 10  # Memoria
sar -n DEV 1 10  # Red
```

#### ¿Por qué se instaló?
Se instaló para tener herramientas de diagnóstico cuando el servidor estaba con problemas de CPU. Permite identificar cuellos de botella en tiempo real.

### 2. Script de Monitoreo Completo

Ya tienes el script `/var/scripts/monitor-performance.sh` que muestra:
- Docker stats
- Queries MySQL lentas
- Estado de workers Supervisor
- Logs recientes de Laravel

**Uso:**
```bash
/var/scripts/monitor-performance.sh
```

### 3. Monitoreo Continuo con Watch

```bash
# Monitorear docker stats cada 2 segundos
watch -n 2 'docker stats --no-stream'

# Monitorear conexiones MySQL
watch -n 5 'docker exec mariadb_nt-suite_pro mysql -uroot -p[PASSWORD] -e "SHOW PROCESSLIST\G" | grep -E "Id:|User:|Command:|Time:|State:"'
```

### 4. Supervisor - Gestión de Workers de Cola

#### ¿Qué es Supervisor?
Supervisor gestiona los workers de Laravel Queue que procesan trabajos en segundo plano como:
- Envío de emails
- Generación de PDFs
- Consultas a SUNAT
- Procesamiento de facturas
- Notificaciones

#### Configuración Actual

**Ver configuración:**
```bash
docker exec supervisor_nt-suite_pro cat /etc/supervisor/conf.d/laravel-worker.conf
```

**Configuración típica:**
```ini
[program:laravel-worker]
process_name=%(program_name)s_%(process_num)02d
command=php /var/www/html/artisan queue:work --sleep=3 --tries=3 --max-time=3600
autostart=true
autorestart=true
stopasgroup=true
killasgroup=true
user=www-data
numprocs=4
redirect_stderr=true
stdout_logfile=/var/www/html/storage/logs/worker.log
stopwaitsecs=3600
```

**Parámetros importantes:**
- `numprocs=4` → 4 workers en paralelo (ajustable según carga)
- `--sleep=3` → Espera 3 segundos entre jobs
- `--tries=3` → Reintenta 3 veces si falla
- `--max-time=3600` → Worker se reinicia cada hora (previene memory leaks)

#### Comandos Útiles de Supervisor

```bash
# Ver estado de todos los workers
docker exec supervisor_nt-suite_pro supervisorctl status

# Reiniciar todos los workers
docker exec supervisor_nt-suite_pro supervisorctl restart all

# Detener workers
docker exec supervisor_nt-suite_pro supervisorctl stop all

# Iniciar workers
docker exec supervisor_nt-suite_pro supervisorctl start all

# Ver logs de un worker específico
docker exec supervisor_nt-suite_pro supervisorctl tail laravel-worker:laravel-worker_00

# Recargar configuración
docker exec supervisor_nt-suite_pro supervisorctl reread
docker exec supervisor_nt-suite_pro supervisorctl update
```

#### Ver Trabajos en Cola

```bash
# Ver trabajos pendientes en Redis
docker exec redis_nt-suite_pro redis-cli LLEN queues:default

# Ver todas las colas
docker exec redis_nt-suite_pro redis-cli KEYS queues:*

# Limpiar cola (usar con precaución)
docker exec redis_nt-suite_pro redis-cli DEL queues:default
```

#### Monitorear Workers con Horizon (Alternativa)

Si usas Laravel Horizon en lugar de Supervisor básico:

```bash
# Instalar Horizon
composer require laravel/horizon
php artisan horizon:install

# Acceder al dashboard
https://nt-suite.pro/horizon
```

**Ventajas de Horizon:**
- Dashboard visual de colas
- Estadísticas en tiempo real
- Gestión de prioridades
- Métricas de rendimiento
- Balance automático de workers

#### Optimizar Workers según Carga

**CPU actual: 0.02% - Workers muy ociosos**

Si hay muchos jobs pendientes:
```bash
# Aumentar workers (editar configuración)
numprocs=8  # De 4 a 8
```

Si hay pocos jobs:
```bash
# Reducir workers
numprocs=2  # De 4 a 2
```

**Después de cambios:**
```bash
docker exec supervisor_nt-suite_pro supervisorctl reread
docker exec supervisor_nt-suite_pro supervisorctl update
docker exec supervisor_nt-suite_pro supervisorctl restart all
```

#### Troubleshooting de Workers

**Workers no procesan jobs:**
```bash
# 1. Verificar que workers estén corriendo
docker exec supervisor_nt-suite_pro supervisorctl status

# 2. Ver logs de errores
docker exec supervisor_nt-suite_pro tail -f /var/www/html/storage/logs/worker.log

# 3. Verificar conexión a Redis
docker exec fpm_nt-suite_pro php artisan queue:monitor

# 4. Procesar 1 job manualmente para debug
docker exec fpm_nt-suite_pro php artisan queue:work --once
```

**Workers consumen mucha memoria:**
```bash
# Reducir max-time para reiniciar más seguido
--max-time=1800  # 30 minutos en lugar de 1 hora

# O reducir max-jobs
--max-jobs=1000  # Reiniciar después de 1000 jobs
```

---

## 📈 Métricas Importantes a Monitorear

### CPU
- **Scheduling**: Debe estar < 5% (Actual: 0.01% ✅)
- **FPM**: 20-50% es normal, > 100% indica alto tráfico (Actual: 36% ✅)
- **MariaDB**: 10-30% normal, > 50% revisar queries (Actual: 6.96% ✅)
- **Supervisor**: < 10% (Actual: 0.02% ✅)

### Memoria
- **FPM**: 100-300MB normal (Actual: 117MB ✅)
- **MariaDB**: 500MB-2GB según carga (Actual: 956MB ✅)
- **Redis**: 50-100MB normal (Actual: 27MB - SUBUTILIZADO ⚠️)
- **Supervisor**: 150-300MB con workers activos (Actual: 213MB ✅)
- **Disponible**: 13.8GB de 15.25GB libres (90% disponible)

### Señales de Alerta
- CPU scheduling > 10%
- FPM > 200% sostenido
- MariaDB > 80% sostenido
- Memoria swap en uso
- Conexiones MySQL > 100

---

## 🔄 Tareas de Optimización Pendientes

### ✅ Completado
- [x] Corregir scheduling duplicado (95% → 0.01% CPU)
- [x] Instalar herramientas de monitoreo (Telescope, sysstat)
- [x] Crear scripts de análisis de tráfico
- [x] Documentar soluciones

### 🎯 Prioridad Alta (Siguientes Pasos)

#### 1. Implementar Cache de Redis para Endpoints Frecuentes ⭐
**Estado actual:** Redis subutilizado (27MB de RAM, 0.30% CPU)  
**Problema:** `/pos/tables` retorna 234KB y se llama 75+ veces  
**Oportunidad:** Hay 13.8GB de RAM disponible

**Implementación:**
```php
// En el controlador de /pos/tables
public function getTables(Request $request) {
    $tenantId = tenant()->id;
    
    return Cache::remember("pos:tables:{$tenantId}", 300, function() {
        return Table::with(['orders.items', 'currentOrder'])->get();
    });
}

// Invalidar cache al crear/actualizar órdenes
Cache::forget("pos:tables:{$tenantId}");
```

**Endpoints a cachear:**
- `/pos/tables` - 75 requests (234KB cada una) → Cachear 5 minutos
- `/pos/items` - 10 requests → Cachear 10 minutos
- `/services/exchange/{date}` - 12 requests → Cachear 1 hora
- `/pos/payment_tables` - 10 requests → Cachear 5 minutos

**Impacto esperado:**
- Reducir CPU de FPM: 36% → 15-20%
- Reducir queries a MySQL: ~50%
- Tiempo de respuesta: <50ms (vs 200-300ms actual)

#### 2. Corregir Bug de Request `/null`
**Problema:** 8 requests a `/null` retornan 404  
**Causa:** Probablemente un endpoint undefined en JavaScript  
**Acción:** Revisar código frontend que hace llamadas AJAX

```bash
# Buscar en el código
grep -r "axios.get.*null" resources/js/
grep -r "fetch.*null" resources/js/
```

#### 3. Optimizar Queries N+1 con Telescope
**Acción:** Usar Telescope para identificar queries repetitivas

```bash
# Acceder a Telescope
https://nt-suite.pro/telescope/queries
# Filtrar por: Duration > 100ms o Rows > 1000
```

**Corrección típica:**
```php
// ❌ Malo (N+1)
$documents = Document::all();
foreach($documents as $doc) {
    echo $doc->customer->name; // Query por cada documento
}

// ✅ Bueno
$documents = Document::with('customer')->get();
foreach($documents as $doc) {
    echo $doc->customer->name; // Sin queries adicionales
}
```

### 🚀 Prioridad Media

#### 4. Migrar Scheduling a Laravel Queues
**Beneficio:** Escalabilidad y control de recursos

```php
// En lugar de cron cada minuto:
CheckSunatDocumentStatus::dispatch($documentId, $tenantId)
    ->delay(now()->addSeconds(30))
    ->onQueue('sunat');
```

#### 5. Implementar Rate Limiting
**Prevenir abusos en APIs públicas:**

```php
// En routes/api.php
Route::middleware('throttle:60,1')->group(function () {
    Route::post('/api/documents', 'DocumentController@store');
});
```

#### 6. Configurar OPcache de PHP
**Optimizar rendimiento de PHP-FPM:**

```ini
; En php.ini del contenedor FPM
opcache.enable=1
opcache.memory_consumption=256
opcache.interned_strings_buffer=16
opcache.max_accelerated_files=10000
opcache.validate_timestamps=0
```

### 📊 Prioridad Baja

#### 7. Configurar MySQL Query Cache
```sql
SET GLOBAL query_cache_size = 268435456; -- 256MB
SET GLOBAL query_cache_type = 1;
```

#### 8. Implementar CDN para Assets Estáticos
- Usar CloudFlare o similar para CSS/JS/imágenes
- Reducir carga en nginx

#### 9. Configurar Compresión Gzip en Nginx
```nginx
gzip on;
gzip_vary on;
gzip_types text/plain text/css application/json application/javascript;
```

---

## 📞 Comandos Útiles de Diagnóstico Rápido

```bash
# CPU por contenedor
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"

# Queries MySQL activas
docker exec mariadb_nt-suite_pro mysql -uroot -p[PASSWORD] -e "SHOW PROCESSLIST;"

# Logs en vivo de Laravel
docker exec fpm_nt-suite_pro tail -f storage/logs/laravel-$(date +%Y-%m-%d).log

# Workers de Supervisor
docker exec supervisor_nt-suite_pro supervisorctl status

# Reiniciar todo (última opción)
docker-compose restart
```

---

## 📝 Historial de Cambios

**13 de enero de 2026 - 20:30 hrs**
- ✅ **RESUELTO:** Scheduling duplicado (95% → 0.01% CPU)
- ✅ **RESUELTO:** FPM alto CPU (155% → 36% CPU)
- ✅ Corregido script de análisis de logs (usar `docker logs` en lugar de archivos)
- ✅ Instalado Telescope para monitoreo de requests
- ✅ Instalado sysstat para diagnósticos del sistema
- ✅ Creados scripts de análisis de tráfico optimizados
- ✅ Documentado todas las soluciones en TROUBLESHOOTING.md
- 📊 **Métricas finales:** Scheduling 0.01%, FPM 36%, MariaDB 6.96%, RAM disponible 90%
- 🎯 **Siguiente paso:** Implementar Redis cache para endpoints frecuentes

---

## 🆘 Soporte

Si el problema persiste:
1. Revisar Telescope: `https://nt-suite.pro/telescope`
2. Ejecutar: `/var/scripts/monitor-performance.sh`
3. Revisar logs: `/var/scripts/analyze-traffic.sh`
4. Documentar métricas y contactar soporte técnico
