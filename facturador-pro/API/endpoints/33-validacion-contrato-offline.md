# 33 — Validación del Contrato Offline (Invariantes Multi-Usuario)

> Revisión consolidada del contrato para Flutter offline.  
> Garantiza 4 invariantes críticos para operación multi-usuario en un mismo establecimiento.

---

## Principios Fundamentales

Toda operación offline en Pro-8 se apoya en **4 invariantes** que deben respetarse en cliente y servidor:

1. **Series por usuario (sin colisiones):** Cada operador consume una serie (o conjunto de series) distinta para evitar duplicar correlativos con otros vendedores del mismo establecimiento.
2. **Items por establecimiento:** Un usuario sólo ve/vende los items asignados al almacén de su establecimiento.
3. **Idempotencia por `offline_id`:** Re-envíos del mismo documento nunca crean duplicados.
4. **Stock y lotes por almacén:** Stock, lotes agrupados (`ItemLotsGroup`) y series (`ItemLot`) se filtran por el warehouse del establecimiento del usuario autenticado.

---

## Invariante 1 — Series por Usuario

### Fuente única de verdad

Flutter **debe** consumir exclusivamente las series retornadas por:

```
GET /api/offline/series-numbering
```

El controller filtra en 3 modos (ver [04-series-numeracion.md](04-series-numeracion.md) y [18-fix-series-numbering.md](18-fix-series-numbering.md)):

| Modo | Campo `users` | Series devueltas |
|------|---------------|------------------|
| **Múltiple** | `multiple_default_document_types = true` + pivot `user_default_document_types` | Solo las del pivot |
| **Simple** | `users.series_id` (no null) | Solo esa serie |
| **Sin asignación** | Ambos null / vacío | Todas las del establecimiento |

### Regla para Flutter

- Al login, descarga series y **cachéalas**. No asumir series hardcodeadas.
- Al emitir offline: `nuevo_numero = last_number + 1` y **siempre** usar `number` (ej: `B001`) + `document_type_id` del listado descargado.
- Si la serie no aparece en el listado → **no la uses**, aunque el operador la recuerde de memoria.
- **No enviar `numero_documento: "#"` en modo offline.** Enviar el número concreto calculado localmente. El `"#"` implica auto-asignación por el servidor y puede colisionar si dos vendedores emiten simultáneamente.

### Riesgo si se ignora

Vendedor A (B001) y Vendedor B (B002) operan en paralelo offline. Si ambos usan `B001` por error, al sincronizar el segundo obtendrá error 1062 (UNIQUE violation en `filename`). `sync-batch` maneja el caso (ver [15-sync-batch.md](15-sync-batch.md)) **pero** el documento del segundo se rechaza como duplicado.

### Contingencia (series `0###`)

Si el tenant tiene series de contingencia, **también se filtran por usuario** (tienen el mismo `establishment_id` y pasan por el mismo filtro). Flutter puede distinguirlas por el flag `contingency: true` en la respuesta.

---

## Invariante 2 — Items por Establecimiento

### Fuente de verdad

```
GET /api/document/search-items
```

Aplica el scope `Item::scopeWhereWarehouse()`:

```php
// app/Models/Tenant/Item.php L467
$establishment_id = auth()->user()->establishment_id;
$warehouse = Warehouse::where('establishment_id', $establishment_id)->first();
return $query->whereHas('warehouses', function ($q) use ($warehouse) {
    $q->where('warehouse_id', $warehouse->id);
})->orWhere('unit_type_id', 'ZZ');
```

### Reglas para Flutter

- El catálogo local de items **solo contiene** los items del establecimiento del usuario logueado.
- Al cambiar de establecimiento (re-login con otro usuario), **purgar el catálogo** antes de descargar el nuevo.
- El campo `unit_type_id == 'ZZ'` (servicios) se entrega a todos los usuarios (no tiene warehouse).

### Relacionados que respetan la misma regla

| Endpoint | Filtrado |
|----------|----------|
| `GET /api/offline/stock` | `warehouse_id = establishment.warehouse` ([23-stock-por-establecimiento.md](23-stock-por-establecimiento.md)) |
| `GET /api/offline/item-lots-group` | items del warehouse del establecimiento ([30-lotes-series-farmacia.md](30-lotes-series-farmacia.md)) |
| `GET /api/pro8/item-lots/records` | `warehouse_id` del usuario |

---

## Invariante 3 — Idempotencia por `offline_id`

### Protocolo

Flutter genera un **UUID v4 único por documento** antes de emitirlo offline. Ese `offline_id` viaja en:

- El cuerpo de cada elemento de `sync-batch` (`{ offline_id, doc_type, data }`)
- Se persiste en la tabla correspondiente: `documents.offline_id`, `sale_notes.offline_id`, `dispatches.offline_id`, `retentions.offline_id`

### Flujo de `sync-batch`

```
Para cada sale:
  1. Si offline_id existe en BD → retornar registro existente (success: true, was_duplicate: true)
  2. Si no existe → procesar normalmente
  3. Al crear, grabar offline_id en la fila creada
```

Ver [16-idempotencia.md](16-idempotencia.md) y [15-sync-batch.md](15-sync-batch.md).

### Reglas para Flutter

- **Nunca regenerar `offline_id`** tras un error de red. Reintentar con el mismo UUID.
- **No reutilizar `offline_id`** entre documentos distintos (ni siquiera si el primero fue rechazado). Cada documento emitido offline tiene su propio UUID.
- Persistir el `offline_id` en SQLite junto con el payload antes de intentar enviar.
- Tras respuesta exitosa del servidor, **mapear** `offline_id → server_id` en la BD local para referencias futuras (notas de crédito, anulaciones, etc.).

### Estados locales sugeridos

```sql
CREATE TABLE pending_documents (
  offline_id TEXT PRIMARY KEY,          -- UUID v4
  doc_type TEXT,
  payload JSON,
  status TEXT,                          -- pending|synced|rejected
  server_id INTEGER,                    -- asignado tras sync exitoso
  server_number TEXT,                   -- ej: "B001-90"
  external_id TEXT,                     -- UUID del backend
  error_message TEXT,
  attempts INTEGER DEFAULT 0,
  created_at DATETIME,
  last_attempt_at DATETIME
);
```

### Casos borde

| Caso | Comportamiento correcto |
|------|-------------------------|
| Timeout tras enviar (no sé si llegó) | Reintentar con mismo `offline_id` → idempotencia resuelve |
| Error 1062 (UNIQUE `filename`) | `sync-batch` retorna el registro existente como éxito |
| Dos dispositivos del mismo usuario sincronizan en paralelo | El primero gana; el segundo obtiene `was_duplicate: true` |
| Usuario elimina la app y reinstala | Re-login + descarga series. `offline_id`s locales se pierden — documentos no sincronizados quedan huérfanos (recuperación manual) |

---

## Invariante 4 — Stock y Lotes por Almacén

### Filtrado aplicado en endpoints

| Endpoint | Columna / scope |
|----------|-----------------|
| `GET /api/offline/stock` | `item_warehouse.warehouse_id = establecimiento.warehouse` |
| `GET /api/offline/item-lots-group` | `items` asociados al warehouse del establecimiento |
| `POST /api/documents` (descuento) | `InventoryKardexServiceProvider` descuenta del warehouse del `establishment_id` del document |

### Regla para Flutter

- El stock local reflejado en la UI es el del **único warehouse** del establecimiento del usuario.
- Si el tenant maneja multi-almacén por establecimiento, Flutter NO debe permitir cambiar de warehouse — el backend siempre impone el del establecimiento.
- Al descontar lotes localmente (FEFO), operar **solo** sobre los lotes descargados del endpoint (no usar lotes de otros establecimientos aunque se vieran en un reporte).

---

## Matriz de Verificación (Checklist de Flutter)

| # | Verificación | Fuente del dato |
|---|--------------|-----------------|
| ✅ | Serie consumida viene del endpoint `series-numbering` | [04](04-series-numeracion.md) |
| ✅ | `last_number` local se actualiza tras cada emisión | [04](04-series-numeracion.md) |
| ✅ | Items del catálogo son solo del establecimiento | [03](03-items-categorias.md), [21](21-productos-crud.md) |
| ✅ | Stock es del warehouse del establecimiento | [23](23-stock-por-establecimiento.md) |
| ✅ | Lotes descargados respetan warehouse | [30](30-lotes-series-farmacia.md) |
| ✅ | Cada documento offline tiene `offline_id` UUID v4 | [16](16-idempotencia.md) |
| ✅ | Reintentos usan el **mismo** `offline_id` | [16](16-idempotencia.md) |
| ✅ | `numero_documento` se calcula localmente (no `"#"`) en offline | [04](04-series-numeracion.md), [15](15-sync-batch.md) |
| ✅ | `external_id` del backend se guarda tras cada sync exitoso | [15](15-sync-batch.md) |
| ✅ | Giros de negocio detectados vía `business-turns` | [28](28-giros-de-negocio.md) |
| ✅ | Payload grifo incluye `plate_number` + atributo `7000` | [29](29-grifo-placas.md) |
| ✅ | Payload farmacia envía `IdLoteSelected` por item con lotes | [30](30-lotes-series-farmacia.md) |
| ✅ | Payload hotel/transport envía bloques completos | [31](31-hotel-transporte-restaurante.md) |

---

## Matriz de Verificación (Checklist de Backend)

| # | Verificación | Ubicación |
|---|--------------|-----------|
| ✅ | `SeriesNumberingController` filtra por `user->series_id` o pivot | `SeriesNumberingController.php` |
| ✅ | `MobileController::searchItems` aplica `whereWarehouse()` | `MobileController.php L455` |
| ✅ | `StockController` filtra por `establishment.warehouse` | `StockController.php L20` |
| ✅ | `ItemLotController` filtra por items del warehouse | `ItemLotController.php L35-L42` |
| ✅ | `OfflineSyncController::checkOfflineIdExists` evita duplicados | `OfflineSyncController.php L140` |
| ✅ | `documents/sale_notes/dispatches/retentions` tienen columna `offline_id` UNIQUE | Migraciones |
| ✅ | Validación `filename` UNIQUE en BD captura colisión de serie/número | Schema constraint |
| ✅ | `BusinessTurnController` retorna config por tenant | `BusinessTurnController.php` |

---

## Flujo de Arranque Recomendado

```
┌─────────────────────────────────────────────────┐
│ POST /api/login                                  │
│  → token + user{establishment_id, series_id,...} │
└─────────────────────────────────────────────────┘
                      │
                      ▼
     ┌────────────────┴────────────────┐
     ▼                ▼                ▼
┌───────────┐  ┌──────────────┐  ┌───────────────┐
│ series-   │  │ business-    │  │ search-items  │
│ numbering │  │ turns        │  │ (catálogo)    │
└───────────┘  └──────────────┘  └───────────────┘
     │                │                │
     ▼                ▼                ▼
┌─────────────────────────────────────────────────┐
│ stock  +  item-lots-group (si is_pharmacy)      │
└─────────────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────┐
│ Flutter listo para operar OFFLINE                │
│  - Emite docs con números calculados localmente  │
│  - Cada doc lleva offline_id (UUID v4)           │
│  - Se guardan en SQLite status=pending           │
└─────────────────────────────────────────────────┘
                      │
             (vuelve la conexión)
                      ▼
┌─────────────────────────────────────────────────┐
│ POST /api/offline/sync-batch                     │
│  → Backend: idempotencia por offline_id          │
│  → Flutter: marca synced y guarda server_id      │
└─────────────────────────────────────────────────┘
```

---

## Resumen Ejecutivo

Pro-8 ya implementa los 4 invariantes en backend. Flutter debe:

1. **Cargar sólo datos del backend** — Series, items, stock y lotes son derivados del usuario autenticado. No asumir ni hardcodear.
2. **Generar UUID v4 como `offline_id`** antes de emitir y no cambiarlo nunca.
3. **Calcular números localmente** (`last_number + 1`) sin usar `"#"` en modo offline.
4. **Reintentar con mismo payload** si hay fallos de red — la idempotencia del backend lo resolverá.
5. **Purgar datos locales** al cambiar de usuario/establecimiento — nunca mezclar catálogos.
