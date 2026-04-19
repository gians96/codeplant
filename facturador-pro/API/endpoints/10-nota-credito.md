# 10 — Nota de Crédito Electrónica

> `POST /api/documents`  
> **Controller:** `Tenant\Api\DocumentController@store`  
> **Middleware:** `input.request:document,api`  
> **Auth:** `Bearer {token}`  
> **Código tipo:** `"07"`

---

## Descripción

La nota de crédito se emite para **anular o corregir** una factura o boleta previamente emitida. Se crea a través del **mismo endpoint** que facturas/boletas, pero con `codigo_tipo_documento: "07"` y campos adicionales para referenciar el documento afectado.

> 📘 **Estructura común:** El payload completo (cliente, items, totales, idempotencia, acciones, respuesta, etc.) es **idéntico** al de factura/boleta. Ver [09-boleta-factura.md](09-boleta-factura.md) como referencia canónica.
>
> Este documento sólo describe los **campos específicos** de nota de crédito:
> - `codigo_tipo_documento`: `"07"`
> - `codigo_tipo_nota`: catálogo 09 SUNAT (01 = anulación, 02 = anulación por error en RUC, 03 = corrección descripción, etc.)
> - `motivo_o_sustento_de_nota`: texto libre
> - `documento_afectado.external_id`: UUID del documento original

---

## Payload

```json
{
    "serie_documento": "FC01",
    "numero_documento": "#",
    "fecha_de_emision": "2026-04-18",
    "hora_de_emision": "15:00:00",
    "codigo_tipo_documento": "07",
    "codigo_tipo_moneda": "PEN",
    "codigo_tipo_nota": "01",
    "motivo_o_sustento_de_nota": "Anulación de la operación",
    "documento_afectado": {
        "external_id": "4506ba3e-fd30-44b3-9646-603d8236a02f"
    },
    "codigo_vendedor": 1,
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
            "codigo_interno": "ASD",
            "descripcion": "Precio",
            "codigo_producto_sunat": null,
            "unidad_de_medida": "NIU",
            "cantidad": 1,
            "valor_unitario": 3.1271186440677967,
            "precio_unitario": 3.69,
            "codigo_tipo_precio": "01",
            "codigo_tipo_afectacion_igv": "10",
            "total_base_igv": 3.1271186440677967,
            "porcentaje_igv": 18,
            "total_igv": 0.5628813559322032,
            "total_impuestos": 0.5628813559322032,
            "total_valor_item": 3.1271186440677967,
            "total_item": 3.69
        }
    ],
    "totales": {
        "total_exportacion": 0,
        "total_operaciones_gravadas": 3.1271186440677967,
        "total_operaciones_inafectas": 0,
        "total_operaciones_exoneradas": 0,
        "total_operaciones_gratuitas": 0,
        "total_igv": 0.5628813559322032,
        "total_impuestos": 0.5628813559322032,
        "total_valor": 3.1271186440677967,
        "total_venta": 3.69
    }
}
```

---

## Campos Específicos de Nota de Crédito

### Diferencias con Boleta/Factura

| Campo | Valor | Descripción |
|-------|-------|-------------|
| `codigo_tipo_documento` | `"07"` | Nota de Crédito |
| `codigo_tipo_nota` | string | **Requerido.** Tipo de nota de crédito (ver tabla) |
| `motivo_o_sustento_de_nota` | string | **Requerido.** Motivo de la nota |
| `documento_afectado` | object | **Requerido.** Referencia al documento que se corrige |

> **No lleva** `codigo_tipo_operacion`, `fecha_de_vencimiento`, `pagos[]`, `cuotas[]`.

### `documento_afectado`

| Campo | Tipo | Descripción |
|-------|------|-------------|
| `external_id` | string | **Preferido.** UUID del documento afectado (obtenido al crear la factura/boleta) |

**Alternativa** (si no se tiene el `external_id`):

```json
"documento_afectado": {
    "serie_documento": "F001",
    "numero_documento": "15",
    "codigo_tipo_documento": "01"
}
```

| Campo | Tipo | Descripción |
|-------|------|-------------|
| `serie_documento` | string | Serie del documento afectado |
| `numero_documento` | string | Número del documento afectado |
| `codigo_tipo_documento` | string | `"01"` (Factura) o `"03"` (Boleta) |

### Tipos de Nota de Crédito (`codigo_tipo_nota`)

| Código | Descripción |
|--------|-------------|
| `01` | Anulación de la operación |
| `02` | Anulación por error en el RUC |
| `03` | Corrección por error en la descripción |
| `04` | Descuento global |
| `05` | Descuento por ítem |
| `06` | Devolución total |
| `07` | Devolución por ítem |
| `08` | Bonificación |
| `09` | Disminución en el valor |
| `10` | Otros conceptos |
| `11` | Ajustes de operaciones de exportación |
| `12` | Ajustes afectos al IVAP |
| `13` | Corrección del monto neto pendiente de pago |

### Serie según documento afectado

| Documento afectado | Serie NC |
|-------------------|----------|
| Factura (F001) | FC01 |
| Boleta (B001) | BC01 |

---

## Response (200 OK)

Misma estructura que Boleta/Factura:

```json
{
    "success": true,
    "data": {
        "number": "FC01-3",
        "filename": "20538856674-07-FC01-3",
        "external_id": "uuid-nc",
        "state_type_id": "01",
        "state_type_description": "Registrado",
        "id": 456,
        "print_ticket": "https://..."
    },
    "links": {
        "xml": "https://...",
        "pdf": "https://...",
        "cdr": "https://..."
    }
}
```

---

## Notas para Offline

- **Requiere que el documento afectado esté sincronizado primero.** La NC necesita el `external_id` del documento original que asigna el backend.
- Flujo offline:
  1. Crear Factura/Boleta offline → sincronizar → obtener `external_id`
  2. Crear NC offline referenciando ese `external_id` → sincronizar
- Si el documento original fue creado offline y aún no sincronizado, la NC debe **quedar en cola** hasta que se sincronice el original.
- Los items y totales de la NC deben coincidir con lo que se está corrigiendo del documento original (parcial o total).
