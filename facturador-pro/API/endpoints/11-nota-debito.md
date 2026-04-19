# 11 — Nota de Débito Electrónica

> `POST /api/documents`  
> **Controller:** `Tenant\Api\DocumentController@store`  
> **Middleware:** `input.request:document,api`  
> **Auth:** `Bearer {token}`  
> **Código tipo:** `"08"`

---

## Descripción

La nota de débito se emite para **incrementar el valor** de una factura o boleta previamente emitida (intereses, penalidades, gastos adicionales). Usa el **mismo endpoint** que facturas/boletas con `codigo_tipo_documento: "08"`.

---

## Payload

```json
{
    "serie_documento": "FD01",
    "numero_documento": "#",
    "fecha_de_emision": "2026-04-18",
    "hora_de_emision": "15:30:00",
    "codigo_tipo_documento": "08",
    "codigo_tipo_moneda": "PEN",
    "codigo_tipo_nota": "01",
    "motivo_o_sustento_de_nota": "Intereses por mora",
    "documento_afectado": {
        "external_id": "90a15d6f-7043-432e-9d06-9f52c0d0af6a"
    },
    "codigo_vendedor": 1,
    "datos_del_cliente_o_receptor": {
        "codigo_tipo_documento_identidad": "6",
        "numero_documento": "20552103816",
        "apellidos_y_nombres_o_razon_social": "AGROLIGHT PERU S.A.C.",
        "codigo_pais": "PE",
        "ubigeo": "150101",
        "direccion": "PJ. JORGE BASADRE NRO. 158",
        "correo_electronico": null,
        "telefono": null
    },
    "items": [
        {
            "codigo_interno": "-",
            "descripcion": "Intereses por mora - Factura F001-10",
            "codigo_producto_sunat": null,
            "unidad_de_medida": "ZZ",
            "cantidad": 1,
            "valor_unitario": 50.847457627118,
            "precio_unitario": 60.00,
            "codigo_tipo_precio": "01",
            "codigo_tipo_afectacion_igv": "10",
            "total_base_igv": 50.847457627118,
            "porcentaje_igv": 18,
            "total_igv": 9.152542372881,
            "total_impuestos": 9.152542372881,
            "total_valor_item": 50.847457627118,
            "total_item": 60.00
        }
    ],
    "totales": {
        "total_exportacion": 0,
        "total_operaciones_gravadas": 50.847457627118,
        "total_operaciones_inafectas": 0,
        "total_operaciones_exoneradas": 0,
        "total_operaciones_gratuitas": 0,
        "total_igv": 9.152542372881,
        "total_impuestos": 9.152542372881,
        "total_valor": 50.847457627118,
        "total_venta": 60.00
    }
}
```

---

## Campos Específicos de Nota de Débito

| Campo | Valor | Descripción |
|-------|-------|-------------|
| `codigo_tipo_documento` | `"08"` | Nota de Débito |
| `codigo_tipo_nota` | string | **Requerido.** Tipo de nota de débito (ver tabla) |
| `motivo_o_sustento_de_nota` | string | **Requerido.** Motivo |
| `documento_afectado` | object | **Requerido.** Referencia al documento original |

### Tipos de Nota de Débito (`codigo_tipo_nota`)

| Código | Descripción |
|--------|-------------|
| `01` | Intereses por mora |
| `02` | Aumento en el valor |
| `03` | Penalidades / otros conceptos |
| `10` | Ajustes de operaciones de exportación |
| `11` | Ajustes afectos al IVAP |

### `documento_afectado`

Misma estructura que Nota de Crédito (ver [10-nota-credito.md](10-nota-credito.md)):

```json
"documento_afectado": {
    "external_id": "uuid-del-documento-original"
}
```

### Serie según documento afectado

| Documento afectado | Serie ND |
|-------------------|----------|
| Factura (F001) | FD01 |
| Boleta (B001) | BD01 |

---

## Response (200 OK)

Misma estructura que los demás documentos:

```json
{
    "success": true,
    "data": {
        "number": "FD01-1",
        "filename": "20538856674-08-FD01-1",
        "external_id": "uuid-nd",
        "state_type_id": "01",
        "id": 789,
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

- Misma restricción que NC: **requiere que el documento afectado esté sincronizado** para obtener su `external_id`.
- Las notas de débito no son comunes en operaciones de alta rotación, pero se documentan para completitud.
- Items y totales representan los **montos adicionales** a cobrar (intereses, penalidades), no el monto total del documento original.
