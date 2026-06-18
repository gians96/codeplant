# Configuracion de las PCs cliente (archivo hosts)

Guia detallada para que los usuarios **dentro de la sede** accedan al facturador
por **nombre de dominio** mientras no exista DNS publico o split-horizon en el
FortiGate.

> Guia general del sistema: [`README.md`](README.md)
>
> Contexto tecnico: [`ARQUITECTURA-Y-CONTEXTO.md`](ARQUITECTURA-Y-CONTEXTO.md)

---

## Indice

1. [Por que se necesita el archivo hosts](#1-por-que-se-necesita-el-archivo-hosts)
2. [Que resuelve y que no resuelve](#2-que-resuelve-y-que-no-resuelve)
3. [Datos que necesitas antes de empezar](#3-datos-que-necesitas-antes-de-empezar)
4. [Obtener las lineas exactas desde el servidor](#4-obtener-las-lineas-exactas-desde-el-servidor)
5. [Windows — script automatico (recomendado)](#5-windows--script-automatico-recomendado)
6. [Windows — configuracion manual](#6-windows--configuracion-manual)
7. [Linux / Mac — script automatico](#7-linux--mac--script-automatico)
8. [Linux / Mac — configuracion manual](#8-linux--mac--configuracion-manual)
9. [Cuando se crea una empresa nueva](#9-cuando-se-crea-una-empresa-nueva)
10. [Varios dominios en el mismo servidor](#10-varios-dominios-en-el-mismo-servidor)
11. [Fase 2: que pasa cuando hay acceso publico](#11-fase-2-que-pasa-cuando-hay-acceso-publico)
12. [Verificacion y troubleshooting](#12-verificacion-y-troubleshooting)

---

## 1. Por que se necesita el archivo hosts

Pro-8 es multi-tenant: cada empresa se identifica por un **subdominio**:

```text
empresa1.fe.consurtrading.org
empresa2.fe.consurtrading.org
```

El servidor resuelve el tenant leyendo el header HTTP `Host`. Para que el
navegador envie ese nombre, la PC debe **saber que ese dominio apunta a la IP
LAN del servidor**.

En Fase 1 (sin DNS publico):

- No hay registro DNS que resuelva `*.fe.consurtrading.org`.
- No se puede usar `empresa1.192.168.1.100` (subdominio de IP invalido).
- Solucion: editar el archivo `hosts` de cada PC interna.

```text
192.168.1.100    empresa1.fe.consurtrading.org
```

El navegador pide `http://empresa1.fe.consurtrading.org`, la PC envia el
request a `192.168.1.100`, y el servidor identifica el tenant correctamente.

---

## 2. Que resuelve y que no resuelve

| Acceso | Requiere hosts? | URL ejemplo |
|--------|-----------------|-------------|
| Panel central por **IP** | **No** | `http://192.168.1.100/login` |
| Panel central por **nombre** | **Si** | `http://fe.consurtrading.org/login` |
| Tenant (empresa) por **nombre** | **Si** | `http://empresa1.fe.consurtrading.org/login` |
| WebSocket (VendeMaster/restaurant) | **Si** | `ws.fe.consurtrading.org` en hosts |

---

## 3. Datos que necesitas antes de empezar

| Dato | Ejemplo Consurtrading | Donde obtenerlo |
|------|----------------------|-----------------|
| IP LAN del servidor | `192.168.1.100` | Instalador / `hostname -I` en servidor |
| Dominio base | `fe.consurtrading.org` | Lo definiste en `install.sh` → `APP_URL_BASE` |
| Subdominios de empresas | `empresa1`, `empresa2` | Panel → Clientes, o `list-tenant-hosts.sh` |

---

## 4. Obtener las lineas exactas desde el servidor

Conectate por SSH a la VM del servidor y ejecuta:

```bash
cd /opt/proyectos/fe.consurtrading.org/app
bash scripts/list-tenant-hosts.sh
```

Salida ejemplo:

```text
# ---- pro-8 hosts (Consurtrading) ----
# Pegar en  Windows: C:\Windows\System32\drivers\etc\hosts
#           Linux/Mac: /etc/hosts
192.168.1.100    fe.consurtrading.org
192.168.1.100    ws.fe.consurtrading.org
192.168.1.100    empresa1.fe.consurtrading.org
192.168.1.100    empresa2.fe.consurtrading.org
# --------------------------------------
```

Copia esas lineas a cada PC que necesite acceder por nombre.

> El script lee la tabla `hostnames` de la base de datos, asi que siempre
> refleja las empresas **realmente creadas**.

---

## 5. Windows — script automatico (recomendado)

### Requisitos

- PowerShell **como Administrador**
- Archivo `set-hosts.ps1` (incluido en `install/onpremise/`)

### Uso basico (solo dominio base + WebSocket)

```powershell
.\set-hosts.ps1 -ServerIp 192.168.1.100 -BaseDomain fe.consurtrading.org
```

### Con empresas

```powershell
.\set-hosts.ps1 -ServerIp 192.168.1.100 -BaseDomain fe.consurtrading.org -Empresas empresa1,empresa2,empresa3
```

### Que hace el script

1. Abre `C:\Windows\System32\drivers\etc\hosts`.
2. Elimina el bloque previo entre marcadores `# >>> pro-8 ...` y `# <<< pro-8 ...`
   (idempotente — no duplica entradas).
3. Escribe el bloque nuevo con IP + dominios.
4. Ejecuta `ipconfig /flushdns` para aplicar de inmediato.

### Bloque generado (ejemplo)

```text
# >>> pro-8 (fe.consurtrading.org) >>>
192.168.1.100    fe.consurtrading.org
192.168.1.100    ws.fe.consurtrading.org
192.168.1.100    empresa1.fe.consurtrading.org
192.168.1.100    empresa2.fe.consurtrading.org
# <<< pro-8 (fe.consurtrading.org) <<<
```

---

## 6. Windows — configuracion manual

1. Abre el **Bloc de notas como Administrador**:
   - Inicio → escribe "Notepad" → clic derecho → "Ejecutar como administrador"
2. Archivo → Abrir → navega a:

```text
C:\Windows\System32\drivers\etc\hosts
```

3. Cambia filtro de "Documentos de texto" a **"Todos los archivos"**.
4. Agrega al final las lineas del paso 4.
5. Guarda.
6. Abre CMD o PowerShell y ejecuta:

```cmd
ipconfig /flushdns
```

7. Prueba en el navegador: `http://empresa1.fe.consurtrading.org/login`

---

## 7. Linux / Mac — script automatico

### Requisitos

- `sudo`
- Archivo `set-hosts.sh`

```bash
chmod +x set-hosts.sh
sudo ./set-hosts.sh 192.168.1.100 fe.consurtrading.org empresa1 empresa2
```

Solo dominio base (sin empresas aun):

```bash
sudo ./set-hosts.sh 192.168.1.100 fe.consurtrading.org
```

El script escribe en `/etc/hosts` con los mismos marcadores idempotentes que la
version Windows.

---

## 8. Linux / Mac — configuracion manual

```bash
sudo nano /etc/hosts
```

Agrega las lineas al final, guarda (Ctrl+O, Enter, Ctrl+X).

Verificar:

```bash
ping -c 1 empresa1.fe.consurtrading.org
# Debe resolver a 192.168.1.100
```

---

## 9. Cuando se crea una empresa nueva

Cada vez que creas un cliente en el panel (subdominio nuevo), **las PCs que
vayan a usar esa empresa** necesitan la nueva linea en `hosts`.

### Procedimiento recomendado

1. Crear empresa en panel central → Clientes → Nuevo (ej. subdominio `empresa3`).
2. En el servidor:

```bash
cd /opt/proyectos/fe.consurtrading.org/app
bash scripts/list-tenant-hosts.sh
```

3. En cada PC, re-ejecutar el helper **incluyendo la empresa nueva**:

```powershell
# Windows
.\set-hosts.ps1 -ServerIp 192.168.1.100 -BaseDomain fe.consurtrading.org -Empresas empresa1,empresa2,empresa3
```

```bash
# Linux
sudo ./set-hosts.sh 192.168.1.100 fe.consurtrading.org empresa1 empresa2 empresa3
```

O agregar manualmente una sola linea:

```text
192.168.1.100    empresa3.fe.consurtrading.org
```

> **No hace falta reiniciar el servidor** al crear empresas. Solo actualizar hosts en PCs.

---

## 10. Varios dominios en el mismo servidor

Si instalaste dos dominios (ej. `fe.consurtrading.org` y `fact.otraempresa.com`)
en el **mismo servidor con la misma IP**, cada PC necesita entradas para **ambos**:

```text
192.168.1.100    fe.consurtrading.org
192.168.1.100    ws.fe.consurtrading.org
192.168.1.100    empresa1.fe.consurtrading.org

192.168.1.100    fact.otraempresa.com
192.168.1.100    ws.fact.otraempresa.com
192.168.1.100    cliente1.fact.otraempresa.com
```

Ejecuta `list-tenant-hosts.sh` en **cada** carpeta de proyecto y combina las
lineas (omitir duplicados de IP si ya estan).

---

## 11. Fase 2: que pasa cuando hay acceso publico

Tras emitir SSL (`ssl.sh`) y que el admin de red configure DNS publico + FortiGate:

| Usuario | Como accede | Necesita hosts? |
|---------|-------------|-----------------|
| **Fuera de la sede** | `https://empresa1.fe.consurtrading.org` via DNS publico | **No** |
| **Dentro de la sede (con DNS FortiGate)** | Resuelve local automaticamente | **No** |
| **Dentro de la sede (sin DNS FortiGate)** | hosts → LAN (mas rapido, sin salir a internet) | **Si** |

### Objetivo: DNS local en el FortiGate (reemplaza los hosts por PC)

Los archivos `hosts` por PC son el **fallback temporal** mientras el admin del
FortiGate no este disponible. La configuracion objetivo es una **zona DNS en el
FortiGate** por cada dominio base (mas rapida y funciona **sin internet**):

```text
config system dns-database → zona "fe.consurtrading.org":
  @    A   192.168.1.100
  *    A   192.168.1.100    ← si la version de FortiOS no soporta wildcard,
                              una entrada por tenant (list-tenant-hosts.sh)
  ws   A   192.168.1.100
```

- El **DHCP** de la LAN debe entregar el FortiGate como servidor DNS.
- Con esto, **retirar** las entradas pro-8 del hosts de las PCs.
- El checklist completo por dominio queda en `/opt/proyectos/<dominio>/<dominio>-onprem.txt`
  (seccion "PENDIENTES ADMIN DE RED").

---

## 12. Verificacion y troubleshooting

### Verificar resolucion DNS local

**Windows:**

```cmd
ping fe.consurtrading.org
ping empresa1.fe.consurtrading.org
```

**Linux/Mac:**

```bash
getent hosts empresa1.fe.consurtrading.org
```

Debe mostrar `192.168.1.100` (o la IP LAN correcta).

### El navegador abre otra pagina o error de conexion

1. Confirmar que la IP en hosts es la de la **VM correcta** (no la del ESXi
   `192.168.1.3`, sino la de la VM Ubuntu donde corre Docker).
2. Confirmar que el stack esta arriba en el servidor:

```bash
cd /opt/proyectos/fe.consurtrading.org/app
docker compose ps
```

3. Probar desde el servidor:

```bash
curl -I -H "Host: empresa1.fe.consurtrading.org" http://127.0.0.1/login
```

Debe responder HTTP 200 o 302 (redirect a login), no 404.

### Windows: "Acceso denegado" al guardar hosts

- Abrir Notepad **como Administrador**.
- O usar `set-hosts.ps1` en PowerShell admin.

### Cambie la IP del servidor

Re-ejecutar el helper con la IP nueva en **todas** las PCs. El bloque idempotente
reemplaza el anterior.

### HTTPS desde PC interna con hosts

Si `ssl.sh` ya emitio el certificado (se puede desde la Fase 1, sin IP publica):

- Acceder por `https://empresa1.fe.consurtrading.org`
- El certificado es valido si se emitio correctamente con Let's Encrypt
- Si el hosts apunta a LAN, el trafico va directo al servidor sin pasar por
  FortiGate (split-horizon)

---

## Referencia rapida de archivos

| SO | Ruta del archivo hosts |
|----|------------------------|
| Windows | `C:\Windows\System32\drivers\etc\hosts` |
| Linux | `/etc/hosts` |
| macOS | `/etc/hosts` |

| Helper | Plataforma |
|--------|------------|
| `set-hosts.ps1` | Windows (PowerShell admin) |
| `set-hosts.sh` | Linux / macOS (sudo) |
| `list-tenant-hosts.sh` | Servidor (genera lineas) |
