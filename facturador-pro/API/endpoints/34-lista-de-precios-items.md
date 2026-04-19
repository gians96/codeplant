# 34 — Lista de Precios por Item (`item_unit_types`)

> Cada item puede tener **múltiples precios de venta** (lista de precios) asociados a unidades de medida distintas. Al momento de vender, Flutter puede permitir que el operador elija uno.

---

## Concepto

En Pro-8, la "lista de precios" **no** es una tabla de listas de precios globales (tipo "Mayorista", "Minorista"). Es una relación 1:N entre `items` y **unidades de medida de venta**:

- Un item puede venderse como "UNIDAD" (`NIU`) a S/ 5.00
- El mismo item puede venderse como "CAJA × 12" a S/ 50.00
- Cada unidad de medida puede tener hasta **3 precios + 1 por defecto**

Esto vive en la tabla `item_unit_types`:

| Columna | Tipo | Descripción |
|---------|------|-------------|
| `id` | int | PK |
| `item_id` | int | FK → items |
| `unit_type_id` | string | FK → `cat_unit_types` (ej: `NIU`, `BX`, `GLN`) |
| `quantity_unit` | decimal(12,4) | Factor de conversión (1 CAJA = 12 UNIDADES) |
| `description` | string | Descripción libre (ej: `"Paracetamol caja × 12"`) |
| `price1` | decimal(12,2) | Precio 1 |
| `price2` | decimal(12,2) | Precio 2 |
| `price3` | decimal(12,2) | Precio 3 |
| `price_default` | int | Cuál de los 3 es el precio por defecto (1, 2 o 3) |
| `barcode` | string | Código de barras de esa presentación |

> `item_unit_types` también se conoce en el código como **"presentaciones"** o **"unidades de venta"**.

---

## Flag de Configuración: `select_available_price_list`

```sql
-- tabla `configurations`
select_available_price_list BOOLEAN DEFAULT FALSE
```

Se expone en la configuración offline (ver [20-configuracion-offline.md](20-configuracion-offline.md)):

```json
{
    "select_available_price_list": true
}
```

### Comportamiento

| Valor | Comportamiento en el POS |
|-------|--------------------------|
| `false` (default) | Agregar item usa **directamente** su `sale_unit_price` (precio plano del item) |
| `true` | Al agregar, si `item_unit_types` no está vacío → mostrar modal con las presentaciones disponibles y que el usuario elija precio |

### ¿Dónde se descarga?

En el endpoint de configuración general del tenant:

```
GET /api/offline/configurations   (o payload del login)
```

El campo `select_available_price_list` viene dentro del objeto `configuration`. Flutter lo cachea en `SharedPreferences` al iniciar sesión.

---

## Dónde vienen los precios

El endpoint **`GET /api/document/search-items`** ya retorna el array `item_unit_types` por cada item:

```json
{
    "id": 25,
    "description": "Paracetamol 500mg",
    "unit_type_id": "NIU",
    "sale_unit_price": "5.00",
    "currency_type_id": "PEN",
    "item_unit_types": [
        {
            "id": 101,
            "description": "Blíster × 10 tabletas",
            "unit_type_id": "NIU",
            "quantity_unit": 1,
            "price1": 5.00,
            "price2": 4.50,
            "price3": 4.00,
            "price_default": 1
        },
        {
            "id": 102,
            "description": "Caja × 10 blísters",
            "unit_type_id": "BX",
            "quantity_unit": 10,
            "price1": 45.00,
            "price2": 42.00,
            "price3": 40.00,
            "price_default": 1
        }
    ]
}
```

> **Ref:** `app/Http/Controllers/Tenant/Api/MobileController.php` → `searchItems()` L495-L506.

### Campos clave

| Campo | Uso |
|-------|-----|
| `id` | **Este es el `item_unit_type_id`** que se envía en el payload al vender |
| `description` | Texto a mostrar en el selector |
| `unit_type_id` | Código SUNAT de la unidad (`NIU`, `BX`, `GLN`, `KGM`, etc.) — se envía en `unidad_de_medida` |
| `quantity_unit` | Factor: cuántas unidades base equivale (para kardex/stock) |
| `price1/2/3` | Los 3 precios posibles |
| `price_default` | Indica cuál usar si el usuario no elige (`1`, `2` o `3`) |

---

## Cómo Elegir el Precio en Flutter

### Caso A — `select_available_price_list = false`

Flujo simple (no se muestra nada al operador):

```dart
cartItem.unitPrice = item.saleUnitPrice;          // "5.00"
cartItem.unitTypeId = item.unitTypeId;            // "NIU"
cartItem.itemUnitTypeId = null;                    // no se envía
```

### Caso B — `select_available_price_list = true`

Al agregar, si `item.itemUnitTypes` tiene ≥ 1 entrada:

```
┌──────────────────────────────────────────┐
│ Paracetamol 500mg — Elegir presentación   │
├──────────────────────────────────────────┤
│ ○ Blíster × 10                            │
│   • Precio 1: S/ 5.00  ★ default          │
│   • Precio 2: S/ 4.50                     │
│   • Precio 3: S/ 4.00                     │
├──────────────────────────────────────────┤
│ ○ Caja × 10 blísters                      │
│   • Precio 1: S/ 45.00 ★ default          │
│   • Precio 2: S/ 42.00                    │
│   • Precio 3: S/ 40.00                    │
└──────────────────────────────────────────┘
```

Al confirmar:

```dart
final presentation = item.itemUnitTypes[selectedIndex];
final selectedPrice = selectedPriceNumber == 1
    ? presentation.price1
    : (selectedPriceNumber == 2 ? presentation.price2 : presentation.price3);

cartItem.itemUnitTypeId = presentation.id;           // 102
cartItem.unitTypeId = presentation.unitTypeId;       // "BX"
cartItem.unitPrice = selectedPrice;                  // 42.00
cartItem.quantityUnit = presentation.quantityUnit;   // 10 (para kardex)
```

---

## Payload del Documento con Presentación Elegida

Al emitir el comprobante, el item lleva los campos **ya mapeados a la presentación seleccionada**:

```json
{
    "items": [
        {
            "codigo_interno": "MED-001",
            "descripcion": "Paracetamol 500mg — Caja × 10 blísters",
            "unidad_de_medida": "BX",
            "cantidad": 2,
            "valor_unitario": 35.59,
            "precio_unitario": 42.00,
            "codigo_tipo_precio": "01",
            "codigo_tipo_afectacion_igv": "10",
            "item_unit_type_id": 102,
            "quantity_unit": 10,
            "total_base_igv": 71.19,
            "porcentaje_igv": 18,
            "total_igv": 12.81,
            "total_impuestos": 12.81,
            "total_valor_item": 71.19,
            "total_item": 84.00
        }
    ]
}
```

### Campos específicos de presentación

| Campo API | Descripción |
|-----------|-------------|
| `unidad_de_medida` | `unit_type_id` de la presentación elegida |
| `precio_unitario` | Precio elegido (1, 2 o 3) |
| `valor_unitario` | `precio_unitario / (1 + igv%)` si afectación `10` |
| `item_unit_type_id` | **ID del `item_unit_types` seleccionado** (entero) |
| `quantity_unit` | Factor de conversión (informativo, se usa en kardex) |

> El `item_unit_type_id` es **clave** para que el kardex descuente correctamente el stock base (el descuento real = `cantidad × quantity_unit`).

---

## Filtrado por Establecimiento / Usuario

Las presentaciones (`item_unit_types`) **no** se filtran por establecimiento — son parte del catálogo del item. Sin embargo:

- El **item** ya viene filtrado por warehouse del establecimiento (ver [33-validacion-contrato-offline.md](33-validacion-contrato-offline.md)).
- Por lo tanto, Flutter sólo ve presentaciones de items que puede vender.
- **No hay asignación de presentaciones por usuario.** Si un tenant quiere restringir "solo caja, no unidades" para un vendedor, debe crear items distintos o usar `disabled` a nivel item.

---

## Casos Especiales

### Item con 1 sola presentación

Aunque `select_available_price_list = true`, si el item tiene **exactamente una** entrada en `item_unit_types`, Flutter puede saltarse el selector y usar directamente la `price_default` de esa presentación.

### Item sin `item_unit_types`

Algunos items (especialmente servicios `unit_type_id == 'ZZ'`) pueden no tener presentaciones. En ese caso:

- Usar `sale_unit_price` plano del item.
- No enviar `item_unit_type_id` en el payload.

### Override manual de precio (descuento en línea)

Si `configuration.edit_sale_unit_price = true` (otro flag), el operador puede **editar el precio manualmente** tras elegir presentación. Flutter actualiza `precio_unitario` y recalcula `valor_unitario`, IGV e impuestos localmente.

---

## Almacenamiento Local (SQLite)

```sql
CREATE TABLE item_unit_types (
  id INTEGER PRIMARY KEY,
  item_id INTEGER NOT NULL,
  unit_type_id TEXT,
  description TEXT,
  quantity_unit REAL,
  price1 REAL,
  price2 REAL,
  price3 REAL,
  price_default INTEGER,
  barcode TEXT,
  FOREIGN KEY (item_id) REFERENCES items(id) ON DELETE CASCADE
);

CREATE INDEX idx_iut_item ON item_unit_types(item_id);
CREATE INDEX idx_iut_barcode ON item_unit_types(barcode);
```

Al llamar `search-items`, persistir el array completo en esta tabla.

---

## Búsqueda por Código de Barras de Presentación

Cada `item_unit_type` puede tener su propio `barcode` (caja con código distinto a la unidad).

```dart
// Buscar por barcode local
final match = await db.query(
  'item_unit_types',
  where: 'barcode = ?',
  whereArgs: [scannedCode],
);
if (match.isNotEmpty) {
    final iut = match.first;
    final item = await db.getItem(iut['item_id']);
    // Agregar con esa presentación automáticamente
    addToCart(item, presentation: iut);
}
```

---

## Resumen

| # | Verificación | Cómo lo resuelve Pro-8 |
|---|--------------|------------------------|
| ✅ | ¿Hay lista de precios por item? | `item_unit_types[]` en `search-items` |
| ✅ | ¿Se puede elegir al vender? | Sí, si `configuration.select_available_price_list = true` |
| ✅ | ¿Los precios están asignados? | Sí, por item (no por usuario ni establecimiento) |
| ✅ | ¿Se descargan offline? | Sí, vienen en el payload de `search-items` |
| ✅ | ¿Se envían en la venta? | Sí, como `item_unit_type_id` + `unidad_de_medida` + `precio_unitario` elegidos |

---

## Referencias de Código

| Archivo | Línea | Propósito |
|---------|-------|-----------|
| `app/Http/Controllers/Tenant/Api/MobileController.php` | 495-506 | Retorna `item_unit_types` en `search-items` |
| `database/migrations/tenant/2019_05_07_160954_tenant_item_unit_types_table.php` | 15 | Schema `item_unit_types` |
| `database/migrations/tenant/2021_08_09_131738_tenant_add_select_available_price_list_to_configurations.php` | 17 | Flag `select_available_price_list` |
| `app/Models/Tenant/Configuration.php` | 651, 2279 | Getter/setter del flag |
| `resources/js/views/tenant/pos/fast.vue` | 950 | Lógica POS web: abre modal si el flag está activo |
| `resources/js/views/tenant/pos/index.vue` | 1816 | Misma lógica en POS principal |
