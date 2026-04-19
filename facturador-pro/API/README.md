# API Contract — Modo Offline · Facturador Pro-8

> **Versión:** 1.0.0  
> **Fecha:** 2026-04-18  
> **Autor:** Equipo Pro-8  
> **Propósito:** Documentación de endpoints para la aplicación Flutter (modo offline / alta rotación de ventas)

---

## Visión General

Este documento describe el contrato de API para la aplicación offline del Facturador Pro-8, diseñada para **empresas de alta rotación de ventas** que necesitan operar con **mínimo tiempo de espera** y **resiliencia ante pérdida de conectividad**.

### Flujo de Operación

```
┌─────────────────────────────────────────────────────────────────┐
│                        DESCARGA INICIAL                         │
│  (requiere conexión a internet — una sola vez o periódicamente) │
│                                                                 │
│  1. POST /api/login ──────────────────── Token + Config         │
│  2. GET  /api/company ────────────────── Series, Clientes,      │
│                                          Métodos de pago        │
│  3. GET  /api/sellnow/items ──────────── Items (por sucursal)   │
│  4. GET  /api/sellnow/categories ─────── Categorías             │
│  5. GET  /api/offline/series-numbering ─ Series + última num.   │
│  6. GET  /api/pro8/catalogs/ubigeo ───── Ubigeo (dpto/prov/dist)│
│  7. GET  /api/restaurant/available-sellers ── Vendedores        │
│  8. GET  /api/cash/opening_cash ──────── Estado de caja         │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                     OPERACIÓN LOCAL (OFFLINE)                   │
│         (sin necesidad de conexión a internet)                  │
│                                                                 │
│  • Crear comprobantes localmente (Boleta, Factura, NV, NC, ND,  │
│    Guía Remitente, Guía Transportista)                          │
│  • Cada comprobante recibe un offline_id (UUID v4) generado     │
│    por Flutter para garantizar idempotencia                     │
│  • Numeración local basada en series-numbering descargado       │
│  • Crear clientes localmente usando ubigeo descargado           │
│  • Aperturar/cerrar caja localmente                             │
│                                                                 │
│  Estados: LOCAL → PENDIENTE_SYNC                                │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                SINCRONIZACIÓN EN SEGUNDO PLANO                  │
│             (cuando hay conexión disponible)                    │
│                                                                 │
│  POST /api/offline/sync-batch                                   │
│  • Envía lote de comprobantes pendientes                        │
│  • Backend verifica offline_id (idempotencia):                  │
│    - Si existe → retorna datos del documento existente          │
│    - Si no existe → crea el documento y persiste offline_id     │
│  • Registra automáticamente en la caja activa                   │
│                                                                 │
│  Estados: PENDIENTE_SYNC → SINCRONIZADO | ERROR                 │
└─────────────────────────────────────────────────────────────────┘
```

### Principios de Diseño

| Principio | Descripción |
|-----------|-------------|
| **Idempotencia** | Cada comprobante lleva un `offline_id` (UUID v4). Si el backend ya lo procesó, retorna el existente sin duplicar |
| **Series por vendedor** | Cada vendedor tiene series asignadas manualmente. No hay conflicto de numeración entre vendedores de la misma sucursal |
| **Datos por sucursal** | Items, series y warehouse se filtran por el establishment del usuario autenticado |
| **Offline-first** | La app funciona 100% sin internet. La sincronización es eventual y en segundo plano |
| **Orden de sincronización** | Las NC/ND requieren que el documento afectado esté sincronizado primero (necesitan `external_id` del backend) |

---

## Tabla de Contenidos

### Fase 1 — Descarga Inicial (datos para almacenamiento local)

| # | Documento | Endpoint | Descripción |
|---|-----------|----------|-------------|
| 01 | [Autenticación](endpoints/01-autenticacion.md) | `POST /api/login` | Login + token + config empresa |
| 02 | [Datos de Empresa](endpoints/02-datos-empresa.md) | `GET /api/company` | Series, clientes, métodos de pago |
| 03 | [Items y Categorías](endpoints/03-items-categorias.md) | `GET /api/sellnow/items` | Items filtrados por sucursal |
| 04 | [Series y Numeración](endpoints/04-series-numeracion.md) | `GET /api/offline/series-numbering` | Series del usuario + última numeración |
| 05 | [Ubigeo](endpoints/05-ubigeo.md) | `GET /api/pro8/catalogs/ubigeo` | Departamentos/Provincias/Distritos |
| 06 | [Vendedores](endpoints/06-vendedores.md) | `GET /api/restaurant/available-sellers` | Vendedores disponibles |
| 07 | [Caja](endpoints/07-caja.md) | `GET/POST /api/cash/*` | Apertura, cierre, verificación |
| 08 | [Clientes](endpoints/08-clientes.md) | `GET/POST /api/service/*` | DNI, RUC, crear cliente |

### Fase 2 — Comprobantes (payloads para creación)

| # | Documento | Endpoint | Código tipo |
|---|-----------|----------|-------------|
| 09 | [Boleta / Factura](endpoints/09-boleta-factura.md) | `POST /api/documents` | `03` / `01` |
| 10 | [Nota de Crédito](endpoints/10-nota-credito.md) | `POST /api/documents` | `07` |
| 11 | [Nota de Débito](endpoints/11-nota-debito.md) | `POST /api/documents` | `08` |
| 12 | [Nota de Venta](endpoints/12-nota-venta.md) | `POST /api/sale-note` | `80` |
| 13 | [Guía Remisión Remitente](endpoints/13-guia-remision-remitente.md) | `POST /api/dispatches` | `09` |
| 14 | [Guía Remisión Transportista](endpoints/14-guia-remision-transportista.md) | `POST /api/dispatch-carrier` | `31` |

### Fase 3 — Sincronización e Idempotencia

| # | Documento | Descripción |
|---|-----------|-------------|
| 15 | [Sync Batch](endpoints/15-sync-batch.md) | Endpoint de sincronización masiva |
| 16 | [Idempotencia](endpoints/16-idempotencia.md) | Estrategia de `offline_id` + migraciones |
| 17 | [Flujo Offline Completo](endpoints/17-flujo-offline-completo.md) | Diagrama E2E + estados + reintentos |
| 18 | [Fix Series Numbering](endpoints/18-fix-series-numbering.md) | Correcciones al endpoint de series |

### Fase 4 — Reportes y Configuración

| # | Documento | Endpoint |
|---|-----------|----------|
| 19 | [Reporte de Caja](endpoints/19-cash-report.md) | `GET /api/offline/cash-report/{cashId}` |
| 20 | [Configuración Offline](endpoints/20-configuracion-offline.md) | `GET/POST /offline-configurations/*` |

### Fase 5 — Productos, Inventario y Operaciones Avanzadas

| # | Documento | Endpoint / Tema |
|---|-----------|-----------------|
| 21 | [Productos CRUD](endpoints/21-productos-crud.md) | `POST /api/item`, `POST /api/items/{id}/update`, `GET /api/document/search-items` |
| 22 | [Inventario: Movimientos](endpoints/22-inventario-movimientos.md) | `POST /api/inventory/transaction` |
| 23 | [Stock por Establecimiento](endpoints/23-stock-por-establecimiento.md) | Arquitectura `item_warehouse`, descuento automático, `GET /api/offline/stock` |
| 24 | [Detracciones y Retención IGV](endpoints/24-detraccion-retencion-igv.md) | Campos `detraccion{}` y `retencion{}` en facturas |
| 25 | [Comprobante de Retención](endpoints/25-comprobante-retencion.md) | `POST /api/retentions` (tipo 20) |
| 26 | [Envío Diferido y Update Estado](endpoints/26-envio-diferido-update-estado.md) | `POST /api/documents/send`, `POST /api/documents/updatedocumentstatus` |
| 27 | [Contingencia](endpoints/27-contingencia.md) | Series `0xxx`, flujo contingencia desde Flutter |

---

## Autenticación

Todos los endpoints (excepto `POST /api/login`) requieren:

```
Authorization: Bearer {token}
```

El token se obtiene en el login y no expira mientras la sesión esté activa.

---

## Códigos de Tipo de Documento

| Código | Tipo | Serie ejemplo |
|--------|------|---------------|
| `01` | Factura Electrónica | F001 |
| `03` | Boleta de Venta Electrónica | B001 |
| `07` | Nota de Crédito Electrónica | FC01 / BC01 |
| `08` | Nota de Débito Electrónica | FD01 / BD01 |
| `09` | Guía de Remisión Remitente | T001 |
| `20` | Comprobante de Retención | R001 |
| `31` | Guía de Remisión Transportista | V001 |
| `80` | Nota de Venta | NV01 |

---

## Archivos del Backend Relevantes

| Archivo | Responsabilidad |
|---------|-----------------|
| `modules/Offline/Http/Controllers/OfflineSyncController.php` | Sincronización batch |
| `modules/Offline/Http/Controllers/SeriesNumberingController.php` | Series + numeración |
| `app/CoreFacturalo/Requests/Api/Transform/DocumentTransform.php` | Transformación payload documentos |
| `app/CoreFacturalo/Requests/Api/Transform/DispatchTransform.php` | Transformación payload guías |
| `app/Http/Controllers/Tenant/Api/DocumentController.php` | Creación de documentos (01/03/07/08) |
| `app/Http/Controllers/Tenant/Api/SaleNoteController.php` | Creación de notas de venta (80) |
| `app/Http/Controllers/Tenant/Api/DispatchController.php` | Creación de guías remitente (09) |
| `modules/Dispatch/Http/Controllers/Api/DispatchCarrierController.php` | Creación de guías transportista (31) |
