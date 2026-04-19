# 20 — Configuración Offline

> **Endpoints auxiliares** para configurar y gestionar el modo offline.

---

## 1. Estado del Módulo Offline

> `GET /api/offline/status`  
> **Controller:** `Modules\Offline\Http\Controllers\OfflineConfigController@status`

### Response (200 OK)

```json
{
    "success": true,
    "data": {
        "module_enabled": true,
        "last_sync": "2026-04-18T14:30:00.000000Z",
        "pending_count": 0,
        "version": "1.0.0"
    }
}
```

---

## 2. Tablas Auxiliares de Despacho

> `GET /api/dispatches/tables`  
> **Controller:** `Tenant\Api\DispatchController@tables`

### Response (200 OK)

Retorna catálogos necesarios para crear guías de remisión:

```json
{
    "transfer_reason_types": [
        { "id": "01", "description": "Venta" },
        { "id": "02", "description": "Compra" },
        { "id": "04", "description": "Traslado entre establecimientos" }
    ],
    "transport_mode_types": [
        { "id": "01", "description": "Transporte público" },
        { "id": "02", "description": "Transporte privado" }
    ],
    "unit_types": [
        { "id": "KGM", "description": "Kilogramo" },
        { "id": "TNE", "description": "Tonelada" }
    ]
}
```

> Descargar una vez y almacenar localmente si la app maneja guías de remisión.

---

## 3. Tipo de Cambio del Día

> `GET /api/service/exchange-rate`  
> **Controller:** `Tenant\Api\ServiceController@exchangeRate`

### Response

```json
{
    "success": true,
    "data": {
        "date": "2026-04-18",
        "purchase": 3.725,
        "sale": 3.730
    }
}
```

> Se usa cuando `codigo_tipo_moneda = "USD"`. Descargar al inicio del día y usar localmente.

---

## 4. Búsqueda de Items (con internet)

> `GET /api/sellnow/search-items?input={query}`  
> **Controller:** `Tenant\Api\SellnowController@searchItems`

Busca items por nombre, código interno o código de barras. Útil para refrescar catálogo parcial cuando hay internet.

---

## 5. Impresión de Comprobante

> `GET /api/print/document/{external_id}/ticket`  
> `GET /api/print/sale-note/{external_id}/ticket`

Retorna HTML del ticket para impresión. Solo disponible después de sincronizar.

Para impresión offline (antes de sincronizar), Flutter debe generar el ticket localmente usando los datos almacenados en SQLite.

---

## Resumen de Endpoints por Fase

### Fase 1: Descarga Inicial (con internet)

| # | Endpoint | Referencia |
|---|----------|------------|
| 1 | `POST /api/login` | [01-autenticacion.md](01-autenticacion.md) |
| 2 | `GET /api/company` | [02-datos-empresa.md](02-datos-empresa.md) |
| 3 | `GET /api/sellnow/items` | [03-items-categorias.md](03-items-categorias.md) |
| 4 | `GET /api/sellnow/categories` | [03-items-categorias.md](03-items-categorias.md) |
| 5 | `GET /api/offline/series-numbering` | [04-series-numeracion.md](04-series-numeracion.md) |
| 6 | `GET /api/pro8/catalogs/ubigeo` | [05-ubigeo.md](05-ubigeo.md) |
| 7 | `GET /api/restaurant/available-sellers` | [06-vendedores.md](06-vendedores.md) |
| 8 | `GET /api/cash/opening_cash` | [07-caja.md](07-caja.md) |
| 9 | `GET /api/dispatches/tables` | Este archivo |
| 10 | `GET /api/service/exchange-rate` | Este archivo |

### Fase 2: Operación Offline (sin internet)

- Crear comprobantes usando datos locales
- Ver [17-flujo-offline-completo.md](17-flujo-offline-completo.md)

### Fase 3: Sincronización (con internet)

| # | Endpoint | Referencia |
|---|----------|------------|
| 1 | `POST /api/offline/sync-batch` | [15-sync-batch.md](15-sync-batch.md) |

### Fase 4: Post-Sync

| # | Endpoint | Referencia |
|---|----------|------------|
| 1 | `GET /api/offline/series-numbering` | Actualizar numeración |
| 2 | `GET /api/offline/cash-report/{id}` | [19-cash-report.md](19-cash-report.md) |
| 3 | `GET /api/cash/close/{id}` | [07-caja.md](07-caja.md) |
