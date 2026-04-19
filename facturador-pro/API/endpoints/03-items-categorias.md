# 03 — Items y Categorías

> **Uso offline:** Descarga el catálogo de productos filtrado por la sucursal (warehouse) del usuario autenticado.

> ⚠️ **Ruta canónica:** Para descarga inicial y búsqueda en producción usar `GET /api/document/search-items` (ver [21-productos-crud.md](21-productos-crud.md)). Los endpoints `/api/sellnow/items` y `/api/sellnow/categories` de este documento se mantienen por compatibilidad con clientes legacy; **nuevas integraciones deben usar `search-items`**.

---

## 1. Obtener Items (legacy)

> `GET /api/sellnow/items`  
> **Controller:** `Tenant\Api\SellnowController@items`  
> **Auth:** `Bearer {token}`

### Headers

```
Accept: application/json
Authorization: Bearer {token}
```

### Response (200 OK)

```json
{
    "success": true,
    "data": [
        {
            "id": 1,
            "internal_id": "ASD",
            "description": "Precio",
            "second_name": null,
            "barcode": null,
            "item_code": null,
            "unit_type_id": "NIU",
            "currency_type_id": "PEN",
            "sale_unit_price": 3.69,
            "purchase_unit_price": 0,
            "sale_affectation_igv_type_id": "10",
            "has_igv": true,
            "has_isc": false,
            "is_set": false,
            "image": "https://demo.nt-suite.pro/storage/uploads/items/item_1.jpg",
            "image_medium": "https://demo.nt-suite.pro/storage/uploads/items/item_1_medium.jpg",
            "stock": 1000,
            "stock_min": 0,
            "category_id": null,
            "brand_id": null,
            "category": null,
            "brand": null,
            "favorite": false,
            "restaurant_favorite": false,
            "item_unit_types": [
                {
                    "id": 1,
                    "description": "CAJA x 12",
                    "item_id": 1,
                    "unit_type_id": "BX",
                    "quantity_unit": 12,
                    "price1": 40.00,
                    "price2": 38.00,
                    "price3": 35.00,
                    "price_default": "price1"
                }
            ],
            "lots": [],
            "modifiers": []
        }
    ]
}
```

### Campos del Item

| Campo | Tipo | Descripción |
|-------|------|-------------|
| `id` | int | ID del item |
| `internal_id` | string | Código interno (se envía como `codigo_interno` en documentos) |
| `description` | string | Descripción del producto |
| `second_name` | string\|null | Nombre secundario |
| `barcode` | string\|null | Código de barras |
| `item_code` | string\|null | Código producto SUNAT |
| `unit_type_id` | string | Unidad de medida: `NIU` (unidad), `KGM` (kg), `BX` (caja), etc. |
| `currency_type_id` | string | Moneda: `PEN`, `USD` |
| `sale_unit_price` | float | Precio de venta unitario **con IGV** |
| `purchase_unit_price` | float | Precio de compra |
| `sale_affectation_igv_type_id` | string | Tipo afectación IGV: `10`=Gravado, `20`=Exonerado, `30`=Inafecto |
| `has_igv` | bool | Si el precio incluye IGV |
| `has_isc` | bool | Si tiene ISC |
| `is_set` | bool | Si es un combo/set de productos |
| `image` | string\|null | URL imagen completa |
| `image_medium` | string\|null | URL imagen mediana |
| `stock` | float | Stock disponible en el warehouse de la sucursal |
| `stock_min` | float | Stock mínimo |
| `category_id` | int\|null | ID de categoría |
| `brand_id` | int\|null | ID de marca |
| `category` | object\|null | `{ id, name }` |
| `brand` | object\|null | `{ id, name }` |
| `favorite` | bool | Marcado como favorito (app ventas) |
| `restaurant_favorite` | bool | Marcado como favorito (restaurante) |
| `item_unit_types` | array | Presentaciones alternativas (caja, docena, etc.) |
| `lots` | array | Lotes disponibles (para productos con lote/serie) |
| `modifiers` | array | Modificadores del producto (extras, complementos) |

### `item_unit_types[]`

| Campo | Tipo | Descripción |
|-------|------|-------------|
| `id` | int | ID de la presentación |
| `description` | string | Nombre de la presentación |
| `unit_type_id` | string | Código unidad de medida |
| `quantity_unit` | float | Cantidad de unidades base por presentación |
| `price1` | float | Precio 1 (con IGV) |
| `price2` | float | Precio 2 |
| `price3` | float | Precio 3 |
| `price_default` | string | Cuál precio usar por defecto |

> **Filtrado por sucursal:** Los items y su stock se filtran automáticamente por el warehouse asociado al `establishment_id` del usuario autenticado. Cada sucursal ve solo su inventario.

---

## 2. Obtener Categorías

> `GET /api/sellnow/categories`  
> **Controller:** `Tenant\Api\SellnowController@categories`  
> **Auth:** `Bearer {token}`

### Response (200 OK)

```json
{
    "success": true,
    "data": [
        {
            "id": 1,
            "name": "Electrónica"
        },
        {
            "id": 2,
            "name": "Alimentos"
        }
    ]
}
```

> Retorna **todas** las categorías del tenant (sin filtro por sucursal).

---

## Notas para Offline

- **Almacenar items en SQLite** con todos sus campos para búsqueda local por `description`, `internal_id` o `barcode`.
- El `stock` descargado es una snapshot. Considerar sincronizar periódicamente para actualizar stock.
- Para cálculos de impuestos offline:
  - Si `sale_affectation_igv_type_id = "10"` (gravado) y `has_igv = true`:
    - `unit_value = sale_unit_price / 1.18`
    - `total_igv = unit_value * 0.18 * quantity`
  - Si `sale_affectation_igv_type_id = "20"` o `"30"`: no se calcula IGV
- Las `item_unit_types` permiten vender por presentación (ej: vender por caja de 12 unidades a un precio diferente).
