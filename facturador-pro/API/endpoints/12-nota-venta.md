# 12 — Nota de Venta

> `POST /api/sale-note`  
> **Controller:** `Tenant\Api\SaleNoteController@store`  
> **Auth:** `Bearer {token}`  
> **Código tipo:** `"80"` (documento no fiscal / interno)

---

## Descripción

La nota de venta es un **comprobante interno** (no va a SUNAT). Es el documento más usado en operaciones de alta rotación porque no requiere firma digital ni conexión con SUNAT. Ideal para modo offline.

> **Diferencia clave:** Este endpoint **no usa** el middleware `input.request:document,api`. Los campos se envían en inglés (directamente), no en español como facturas/boletas.

---

## Request

### Headers

```
Content-Type: application/json
Accept: application/json
Authorization: Bearer {token}
```

### Payload

```json
{
    "document_type_id": "80",
    "prefix": "NV",
    "series_id": 10,
    "establishment_id": null,
    "date_of_issue": "2026-04-18",
    "time_of_issue": "14:30:00",
    "customer_id": 5,
    "currency_type_id": "PEN",
    "purchase_order": null,
    "plate_number": "",
    "exchange_rate_sale": 0,
    "operation_type_id": null,
    "charges": [],
    "discounts": [],
    "attributes": [],
    "guides": [],
    "additional_information": null,
    "seller_id": 1,
    "actions": {
        "format_pdf": "a4"
    },
    "apply_concurrency": false,
    "type_period": null,
    "quantity_period": 0,
    "automatic_date_of_issue": null,
    "enabled_concurrency": false,
    "total_prepayment": 0,
    "total_charge": 0,
    "total_discount": 0,
    "total_exportation": 0,
    "total_free": 0,
    "total_unaffected": 0,
    "total_exonerated": 0,
    "total_base_isc": 0,
    "total_isc": 0,
    "total_base_other_taxes": 0,
    "total_other_taxes": 0,
    "payments": [
        {
            "payment_method_type_id": "01",
            "destination_id": null,
            "reference": null,
            "payment": 102,
            "payment_received": 110
        }
    ],
    "datos_del_cliente_o_receptor": {
        "codigo_tipo_documento_identidad": "1",
        "numero_documento": "76251607",
        "apellidos_y_nombres_o_razon_social": "ARIAS BONIFACIO, GIANMARCOS DANIEL",
        "codigo_pais": "PE",
        "ubigeo": "",
        "direccion": null,
        "correo_electronico": null,
        "telefono": null
    },
    "items": [
        {
            "item_id": 3,
            "item": {
                "id": 3,
                "item_id": 3,
                "name": "Producto KG",
                "full_description": "Producto KG",
                "description": "Producto KG",
                "currency_type_id": "PEN",
                "internal_id": "FFF",
                "item_code": null,
                "currency_type_symbol": "S/",
                "unit_type_id": "KGM",
                "sale_affectation_igv_type_id": "10",
                "has_igv": true,
                "unit_price": 102,
                "sale_unit_price": 102
            },
            "currency_type_id": "PEN",
            "affectation_igv_type_id": "10",
            "system_isc_type_id": null,
            "total_base_isc": 0,
            "percentage_isc": 0,
            "total_isc": 0,
            "total_base_other_taxes": 0,
            "percentage_other_taxes": 0,
            "total_other_taxes": 0,
            "total_plastic_bag_taxes": 0,
            "price_type_id": "01",
            "total_discount": 0,
            "total_charge": 0,
            "attributes": [],
            "charges": [],
            "discounts": [],
            "quantity": 1,
            "unit_price": 102,
            "unit_value": 86.4406779661017,
            "total_value": 86.4406779661017,
            "percentage_igv": 18,
            "total_base_igv": 86.4406779661017,
            "total_igv": 15.559322033898297,
            "total": 102,
            "total_taxes": 15.559322033898297
        }
    ],
    "total_taxed": 86.4406779661017,
    "total_taxes": 15.559322033898297,
    "total_igv": 15.559322033898297,
    "total_value": 86.4406779661017,
    "subtotal": 102,
    "total": 102
}
```

---

## Campos del Payload

### Cabecera

| Campo | Tipo | Requerido | Descripción |
|-------|------|-----------|-------------|
| `document_type_id` | string | **Sí** | Siempre `"80"` |
| `prefix` | string | **Sí** | `"NV"` |
| `series_id` | int | **Sí** | ID de la serie (de `series-numbering` o `company`) |
| `establishment_id` | int\|null | No | Se resuelve del usuario autenticado |
| `date_of_issue` | string | **Sí** | `YYYY-MM-DD` |
| `time_of_issue` | string | **Sí** | `HH:mm:ss` |
| `customer_id` | int | **Sí** | ID del cliente en BD |
| `currency_type_id` | string | **Sí** | `"PEN"`, `"USD"` |
| `exchange_rate_sale` | float | **Sí** | Tipo de cambio (0 o 1 para PEN) |
| `seller_id` | int | No | ID del vendedor |
| `purchase_order` | string\|null | No | Orden de compra |
| `plate_number` | string | No | Placa vehículo |
| `additional_information` | string\|null | No | Info adicional para PDF |

### `datos_del_cliente_o_receptor`

Misma estructura que Boleta/Factura (campos en español):

| Campo | Tipo | Requerido |
|-------|------|-----------|
| `codigo_tipo_documento_identidad` | string | **Sí** |
| `numero_documento` | string | **Sí** |
| `apellidos_y_nombres_o_razon_social` | string | **Sí** |
| `codigo_pais` | string | No |
| `ubigeo` | string | No |
| `direccion` | string\|null | No |
| `correo_electronico` | string\|null | No |
| `telefono` | string\|null | No |

### `items[]`

> **Diferencia con Boleta/Factura:** Los items usan campos en **inglés** y envían el objeto `item` embebido completo.

| Campo | Tipo | Requerido | Descripción |
|-------|------|-----------|-------------|
| `item_id` | int | **Sí** | ID del item en BD |
| `item` | object | **Sí** | Objeto item completo (ver abajo) |
| `currency_type_id` | string | **Sí** | `"PEN"` |
| `affectation_igv_type_id` | string | **Sí** | `"10"`, `"20"`, `"30"` |
| `quantity` | float | **Sí** | Cantidad |
| `unit_price` | float | **Sí** | Precio con IGV |
| `unit_value` | float | **Sí** | Precio sin IGV |
| `total_value` | float | **Sí** | `unit_value * quantity` |
| `percentage_igv` | float | **Sí** | `18` |
| `total_base_igv` | float | **Sí** | `unit_value * quantity` |
| `total_igv` | float | **Sí** | `total_base_igv * 0.18` |
| `total` | float | **Sí** | `unit_price * quantity` |
| `total_taxes` | float | **Sí** | `total_igv + total_isc + ...` |
| `price_type_id` | string | **Sí** | `"01"` precio unitario |

#### Objeto `item` embebido

| Campo | Tipo | Descripción |
|-------|------|-------------|
| `id` | int | ID del item |
| `item_id` | int | ID del item (duplicado para compatibilidad) |
| `name` | string | Nombre del producto |
| `full_description` | string | Descripción completa |
| `description` | string | Descripción corta |
| `currency_type_id` | string | Moneda |
| `internal_id` | string | Código interno |
| `unit_type_id` | string | Unidad de medida |
| `sale_affectation_igv_type_id` | string | Afectación IGV |
| `has_igv` | bool | Si incluye IGV |
| `unit_price` | float | Precio de venta con IGV |
| `sale_unit_price` | float | Precio de venta |

### `payments[]`

| Campo | Tipo | Requerido | Descripción |
|-------|------|-----------|-------------|
| `payment_method_type_id` | string | **Sí** | `"01"` Efectivo, `"02"` Tarjeta, etc. |
| `destination_id` | int\|null | No | ID destino de pago |
| `reference` | string\|null | No | Referencia del pago |
| `payment` | float | **Sí** | Monto del pago |
| `payment_received` | float | No | Monto recibido |

### Totales (a nivel de payload, no en objeto `totales`)

| Campo | Tipo | Descripción |
|-------|------|-------------|
| `total_taxed` | float | Op. gravadas |
| `total_exonerated` | float | Op. exoneradas |
| `total_unaffected` | float | Op. inafectas |
| `total_free` | float | Op. gratuitas |
| `total_taxes` | float | Total impuestos |
| `total_igv` | float | Total IGV |
| `total_value` | float | Subtotal sin impuestos |
| `subtotal` | float | Subtotal |
| `total` | float | **Total final** |

---

## Response (200 OK)

```json
{
    "success": true,
    "data": {
        "id": 25,
        "number": "NV01-25",
        "external_id": "4611364d-2bc8-482c-9eea-4162216d582b",
        "filename": "NV01-25-20260418",
        "print_ticket": "https://demo.nt-suite.pro/sale-notes/print/4611364d-2bc8-482c-9eea-4162216d582b/ticket"
    },
    "links": {
        "pdf": "https://demo.nt-suite.pro/downloads/salenote/sale_note/4611364d-2bc8-482c-9eea-4162216d582b"
    },
    "data_ws": {
        "message_text": null,
        "pdf_a4_filename": "NV01-25-20260418.pdf",
        "full_filename": "NV01-25-20260418",
        "customer_telephone": null
    }
}
```

---

## Notas para Offline

- **No requiere SUNAT.** Es el comprobante ideal para modo offline puro.
- **`customer_id` es requerido.** Si el cliente fue creado offline, usar el ID local temporal. Al sincronizar con `sync-batch` y `force_create_if_not_exist = true`, el backend crea el cliente si no existe.
- **`series_id` es el ID** de la serie en BD (no el código). Obtenerlo de `series-numbering`.
- **No tiene `numero_documento`** como campo explícito — el número lo genera el backend basado en `series_id`. Para offline, el backend auto-numera al sincronizar.
- **La nota de venta NO tiene constraint unique** en BD para el filename. Esto hace que la idempotencia con `offline_id` sea **crítica** para evitar duplicados al re-enviar.
