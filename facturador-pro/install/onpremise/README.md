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
2. [Caso de referencia: dominio](#2-caso-de-referencia-dominio)
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
dominio final desde la instalacion (ej. `fe.dominio.org`). Los `fqdn` de
cada empresa (`empresa1.fe.dominio.org`) ya quedan correctos en la tabla
`hostnames`.

---

## 2. Caso de referencia: dominio

| Nombre | Uso |
|--------|-----|
| `dominio.org` | Web oficial (ajena a este sistema) |
| `reportes.dominio.org` | Subdominio de reportes (ajeno) |
| **`fe.dominio.org`** | **Base del facturador** — panel central de gestion |
| `empresa1.fe.dominio.org` | Tenant (empresa 1) |
| `empresa2.fe.dominio.org` | Tenant (empresa 2) |
| `ws.fe.dominio.org` | WebSocket / Broadcasting (Soketi) — **reservado, no crear tenant "ws"** |

El instalador es **generico**: al ejecutar `install.sh` puedes poner cualquier
dominio base (ej. `fact.otraempresa.com`) para otro cliente en el mismo servidor.

---

## 3. Como funciona APP_URL_BASE y los tenants

Pro-8 usa **hyn/multi-tenant**. El flujo es:

```text
.env
  APP_URL_BASE=fe.dominio.org    ← sufijo raiz (NO es la URL de cada tenant)
  APP_URL=http://${APP_URL_BASE}       ← URL del panel central

Al CREAR un cliente (tenant):
  subdominio ingresado: "empresa1"
  fqdn guardado en BD:  empresa1 + "." + APP_URL_BASE
                      = empresa1.fe.dominio.org

En CADA request HTTP:
  1. El navegador envia header Host: empresa1.fe.dominio.org
  2. hyn busca ese Host en la tabla hostnames.fqdn
  3. Si coincide → conecta la BD del tenant y carga rutas de tenant
  4. Si Host = fe.dominio.org → panel central (system)
```

**Por que no funciona `empresa1.192.168.1.100`:** los subdominios de una IP no
son nombres DNS validos. El header `Host` debe ser un nombre que exista en
`hostnames.fqdn`. Por eso en Fase 1 se usa el archivo `hosts` de cada PC para
resolver `empresa1.fe.dominio.org` → `192.168.1.100`.

**Enrutamiento automatico de empresas nuevas:** el contenedor nginx declara
`VIRTUAL_HOST="fe.dominio.org, *.fe.dominio.org, 192.168.1.100"`.
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

Ejemplo con raiz `/opt/proyectos` y un dominio `fe.dominio.org`:

```text
/opt/proyectos/
├── install.sh                          ← scripts de esta carpeta (descargados aqui)
├── update.sh
├── ssl.sh                              ← emite O renueva el wildcard SSL
├── uninstall.sh                        ← elimina un dominio (contenedores+volumenes+carpeta)
├── set-hosts.sh / set-hosts.ps1
│
├── _infra/                             ← COMPARTIDO por todos los dominios
│   ├── proxy/
│   │   └── docker-compose.yml          ← nginx-proxy en 80/443
│   └── certs/                          ← certificados SSL (Fase 2)
│       ├── fe.dominio.org.crt
│       ├── fe.dominio.org.key
│       ├── ws.fe.dominio.org.crt
│       └── ws.fe.dominio.org.key
│
├── fe.dominio.org/               ← PROYECTO (uno por dominio, autocontenido)
│   ├── app/                            ← repo pro-8 clonado
│   │   ├── .env                        ← APP_URL_BASE, credenciales, COMPOSE_PROJECT_NAME
│   │   ├── docker-compose.yml
│   │   ├── supervisor.conf
│   │   ├── artisan
│   │   ├── storage/                    ← datos de app + backups pre-update
│   │   ├── docker/
│   │   │   ├── nginx/default           ← config nginx con proxy /app (Soketi)
│   │   │   ├── php-fpm/
│   │   │   ├── mariadb/my.cnf
│   │   │   ├── scheduling/
│   │   │   └── supervisor/
│   │   └── scripts/
│   │       ├── onprem-setup.sh         ← motor de despliegue
│   │       ├── onprem-update.sh
│   │       └── list-tenant-hosts.sh
│   └── fe.dominio.org-onprem.txt ← credenciales (admin, MySQL, contenedores)
│
└── otro-dominio.com/                   ← segundo dominio (misma estructura)
    ├── app/
    └── otro-dominio.com-onprem.txt
```

### Contenedores por dominio

Para `fe.dominio.org` (puntos → guiones bajos en nombres Docker):

| Contenedor | Funcion |
|------------|---------|
| `nginx_fe_dominio_org` | Nginx interno de la app |
| `fpm_fe_dominio_org` | PHP-FPM 8.2 + Laravel |
| `mariadb_fe_dominio_org` | MariaDB 10.5.6 |
| `redis_fe_dominio_org` | Redis (colas, sesiones) |
| `soketi_fe_dominio_org` | WebSocket (Soketi) |
| `scheduling_fe_dominio_org` | Laravel scheduler (cron) |
| `supervisor_fe_dominio_org` | Queue workers |
| `proxy-proxy-1` (compartido) | nginx-proxy — enruta por `VIRTUAL_HOST` |

### Volumenes Docker (por dominio, NO borrar)

```text
fe_dominio_org_mysqldata1    ← base de datos system + tenants
fe_dominio_org_redisdata1    ← datos persistentes Redis
```

El prefijo del volumen es **determinista**: el instalador fija
`COMPOSE_PROJECT_NAME=<dominio con puntos→guion_bajo>` en el `.env` (ej.
`fe_dominio_org`), de modo que el nombre del volumen NO depende de en que
carpeta viva el repo. Asi `uninstall.sh` puede eliminarlos de forma fiable.
Verificar con `docker volume ls`.

> Instalaciones antiguas (anteriores a este cambio) pueden tener el prefijo
> basado en el nombre de carpeta sin puntos (ej. `fedominioorg_mysqldata1`);
> `uninstall.sh` reconoce ambos formatos.

---

## 6. Scripts disponibles

### En `codeplant/facturador-pro/install/onpremise/` (bootstrap / operacion)

| Script | Cuando usarlo |
|--------|---------------|
| `install.sh` | Primera instalacion de un dominio (Fase 1). Reutilizable para agregar mas dominios. |
| `update.sh` | Actualizar codigo de un dominio ya instalado (menu selector + rama). |
| `ssl.sh` | SSL wildcard: **emite** (primera vez, activa HTTPS) o **renueva** (~90 dias) segun detecte. Menu selector de dominio. |
| `uninstall.sh` | Eliminar por completo un dominio: contenedores + **volumenes** + carpeta. Unica forma correcta de borrar un dominio (evita el `Access denied` al reinstalar). |
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

Copiar/pegar para una instalacion nueva o para actualizar los scripts en un
servidor existente:

```bash
mkdir -p /opt/proyectos && cd /opt/proyectos

BASE_URL="https://raw.githubusercontent.com/gians96/codeplant/master/facturador-pro/install/onpremise"

for file in install.sh update.sh ssl.sh uninstall.sh set-hosts.sh set-hosts.ps1 README.md ARQUITECTURA-Y-CONTEXTO.md configurar-pcs-host.md; do
    curl -fSL -o "$file" "$BASE_URL/$file"
done

chmod +x install.sh update.sh ssl.sh uninstall.sh set-hosts.sh
```

### 7.2 Ejecutar instalacion

```bash
sudo ./install.sh
```

### 7.3 Preguntas del instalador

| Pregunta | Default | Descripcion |
|----------|---------|-------------|
| Dominio base | *(obligatorio)* | Ej. `fe.dominio.org`. Se convierte en `APP_URL_BASE`. |
| IP LAN del servidor | autodetectada | IP de la VM en la red local (ej. `192.168.1.100`). |
| Numero de servicio | `# instalados + 1` | Identificador interno (afecta nombre de servicios en compose). |
| Puerto MySQL host | auto libre 3001–3999 | Puerto expuesto al host para acceso remoto a MariaDB. |
| Rama del repositorio | `master` | Rama de `pro-8` a clonar. |

Al inicio el script **lista los dominios ya instalados** en la carpeta actual.

### 7.4 Que hace install.sh (paso a paso)

1. **Preflight (primero)**: comprueba Docker instalado + daemon activo, plugin
   `docker compose`, `git` y `curl` (instala lo que falte). Asi falla temprano
   y con un mensaje claro si algo no esta listo.
2. Lista los dominios ya instalados y valida el dominio (no puede empezar con `ws.`).
3. **Guarda anti-huerfanos**: si detecta restos Docker (contenedores/volumenes)
   de una instalacion previa del mismo dominio cuya carpeta ya no existe, avisa
   y ofrece purgarlos (evita el error `Access denied` al reinstalar).
4. Crea la red `proxynet` y levanta `nginx-proxy` (80/443) en `_infra/proxy/`
   (solo la primera vez; compartido por todos los dominios).
5. Clona `pro-8` en `<dominio>/app/` (rama elegida).
6. Ejecuta `scripts/onprem-setup.sh` dentro del proyecto:
   - Genera `docker-compose.yml`, `.env` (con `COMPOSE_PROJECT_NAME`),
     `supervisor.conf`, Dockerfiles.
   - Levanta 7 contenedores (nginx, fpm, mariadb, redis, soketi, scheduling, supervisor).
   - `composer install`, `migrate:refresh --seed`, `config:cache`.
   - Crea usuario admin y plan "Ilimitado".
7. Imprime `docker compose ps`, credenciales y lineas para `hosts`.

### 7.5 Credenciales generadas

Archivo: `/opt/proyectos/<dominio>/<dominio>-onprem.txt`

Contiene:

- URL del panel central
- Email y password del administrador
- Password root de MySQL
- Puerto MySQL del host
- Nombres de contenedores

### 7.6 Acceso inmediato despues de instalar

| Recurso | URL (Fase 1) |
|---------|--------------|
| Panel central | `http://192.168.1.100` o `http://fe.dominio.org` *(con hosts)* |
| Crear tenants | Panel → Clientes → Nuevo (subdominio ej. `empresa1`) |
| Tenant empresa1 | `http://empresa1.fe.dominio.org` *(con hosts)* |

---

## 8. Multi-dominio en el mismo servidor

Cada dominio base es un **proyecto independiente con su propio gestor de
tenants**. Ejemplo objetivo en el servidor de dominio:

```text
fe.dominio.org                 ← BASE proyecto 1 (gestor de tenants)
  empresa1.fe.dominio.org      ←   tenant
  empresa2.fe.dominio.org      ←   tenant

ntsuite.dominio.org            ← BASE proyecto 2 (gestor de tenants)
  empresa1.ntsuite.dominio.org ←   tenant
  empresa2.ntsuite.dominio.org ←   tenant
```

Para instalar el **segundo dominio** basta re-ejecutar el instalador:

```bash
cd /opt/proyectos
sudo ./install.sh
# Dominio: ntsuite.dominio.org
# El script asigna automaticamente otro puerto MySQL libre (3002, ...)
```

Cada dominio base necesita su **propio cert wildcard** (`sudo ./ssl.sh` una vez
por dominio) y su **propia zona DNS** en el FortiGate (seccion 11.3). El
VIP/NAT 80/443 es **uno solo** para todos.

### Por que no chocan

| Recurso | Aislamiento |
|---------|-------------|
| Codigo + `.env` | Carpeta propia `./<dominio>/app/` |
| Contenedores | Nombre `nginx_<dom>`, `fpm_<dom>`, etc. |
| Base de datos | Volumen propio `<dom>_mysqldata<N>` |
| Redis | Volumen propio `<dom>_redisdata<N>` |
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
    fe.dominio.org   ntsuite.dominio.org   cualquier-dominio.com
    (stack Docker propio)  (stack propio)              (stack propio)
```

> El instalador es **generico**: el dominio base puede ser **cualquiera**
> (de cualquier cliente); no esta atado a `dominio.org`. Cada
> `install.sh` agrega un stack mas detras del mismo proxy.

---

## 9. Configuracion de PCs (archivo hosts)

Ver guia completa: [`configurar-pcs-host.md`](configurar-pcs-host.md).

Resumen rapido — en el **servidor**, obtener lineas exactas:

```bash
cd /opt/proyectos/fe.dominio.org/app
bash scripts/list-tenant-hosts.sh
```

En cada **PC interna**:

```bash
# Linux / Mac
sudo ./set-hosts.sh 192.168.1.100 fe.dominio.org empresa1 empresa2
```

```powershell
# Windows (PowerShell como Administrador)
.\set-hosts.ps1 -ServerIp 192.168.1.100 -BaseDomain fe.dominio.org -Empresas empresa1,empresa2
```

> Cada empresa nueva requiere agregar su linea en el `hosts` de las PCs que la
> usen, o re-ejecutar el helper con la empresa nueva.

---

## 10. SSL wildcard: emitir o renovar (ssl.sh)

Un solo script para todo el ciclo SSL. **Detecta automaticamente** el modo:

- Sin certificado previo → **EMITE** el wildcard y activa HTTPS en el `.env`
  (`FORCE_HTTPS=true`, pusher a 443/https).
- Con certificado previo → **RENUEVA** (`--force-renewal`).
- Con `--repair-proxy` → **repara HTTPS/proxy sin renovar certificado**.

```bash
cd /opt/proyectos
sudo ./ssl.sh
# Elige el dominio del menu, o directo:
sudo ./ssl.sh --domain fe.dominio.org --email admin@dominio.org
```

Para reparar un dominio que ya tiene certificado, pero Cloudflare muestra
`522` o el origen no responde por `443`, descargar primero el `ssl.sh` nuevo y
ejecutar:

```bash
cd /opt/proyectos
curl -fSL -o ssl.sh https://raw.githubusercontent.com/gians96/codeplant/master/facturador-pro/install/onpremise/ssl.sh
chmod +x ssl.sh

sudo ./ssl.sh --domain ceos-facturacion.com --repair-proxy
```

El script debe imprimir headers para las pruebas locales:

```bash
curl -vkI --connect-timeout 5 --resolve ceos-facturacion.com:443:127.0.0.1 https://ceos-facturacion.com
```

Si `demo.ceos-facturacion.com` carga pero `ceos-facturacion.com` devuelve
`522` en Cloudflare, revisa que ambos registros DNS esten en el mismo modo:
`Solo DNS` o ambos con proxy naranja. Si el apex esta con proxy naranja y el
wildcard esta `Solo DNS`, los tenants pueden entrar directo al origen mientras
el panel central pasa por Cloudflare y falla por reglas WAN/Firewall.

`www.ceos-facturacion.com` no debe crearse como tenant: el repair agrega
`www.<dominio>` al proxy y lo redirige al dominio base del panel central.

### 10.1 NO requiere IP publica ni FortiGate

El reto **DNS-01** valida creando un TXT en el DNS **publico** del registrador;
no comprueba que el servidor sea alcanzable desde internet. Por eso el SSL se
puede emitir **desde la Fase 1** (solo LAN): las PCs acceden por el nombre real
(`https://empresa1.fe.dominio.org` via hosts/DNS FortiGate) y el
certificado es valido. Cuando llegue la IP publica, el mismo cert sirve para
el acceso externo sin tocar nada.

**Unico requisito:** acceso al panel DNS del registrador para crear el TXT.

### 10.2 Proceso certbot (DNS-01 manual)

1. Certbot muestra uno o dos registros TXT `_acme-challenge.fe.dominio.org`.
2. Crearlos en el panel DNS del registrador.
3. Esperar propagacion (5–30 min; verificar con `dig TXT _acme-challenge.fe.dominio.org @8.8.8.8`).
4. Presionar Enter en certbot (**no usar Ctrl+C**).
5. El script copia certs a `certs/`, cambia `.env` a HTTPS (solo primera vez) y
   reinicia el proxy.

Un solo certificado `*.fe.dominio.org` cubre **todas** las empresas de
ese dominio base. Cada dominio base instalado (ej. `ntsuite.dominio.org`)
lleva su **propio** wildcard: ejecutar `ssl.sh` una vez por dominio.

### 10.3 Renovacion (~90 dias, manual)

Como el DNS del registrador no tiene API, la renovacion es **manual**: mismo
comando (`sudo ./ssl.sh --domain fe.dominio.org`), certbot pide recrear
el TXT. El script imprime la **fecha sugerida** de proxima renovacion (~75
dias); agendarla en calendario.

> Automatizacion futura (opcional): delegar `_acme-challenge.fe.dominio.org`
> por CNAME a una zona DNS con API (acme-dns, o una zona auxiliar gratuita en
> Cloudflare) y usar un hook de certbot. Asi la renovacion deja de ser manual
> sin cambiar de registrador.

### 10.4 Alternativas descartadas

| Alternativa | Por que NO |
|-------------|-----------|
| **Cloudflare** | El plan gratuito emite wildcard de un nivel (`*.dominio.org`); para `*.fe.dominio.org` exige plan de pago (ACM). |
| **FortiGate como CA** (cert interno) | Habria que instalar el CA cert en CADA PC/celular; warnings en dispositivos sin el; no sirve para el acceso publico. |
| **FortiGate SSL offloading en el VIP** | Centraliza los certs en un equipo cuyo admin no siempre esta disponible; el cert igual habria que emitirlo/renovarlo. |
| **HTTP-01 (certbot standalone/webroot)** | No emite wildcard; cada tenant nuevo necesitaria re-emitir. |

---

## 11. Fase 2 — Checklist del admin de red (FortiGate)

La app **ya funciona en LAN** sin nada de esto (hosts → IP del servidor).
Cuando el administrador del FortiGate este disponible, solo debe "conectar".
Este checklist tambien queda **generado por dominio** al final del archivo de
credenciales `/opt/proyectos/<dominio>/<dominio>-onprem.txt`.

### 11.1 DNS publico (panel del registrador) — POR dominio base

```text
A   fe.dominio.org       → IP_PUBLICA
A   *.fe.dominio.org     → IP_PUBLICA   (wildcard: cubre todos los tenants)
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
config system dns-database → zona "fe.dominio.org" (primary/shadow):
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
| Externo (internet) | `https://empresa1.fe.dominio.org` (DNS publico → VIP → LAN) |
| Interno (LAN) | `https://empresa1.fe.dominio.org` (DNS FortiGate → LAN directo) |

- Si el SSL no se emitio antes: `sudo ./ssl.sh --domain fe.dominio.org`.
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
sudo ./update.sh --domain fe.dominio.org --branch master
sudo ./update.sh --domain fe.dominio.org --skip-backup   # no recomendado en prod
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

Ejemplo para `fe.dominio.org` en **Fase 1 (HTTP)**:

```env
APP_NAME=fe.dominio.org
APP_ENV=production
APP_DEBUG=false
APP_URL_BASE=fe.dominio.org
APP_URL=http://${APP_URL_BASE}
FORCE_HTTPS=false

DB_CONNECTION=system
DB_HOST=mariadb_fe_dominio_org
DB_DATABASE=fe_dominio_org
DB_USERNAME=root
DB_PASSWORD=<generado>

CACHE_DRIVER=file          # CRITICO: redis_tenancy rompe CLI si CACHE_DRIVER=redis
QUEUE_CONNECTION=redis
SESSION_DRIVER=redis
REDIS_HOST=redis_fe_dominio_org

BROADCAST_DRIVER=pusher
PUSHER_HOST=soketi_fe_dominio_org
PUSHER_PORT=6001
PUSHER_SCHEME=http
PUSHER_CLIENT_HOST=ws.fe.dominio.org
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
cd /opt/proyectos/fe.dominio.org/app
docker compose ps

# Logs en tiempo real
docker compose logs -f fpm_1

# Entrar al contenedor PHP
docker exec -it fpm_fe_dominio_org bash

# Artisan (siempre con CACHE_DRIVER=file en CLI)
docker compose exec fpm_1 sh -c "CACHE_DRIVER=file php artisan migrate:status"

# Listar tenants / lineas hosts
bash scripts/list-tenant-hosts.sh

# Reiniciar solo un stack (sin tocar proxy ni otros dominios)
docker compose restart

# Ver volumenes (NO borrar en prod)
docker volume ls | grep fe_dominio
```

---

## 15. Troubleshooting

### Cloudflare 522, pero el origen directo responde

Sintoma:

```text
https://ceos-facturacion.com                  -> 522 desde Cloudflare
https://demo.ceos-facturacion.com/login       -> a veces carga si esta en Solo DNS
curl --resolve dominio:443:IP_PUBLICA https://dominio -> 302 /login
```

**Diagnostico:** si el acceso directo al origen responde `301`, `302` o `200`,
Docker, `nginx-proxy`, SSL y Laravel ya estan atendiendo. El `522` queda entre
Cloudflare y el servidor de origen: FortiGate/VIP/NAT, firewall, IPS/DoS/GeoIP
o reglas que no permiten las IPs de Cloudflare.

Pruebas recomendadas:

```bash
# En el servidor: valida Docker/proxy sin salir a internet
curl -vkI --resolve ceos-facturacion.com:443:127.0.0.1 https://ceos-facturacion.com
curl -vkI --resolve ceos-facturacion.com:80:127.0.0.1 http://ceos-facturacion.com
```

```powershell
# Desde una red externa: valida NAT/VIP directo al origen
curl.exe -vkI --resolve ceos-facturacion.com:443:143.0.248.236 https://ceos-facturacion.com
curl.exe -vI  --resolve ceos-facturacion.com:80:143.0.248.236 http://ceos-facturacion.com

# Sin --resolve: valida el camino real por Cloudflare si el proxy naranja esta activo
curl.exe -vkI https://ceos-facturacion.com
```

Interpretacion:

| Resultado | Lectura |
|-----------|---------|
| Local `127.0.0.1:443` responde | El proxy Docker y el certificado estan OK. |
| Directo a `IP_PUBLICA:443` responde | FortiGate/NAT hacia el servidor esta OK para clientes normales. |
| Directo responde, pero Cloudflare da `522` | Cloudflare no logra conectar al origen: revisar firewall/IPS/DoS/GeoIP/allowlist. |
| `demo.<dominio>` carga y el apex no | Un registro puede estar en `Solo DNS` y el otro con proxy naranja. Unificar el modo. |

Solucion rapida mientras se revisa la red: poner `ceos-facturacion.com`,
`*.ceos-facturacion.com` y `www.ceos-facturacion.com` en `Solo DNS`. Si se
necesita proxy naranja, permitir el trafico de Cloudflare hacia puertos `80` y
`443` en FortiGate/firewall y revisar perfiles IPS/DoS/GeoIP.

### `400 Bad Request: plain HTTP request was sent to HTTPS port`

Sintoma al abrir en navegador:

```text
143.0.248.236:443 -> 400 Bad Request
The plain HTTP request was sent to HTTPS port
```

Causa: se escribio la IP con puerto, pero sin `https://`. El navegador envio
HTTP normal al puerto TLS. No es fallo del proxy ni del certificado.

Prueba correcta:

```text
https://143.0.248.236
```

Para Pro-8, la prueba util debe preservar `Host` y SNI:

```bash
curl -vkI --resolve ceos-facturacion.com:443:143.0.248.236 https://ceos-facturacion.com
```

### `www.<dominio>` devuelve 404 o cae como tenant

`www` no debe crearse como tenant. Debe ser alias del panel central y redirigir
al dominio base. Ejecutar:

```bash
cd /opt/proyectos
sudo ./ssl.sh --domain ceos-facturacion.com --repair-proxy
```

Validacion:

```bash
curl -vkI --resolve www.ceos-facturacion.com:443:127.0.0.1 https://www.ceos-facturacion.com/login
```

Debe responder `301` hacia `https://ceos-facturacion.com/login`.

### Laravel 500 despues de corregir Cloudflare/proxy

Cuando el proxy ya funciona, el navegador puede mostrar la pagina `500` propia
de Laravel. En ese punto el problema ya no es Cloudflare: hay que revisar FPM,
Composer, `storage/` y las caches de Laravel.

Logs:

```bash
cd /opt/proyectos/ceos-facturacion.com/app
docker compose logs --tail=120 fpm_1
docker compose exec -T fpm_1 sh -c "tail -120 /var/www/html/storage/logs/laravel.log"
```

Errores vistos:

| Error | Causa probable | Solucion |
|-------|----------------|----------|
| `Class "Illuminate\Foundation\Application" not found` | Falta `vendor/` o Composer no termino. | Ejecutar `composer install` dentro de `fpm_1`. |
| `Class "Barryvdh\Debugbar\ServiceProvider" not found` | Se instalo con `--no-dev`, pero la app intenta cargar Debugbar. | Instalar sin `--no-dev` o quitar ese provider/config del proyecto. |
| `Please provide a valid cache path` | Faltan carpetas de `storage/framework` o permisos. | Crear carpetas y permisos de Laravel. |
| `tail: cannot open ... laravel.log` | No existe `storage/logs/laravel.log`. | Crear archivo y permisos antes de volver a probar. |

Recuperacion base:

```bash
cd /opt/proyectos/ceos-facturacion.com/app

docker compose exec -T -u root fpm_1 sh -c "
mkdir -p storage/logs storage/framework/views storage/framework/cache/data storage/framework/sessions bootstrap/cache
touch storage/logs/laravel.log
chown -R www-data:www-data storage bootstrap/cache
chmod -R 775 storage bootstrap/cache
"

docker compose exec -T fpm_1 sh -c "cd /var/www/html && composer install --optimize-autoloader"
docker compose exec -T fpm_1 sh -c "cd /var/www/html && composer dump-autoload -o"
docker compose exec -T fpm_1 sh -c "CACHE_DRIVER=file php artisan package:discover"
docker compose exec -T fpm_1 sh -c "CACHE_DRIVER=file php artisan config:clear"
docker compose exec -T fpm_1 sh -c "CACHE_DRIVER=file php artisan cache:clear"
docker compose exec -T fpm_1 sh -c "CACHE_DRIVER=file php artisan route:clear"
docker compose exec -T fpm_1 sh -c "CACHE_DRIVER=file php artisan view:clear"
docker compose exec -T fpm_1 sh -c "CACHE_DRIVER=file php artisan config:cache"
docker compose restart fpm_1 supervisor_1 scheduling_1
```

### `Access denied for user 'root'` al REINSTALAR un dominio

Sintoma (durante `migrate:refresh --seed`):

```text
SQLSTATE[HY000] [1045] Access denied for user 'root'@'172.x.x.x' (using password: YES)
```

**Causa:** se borro la carpeta del proyecto y/o los contenedores **a mano**, pero
NO los volumenes. `docker rm` + `rm -rf` **no** elimina los volumenes Docker.
MariaDB solo fija la password de `root` en la PRIMERA inicializacion (data-dir
vacio); al reinstalar se genera un `.env` con password NUEVA, pero el volumen
conserva la VIEJA → rechazo de conexion.

**Solucion (limpiar el volumen huerfano y reinstalar):**

```bash
cd /opt/proyectos
# Opcion A (recomendada): herramienta dedicada (detecta restos aunque la carpeta no exista)
sudo ./uninstall.sh --domain ceos-facturacion.com
# Opcion B (manual): identificar y borrar los volumenes del dominio
docker volume ls | grep -Ei 'ceos.*(mysqldata|redisdata)'
docker volume rm <los_que_aparezcan>

sudo ./install.sh           # reinstalacion limpia (sin Access denied)
```

> El nuevo `install.sh` **detecta automaticamente** estos restos antes de
> reinstalar y ofrece purgarlos. Para no llegar a este estado, elimina siempre
> los dominios con `uninstall.sh`, nunca con `rm -rf`.

### Cambie la IP / la red del servidor

**No borres nada.** Re-ejecuta el instalador con el **mismo dominio** y la IP
nueva: detecta el `.env` existente, **reutiliza los secretos**, regenera
`docker-compose.yml`/config (nuevo `VIRTUAL_HOST` con la IP nueva) y **no toca la
base de datos**.

```bash
cd /opt/proyectos
sudo ./install.sh
# Dominio: <el mismo de antes>   |   IP LAN: <la nueva>
# Responde "s" a "ya parece instalado, re-generar config?"
```

Luego actualiza la IP en el `hosts`/DNS de las PCs (`set-hosts.sh`) o en el
FortiGate. (Borrar y reinstalar es justo lo que provoca el `Access denied` de
arriba.)

### Eliminar un dominio por completo

```bash
cd /opt/proyectos
sudo ./uninstall.sh --domain fe.dominio.org              # con confirmacion
sudo ./uninstall.sh --domain fe.dominio.org --with-backup # vuelca la BD antes
```

Borra contenedores + volumenes + carpeta de ESE dominio. No toca el proxy
compartido, los certificados ni los demas dominios.

### La carpeta quedo anidada (`<dominio>/<dominio>`)

Ocurria al ejecutar `install.sh` **desde dentro** de una carpeta. Ya no pasa: el
script se ancla a su propia ubicacion. Borra la carpeta mal creada con
`uninstall.sh` (o `rm -rf` si no llego a levantar contenedores) y reinstala.

### Puerto 80/443 ocupado (el proxy no levanta)

```bash
ss -tuln | grep -E ':80 |:443 '     # ver quien los usa
docker ps -a                         # ¿hay otro proxy/servicio?
```

El `nginx-proxy` es **uno solo y compartido**; no instales un segundo.

### La PC no abre `empresa1.fe.dominio.org`

1. Verificar linea en `hosts` apuntando a la IP LAN correcta.
2. Windows: `ipconfig /flushdns`.
3. Probar desde el servidor: `curl -H "Host: empresa1.fe.dominio.org" http://127.0.0.1/login`.

### Panel central abre pero el tenant da 404

- El tenant puede no existir aun en la tabla `hostnames`.
- Verificar que el subdominio se creo desde el panel (Clientes → Nuevo).
- Ejecutar `list-tenant-hosts.sh` y confirmar que aparece el fqdn.

### Error SQL / Access denied en tenant

```bash
docker exec fpm_fe_dominio_org sh -c "CACHE_DRIVER=file php artisan tenancy:key:update"
docker exec fpm_fe_dominio_org sh -c "CACHE_DRIVER=file php artisan config:cache"
```

### Certbot falla en DNS-01

- Verificar que el TXT `_acme-challenge` esta creado y propagado antes de Enter.
- Comprobar con: `dig TXT _acme-challenge.fe.dominio.org @8.8.8.8`.

### Puerto MySQL ocupado al instalar segundo dominio

- El script busca automaticamente un puerto libre. Si falla, revisar:
  `ss -tuln | grep 300` y `docker ps -a`.

### WebSocket / VendeMaster no conecta

- Fase 1: incluir `ws.fe.dominio.org` en el `hosts` de la PC.
- Fase 2: verificar certificado de `ws.fe.dominio.org` en `_infra/certs/`.

---

## 16. Datos que NO se deben borrar

| Recurso | Riesgo si se borra |
|---------|-------------------|
| Volumen `mysqldata*` | Perdida total de BD (system + todos los tenants) |
| Volumen `redisdata*` | Perdida de colas/sesiones en Redis |
| `.env` | Credenciales y configuracion irreversible sin backup |
| `_infra/certs/*.crt` / `*.key` | HTTPS deja de funcionar hasta re-emitir |
| `storage/app/backups/` | Unicos respaldos pre-update |

**Comandos prohibidos en produccion (salvo que quieras ELIMINAR el dominio):**

```bash
docker compose down -v          # borra volumenes
docker volume rm mysqldata1     # borra BD
docker system prune --volumes     # borra todo lo no usado incluyendo datos
```

Para detener contenedores sin perder datos: `docker compose down` (sin `-v`).

> ¿Quieres **eliminar** un dominio a proposito? No lo hagas a mano (deja
> volumenes huerfanos y luego el `Access denied` al reinstalar). Usa:
> `sudo ./uninstall.sh --domain <dominio>` — borra contenedores, volumenes y
> carpeta de forma ordenada y deja intacto el resto.
