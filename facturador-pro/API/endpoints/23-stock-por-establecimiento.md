# 23 — Stock por Establecimiento

> **Modelo:** `item_warehouse` (tabla `item_warehouse`)  
> **Relación:** Cada establecimiento tiene exactamente 1 almacén (warehouse)

---

## Descripción

El stock en Pro-8 se gestiona **por almacén**, y cada establecimiento (sucursal/local) tiene un almacén asociado. Cuando se emite un comprobante, el stock se descuenta automáticamente del almacén correspondiente.

---

## Arquitectura del Stock

```
Establishment (Establecimiento/Sucursal)
    └── Warehouse (Almacén) ── 1:1
            └── ItemWarehouse ── 1:N
                    ├── item_id: 1   → stock: 95
                    ├── item_id: 2   → stock: 200
                    └── item_id: 3   → stock: 0
```

### Tabla `item_warehouse`

| Columna | Tipo | Descripción |
|---------|------|-------------|
| `item_id` | int | FK → `items.id` |
| `warehouse_id` | int | FK → `warehouses.id` |
| `stock` | decimal | Cantidad actual en ese almacén |

> **PK compuesta:** `(item_id, warehouse_id)` — un item tiene un registro de stock por cada almacén.

---

## Descuento Automático de Stock

### Flujo al emitir comprobante

```
Facturalo::save()
  └── Document::create($inputs)
        └── foreach items → $document->items()->create($row)
              └── [MODEL EVENT] DocumentItem::created
                    └── InventoryKardexServiceProvider
                          ├── createInventoryKardex()  // Registro kardex
                          └── updateStock()            // Actualiza item_warehouse
```

### Factor de stock según tipo de documento

| Tipo documento | Factor | Efecto |
|----------------|--------|--------|
| `01` Factura | `-1` | Descuenta stock |
| `03` Boleta | `-1` | Descuenta stock |
| `07` Nota de Crédito | `+1` | **Devuelve** stock |
| `08` Nota de Débito | `-1` | Descuenta stock |
| `80` Nota de Venta | `-1` | Descuenta stock |
| `09` / `31` Guía | No afecta stock | Solo traslado |

### Código relevante (referencia)

```php
// modules/Inventory/Providers/InventoryKardexServiceProvider.php
DocumentItem::created(function (DocumentItem $document_item) {
    $factor = ($document->document_type_id === '07') ? 1 : -1;
    
    // Determinar almacén
    $warehouse = ($document_item->warehouse_id) 
        ? $this->findWarehouseById($document_item->warehouse_id)
        : $this->findWarehouse(); // del establecimiento del usuario
    
    // Registrar en kardex
    $this->createInventoryKardex($document, $item_id, $quantity * $factor, $warehouse->id);
    
    // Actualizar stock
    $this->updateStock($item_id, $quantity * $factor, $warehouse->id);
});
```

### Control de stock

```php
// modules/Inventory/Traits/InventoryTrait.php
private function updateStock($item_id, $quantity, $warehouse_id) {
    $item_warehouse = ItemWarehouse::firstOrNew([
        'item_id' => $item_id, 
        'warehouse_id' => $warehouse_id
    ]);
    $item_warehouse->stock += $quantity; // quantity ya viene negativo para ventas
    
    // Validación: si stock_control está activo y queda < 0
    if ($quantity < 0 && $inventory_configuration->stock_control && $item_warehouse->stock < 0) {
        throw new Exception("El producto {$description} no tiene suficiente stock!");
    }
    $item_warehouse->save();
}
```

> **`stock_control`:** Es una configuración global. Si está activado, impide vender si no hay stock suficiente. La excepción se captura en `OfflineSyncController` y se retorna como error individual del item en el batch (no rompe el batch completo).

---

## Descarga de Stock para Flutter

### Opción 1: Via descarga de items (ya existente)

```
GET /api/document/search-items
```

Cada item incluye el array `warehouses[]` con stock por almacén:

```json
{
    "id": 3,
    "internal_id": "PROD001",
    "description": "Aceite de Oliva",
    "warehouses": [
        {
            "warehouse_id": 1,
            "warehouse_description": "Almacén Sede Lima",
            "stock": "95.0000"
        },
        {
            "warehouse_id": 2,
            "warehouse_description": "Almacén Sede Arequipa",
            "stock": "30.0000"
        }
    ]
}
```

### Opción 2: Endpoint dedicado de stock (módulo Offline)

```
GET /api/offline/stock
Authorization: Bearer {token}
```

Retorna solo el stock del establecimiento del usuario autenticado (más ligero para sync delta):

```json
{
    "success": true,
    "data": {
        "warehouse_id": 1,
        "warehouse_description": "Almacén Sede Lima",
        "establishment_id": 1,
        "items": [
            {
                "item_id": 3,
                "internal_id": "PROD001",
                "description": "Aceite de Oliva",
                "stock": "95.0000"
            },
            {
                "item_id": 5,
                "internal_id": "PROD002",
                "description": "Vinagre 500ml",
                "stock": "200.0000"
            }
        ]
    }
}
```

---

## Manejo de Stock en Flutter (Offline)

### Flujo recomendado

```
┌─────────────────────────────────────────────────────┐
│               DESCARGA INICIAL                       │
│                                                      │
│  GET /api/document/search-items                      │
│  → Guardar items[] con warehouses[].stock en SQLite  │
│  → warehouse_id del establishment del usuario        │
└─────────────────────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────┐
│              OPERACIÓN OFFLINE                        │
│                                                      │
│  Al crear comprobante:                               │
│  1. Verificar stock local ≥ cantidad                 │
│  2. Si OK → crear comprobante + descontar stock      │
│     local en SQLite                                  │
│  3. Si NO → mostrar alerta (puede permitir o no     │
│     según config)                                    │
│                                                      │
│  Estado local: stock_servidor - Σ ventas_offline      │
└─────────────────────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────┐
│              SINCRONIZACIÓN                           │
│                                                      │
│  POST /api/offline/sync-batch                        │
│  → Backend descuenta stock real (Model Events)       │
│  → Si stock_control activo y stock < 0:              │
│    responde error INDIVIDUAL para ese comprobante    │
│    (el batch continúa con los demás)                 │
│                                                      │
│  Post-sync:                                          │
│  GET /api/offline/stock (o search-items)             │
│  → Actualizar stock local con valores reales del     │
│    servidor                                          │
└─────────────────────────────────────────────────────┘
```

### Conflictos de stock

| Escenario | Qué pasa |
|-----------|----------|
| Vendedor A y B venden el mismo producto offline | Ambos descuentan localmente. Al sincronizar, el primero pasa OK. El segundo puede fallar si `stock_control=true` y ya no hay stock |
| `stock_control = false` | El stock puede quedar negativo. No hay error, todo se sincroniza |
| `stock_control = true` + stock insuficiente | El comprobante falla al sincronizar con mensaje: `"El producto X no tiene suficiente stock!"`. Se reporta como error individual en sync-batch |

### Recomendación para Flutter

1. **Descargar stock** al inicio de cada turno/apertura de caja
2. **Descontar localmente** cada venta del stock en SQLite
3. **Mostrar alertas** si stock local ≤ `stock_min` 
4. **Permitir venta aunque stock sea 0** si `stock_control = false` (configuración descargada)
5. **Re-sincronizar stock** después de cada batch exitoso
6. **warehouse_id** en items: enviar siempre el `warehouse_id` del establecimiento del vendedor para asegurar descuento correcto

---

## Notas para Offline

- **El stock se descuenta AUTOMÁTICAMENTE** al crear DocumentItem/SaleNoteItem. No hay que llamar a ningún endpoint adicional de stock al emitir un comprobante.
- **warehouse_id en items:** Si se envía `warehouse_id` en cada item del comprobante, se descuenta de ese almacén específico. Si no se envía, se usa el del establecimiento del usuario autenticado.
- **Guías de remisión (09/31):** NO descuentan stock. Solo representan traslado.
- **Nota de crédito (07):** DEVUELVE stock (factor +1).
- **Unidad `ZZ`:** Los items con unidad `ZZ` (sin stock) no validan stock aunque `stock_control=true`.
