# 30 — Lotes, Series y Farmacia (DIGEMID)

> **Giro:** `pharmacy` (id=5) — Farmacia  
> **Auth:** `Bearer {token}`

---

## Descripción

Pro-8 maneja **dos sistemas independientes** de trazabilidad en items:

1. **Lotes agrupados** (`lots_enabled`) — Para farmacia, alimentos, químicos. Un lote tiene código, cantidad disponible y fecha de vencimiento.
2. **Series individuales** (`series_enabled`) — Para electrónicos, equipos. Cada unidad tiene un número de serie único.

Ambos sistemas son **mutuamente excluyentes por item** (un item usa lotes O series, no ambos).

---

## 1. Lotes Agrupados (`ItemLotsGroup`)

### Modelo y schema

**Tabla:** `item_lots_group`

| Columna | Tipo | Descripción |
|---------|------|-------------|
| `id` | int | PK |
| `code` | string | Código del lote (ej: `"LOT-2026-001"`) |
| `quantity` | decimal(12,4) | Cantidad disponible **actual** |
| `old_quantity` | decimal(12,4) | Cantidad original (historial) |
| `date_of_due` | date | Fecha de vencimiento |
| `item_id` | int | FK → `items.id` |

> **Ref:** `modules/Item/Models/ItemLotsGroup.php`

### Descarga de lotes por item

```
GET /api/offline/item-lots-group?item_id={id}
Authorization: Bearer {token}
```

> **Filtrado por establecimiento:** El endpoint sólo retorna lotes de items asignados al **warehouse del establecimiento** del usuario autenticado. Consistente con `search-items` y `/api/offline/stock` (ver [33-validacion-contrato-offline.md](33-validacion-contrato-offline.md)).

**Query params:**

| Parámetro | Tipo | Requerido | Descripción |
|-----------|------|-----------|-------------|
| `item_id` | int | No | Si se envía, filtra por item |
| `only_available` | bool | No | `true` = solo lotes con `quantity > 0` (default) |

**Response (200):**
```json
{
    "success": true,
    "data": [
        {
            "id": 101,
            "item_id": 25,
            "item_description": "Paracetamol 500mg x 10 tabletas",
            "cod_digemid": "E1234567",
            "code": "LOT-2026-001",
            "quantity": 150,
            "date_of_due": "2027-06-30",
            "days_to_expire": 437
        },
        {
            "id": 102,
            "item_id": 25,
            "item_description": "Paracetamol 500mg x 10 tabletas",
            "cod_digemid": "E1234567",
            "code": "LOT-2026-002",
            "quantity": 50,
            "date_of_due": "2026-12-15",
            "days_to_expire": 240
        }
    ]
}
```

> **Ordenamiento:** Los lotes se retornan ordenados por `date_of_due ASC` (FEFO — First Expired First Out).

### Envío de lotes en venta

Al crear un comprobante que usa lotes, se envía el campo `IdLoteSelected` **por cada item**:

#### Opción A — Lote único

```json
{
    "items": [
        {
            "codigo_interno": "MED-001",
            "descripcion": "Paracetamol 500mg",
            "cantidad": 5,
            "IdLoteSelected": 102,
            "...": "resto del item"
        }
    ]
}
```

Donde `IdLoteSelected` es el `id` del `ItemLotsGroup` del cual se descontará la cantidad.

#### Opción B — Múltiples lotes (split por FEFO)

Cuando la cantidad pedida supera un lote, se divide entre varios:

```json
{
    "items": [
        {
            "codigo_interno": "MED-001",
            "descripcion": "Paracetamol 500mg",
            "cantidad": 60,
            "IdLoteSelected": [
                { "id": 102, "compromise_quantity": 50 },
                { "id": 101, "compromise_quantity": 10 }
            ],
            "...": "resto del item"
        }
    ]
}
```

**Validación:** `sum(compromise_quantity) == cantidad pedida`

### Descuento automático al sincronizar

Cuando el documento se crea, el `InventoryKardexServiceProvider` descuenta automáticamente:

```php
// Ref: modules/Inventory/Providers/InventoryKardexServiceProvider.php L167-225
foreach ($lotesSelecteds as $item) {
    $lot = ItemLotsGroup::find($item->id);
    $lot->quantity += ($quantity_unit * $item->compromise_quantity) * $document_factor;
    // document_factor: -1 para venta, +1 para nota de crédito
    $lot->save();
}
```

**Factor según tipo de documento:**

| Tipo | Factor | Efecto |
|------|--------|--------|
| 01 Factura | -1 | Descuenta |
| 03 Boleta | -1 | Descuenta |
| 80 Nota de Venta | -1 | Descuenta |
| 07 Nota de Crédito | **+1** | **Devuelve al lote** |
| 08 Nota de Débito | -1 | Descuenta |

### Validación de stock por lote

Si `stock_control = true` y el lote queda con `quantity < 0`, se lanza excepción:

```
"El lote 'LOT-2026-001' del producto Paracetamol 500mg no tiene suficiente stock!"
```

---

## 2. Series Individuales (`ItemLot`)

### Modelo y schema

**Tabla:** `item_lots`

| Columna | Tipo | Descripción |
|---------|------|-------------|
| `id` | int | PK |
| `series` | string | Número de serie único (ej: IMEI, chasis) |
| `date` | date | Fecha de ingreso |
| `item_id` | int | FK → `items.id` |
| `warehouse_id` | int | FK → `warehouses.id` (nullable) |
| `has_sale` | bool | `true` = ya vendido, `false` = disponible |
| `item_loteable_type` | string | Polimórfica (PurchaseItem, etc.) |
| `item_loteable_id` | int | ID del modelo origen |
| `state` | string(20) | Estado opcional |

> **Ref:** `modules/Item/Models/ItemLot.php`

### Endpoint existente

```
GET /api/pro8/item-lots/records?item_id={id}
Authorization: Bearer {token}
```

**Response:**
```json
{
    "success": true,
    "data": [
        {
            "id": 50,
            "series": "IMEI-123456789012345",
            "item_id": 15,
            "warehouse_id": 1,
            "has_sale": false,
            "date": "2026-03-01"
        }
    ]
}
```

### Envío de series en venta

Se envía el array `lots[]` en el item con las series seleccionadas (`has_sale: true`):

```json
{
    "items": [
        {
            "codigo_interno": "CEL-001",
            "descripcion": "Samsung Galaxy A54",
            "cantidad": 1,
            "lots": [
                {
                    "id": 50,
                    "series": "IMEI-123456789012345",
                    "has_sale": true
                }
            ],
            "...": "resto del item"
        }
    ]
}
```

**Validación:** `count(lots[where has_sale=true]) == cantidad pedida`

### Descuento automático

Al crear el documento:
- Para **venta**: `ItemLot::find($id)->update(['has_sale' => true])`
- Para **nota de crédito** (07): `has_sale => false` (libera la serie de vuelta)

---

## 3. Diferencias entre Lotes y Series

| Aspecto | Lotes (`lots_enabled`) | Series (`series_enabled`) |
|---------|------------------------|---------------------------|
| **Uso típico** | Farmacia, alimentos, bebidas | Electrónicos, equipos |
| **Granularidad** | 1 lote = N unidades (mismo vencimiento) | 1 serie = 1 unidad |
| **Identificador** | `code` (string, no único) | `series` (único por item) |
| **Fecha vencimiento** | `date_of_due` (obligatoria) | No aplica (opcional) |
| **Tracking de venta** | Descuenta `quantity` | Marca `has_sale = true` |
| **Selección en venta** | `IdLoteSelected` (int o array) | `lots[]` (array de IDs) |
| **Estrategia** | FEFO (más próximo a vencer primero) | Manual (usuario elige) |

---

## 4. DIGEMID (Farmacia)

### ¿Qué es DIGEMID?

DIGEMID (Dirección General de Medicamentos, Insumos y Drogas) es el organismo regulador peruano que mantiene el catálogo oficial de productos farmacéuticos.

### Campos DIGEMID en `items`

| Campo | Tipo | Descripción |
|-------|------|-------------|
| `cod_digemid` | string | Código DIGEMID del producto |
| `sanitary` | string | Número de registro sanitario |
| `date_of_due` | date | Fecha de vencimiento del registro sanitario (a nivel producto) |
| `lots_enabled` | bool | Si el producto maneja lotes (farmacia) |

### Modelo `CatDigemid`

**Tabla:** `cat_digemid` — Catálogo completo DIGEMID del item

| Campo | Descripción |
|-------|-------------|
| `item_id` | FK → items |
| `cod_digemid` | Código DIGEMID |
| `nom_prod` | Nombre producto |
| `concent` | Concentración |
| `nom_form_farm` | Forma farmacéutica |
| `nom_form_farm_simplif` | Forma simplificada |
| `presentac` | Presentación |
| `fracciones` | Fracciones |
| `fec_vcto_reg_sanitario` | Fecha vencimiento registro sanitario |
| `num_reg_san` | Número registro sanitario |
| `nom_titular` | Titular del registro |
| `prices` | Precios regulados (JSON) |
| `max_prices` | Precios máximos (JSON) |

> **Ref:** `modules/Digemid/Models/CatDigemid.php`

### Respuesta extendida de item (farmacia)

Cuando `GET /api/document/search-items` retorna items de farmacia, incluye campos adicionales:

```json
{
    "id": 25,
    "internal_id": "MED-001",
    "description": "Paracetamol 500mg x 10 tabletas",
    "unit_type_id": "NIU",
    "sale_unit_price": "5.00",
    "lots_enabled": true,
    "series_enabled": false,
    "cod_digemid": "E1234567",
    "sanitary": "N-12345",
    "date_of_due": "2027-12-31",
    "lots_group": [
        {
            "id": 101,
            "code": "LOT-2026-001",
            "quantity": 150,
            "date_of_due": "2027-06-30",
            "checked": false,
            "compromise_quantity": 0
        },
        {
            "id": 102,
            "code": "LOT-2026-002",
            "quantity": 50,
            "date_of_due": "2026-12-15",
            "checked": false,
            "compromise_quantity": 0
        }
    ],
    "lots": []
}
```

Los campos `checked` y `compromise_quantity` son para el frontend (al seleccionar un lote, Flutter los actualiza localmente).

---

## 5. Ejemplo Completo — Boleta de Farmacia

```json
{
    "serie_documento": "B001",
    "numero_documento": "#",
    "fecha_de_emision": "2026-04-19",
    "hora_de_emision": "10:30:00",
    "codigo_tipo_operacion": "0101",
    "codigo_tipo_documento": "03",
    "codigo_tipo_moneda": "PEN",
    "datos_del_cliente_o_receptor": {
        "codigo_tipo_documento_identidad": "1",
        "numero_documento": "12345678",
        "apellidos_y_nombres_o_razon_social": "PÉREZ GARCÍA JUAN"
    },
    "totales": {
        "total_operaciones_gravadas": 25.42,
        "total_igv": 4.58,
        "total_impuestos": 4.58,
        "total_valor": 25.42,
        "total_venta": 30
    },
    "items": [
        {
            "codigo_interno": "MED-001",
            "descripcion": "Paracetamol 500mg x 10 tabletas",
            "unidad_de_medida": "NIU",
            "cantidad": 3,
            "valor_unitario": 4.2373,
            "precio_unitario": 5,
            "codigo_tipo_precio": "01",
            "codigo_tipo_afectacion_igv": "10",
            "total_base_igv": 12.71,
            "porcentaje_igv": 18,
            "total_igv": 2.29,
            "total_impuestos": 2.29,
            "total_valor_item": 12.71,
            "total_item": 15,
            "IdLoteSelected": 102
        },
        {
            "codigo_interno": "MED-002",
            "descripcion": "Ibuprofeno 400mg x 20 tabletas",
            "unidad_de_medida": "NIU",
            "cantidad": 2,
            "valor_unitario": 6.3559,
            "precio_unitario": 7.5,
            "codigo_tipo_precio": "01",
            "codigo_tipo_afectacion_igv": "10",
            "total_base_igv": 12.71,
            "porcentaje_igv": 18,
            "total_igv": 2.29,
            "total_impuestos": 2.29,
            "total_valor_item": 12.71,
            "total_item": 15,
            "IdLoteSelected": [
                { "id": 201, "compromise_quantity": 1 },
                { "id": 202, "compromise_quantity": 1 }
            ]
        }
    ],
    "pagos": [
        {
            "codigo_metodo_pago": "01",
            "monto": 30
        }
    ]
}
```

---

## 6. Notas para Offline

### Descarga inicial

1. `GET /api/document/search-items` — Retorna items con `lots_group[]`, `lots[]`, `lots_enabled`, `series_enabled`
2. Guardar cada `lots_group` en SQLite asociado al `item_id`

### Descuento local

Al agregar un item con lote a la venta:

```dart
// Pseudocódigo Flutter
void addItemToCart(Item item, int quantity) {
    if (item.lotsEnabled) {
        // Aplicar FEFO: elegir lote con date_of_due más cercana
        final sortedLots = item.lotsGroup
            .where((l) => l.quantity > 0)
            .toList()
          ..sort((a, b) => a.dateOfDue.compareTo(b.dateOfDue));
        
        int remaining = quantity;
        List<Map> selected = [];
        
        for (final lot in sortedLots) {
            if (remaining <= 0) break;
            final take = min(remaining, lot.quantity);
            selected.add({'id': lot.id, 'compromise_quantity': take});
            remaining -= take;
            // Descontar localmente
            lot.quantity -= take;
        }
        
        if (remaining > 0) {
            throw Exception('Stock insuficiente en lotes disponibles');
        }
        
        cartItem.idLoteSelected = selected.length == 1
            ? selected[0]['id']
            : selected;
    }
}
```

### Alertas de vencimiento

```dart
// Productos próximos a vencer (< 90 días)
final expiringLots = allLots.where((l) {
    final days = l.dateOfDue.difference(DateTime.now()).inDays;
    return days < 90 && l.quantity > 0;
});
```

### Sincronización post-sync

Después de cada `sync-batch` exitoso:

```dart
// Re-sincronizar lotes para tener cantidades actualizadas del servidor
final response = await api.get('/api/offline/item-lots-group');
await db.updateLots(response['data']);
```

### Casos borde

| Caso | Solución |
|------|----------|
| Cliente compra cantidad > stock total de lotes | Validar en frontend antes de cobrar |
| Cliente compra, otro vendedor también vendió el mismo lote offline | Al sincronizar, uno puede fallar si `stock_control=true`. Usar `sync-batch` para manejar errores individuales |
| Lote sin `date_of_due` | No debería existir. Si existe, tratarlo como "sin vencimiento" (ponerlo al final del orden FEFO) |
| Item tiene `lots_enabled=true` pero no tiene lotes en `lots_group[]` | No se puede vender. Mostrar alerta "Sin lotes disponibles" |
