# 25 — Comprobante de Retención (Tipo 20)

> `POST /api/retentions`  
> **Auth:** `Bearer {token}`  
> **Serie:** `R001`

---

## Descripción

El comprobante de retención (CRE) es un documento electrónico emitido por un **agente de retención** para acreditar la retención del IGV a su proveedor. Es diferente al campo `retencion{}` dentro de una factura (retención IGV, ver [24-detraccion-retencion-igv.md](24-detraccion-retencion-igv.md)).

- **Emisor:** La empresa (agente de retención designado por SUNAT)
- **Proveedor:** El receptor de la retención
- **Serie:** `R001`, `R002`, etc.

---

## Endpoint

```
POST /api/retentions
Authorization: Bearer {token}
Content-Type: application/json
```

---

## Payload

```json
{
    "serie_documento": "R001",
    "numero_documento": "#",
    "fecha_de_emision": "2026-04-18",
    "hora_de_emision": "14:30:00",
    "codigo_tipo_documento": "20",
    "codigo_tipo_moneda": "PEN",
    "codigo_regimen_retencion": "01",
    "tasa_retencion": 3,
    "total_retencion": 354,
    "total_pago": 11446,
    "observacion": "Retención correspondiente a factura F001-122",
    "datos_del_emisor": {
        "codigo_del_domicilio_fiscal": "0000"
    },
    "datos_del_proveedor": {
        "codigo_tipo_documento_identidad": "6",
        "numero_documento": "20100120342",
        "apellidos_y_nombres_o_razon_social": "PROVEEDOR SERVICIOS S.A.C.",
        "nombre_comercial": "PROVEEDOR S.A.C.",
        "codigo_pais": "PE",
        "ubigeo": "150101",
        "direccion": "Av. Arequipa 1234, Lima",
        "correo_electronico": "contabilidad@proveedor.com",
        "telefono": "01-2345678"
    },
    "documentos": [
        {
            "serie_documento": "F001",
            "numero_documento": "122",
            "codigo_tipo_documento": "01",
            "fecha_de_emision": "2026-04-01",
            "codigo_tipo_moneda": "PEN",
            "total_documento": 11800,
            "fecha_de_retencion": "2026-04-18",
            "total_retencion": 354,
            "total_a_pagar": 11446,
            "tipo_de_cambio": {
                "codigo_tipo_moneda_referencia": "PEN",
                "codigo_tipo_moneda_objetivo": "PEN",
                "factor": 1,
                "fecha_de_cambio": "2026-04-18"
            },
            "pagos": [
                {
                    "codigo_metodo_pago": "001",
                    "monto": 11800,
                    "fecha_de_pago": "2026-04-18"
                }
            ]
        }
    ]
}
```

---

## Campos de Cabecera

| Campo | Tipo | Requerido | Descripción |
|-------|------|-----------|-------------|
| `serie_documento` | string | **Sí** | Serie de retención: `"R001"`, `"R002"`, etc. |
| `numero_documento` | string | **Sí** | `"#"` para auto-numerar |
| `fecha_de_emision` | string | **Sí** | `YYYY-MM-DD` |
| `hora_de_emision` | string | **Sí** | `HH:mm:ss` |
| `codigo_tipo_documento` | string | **Sí** | `"20"` = Comprobante de retención |
| `codigo_tipo_moneda` | string | **Sí** | `"PEN"`, `"USD"` |
| `codigo_regimen_retencion` | string | **Sí** | `"01"` = Tasa 3%, `"02"` = Tasa 6% |
| `tasa_retencion` | float | **Sí** | `3` o `6` según régimen |
| `total_retencion` | float | **Sí** | Suma de retenciones de todos los documentos |
| `total_pago` | float | **Sí** | Suma de `total_a_pagar` de todos los documentos |
| `observacion` | string | No | Observaciones libres |

### Regímenes de retención

| Código | Descripción | Tasa |
|--------|-------------|------|
| `01` | Régimen de retenciones | 3% |
| `02` | Régimen de retenciones - tasa especial | 6% |

---

## Datos del Emisor

| Campo | Tipo | Requerido | Descripción |
|-------|------|-----------|-------------|
| `codigo_del_domicilio_fiscal` | string | **Sí** | `"0000"` = domicilio fiscal principal |

> Los demás datos del emisor se toman de la empresa configurada en el sistema.

---

## Datos del Proveedor

| Campo | Tipo | Requerido | Descripción |
|-------|------|-----------|-------------|
| `codigo_tipo_documento_identidad` | string | **Sí** | `"6"` = RUC |
| `numero_documento` | string | **Sí** | RUC del proveedor |
| `apellidos_y_nombres_o_razon_social` | string | **Sí** | Razón social |
| `nombre_comercial` | string | No | Nombre comercial |
| `codigo_pais` | string | No | `"PE"` |
| `ubigeo` | string | No | Ubigeo (6 dígitos) |
| `direccion` | string | No | Dirección completa |
| `correo_electronico` | string | No | Email para envío automático |
| `telefono` | string | No | Teléfono |

---

## Array `documentos[]`

Cada elemento es un documento al que se le aplica la retención.

| Campo | Tipo | Requerido | Descripción |
|-------|------|-----------|-------------|
| `serie_documento` | string | **Sí** | Serie del documento (ej: `"F001"`) |
| `numero_documento` | string | **Sí** | Número del documento (ej: `"122"`) |
| `codigo_tipo_documento` | string | **Sí** | `"01"` Factura, `"03"` Boleta, etc. |
| `fecha_de_emision` | string | **Sí** | Fecha de emisión del documento original |
| `codigo_tipo_moneda` | string | **Sí** | Moneda del documento original |
| `total_documento` | float | **Sí** | Total del documento original |
| `fecha_de_retencion` | string | **Sí** | Fecha en que se efectúa la retención |
| `total_retencion` | float | **Sí** | Monto de retención para este documento |
| `total_a_pagar` | float | **Sí** | `total_documento - total_retencion` |
| `tipo_de_cambio` | object | **Sí** | Tipo de cambio al momento de la retención |
| `pagos` | array | **Sí** | Pagos realizados por este documento |

### Objeto `tipo_de_cambio`

| Campo | Tipo | Descripción |
|-------|------|-------------|
| `codigo_tipo_moneda_referencia` | string | Moneda del documento |
| `codigo_tipo_moneda_objetivo` | string | Moneda de pago |
| `factor` | float | Factor de cambio. `1` si ambas monedas son iguales |
| `fecha_de_cambio` | string | `YYYY-MM-DD` |

### Array `pagos[]` (dentro de cada documento)

| Campo | Tipo | Requerido | Descripción |
|-------|------|-----------|-------------|
| `codigo_metodo_pago` | string | **Sí** | `"001"` Efectivo, `"002"` Cheque, `"003"` Transferencia |
| `monto` | float | **Sí** | Monto del pago |
| `fecha_de_pago` | string | **Sí** | `YYYY-MM-DD` |

---

## Response (200 OK)

```json
{
    "success": true,
    "data": {
        "number": "R001-1",
        "filename": "20538856674-20-R001-1",
        "external_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
    },
    "links": {
        "xml": "https://demo.nt-suite.pro/downloads/document/xml/a1b2c3d4...",
        "pdf": "https://demo.nt-suite.pro/downloads/document/pdf/a1b2c3d4...",
        "cdr": "https://demo.nt-suite.pro/downloads/document/cdr/a1b2c3d4..."
    },
    "response": {
        "code": "0",
        "description": "El Comprobante de Retención R001-1 ha sido aceptado"
    }
}
```

---

## Cálculos

```
Por cada documento:
  total_retencion = total_documento × tasa_retencion / 100
  total_a_pagar   = total_documento - total_retencion

Totales del CRE:
  total_retencion (cabecera) = Σ documentos[].total_retencion
  total_pago      (cabecera) = Σ documentos[].total_a_pagar
```

---

## Notas para Offline

- **Uso desde Flutter:** Este documento es poco frecuente en operación POS. Normalmente se emite desde el módulo contable/administrativo de la web.
- **Serie R001:** Las series de retención se obtienen de `GET /api/offline/series-numbering` con `tipo_documento=20`. Ver [07-series-numeracion.md](07-series-numeracion.md).
- **Sync-batch:** Se puede sincronizar retenciones en el batch usando `tipo_documento: "20"`. El `OfflineSyncController` redirige a `POST /api/retentions`.
- **Idempotencia:** El campo `offline_id` funciona igual que para los demás documentos. La unicidad se controla por el `filename`: `{RUC}-20-{serie}-{numero}`.
