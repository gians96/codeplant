# 09 — Boleta y Factura Electrónica

> `POST /api/documents`  
> **Controller:** `Tenant\Api\DocumentController@store`  
> **Middleware:** `input.request:document,api` (transforma campos español → inglés)  
> **Auth:** `Bearer {token}`  
> **Código tipo:** `"03"` (Boleta) · `"01"` (Factura)

---

## Pipeline de Procesamiento

```
Payload (español) → DocumentTransform → DocumentValidation → DocumentInput → Facturalo::save()
                     ↓                    ↓                    ↓
               Traduce campos       Valida series,       Genera external_id,
               español→inglés      persona, items       type, series/number
```

---

## Request

### Headers

```
Content-Type: application/json
Accept: application/json
Authorization: Bearer {token}
```

### Payload — Boleta (codigo_tipo_documento: "03")

```json
{
    "serie_documento": "B001",
    "numero_documento": "#",
    "fecha_de_emision": "2026-04-18",
    "hora_de_emision": "14:30:00",
    "codigo_tipo_operacion": "0101",
    "codigo_tipo_documento": "03",
    "codigo_tipo_moneda": "PEN",
    "fecha_de_vencimiento": "2026-05-18",
    "numero_orden_de_compra": "",
    "numero_de_placa": "",
    "codigo_vendedor": 1,
    "codigo_condicion_de_pago": "01",
    "informacion_adicional": null,
    "pagos": [
        {
            "codigo_metodo_pago": "01",
            "codigo_destino_pago": null,
            "monto": 105.69,
            "referencia": null,
            "pago_recibido": 110.00
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
        },
        {
            "codigo_interno": "FFF",
            "descripcion": "Producto KG",
            "codigo_producto_sunat": null,
            "unidad_de_medida": "KGM",
            "cantidad": 1,
            "valor_unitario": 86.4406779661017,
            "precio_unitario": 102,
            "codigo_tipo_precio": "01",
            "codigo_tipo_afectacion_igv": "10",
            "total_base_igv": 86.4406779661017,
            "porcentaje_igv": 18,
            "total_igv": 15.559322033898297,
            "total_impuestos": 15.559322033898297,
            "total_valor_item": 86.4406779661017,
            "total_item": 102
        }
    ],
    "totales": {
        "total_exportacion": 0,
        "total_operaciones_gravadas": 89.5677966101695,
        "total_operaciones_inafectas": 0,
        "total_operaciones_exoneradas": 0,
        "total_operaciones_gratuitas": 0,
        "total_igv": 16.1222033898305,
        "total_impuestos": 16.1222033898305,
        "total_valor": 89.5677966101695,
        "total_venta": 105.69
    }
}
```

### Payload — Factura (codigo_tipo_documento: "01")

Misma estructura, con diferencias:

| Campo | Boleta (03) | Factura (01) |
|-------|-------------|--------------|
| `serie_documento` | `"B001"` | `"F001"` |
| `codigo_tipo_documento` | `"03"` | `"01"` |
| `datos_del_cliente_o_receptor.codigo_tipo_documento_identidad` | `"1"` (DNI) o `"0"` (sin doc) | `"6"` (RUC) **obligatorio** |
| Cuotas de pago (crédito) | Opcional | Permitido |

---

## Campos del Payload

### Cabecera

| Campo | Tipo | Requerido | Descripción |
|-------|------|-----------|-------------|
| `serie_documento` | string | **Sí** | Serie: `"F001"`, `"B001"` |
| `numero_documento` | string | **Sí** | `"#"` = auto-numerar. Para offline: número concreto `"90"` |
| `fecha_de_emision` | string | **Sí** | Formato `YYYY-MM-DD` |
| `hora_de_emision` | string | **Sí** | Formato `HH:mm:ss` |
| `codigo_tipo_operacion` | string | **Sí** | `"0101"` = Venta interna. Ver catálogo SUNAT |
| `codigo_tipo_documento` | string | **Sí** | `"01"` = Factura, `"03"` = Boleta |
| `codigo_tipo_moneda` | string | **Sí** | `"PEN"` = Soles, `"USD"` = Dólares |
| `fecha_de_vencimiento` | string | No | Formato `YYYY-MM-DD` |
| `numero_orden_de_compra` | string | No | Orden de compra del cliente |
| `numero_de_placa` | string | No | Placa de vehículo (combustibles) |
| `codigo_vendedor` | int | No | ID del vendedor (del login `sellerId`) |
| `codigo_condicion_de_pago` | string | No | `"01"` = Contado (default) |
| `informacion_adicional` | string\|null | No | Información extra para el PDF |
| `factor_tipo_de_cambio` | float | No | Tipo de cambio (default 1 para PEN) |

### `datos_del_cliente_o_receptor`

| Campo | Tipo | Requerido | Descripción |
|-------|------|-----------|-------------|
| `codigo_tipo_documento_identidad` | string | **Sí** | `"0"`, `"1"`, `"4"`, `"6"`, `"7"`, `"A"` |
| `numero_documento` | string | **Sí** | Número de documento |
| `apellidos_y_nombres_o_razon_social` | string | **Sí** | Nombre completo o razón social |
| `codigo_pais` | string | No | `"PE"` (default) |
| `ubigeo` | string | No | Código ubigeo (6 dígitos) |
| `direccion` | string\|null | No | Dirección fiscal |
| `correo_electronico` | string\|null | No | Email (para envío automático) |
| `telefono` | string\|null | No | Teléfono |

### `items[]`

| Campo | Tipo | Requerido | Descripción |
|-------|------|-----------|-------------|
| `codigo_interno` | string | **Sí** | `internal_id` del item descargado |
| `descripcion` | string | **Sí** | Descripción del producto |
| `codigo_producto_sunat` | string\|null | No | Código producto SUNAT |
| `unidad_de_medida` | string | **Sí** | `"NIU"` (unidad), `"KGM"` (kg), `"BX"` (caja), etc. |
| `cantidad` | float | **Sí** | Cantidad vendida |
| `valor_unitario` | float | **Sí** | Precio sin IGV = `precio_unitario / 1.18` (si gravado) |
| `precio_unitario` | float | **Sí** | Precio con IGV |
| `codigo_tipo_precio` | string | **Sí** | `"01"` = Precio unitario, `"02"` = Valor referencial (gratuito) |
| `codigo_tipo_afectacion_igv` | string | **Sí** | `"10"` = Gravado, `"20"` = Exonerado, `"30"` = Inafecto |
| `total_base_igv` | float | **Sí** | Base imponible = `valor_unitario * cantidad` |
| `porcentaje_igv` | float | **Sí** | `18` (tasa IGV estándar) |
| `total_igv` | float | **Sí** | IGV del item = `total_base_igv * porcentaje_igv / 100` |
| `total_impuestos` | float | **Sí** | Total impuestos del item (= total_igv + total_isc + ...) |
| `total_valor_item` | float | **Sí** | Valor sin impuestos = `valor_unitario * cantidad` |
| `total_item` | float | **Sí** | Total con impuestos = `precio_unitario * cantidad` |

#### Campos opcionales del item

| Campo | Tipo | Descripción |
|-------|------|-------------|
| `nombre` | string | Nombre del producto (diferente a descripción) |
| `codigo_tipo_sistema_isc` | string | Tipo sistema ISC |
| `total_base_isc` | float | Base ISC |
| `porcentaje_isc` | float | Porcentaje ISC |
| `total_isc` | float | Total ISC |
| `total_base_otros_impuestos` | float | Base otros impuestos |
| `porcentaje_otros_impuestos` | float | % otros impuestos |
| `total_otros_impuestos` | float | Total otros impuestos |
| `total_impuestos_bolsa_plastica` | float | Impuesto bolsa plástica |
| `total_descuentos` | float | Descuento del item |
| `total_cargos` | float | Cargos del item |
| `descuentos` | array | Descuentos detallados |
| `cargos` | array | Cargos detallados |
| `datos_adicionales` | array | Atributos extra |
| `lots` | array | Lotes/series del item |
| `nombre_producto_pdf` | string | Nombre para el PDF |
| `nombre_producto_xml` | string | Nombre para el XML |
| `dato_adicional` | string | Dato adicional libre |

### `pagos[]`

| Campo | Tipo | Requerido | Descripción |
|-------|------|-----------|-------------|
| `codigo_metodo_pago` | string | **Sí** | `"01"` Efectivo, `"02"` Tarjeta crédito, etc. |
| `codigo_destino_pago` | int\|null | No | ID destino de pago |
| `monto` | float | **Sí** | Monto del pago |
| `referencia` | string\|null | No | Número de operación, voucher, etc. |
| `pago_recibido` | float | No | Monto recibido (para calcular vuelto) |

### `totales`

| Campo | Tipo | Requerido | Descripción |
|-------|------|-----------|-------------|
| `total_exportacion` | float | No | Total operaciones exportación |
| `total_operaciones_gravadas` | float | **Sí** | Suma de `total_base_igv` de items gravados |
| `total_operaciones_inafectas` | float | No | Suma de inafectas |
| `total_operaciones_exoneradas` | float | No | Suma de exoneradas |
| `total_operaciones_gratuitas` | float | No | Suma de gratuitas |
| `total_igv` | float | **Sí** | Suma de `total_igv` de todos los items |
| `total_impuestos` | float | **Sí** | Suma de todos los impuestos |
| `total_valor` | float | **Sí** | Subtotal sin impuestos |
| `total_venta` | float | **Sí** | **Total final con impuestos** |

---

## Response (200 OK)

```json
{
    "success": true,
    "data": {
        "number": "B001-15",
        "filename": "20538856674-03-B001-15",
        "external_id": "4506ba3e-fd30-44b3-9646-603d8236a02f",
        "state_type_id": "01",
        "state_type_description": "Registrado",
        "number_to_letter": "Ciento cinco  con 69/100 ",
        "hash": "T4gJMYiqprUlPMnW8R07DAgQ2+8=",
        "qr": "...",
        "id": 123,
        "print_ticket": "https://demo.nt-suite.pro/print/document/4506ba3e-fd30-44b3-9646-603d8236a02f/ticket"
    },
    "data_ws": {
        "message_text": null,
        "pdf_a4_filename": "20538856674-03-B001-15.pdf",
        "full_filename": "20538856674-03-B001-15",
        "customer_telephone": null
    },
    "links": {
        "xml": "https://demo.nt-suite.pro/downloads/document/xml/4506ba3e-fd30-44b3-9646-603d8236a02f",
        "pdf": "https://demo.nt-suite.pro/downloads/document/pdf/4506ba3e-fd30-44b3-9646-603d8236a02f",
        "cdr": ""
    },
    "response": []
}
```

### Campos clave del response

| Campo | Tipo | Descripción |
|-------|------|-------------|
| `data.id` | int | ID del documento en BD |
| `data.number` | string | Número final asignado: `"B001-15"` |
| `data.external_id` | string | UUID del documento. Se usa para NC/ND y links |
| `data.filename` | string | `{RUC}-{tipo}-{serie}-{numero}` |
| `data.state_type_id` | string | `"01"` Registrado, `"03"` Enviado, `"05"` Aceptado |
| `data.print_ticket` | string | URL para imprimir ticket |
| `links.pdf` | string | URL para descargar PDF |
| `links.xml` | string | URL para descargar XML |
| `links.cdr` | string | URL para descargar CDR (constancia SUNAT) |

---

## Fórmulas de Cálculo para Flutter

```
Para item GRAVADO (codigo_tipo_afectacion_igv = "10"):
  valor_unitario     = precio_unitario / 1.18
  total_base_igv     = valor_unitario * cantidad
  total_igv          = total_base_igv * 0.18
  total_impuestos    = total_igv
  total_valor_item   = total_base_igv
  total_item         = precio_unitario * cantidad

Para item EXONERADO (codigo_tipo_afectacion_igv = "20"):
  valor_unitario     = precio_unitario
  total_base_igv     = valor_unitario * cantidad
  total_igv          = 0
  total_impuestos    = 0
  total_valor_item   = total_base_igv
  total_item         = total_base_igv

Para item INAFECTO (codigo_tipo_afectacion_igv = "30"):
  (mismo que exonerado)

Totales:
  total_operaciones_gravadas   = Σ total_base_igv (items con afectación "10")
  total_operaciones_exoneradas = Σ total_base_igv (items con afectación "20")
  total_operaciones_inafectas  = Σ total_base_igv (items con afectación "30")
  total_igv      = Σ total_igv (todos los items)
  total_impuestos = total_igv + total_isc + total_otros_impuestos
  total_valor    = Σ total_valor_item
  total_venta    = total_valor + total_impuestos
```

---

## Notas para Offline

- Para modo offline, enviar `numero_documento` con el número concreto (ej: `"90"`) en vez de `"#"`.
- El `external_id` lo genera el backend (UUID). Para idempotencia offline se usa el campo `offline_id` en `sync-batch` (ver [16-idempotencia.md](16-idempotencia.md)).
- El `filename` tiene constraint UNIQUE en BD: `{RUC}-{tipo_doc}-{serie}-{numero}`. Si se envía un duplicado, el backend retorna error 1062 que `sync-batch` maneja retornando el documento existente.
- Para ventas al contado: enviar al menos un elemento en `pagos[]`. Para crédito: enviar `cuotas[]`.
