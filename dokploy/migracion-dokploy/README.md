# Migración VPS Dokploy — GEN1 → GEN2

Guía y scripts para migrar el servidor **`sv-sL70MwNvtQe8dPSO9aBE` (161.132.53.113)** de Elastika
desde infraestructura GEN1 a un nuevo VPS GEN2, conservando **toda la configuración, dominios,
certificados SSL, bases de datos y datos de las apps**.

El proveedor NO migra entre generaciones: hay que crear el GEN2 y migrar manualmente. Estos scripts
automatizan ese proceso a nivel Dokploy (NO clonado de disco/ISO, que no funciona entre hardware distinto).

---

## Inventario del servidor ORIGEN (escaneado en vivo 17/06/2026)

| Aspecto | Valor |
|---|---|
| SO | **Ubuntu 24.04.2 LTS**, kernel 6.8 |
| CPU / RAM | 8 vCPU / 30 GB |
| Disco | 630 GB, **63 GB usados** (tras limpiar Minecraft + huérfanos Grupo A) |
| Docker | **28.1.1** |
| Orquestador | **Docker Swarm — 1 nodo manager/leader** |
| Dokploy | **v0.29.8** (¡instalar EXACTA en GEN2!) |
| Servicios | 50 · Volúmenes | 49 |
| Usuario | `undc` (sudo sin password + grupo docker) |

### Datos a migrar (≈ 8 GB)
| Ruta | Peso | Qué contiene |
|---|---|---|
| `/etc/dokploy` | 329 MB | apps (build context), **traefik + `acme.json` SSL**, compose bind-mounts, monitoring |
| `/var/lib/docker/volumes` | ~7.5 GB | 49 volúmenes: **`dokploy-postgres-database`** (config Dokploy) + todas las BD |

> ⚠️ **Crítico:** `dokploy-postgres-database` guarda TODA la definición de tus proyectos/apps/dominios/envs.
> Y `acme.json` guarda los certificados SSL. Sin esos dos, no hay migración.

---

## Estrategia

1. Crear GEN2 (Ubuntu 24.04) e instalar **Dokploy v0.29.8 limpio** → arranca un Swarm nuevo.
2. Detener servicios y Docker en ambos lados.
3. Copiar (`rsync`) `/etc/dokploy` + `/var/lib/docker/volumes` de GEN1 → GEN2.
4. Arrancar Docker/Dokploy en GEN2 → lee su Postgres restaurado y muestra todos los proyectos.
5. **Redeploy** de cada app desde la UI de Dokploy → recrea los servicios Swarm apuntando a los datos ya restaurados.
6. DNS / IP.

**Por qué no copiar el estado de Swarm:** el raft de Swarm está atado a la identidad del nodo y la IP;
copiarlo entre máquinas es frágil. Dokploy recrea los servicios desde su propia base de datos al hacer Redeploy.

---

## La IP — CAMBIA (decisión tomada)

La IP **será nueva** en GEN2. El DNS lo manejas tú, así que:
- **1-2 días antes:** baja el **TTL de tus registros DNS a 300s** (5 min) para que el cambio propague rápido.
- **El día D (tras arrancar GEN2):** apunta todos los registros **A** de tus dominios a la **IP nueva**.
- Traefik **re-emitirá los certificados SSL** (Let's Encrypt) automáticamente cuando el dominio resuelva al GEN2.

> 👉 Guía paso a paso completa de inicio a fin: **`GUIA-COMPLETA.md`**.

---

## Orden de ejecución de los scripts

| # | Script | Dónde se ejecuta | Cuándo | Downtime |
|---|---|---|---|---|
| 1 | `01-backup-db-EN-GEN1.sh` | **GEN1** | Días antes / mismo día | No |
| 2 | `02-instalar-dokploy-EN-GEN2.sh` | **GEN2** | Días antes | No |
| 3 | `03-detener-EN-GEN1.sh` | **GEN1** | Inicio ventana | **Sí (empieza)** |
| 4 | `04-transferir-EN-GEN2.sh` | **GEN2** | Tras detener GEN1 | Sí |
| 5 | `05-arrancar-EN-GEN2.sh` | **GEN2** | Tras transferir | Sí |
| 6 | `06-verificar-EN-GEN2.sh` | **GEN2** | Al final | — |

Sigue además **`CHECKLIST.md`** paso a paso el día de la migración.

### Cómo subir los scripts a cada servidor
```bash
# Desde tu PC (ejemplo a GEN1):
scp 0*.sh undc@161.132.53.113:~/
# y a GEN2 cuando lo tengas:
scp 0*.sh undc@IP_GEN2:~/
```
Luego en el servidor: `chmod +x ~/0*.sh` y ejecutar el que corresponda.

---

## Pendientes que quedaron fuera (revisar tú con calma)

- **Grupo B (huérfanos anónimos, ~1.46 GB):** 4 volúmenes con nombre tipo hash (`38a12b…`, `572cb1…`,
  `3e6d7e…`, `64316148…`, del 2025-12-12). Casi seguro basura de tests; se migrarán igual salvo que los borres.
- **Grupo C (huérfanos CON datos, ~3 GB):** volúmenes `ntsuite-*`, `facturador-*`, `profactseis-*`,
  `produccin-phpmyadmin-*`, `estudiantes-clinica-*`, `rifas-bd-gl65xo-data`, etc. **NO se tocaron** — pueden
  tener datos reales (facturación, clínica). Se migran tal cual; depúralos después de validar.
- **3 servicios en 0 réplicas:** `ciisic-backendciisicvii-y17agg`, `estudiantes-sistramite-di5b2r`, `rifas-bd-gl65xo`.
- 🔒 **Rota la contraseña SSH de `undc`** al terminar (se compartió para el escaneo).
- 🔒 Tienes MySQL/Postgres/Redis expuestos a Internet (puertos 3306/3307/3308/13306/5431/5432/6379) — ciérralos con firewall si no los usas remotamente.
