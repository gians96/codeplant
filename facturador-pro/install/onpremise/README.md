# Facturador Pro-8 — Instalacion ON-PREMISE (multi-dominio)

Guia completa para desplegar Pro-8 multi-tenant en un servidor **local**
(VMware ESXi, bare-metal o VPS) que funciona en **dos fases** sin migrar base de
datos, y permite instalar **varios dominios** en el mismo servidor sin que
choquen entre si.

> **Contexto tecnico y arquitectura del cliente:** lee
> [`ARQUITECTURA-Y-CONTEXTO.md`](ARQUITECTURA-Y-CONTEXTO.md) (diagramas ESXi +
> FortiGate, hyn/multi-tenant, split-horizon, decisiones).
>
> **Configuracion de PCs internas:** lee
> [`configurar-pcs-host.md`](configurar-pcs-host.md).

---

## Indice

1. [Que resuelve esta instalacion](#1-que-resuelve-esta-instalacion)
2. [Caso de referencia: Consurtrading](#2-caso-de-referencia-consurtrading)
3. [Como funciona APP_URL_BASE y los tenants](#3-como-funciona-app_url_base-y-los-tenants)
4. [Requisitos del servidor](#4-requisitos-del-servidor)
5. [Estructura en disco despues de instalar](#5-estructura-en-disco-despues-de-instalar)
6. [Scripts disponibles](#6-scripts-disponibles)
7. [Fase 1 — Instalacion LAN (HTTP)](#7-fase-1--instalacion-lan-http)
8. [Multi-dominio en el mismo servidor](#8-multi-dominio-en-el-mismo-servidor)
9. [Configuracion de PCs (archivo hosts)](#9-configuracion-de-pcs-archivo-hosts)
10. [SSL wildcard: emitir o renovar (ssl.sh)](#10-ssl-wildcard-emitir-o-renovar-sslsh)
11. [Fase 2 — Checklist del admin de red (FortiGate)](#11-fase-2--checklist-del-admin-de-red-fortigate)
12. [Actualizacion del codigo](#12-actualizacion-del-codigo)
13. [Variables .env generadas](#13-variables-env-generadas)
14. [Comandos utiles de operacion](#14-comandos-utiles-de-operacion)
15. [Troubleshooting](#15-troubleshooting)
16. [Datos que NO se deben borrar](#16-datos-que-no-se-deben-borrar)

---

## 1. Que resuelve esta instalacion

| Situacion | Solucion |
|-----------|----------|
| Servidor on-premise sin IP publica (FortiGate pendiente) | Fase 1: acceso por IP LAN + archivo `hosts` en cada PC |
| Multi-tenant por subdominio (`empresa1.dominio.com`) | Dominio base fijado desde el dia 1; hyn resuelve por header `Host` |
| Varios clientes/dominios en el mismo servidor | `install.sh` reutilizable; contenedores y puertos aislados por dominio |
| Misma IP publica para varios dominios | Un solo `nginx-proxy` (80/443) enruta por `VIRTUAL_HOST` |
| Pasar de LAN a internet sin migrar BD | Split-horizon: mismo `APP_URL_BASE`, cambia solo la resolucion DNS |
| Sin Cloudflare (wildcard de 2do nivel es de pago) | DNS directo en registrador + Let's Encrypt DNS-01 manual |

### Las dos fases

```text
FASE 1 (hoy)                         FASE 2 (cuando haya IP publica)
────────────────                     ────────────────────────────────
Acceso LAN: IP + hosts               + Acceso externo: DNS registrador + FortiGate NAT
HTTP (o HTTPS si ya se emitio SSL)   HTTPS puerto 443 (+ HTTP redirect)
ssl.sh OPCIONAL                      ssl.sh ejecutado
```

> **El SSL no depende de la IP publica.** El wildcard Let's Encrypt se emite con
> reto DNS-01: solo hay que crear un TXT en el DNS publico del registrador. Se
> puede tener HTTPS valido en la LAN desde la Fase 1 (las PCs acceden por el
> nombre real via hosts/DNS FortiGate). Ver [seccion 10](#10-ssl-wildcard-emitir-o-renovar-sslsh).

**No hay migracion de base de datos** entre fases porque `APP_URL_BASE` es el
dominio final desde la instalacion (ej. `fe.consurtrading.org`). Los `fqdn` de
cada empresa (`empresa1.fe.consurtrading.org`) ya quedan correctos en la tabla
`hostnames`.

---

## 2. Caso de referencia: Consurtrading

| Nombre | Uso |
|--------|-----|
| `consurtrading.org` | Web oficial (ajena a este sistema) |
| `reportes.consurtrading.org` | Subdominio de reportes (ajeno) |
| **`fe.consurtrading.org`** | **Base del facturador** — panel central de gestion |
| `empresa1.fe.consurtrading.org` | Tenant (empresa 1) |
| `empresa2.fe.consurtrading.org` | Tenant (empresa 2) |
| `ws.fe.consurtrading.org` | WebSocket / Broadcasting (Soketi) — **reservado, no crear tenant "ws"** |

El instalador es **generico**: al ejecutar `install.sh` puedes poner cualquier
dominio base (ej. `fact.otraempresa.com`) para otro cliente en el mismo servidor.

---

## 3. Como funciona APP_URL_BASE y los tenants

Pro-8 usa **hyn/multi-tenant**. El flujo es:

```text
.env
  APP_URL_BASE=fe.consurtrading.org    ← sufijo raiz (NO es la URL de cada tenant)
  APP_URL=http://${APP_URL_BASE}       ← URL del panel central

Al CREAR un cliente (tenant):
  subdominio ingresado: "empresa1"
  fqdn guardado en BD:  empresa1 + "." + APP_URL_BASE
                      = empresa1.fe.consurtrading.org

En CADA request HTTP:
  1. El navegador envia header Host: empresa1.fe.consurtrading.org
  2. hyn busca ese Host en la tabla hostnames.fqdn
  3. Si coincide → conecta la BD del tenant y carga rutas de tenant
  4. Si Host = fe.consurtrading.org → panel central (system)
```

**Por que no funciona `empresa1.192.168.1.100`:** los subdominios de una IP no
son nombres DNS validos. El header `Host` debe ser un nombre que exista en
`hostnames.fqdn`. Por eso en Fase 1 se usa el archivo `hosts` de cada PC para
resolver `empresa1.fe.consurtrading.org` → `192.168.1.100`.

**Enrutamiento automatico de empresas nuevas:** el contenedor nginx declara
`VIRTUAL_HOST="fe.consurtrading.org, *.fe.consurtrading.org, 192.168.1.100"`.
Cada tenant nuevo funciona sin tocar nginx ni reiniciar contenedores.

---

## 4. Requisitos del servidor

| Requisito | Detalle |
|-----------|---------|
| SO | Ubuntu 20.04+ / Debian 11+ (64 bits) |
| RAM | Minimo 4 GB; recomendado 8 GB+ (MariaDB buffer pool 2 GB) |
| Disco | Minimo 40 GB libres por dominio instalado |
| Red | IP LAN fija en la VM (ej. `192.168.1.100`) |
| Acceso | root o sudo |
| Puertos | 80 y 443 libres en el host (proxy compartido) |
| Puertos MySQL | Un puerto libre por dominio en rango 3001–3999 (auto-asignado) |
| Git | Acceso al repo `https://gitlab.com/gians96/pro-8.git` |

Opcional para Fase 2: `certbot` (se instala automaticamente si falta).

---

## 5. Estructura en disco despues de instalar

Ejemplo con raiz `/opt/proyectos` y un dominio `fe.consurtrading.org`:

```text
/opt/proyectos/
├── install.sh                          ← scripts de esta carpeta (copiados aqui)
├── update.sh
├── ssl.sh                              ← emite O renueva el wildcard SSL
├── set-hosts.sh / set-hosts.ps1
│
├── proxy/                              ← COMPARTIDO (una sola vez)
│   └── docker-compose.yml              ← nginx-proxy en 80/443
│
├── certs/                              ← COMPARTIDO (certificados SSL Fase 2)
│   ├── fe.consurtrading.org.crt
│   ├── fe.consurtrading.org.key
│   ├── ws.fe.consurtrading.org.crt
│   └── ws.fe.consurtrading.org.key
│
├── fe.consurtrading.org/               ← PROYECTO (uno por dominio)
│   ├── .env                            ← APP_URL_BASE, credenciales, PUSHER_*
│   ├── docker-compose.yml
│   ├── supervisor.conf
│   ├── artisan
│   ├── storage/                        ← datos de app + backups pre-update
│   ├── docker/
│   │   ├── nginx/default               ← config nginx con proxy /app (Soketi)
│   │   ├── php-fpm/
│   │   ├── mariadb/my.cnf
│   │   ├── scheduling/
│   │   └── supervisor/
│   └── scripts/
│       ├── onprem-setup.sh             ← motor de despliegue
│       ├── onprem-update.sh
│       └── list-tenant-hosts.sh
│
├── fe.consurtrading.org-onprem.txt     ← credenciales generadas (admin, MySQL, contenedores)
│
└── otro-dominio.com/                   ← segundo dominio (misma estructura)
    └── ...
```

### Contenedores por dominio

Para `fe.consurtrading.org` (puntos → guiones bajos en nombres Docker):

| Contenedor | Funcion |
|------------|---------|
| `nginx_fe_consurtrading_org` | Nginx interno de la app |
| `fpm_fe_consurtrading_org` | PHP-FPM 8.2 + Laravel |
| `mariadb_fe_consurtrading_org` | MariaDB 10.5.6 |
| `redis_fe_consurtrading_org` | Redis (colas, sesiones) |
| `soketi_fe_consurtrading_org` | WebSocket (Soketi) |
| `scheduling_fe_consurtrading_org` | Laravel scheduler (cron) |
| `supervisor_fe_consurtrading_org` | Queue workers |
| `proxy-proxy-1` (compartido) | nginx-proxy — enruta por `VIRTUAL_HOST` |

### Volumenes Docker (por dominio, NO borrar)

```text
feconsurtradingorg_mysqldata1      ← base de datos system + tenants
feconsurtradingorg_redisdata1      ← datos persistentes Redis
```

El prefijo del volumen lo genera Docker Compose con el nombre de la carpeta
del proyecto **normalizado** (elimina los puntos: `fe.consurtrading.org` →
`feconsurtradingorg`). Verificar con `docker volume ls`.

---

## 6. Scripts disponibles

### En `codeplant/facturador-pro/install/onpremise/` (bootstrap / operacion)

| Script | Cuando usarlo |
|--------|---------------|
| `install.sh` | Primera instalacion de un dominio (Fase 1). Reutilizable para agregar mas dominios. |
| `update.sh` | Actualizar codigo de un dominio ya instalado (menu selector + rama). |
| `ssl.sh` | SSL wildcard: **emite** (primera vez, activa HTTPS) o **renueva** (~90 dias) segun detecte. Menu selector de dominio. |
| `set-hosts.sh` | Configurar `/etc/hosts` en PC Linux/Mac. |
| `set-hosts.ps1` | Configurar `hosts` en PC Windows (PowerShell admin). |

### En el repo `pro-8/scripts/` (motor versionado con la app)

| Script | Invocado por | Funcion |
|--------|--------------|---------|
| `onprem-setup.sh` | `install.sh` | Genera compose + `.env`, levanta stack, migrate/seed, credenciales. |
| `onprem-update.sh` | `update.sh` | Backup, git pull, composer, migrate, recache, workers. |
| `list-tenant-hosts.sh` | `install.sh` / manual | Lista lineas `hosts` leyendo tabla `hostnames`. |

---

## 7. Fase 1 — Instalacion LAN (HTTP)

### 7.1 Descargar scripts en el servidor

```bash
mkdir -p /opt/proyectos && cd /opt/proyectos

# Scripts de instalacion y operacion
curl -O https://raw.githubusercontent.com/gians96/codeplant/master/facturador-pro/install/onpremise/install.sh
curl -O https://raw.githubusercontent.com/gians96/codeplant/master/facturador-pro/install/onpremise/update.sh
curl -O https://raw.githubusercontent.com/gians96/codeplant/master/facturador-pro/install/onpremise/ssl.sh
curl -O https://raw.githubusercontent.com/gians96/codeplant/master/facturador-pro/install/onpremise/set-hosts.sh

chmod +x *.sh
```

### 7.2 Ejecutar instalacion

```bash
sudo ./install.sh
```

### 7.3 Preguntas del instalador

| Pregunta | Default | Descripcion |
|----------|---------|-------------|
| Dominio base | *(obligatorio)* | Ej. `fe.consurtrading.org`. Se convierte en `APP_URL_BASE`. |
| IP LAN del servidor | autodetectada | IP de la VM en la red local (ej. `192.168.1.100`). |
| Numero de servicio | `# instalados + 1` | Identificador interno (afecta nombre de servicios en compose). |
| Puerto MySQL host | auto libre 3001–3999 | Puerto expuesto al host para acceso remoto a MariaDB. |
| Rama del repositorio | `master` | Rama de `pro-8` a clonar. |

Al inicio el script **lista los dominios ya instalados** en la carpeta actual.

### 7.4 Que hace install.sh (paso a paso)

1. Valida dominio (no puede empezar con `ws.`).
2. Instala Docker Engine + plugin compose (si no existe).
3. Instala `certbot` (opcional, para Fase 2).
4. Crea red Docker `proxynet` (compartida).
5. Levanta `nginx-proxy` en puertos **80 y 443** (solo la primera vez).
6. Clona `pro-8` en `./<dominio>/` (rama elegida).
7. Ejecuta `scripts/onprem-setup.sh` dentro del proyecto:
   - Genera `docker-compose.yml`, `.env`, `supervisor.conf`, Dockerfiles.
   - Levanta 7 contenedores (nginx, fpm, mariadb, redis, soketi, scheduling, supervisor).
   - `composer install`, `migrate:refresh --seed`, `config:cache`.
   - Crea usuario admin y plan "Ilimitado".
8. Imprime `docker compose ps`, credenciales y lineas para `hosts`.

### 7.5 Credenciales generadas

Archivo: `/opt/proyectos/<dominio>-onprem.txt`

Contiene:

- URL del panel central
- Email y password del administrador
- Password root de MySQL
- Puerto MySQL del host
- Nombres de contenedores

### 7.6 Acceso inmediato despues de instalar

| Recurso | URL (Fase 1) |
|---------|--------------|
| Panel central | `http://192.168.1.100` o `http://fe.consurtrading.org` *(con hosts)* |
| Crear tenants | Panel → Clientes → Nuevo (subdominio ej. `empresa1`) |
| Tenant empresa1 | `http://empresa1.fe.consurtrading.org` *(con hosts)* |

---

## 8. Multi-dominio en el mismo servidor

Cada dominio base es un **proyecto independiente con su propio gestor de
tenants**. Ejemplo objetivo en el servidor de Consurtrading:

```text
fe.consurtrading.org                 ← BASE proyecto 1 (gestor de tenants)
  empresa1.fe.consurtrading.org      ←   tenant
  empresa2.fe.consurtrading.org      ←   tenant

ntsuite.consurtrading.org            ← BASE proyecto 2 (gestor de tenants)
  empresa1.ntsuite.consurtrading.org ←   tenant
  empresa2.ntsuite.consurtrading.org ←   tenant
```

Para instalar el **segundo dominio** basta re-ejecutar el instalador:

```bash
cd /opt/proyectos
sudo ./install.sh
# Dominio: ntsuite.consurtrading.org
# El script asigna automaticamente otro puerto MySQL libre (3002, ...)
```

Cada dominio base necesita su **propio cert wildcard** (`sudo ./ssl.sh` una vez
por dominio) y su **propia zona DNS** en el FortiGate (seccion 11.3). El
VIP/NAT 80/443 es **uno solo** para todos.

### Por que no chocan

| Recurso | Aislamiento |
|---------|-------------|
| Codigo + `.env` | Carpeta propia `./<dominio>/` |
| Contenedores | Nombre `nginx_<dom>`, `fpm_<dom>`, etc. |
| Base de datos | Volumen `mysqldata` propio |
| Redis | Volumen `redisdata` propio |
| Puerto MySQL host | Distinto por dominio (3001, 3002, ...) |
| Proxy HTTP/HTTPS | **Compartido** — enruta por `VIRTUAL_HOST` |
| IP publica | **Compartida** — FortiGate NAT 80/443 al mismo servidor |

```text
                    ┌─────────────────────────────────┐
Internet / LAN ───► │  nginx-proxy (:80 / :443)       │
                    │  enruta por VIRTUAL_HOST        │
                    └──────────┬──────────────────────┘
                               │
              ┌────────────────┼─────────────────────┐
              ▼                ▼                     ▼
    fe.consurtrading.org   ntsuite.consurtrading.org   cualquier-dominio.com
    (stack Docker propio)  (stack propio)              (stack propio)
```

> El instalador es **generico**: el dominio base puede ser **cualquiera**
> (de cualquier cliente); no esta atado a `consurtrading.org`. Cada
> `install.sh` agrega un stack mas detras del mismo proxy.

---

## 9. Configuracion de PCs (archivo hosts)

Ver guia completa: [`configurar-pcs-host.md`](configurar-pcs-host.md).

Resumen rapido — en el **servidor**, obtener lineas exactas:

```bash
cd /opt/proyectos/fe.consurtrading.org
bash scripts/list-tenant-hosts.sh
```

En cada **PC interna**:

```bash
# Linux / Mac
sudo ./set-hosts.sh 192.168.1.100 fe.consurtrading.org empresa1 empresa2
```

```powershell
# Windows (PowerShell como Administrador)
.\set-hosts.ps1 -ServerIp 192.168.1.100 -BaseDomain fe.consurtrading.org -Empresas empresa1,empresa2
```

> Cada empresa nueva requiere agregar su linea en el `hosts` de las PCs que la
> usen, o re-ejecutar el helper con la empresa nueva.

---

## 10. SSL wildcard: emitir o renovar (ssl.sh)

Un solo script para todo el ciclo SSL. **Detecta automaticamente** el modo:

- Sin certificado previo → **EMITE** el wildcard y activa HTTPS en el `.env`
  (`FORCE_HTTPS=true`, pusher a 443/https).
- Con certificado previo → **RENUEVA** (`--force-renewal`).

```bash
cd /opt/proyectos
sudo ./ssl.sh
# Elige el dominio del menu, o directo:
sudo ./ssl.sh --domain fe.consurtrading.org --email admin@consurtrading.org
```

### 10.1 NO requiere IP publica ni FortiGate

El reto **DNS-01** valida creando un TXT en el DNS **publico** del registrador;
no comprueba que el servidor sea alcanzable desde internet. Por eso el SSL se
puede emitir **desde la Fase 1** (solo LAN): las PCs acceden por el nombre real
(`https://empresa1.fe.consurtrading.org` via hosts/DNS FortiGate) y el
certificado es valido. Cuando llegue la IP publica, el mismo cert sirve para
el acceso externo sin tocar nada.

**Unico requisito:** acceso al panel DNS del registrador para crear el TXT.

### 10.2 Proceso certbot (DNS-01 manual)

1. Certbot muestra uno o dos registros TXT `_acme-challenge.fe.consurtrading.org`.
2. Crearlos en el panel DNS del registrador.
3. Esperar propagacion (5–30 min; verificar con `dig TXT _acme-challenge.fe.consurtrading.org @8.8.8.8`).
4. Presionar Enter en certbot (**no usar Ctrl+C**).
5. El script copia certs a `certs/`, cambia `.env` a HTTPS (solo primera vez) y
   reinicia el proxy.

Un solo certificado `*.fe.consurtrading.org` cubre **todas** las empresas de
ese dominio base. Cada dominio base instalado (ej. `ntsuite.consurtrading.org`)
lleva su **propio** wildcard: ejecutar `ssl.sh` una vez por dominio.

### 10.3 Renovacion (~90 dias, manual)

Como el DNS del registrador no tiene API, la renovacion es **manual**: mismo
comando (`sudo ./ssl.sh --domain fe.consurtrading.org`), certbot pide recrear
el TXT. El script imprime la **fecha sugerida** de proxima renovacion (~75
dias); agendarla en calendario.

> Automatizacion futura (opcional): delegar `_acme-challenge.fe.consurtrading.org`
> por CNAME a una zona DNS con API (acme-dns, o una zona auxiliar gratuita en
> Cloudflare) y usar un hook de certbot. Asi la renovacion deja de ser manual
> sin cambiar de registrador.

### 10.4 Alternativas descartadas

| Alternativa | Por que NO |
|-------------|-----------|
| **Cloudflare** | El plan gratuito emite wildcard de un nivel (`*.consurtrading.org`); para `*.fe.consurtrading.org` exige plan de pago (ACM). |
| **FortiGate como CA** (cert interno) | Habria que instalar el CA cert en CADA PC/celular; warnings en dispositivos sin el; no sirve para el acceso publico. |
| **FortiGate SSL offloading en el VIP** | Centraliza los certs en un equipo cuyo admin no siempre esta disponible; el cert igual habria que emitirlo/renovarlo. |
| **HTTP-01 (certbot standalone/webroot)** | No emite wildcard; cada tenant nuevo necesitaria re-emitir. |

---

## 11. Fase 2 — Checklist del admin de red (FortiGate)

La app **ya funciona en LAN** sin nada de esto (hosts → IP del servidor).
Cuando el administrador del FortiGate este disponible, solo debe "conectar".
Este checklist tambien queda **generado por dominio** al final del archivo de
credenciales `/opt/proyectos/<dominio>-onprem.txt`.

### 11.1 DNS publico (panel del registrador) — POR dominio base

```text
A   fe.consurtrading.org       → IP_PUBLICA
A   *.fe.consurtrading.org     → IP_PUBLICA   (wildcard: cubre todos los tenants)
```

### 11.2 FortiGate — VIP / Port Forward (UNA sola vez, compartido)

```text
WAN :80   → IP_LAN_SERVIDOR :80
WAN :443  → IP_LAN_SERVIDOR :443
+ politica de firewall WAN→LAN permitiendo 80/443 hacia el VIP
```

Todos los dominios instalados comparten el mismo VIP: el `nginx-proxy`
distingue por header `Host`.

### 11.3 FortiGate — DNS local (resolucion LAN) — POR dominio base

Objetivo: que las PCs internas resuelvan **local** (mas rapido y funciona
**sin internet**), reemplazando los archivos `hosts` por PC:

```text
config system dns-database → zona "fe.consurtrading.org" (primary/shadow):
  @    A   IP_LAN_SERVIDOR
  *    A   IP_LAN_SERVIDOR    ← si la version de FortiOS no soporta wildcard,
                                crear una entrada por tenant (la lista exacta:
                                bash scripts/list-tenant-hosts.sh)
  ws   A   IP_LAN_SERVIDOR
```

Y el **DHCP** de la LAN debe entregar el FortiGate como servidor DNS.

### 11.4 Despues de conectar

| Origen | URL |
|--------|-----|
| Externo (internet) | `https://empresa1.fe.consurtrading.org` (DNS publico → VIP → LAN) |
| Interno (LAN) | `https://empresa1.fe.consurtrading.org` (DNS FortiGate → LAN directo) |

- Si el SSL no se emitio antes: `sudo ./ssl.sh --domain fe.consurtrading.org`.
- Retirar las entradas pro-8 del `hosts` de las PCs (ya no se necesitan).
- Acceder por **dominio**, no por IP (con `FORCE_HTTPS=true` la IP genera
  warning de certificado).

---

## 12. Actualizacion del codigo

```bash
cd /opt/proyectos
sudo ./update.sh
```

Flujo interactivo:

1. Lista dominios instalados → eliges numero.
2. Pregunta rama (default: rama actual del repo).
3. Ejecuta `onprem-update.sh` en el proyecto elegido.

Opciones directas:

```bash
sudo ./update.sh --domain fe.consurtrading.org --branch master
sudo ./update.sh --domain fe.consurtrading.org --skip-backup   # no recomendado en prod
```

### Que hace el update (en orden)

1. Backup en `storage/app/backups/pre-update/FECHA/`:
   - `.env`, `docker-compose.yml`, `supervisor.conf`
   - `all-databases.sql.gz` (dump completo MariaDB)
2. `git pull origin <rama>`
3. `composer install --no-dev`
4. `composer dump-autoload -o`
5. `php artisan migrate --force`
6. `php artisan tenancy:migrate --force`
7. Limpia caches + `config:cache`
8. Purga OPcache (`kill -USR2 1`)
9. Reinicia workers de supervisor

> **Nunca** uses `docker compose down -v` en produccion.

---

## 13. Variables .env generadas

Ejemplo para `fe.consurtrading.org` en **Fase 1 (HTTP)**:

```env
APP_NAME=fe.consurtrading.org
APP_ENV=production
APP_DEBUG=false
APP_URL_BASE=fe.consurtrading.org
APP_URL=http://${APP_URL_BASE}
FORCE_HTTPS=false

DB_CONNECTION=system
DB_HOST=mariadb_fe_consurtrading_org
DB_DATABASE=fe_consurtrading_org
DB_USERNAME=root
DB_PASSWORD=<generado>

CACHE_DRIVER=file          # CRITICO: redis_tenancy rompe CLI si CACHE_DRIVER=redis
QUEUE_CONNECTION=redis
SESSION_DRIVER=redis
REDIS_HOST=redis_fe_consurtrading_org

BROADCAST_DRIVER=pusher
PUSHER_HOST=soketi_fe_consurtrading_org
PUSHER_PORT=6001
PUSHER_SCHEME=http
PUSHER_CLIENT_HOST=ws.fe.consurtrading.org
PUSHER_CLIENT_PORT=80          # mientras no haya SSL: HTTP
PUSHER_CLIENT_SCHEME=http      # ssl.sh cambia a 443/https al emitir el cert

PREFIX_DATABASE=tenancy
MYSQL_PORT_HOST=3001           # puerto expuesto al host
```

Tras `ssl.sh` (primera emision):

```env
APP_URL=https://${APP_URL_BASE}
FORCE_HTTPS=true
PUSHER_CLIENT_PORT=443
PUSHER_CLIENT_SCHEME=https
```

---

## 14. Comandos utiles de operacion

```bash
# Estado de contenedores de un dominio
cd /opt/proyectos/fe.consurtrading.org
docker compose ps

# Logs en tiempo real
docker compose logs -f fpm_1

# Entrar al contenedor PHP
docker exec -it fpm_fe_consurtrading_org bash

# Artisan (siempre con CACHE_DRIVER=file en CLI)
docker compose exec fpm_1 sh -c "CACHE_DRIVER=file php artisan migrate:status"

# Listar tenants / lineas hosts
bash scripts/list-tenant-hosts.sh

# Reiniciar solo un stack (sin tocar proxy ni otros dominios)
docker compose restart

# Ver volumenes (NO borrar en prod)
docker volume ls | grep fe_consurtrading
```

---

## 15. Troubleshooting

### La PC no abre `empresa1.fe.consurtrading.org`

1. Verificar linea en `hosts` apuntando a la IP LAN correcta.
2. Windows: `ipconfig /flushdns`.
3. Probar desde el servidor: `curl -H "Host: empresa1.fe.consurtrading.org" http://127.0.0.1/login`.

### Panel central abre pero el tenant da 404

- El tenant puede no existir aun en la tabla `hostnames`.
- Verificar que el subdominio se creo desde el panel (Clientes → Nuevo).
- Ejecutar `list-tenant-hosts.sh` y confirmar que aparece el fqdn.

### Error SQL / Access denied en tenant

```bash
docker exec fpm_fe_consurtrading_org sh -c "CACHE_DRIVER=file php artisan tenancy:key:update"
docker exec fpm_fe_consurtrading_org sh -c "CACHE_DRIVER=file php artisan config:cache"
```

### Certbot falla en DNS-01

- Verificar que el TXT `_acme-challenge` esta creado y propagado antes de Enter.
- Comprobar con: `dig TXT _acme-challenge.fe.consurtrading.org @8.8.8.8`.

### Puerto MySQL ocupado al instalar segundo dominio

- El script busca automaticamente un puerto libre. Si falla, revisar:
  `ss -tuln | grep 300` y `docker ps -a`.

### WebSocket / VendeMaster no conecta

- Fase 1: incluir `ws.fe.consurtrading.org` en el `hosts` de la PC.
- Fase 2: verificar certificado de `ws.fe.consurtrading.org` en `certs/`.

---

## 16. Datos que NO se deben borrar

| Recurso | Riesgo si se borra |
|---------|-------------------|
| Volumen `mysqldata*` | Perdida total de BD (system + todos los tenants) |
| Volumen `redisdata*` | Perdida de colas/sesiones en Redis |
| `.env` | Credenciales y configuracion irreversible sin backup |
| `certs/*.crt` / `*.key` | HTTPS deja de funcionar hasta re-emitir |
| `storage/app/backups/` | Unicos respaldos pre-update |

**Comandos prohibidos en produccion:**

```bash
docker compose down -v          # borra volumenes
docker volume rm mysqldata1     # borra BD
docker system prune --volumes     # borra todo lo no usado incluyendo datos
```

Para detener contenedores sin perder datos: `docker compose down` (sin `-v`).
