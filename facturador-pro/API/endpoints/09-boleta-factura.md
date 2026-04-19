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

## Tipos de Operación (`codigo_tipo_operacion`)

| Código | Nombre | Descripción | Campos adicionales requeridos |
|--------|--------|-------------|-------------------------------|
| `0101` | **Venta interna** | Operación gravada estándar (la más común) | Ninguno |
| `0112` | **Compra interna** | Compra interna | Ninguno |
| `0200` | **Exportación de Bienes** | Venta a clientes en el extranjero | `total_exportacion` en totales |
| `0201` | **Ventas no domiciliados** | Ventas a no domiciliados que no califican como exportación | — |
| `1001` | **Operación Sujeta a Detracción** | Requiere bloque `detraccion{}` en el payload | `detraccion{}` (ver sección abajo) |
| `1004` | **Detracción - Servicios Transporte Carga** | Detracción específica para transporte | `detraccion{}` con campos de transporte |

> **Para Flutter offline:** Los más usados son `0101` (venta interna) y `1001` (detracción).
> Al seleccionar `1001` o `1004`, se agrega automáticamente la leyenda `2006` = "Operación sujeta a detracción".

---

## Detracciones (`detraccion`)

Cuando `codigo_tipo_operacion` es `"1001"` o `"1004"`, se debe incluir el bloque `detraccion` en el payload. Se envía dentro del mismo JSON a nivel raíz (no dentro de items ni totales).

> **Ref código:** `DocumentTransform.php` → método `detraction()` transforma los campos español→inglés.

### Campos del objeto `detraccion`

| Campo | Tipo | Requerido | Descripción |
|-------|------|-----------|-------------|
| `codigo_tipo_detraccion` | string | **Sí** | Código del bien/servicio sujeto a detracción (catálogo SUNAT 54). Ej: `"037"` (demás servicios gravados con IGV) |
| `porcentaje` | float | **Sí** | Porcentaje de detracción. Ej: `12` |
| `monto` | float | **Sí** | Monto de detracción = `total_venta * porcentaje / 100` |
| `codigo_metodo_pago` | string | **Sí** | `"001"` = Depósito en cuenta |
| `cuenta_bancaria` | string | **Sí** | Número de cuenta Banco de la Nación del proveedor |

#### Campos adicionales para transporte (`1004`)

| Campo | Tipo | Requerido (1004) | Descripción |
|-------|------|-------------------|-------------|
| `detalle_viaje` | string | Sí | Descripción del viaje |
| `direccion_origen` | string | Sí | Dirección punto de partida |
| `direccion_destino` | string | Sí | Dirección punto de llegada |
| `ubigeo_origen` | string | Sí | Ubigeo de origen (6 dígitos) |
| `ubigeo_destino` | string | Sí | Ubigeo de destino (6 dígitos) |
| `valor_referencial_carga_util` | float | No | Valor referencial servicio de transporte carga útil |
| `valor_referencial_servicio_transporte` | float | No | Valor referencial servicio transporte |
| `valor_referencia_carga_efectiva` | float | No | Valor referencia carga efectiva |

### Ejemplo — Factura con detracción (`1001`)

```json
{
    "serie_documento": "F001",
    "numero_documento": "#",
    "fecha_de_emision": "2026-04-18",
    "hora_de_emision": "14:30:00",
    "codigo_tipo_operacion": "1001",
    "codigo_tipo_documento": "01",
    "codigo_tipo_moneda": "PEN",
    "fecha_de_vencimiento": "2026-05-18",
    "datos_del_cliente_o_receptor": {
        "codigo_tipo_documento_identidad": "6",
        "numero_documento": "20501973522",
        "apellidos_y_nombres_o_razon_social": "EMPRESA XYZ S.A.C.",
        "codigo_pais": "PE",
        "ubigeo": "150101",
        "direccion": "Av. Argentina 2458",
        "correo_electronico": "contabilidad@empresa.com",
        "telefono": "01-4271148"
    },
    "detraccion": {
        "codigo_tipo_detraccion": "037",
        "porcentaje": 12,
        "monto": 6000,
        "codigo_metodo_pago": "001",
        "cuenta_bancaria": "00-071-123456"
    },
    "totales": {
        "total_exportacion": 0,
        "total_operaciones_gravadas": 42372.88,
        "total_operaciones_inafectas": 0,
        "total_operaciones_exoneradas": 0,
        "total_operaciones_gratuitas": 0,
        "total_igv": 7627.12,
        "total_impuestos": 7627.12,
        "total_valor": 42372.88,
        "total_venta": 50000
    },
    "items": [
        {
            "codigo_interno": "OLV30",
            "descripcion": "ACEITE DE OLIVA COSMETICO FCO X30ML",
            "codigo_producto_sunat": "51121703",
            "unidad_de_medida": "NIU",
            "cantidad": 500,
            "valor_unitario": 84.7457627118644,
            "precio_unitario": 100,
            "codigo_tipo_precio": "01",
            "codigo_tipo_afectacion_igv": "10",
            "total_base_igv": 42372.88,
            "porcentaje_igv": 18,
            "total_igv": 7627.12,
            "total_impuestos": 7627.12,
            "total_valor_item": 42372.88,
            "total_item": 50000
        }
    ],
    "pagos": [
        {
            "codigo_metodo_pago": "01",
            "monto": 50000
        }
    ]
}
```

> **Leyendas automáticas:** Al usar `1001`, el backend agrega automáticamente `legends[{code:"2006", value:"Operación sujeta a detracción"}]`.

---

## Retención de IGV (`retencion`)

Cuando el cliente es agente de retención del IGV, se puede marcar el documento con retención. Esto no es lo mismo que el comprobante de retención (tipo 20). La retención de IGV se aplica **dentro** del documento (factura/boleta).

> **Ref código:** `invoice.vue` → `changeRetention()`. El campo se almacena como JSON en `Document.retention`.

### Campos del objeto `retencion`

| Campo | Tipo | Requerido | Descripción |
|-------|------|-----------|-------------|
| `code` | string | **Sí** | `"62"` = Retención IGV |
| `percentage` | float | **Sí** | Porcentaje de retención (ej: `3` → 0.03 internamente). Se toma de `config.igv_retention_percentage` |
| `amount` | float | **Sí** | Monto de retención = `base * percentage / 100` |
| `base` | float | **Sí** | Base imponible (normalmente = `total_venta`) |
| `currency_type_id` | string | **Sí** | `"PEN"` o `"USD"` |
| `exchange_rate` | float | No | Tipo de cambio al momento de la retención |

### Ejemplo — Factura con retención IGV

```json
{
    "serie_documento": "F001",
    "numero_documento": "#",
    "fecha_de_emision": "2026-04-18",
    "hora_de_emision": "14:30:00",
    "codigo_tipo_operacion": "0101",
    "codigo_tipo_documento": "01",
    "codigo_tipo_moneda": "PEN",
    "retencion": {
        "code": "62",
        "percentage": 3,
        "amount": 3.54,
        "base": 118,
        "currency_type_id": "PEN",
        "exchange_rate": 1
    },
    "datos_del_cliente_o_receptor": { "..." : "..." },
    "totales": { "..." : "..." },
    "items": [ "..." ]
}
```

> **Nota:** La retención impacta en `total_pending_payment` cuando la condición de pago es crédito (`02`/`03`): el monto pendiente se reduce por el monto de retención.

---

## Condiciones de Pago (`codigo_condicion_de_pago`)

Determina cómo se estructura el pago del comprobante.

| Código | Nombre | Descripción |
|--------|--------|-------------|
| `01` | **Contado** | Pago inmediato. Default si no se envía. Requiere `pagos[]` |
| `02` | **Crédito** | Pago a plazos sin cuotas definidas |
| `03` | **Crédito con cuotas** | Pago a plazos con calendario de cuotas |

### `pagos[]` — Para contado (`01`)

Ya documentado arriba. Se envían los pagos realizados al momento de la venta.

### `cuotas[]` — Para crédito (`02` / `03`)

| Campo | Tipo | Requerido | Descripción |
|-------|------|-----------|-------------|
| `fecha` | string | **Sí** | Fecha de vencimiento de la cuota `YYYY-MM-DD` |
| `codigo_tipo_moneda` | string | **Sí** | `"PEN"`, `"USD"` |
| `monto` | float | **Sí** | Monto de la cuota |
| `codigo_tipo_metodo_pago` | string | No | Método de pago esperado |

### Ejemplo — Factura a crédito con cuotas

```json
{
    "serie_documento": "F001",
    "numero_documento": "#",
    "fecha_de_emision": "2026-04-18",
    "hora_de_emision": "14:30:00",
    "codigo_tipo_operacion": "0101",
    "codigo_tipo_documento": "01",
    "codigo_tipo_moneda": "PEN",
    "codigo_condicion_de_pago": "03",
    "datos_del_cliente_o_receptor": {
        "codigo_tipo_documento_identidad": "6",
        "numero_documento": "20501973522",
        "apellidos_y_nombres_o_razon_social": "EMPRESA XYZ S.A.C.",
        "codigo_pais": "PE",
        "direccion": "Av. Argentina 2458"
    },
    "cuotas": [
        {
            "fecha": "2026-05-18",
            "codigo_tipo_moneda": "PEN",
            "monto": 59
        },
        {
            "fecha": "2026-06-18",
            "codigo_tipo_moneda": "PEN",
            "monto": 59
        }
    ],
    "totales": {
        "total_operaciones_gravadas": 100,
        "total_igv": 18,
        "total_impuestos": 18,
        "total_valor": 100,
        "total_venta": 118
    },
    "items": [
        {
            "codigo_interno": "P0121",
            "descripcion": "Inca Kola 250 ml",
            "unidad_de_medida": "NIU",
            "cantidad": 2,
            "valor_unitario": 50,
            "precio_unitario": 59,
            "codigo_tipo_precio": "01",
            "codigo_tipo_afectacion_igv": "10",
            "total_base_igv": 100,
            "porcentaje_igv": 18,
            "total_igv": 18,
            "total_impuestos": 18,
            "total_valor_item": 100,
            "total_item": 118
        }
    ]
}
```

---

## Campos Adicionales del Item (detalle completo)

Además de los campos requeridos ya documentados, cada item soporta estos campos opcionales que se envían dentro del array `items[]`:

### `informacion_adicional`

```json
{
    "codigo_interno": "P001",
    "descripcion": "Producto ejemplo",
    "informacion_adicional": "Color: Rojo | Talla: M",
    "...": "..."
}
```

Se muestra en el PDF debajo de la descripción del item.

### `warehouse_id` — Stock por almacén

```json
{
    "codigo_interno": "P001",
    "warehouse_id": 2,
    "...": "..."
}
```

Indica desde qué almacén se descuenta el stock. Si no se envía, se usa el almacén del establecimiento del usuario autenticado.

> **Para Flutter offline:** Enviar el `warehouse_id` del establecimiento asociado. Se obtiene de la descarga inicial (`company` → `establishments[]` → `warehouse.id`).

### `lots[]` — Lotes y series

```json
{
    "codigo_interno": "P001",
    "lots": [
        {
            "serie": "LOTE-2026-001",
            "date": "2027-12-31",
            "quantity": 10
        }
    ],
    "...": "..."
}
```

### `descuentos[]` y `cargos[]`

```json
{
    "codigo_interno": "P001",
    "descuentos": [
        {
            "codigo_tipo_descuento": "00",
            "descripcion": "Descuento 10%",
            "porcentaje": 10,
            "monto": 10,
            "base": 100
        }
    ],
    "cargos": [
        {
            "codigo_tipo_cargo": "50",
            "descripcion": "Cargo adicional",
            "porcentaje": 0,
            "monto": 5,
            "base": 100
        }
    ],
    "...": "..."
}
```

### `datos_adicionales[]` — Atributos

```json
{
    "codigo_interno": "P001",
    "datos_adicionales": [
        {
            "codigo": "5010",
            "descripcion": "Número de placa",
            "valor": "ABC-123",
            "fecha_inicio": null,
            "fecha_fin": null,
            "duracion": null
        }
    ],
    "...": "..."
}
```

---

## Campos Adicionales del Documento

Campos opcionales a nivel raíz del payload que controlan comportamientos especiales:

| Campo | Tipo | Descripción |
|-------|------|-------------|
| `numero_orden_de_compra` | string | Número de orden de compra del cliente |
| `numero_de_placa` | string | Placa del vehículo (usado en grifos/combustibles) |
| `codigo_vendedor` | int | ID del vendedor asignado. Ref: [06-vendedores.md](06-vendedores.md) |
| `informacion_adicional` | string\|null | Info extra para PDF. Formato pipe-separated: `"Forma de pago:Efectivo\|Caja: 1"` |
| `factor_tipo_de_cambio` | float | Tipo de cambio cuando la moneda es USD. Default `1` para PEN |
| `acciones` | object | Control de envío (ver sección Factura Sin Enviar) |

### `guias[]` — Guías de remisión vinculadas

```json
{
    "guias": [
        {
            "codigo_tipo_documento": "09",
            "numero_documento": "T001-1"
        },
        {
            "codigo_tipo_documento": "31",
            "numero_documento": "V001-1"
        }
    ],
    "...": "..."
}
```

### `anticipos[]` — Pagos anticipados

```json
{
    "anticipos": [
        {
            "codigo_tipo_documento": "02",
            "numero_documento": "F001-5",
            "codigo_tipo_moneda": "PEN",
            "monto": 500
        }
    ],
    "...": "..."
}
```

### `leyendas[]` — Leyendas SUNAT

Se agregan automáticamente según el tipo de operación, pero pueden enviarse manualmente:

```json
{
    "leyendas": [
        {
            "codigo": "1000",
            "valor": "CIENTO DIECIOCHO CON 00/100 SOLES"
        },
        {
            "codigo": "2006",
            "valor": "Operación sujeta a detracción"
        }
    ]
}
```

---

## Factura de Contingencia

Para generar una factura de contingencia, debe registrar previamente las series de contingencia en el módulo **Usuarios/Locales & Series** → sección **Establecimientos**.

Las series de contingencia **empiezan con `0`** (ej: `0001`, `0F01`).

```json
{
    "serie_documento": "0001",
    "numero_documento": "#",
    "codigo_tipo_operacion": "0101",
    "codigo_tipo_documento": "01",
    "...": "resto del payload normal"
}
```

> **Para Flutter offline:** Si se detecta que no hay internet y la empresa tiene series de contingencia configuradas, usar la serie `0###` para que SUNAT acepte el envío posterior. Las series normales (`F001`, `B001`) también se pueden generar sin enviar usando `acciones.enviar_xml_firmado: false`.

---

## Factura Sin Enviar a SUNAT (modo offline del backend)

Se puede generar el documento completo (XML + PDF) sin enviarlo a SUNAT. Útil cuando el servidor no tiene internet pero el Flutter sí pudo sincronizar.

### Paso 1 — Crear sin enviar

Agregar el bloque `acciones` al payload:

```json
{
    "serie_documento": "F001",
    "numero_documento": "#",
    "codigo_tipo_operacion": "0101",
    "codigo_tipo_documento": "01",
    "acciones": {
        "enviar_xml_firmado": false
    },
    "...": "resto del payload"
}
```

El documento se crea con `state_type_id: "01"` (Registrado) en vez de `"03"` (Enviado).

### Paso 2 — Enviar posteriormente

```
POST /api/documents/send
Authorization: Bearer {token}
```

```json
{
    "external_id": "2dded172-cd17-4078-9c88-10a9b1177f2d"
}
```

**Response (200):**
```json
{
    "success": true,
    "data": {
        "number": "F001-1",
        "filename": "20538856674-01-F001-1",
        "external_id": "2dded172-cd17-4078-9c88-10a9b1177f2d"
    },
    "links": { "xml": "...", "pdf": "...", "cdr": "..." },
    "response": { "code": "0", "description": "La Factura ... ha sido aceptada" }
}
```

### Paso 3 — Actualizar estado manualmente

```
POST /api/documents/updatedocumentstatus
Authorization: Bearer {token}
```

```json
{
    "externail_id": "2dded172-cd17-4078-9c88-10a9b1177f2d",
    "state_type_id": "05"
}
```

> **Nota:** El campo se llama `externail_id` (con typo) en la API real. No es `external_id`.

**Estados disponibles:**

| Código | Estado |
|--------|--------|
| `01` | Registrado |
| `03` | Enviado |
| `05` | Aceptado |
| `07` | Observado |
| `09` | Rechazado |
| `11` | Anulado |
| `13` | Por anular |

---

## Variantes de Afectación IGV por Item

El campo `codigo_tipo_afectacion_igv` determina el tratamiento tributario de cada item:

### Gravado (código `10` - `17`)

| Código | Nombre | IGV | valor_unitario |
|--------|--------|-----|----------------|
| `10` | Gravado - Operación Onerosa | 18% | `precio_unitario / 1.18` |
| `11` | Gravado - Retiro por premio | 18% | `precio_unitario / 1.18` |
| `12` | Gravado - Retiro por donación | 18% | `precio_unitario / 1.18` |
| `13` | Gravado - Retiro | 18% | `precio_unitario / 1.18` |
| `14` | Gravado - Retiro por publicidad | 18% | `precio_unitario / 1.18` |
| `15` | Gravado - Bonificaciones | 18% | `precio_unitario / 1.18` |
| `16` | Gravado - Retiro (Gratuito) | 18% calcula pero `total_impuestos=0` | `0` (precio_referencial) |
| `17` | Gravado - Retiro por convenio colectivo | 18% | `precio_unitario / 1.18` |

### Exonerado (código `20` - `21`)

| Código | Nombre | IGV | valor_unitario |
|--------|--------|-----|----------------|
| `20` | Exonerado - Operación Onerosa | 0% | `= precio_unitario` |
| `21` | Exonerado - Gratuita | 0% | `0` |

### Inafecto (código `30` - `40`)

| Código | Nombre | IGV | valor_unitario |
|--------|--------|-----|----------------|
| `30` | Inafecto - Operación Onerosa | 0% | `= precio_unitario` |
| `31` | Inafecto - Retiro por bonificación | 0% | `0` |
| `32` | Inafecto - Retiro | 0% | `0` |
| `33` | Inafecto - Retiro por muestras médicas | 0% | `0` |
| `34` | Inafecto - Retiro por convenio colectivo | 0% | `0` |
| `35` | Inafecto - Retiro por premio | 0% | `0` |
| `36` | Inafecto - Retiro por publicidad | 0% | `0` |
| `37` | Inafecto - Transferencia gratuita | 0% | `0` |
| `40` | Exportación de bienes | 0% | `= precio_unitario` |

> **Gratuitos (códigos 11-17, 21, 31-37):** El `precio_unitario` debe ser `0`, pero se envía el valor referencial como `valor_unitario`. Se usa `codigo_tipo_precio: "02"` (valor referencial). Los totales se suman en `total_operaciones_gratuitas` en vez de `total_operaciones_gravadas`.

---

## Tipos de Operación (`codigo_tipo_operacion`)

| Código | Nombre | Descripción | Campos adicionales requeridos |
|--------|--------|-------------|-------------------------------|
| `0101` | **Venta interna** | Operación gravada estándar (la más común) | Ninguno |
| `0112` | **Compra interna** | Compra interna | Ninguno |
| `0200` | **Exportación de Bienes** | Venta a clientes en el extranjero | `total_exportacion` en totales |
| `0201` | **Ventas no domiciliados** | Ventas a no domiciliados que no califican como exportación | — |
| `1001` | **Operación Sujeta a Detracción** | Requiere bloque `detraccion{}` en el payload | `detraccion{}` (ver sección abajo) |
| `1004` | **Detracción - Servicios Transporte Carga** | Detracción específica para transporte | `detraccion{}` con campos de transporte |

> **Para Flutter offline:** Los más usados son `0101` (venta interna) y `1001` (detracción).
> Al seleccionar `1001` o `1004`, se agrega automáticamente la leyenda `2006` = "Operación sujeta a detracción".

---

## Detracciones (`detraccion`)

Cuando `codigo_tipo_operacion` es `"1001"` o `"1004"`, se debe incluir el bloque `detraccion` en el payload. Se envía dentro del mismo JSON a nivel raíz (no dentro de items ni totales).

> **Ref código:** `DocumentTransform.php` → método `detraction()` transforma los campos español→inglés.

### Campos del objeto `detraccion`

| Campo | Tipo | Requerido | Descripción |
|-------|------|-----------|-------------|
| `codigo_tipo_detraccion` | string | **Sí** | Código del bien/servicio sujeto a detracción (catálogo SUNAT 54). Ej: `"037"` (demás servicios gravados con IGV) |
| `porcentaje` | float | **Sí** | Porcentaje de detracción. Ej: `12` |
| `monto` | float | **Sí** | Monto de detracción = `total_venta * porcentaje / 100` |
| `codigo_metodo_pago` | string | **Sí** | `"001"` = Depósito en cuenta |
| `cuenta_bancaria` | string | **Sí** | Número de cuenta Banco de la Nación del proveedor |

#### Campos adicionales para transporte (`1004`)

| Campo | Tipo | Requerido (1004) | Descripción |
|-------|------|-------------------|-------------|
| `detalle_viaje` | string | Sí | Descripción del viaje |
| `direccion_origen` | string | Sí | Dirección punto de partida |
| `direccion_destino` | string | Sí | Dirección punto de llegada |
| `ubigeo_origen` | string | Sí | Ubigeo de origen (6 dígitos) |
| `ubigeo_destino` | string | Sí | Ubigeo de destino (6 dígitos) |
| `valor_referencial_carga_util` | float | No | Valor referencial servicio de transporte carga útil |
| `valor_referencial_servicio_transporte` | float | No | Valor referencial servicio transporte |
| `valor_referencia_carga_efectiva` | float | No | Valor referencia carga efectiva |

### Ejemplo — Factura con detracción (`1001`)

```json
{
    "serie_documento": "F001",
    "numero_documento": "#",
    "fecha_de_emision": "2026-04-18",
    "hora_de_emision": "14:30:00",
    "codigo_tipo_operacion": "1001",
    "codigo_tipo_documento": "01",
    "codigo_tipo_moneda": "PEN",
    "fecha_de_vencimiento": "2026-05-18",
    "datos_del_cliente_o_receptor": {
        "codigo_tipo_documento_identidad": "6",
        "numero_documento": "20501973522",
        "apellidos_y_nombres_o_razon_social": "EMPRESA XYZ S.A.C.",
        "codigo_pais": "PE",
        "ubigeo": "150101",
        "direccion": "Av. Argentina 2458",
        "correo_electronico": "contabilidad@empresa.com",
        "telefono": "01-4271148"
    },
    "detraccion": {
        "codigo_tipo_detraccion": "037",
        "porcentaje": 12,
        "monto": 6000,
        "codigo_metodo_pago": "001",
        "cuenta_bancaria": "00-071-123456"
    },
    "totales": {
        "total_exportacion": 0,
        "total_operaciones_gravadas": 42372.88,
        "total_operaciones_inafectas": 0,
        "total_operaciones_exoneradas": 0,
        "total_operaciones_gratuitas": 0,
        "total_igv": 7627.12,
        "total_impuestos": 7627.12,
        "total_valor": 42372.88,
        "total_venta": 50000
    },
    "items": [
        {
            "codigo_interno": "OLV30",
            "descripcion": "ACEITE DE OLIVA COSMETICO FCO X30ML",
            "codigo_producto_sunat": "51121703",
            "unidad_de_medida": "NIU",
            "cantidad": 500,
            "valor_unitario": 84.7457627118644,
            "precio_unitario": 100,
            "codigo_tipo_precio": "01",
            "codigo_tipo_afectacion_igv": "10",
            "total_base_igv": 42372.88,
            "porcentaje_igv": 18,
            "total_igv": 7627.12,
            "total_impuestos": 7627.12,
            "total_valor_item": 42372.88,
            "total_item": 50000
        }
    ],
    "pagos": [
        {
            "codigo_metodo_pago": "01",
            "monto": 50000
        }
    ]
}
```

> **Leyendas automáticas:** Al usar `1001`, el backend agrega automáticamente `legends[{code:"2006", value:"Operación sujeta a detracción"}]`.

---

## Retención de IGV (`retencion`)

Cuando el cliente es agente de retención del IGV, se puede marcar el documento con retención. Esto no es lo mismo que el comprobante de retención (tipo 20). La retención de IGV se aplica **dentro** del documento (factura/boleta).

> **Ref código:** `invoice.vue` → `changeRetention()`. El campo se almacena como JSON en `Document.retention`.

### Campos del objeto `retencion`

| Campo | Tipo | Requerido | Descripción |
|-------|------|-----------|-------------|
| `code` | string | **Sí** | `"62"` = Retención IGV |
| `percentage` | float | **Sí** | Porcentaje de retención (ej: `3` → 0.03 internamente). Se toma de `config.igv_retention_percentage` |
| `amount` | float | **Sí** | Monto de retención = `base * percentage / 100` |
| `base` | float | **Sí** | Base imponible (normalmente = `total_venta`) |
| `currency_type_id` | string | **Sí** | `"PEN"` o `"USD"` |
| `exchange_rate` | float | No | Tipo de cambio al momento de la retención |

### Ejemplo — Factura con retención IGV

```json
{
    "serie_documento": "F001",
    "numero_documento": "#",
    "fecha_de_emision": "2026-04-18",
    "hora_de_emision": "14:30:00",
    "codigo_tipo_operacion": "0101",
    "codigo_tipo_documento": "01",
    "codigo_tipo_moneda": "PEN",
    "retencion": {
        "code": "62",
        "percentage": 3,
        "amount": 3.54,
        "base": 118,
        "currency_type_id": "PEN",
        "exchange_rate": 1
    },
    "datos_del_cliente_o_receptor": { "..." : "..." },
    "totales": { "..." : "..." },
    "items": [ "..." ]
}
```

> **Nota:** La retención impacta en `total_pending_payment` cuando la condición de pago es crédito (`02`/`03`): el monto pendiente se reduce por el monto de retención.

---

## Condiciones de Pago (`codigo_condicion_de_pago`)

Determina cómo se estructura el pago del comprobante.

| Código | Nombre | Descripción |
|--------|--------|-------------|
| `01` | **Contado** | Pago inmediato. Default si no se envía. Requiere `pagos[]` |
| `02` | **Crédito** | Pago a plazos sin cuotas definidas |
| `03` | **Crédito con cuotas** | Pago a plazos con calendario de cuotas |

### `pagos[]` — Para contado (`01`)

Ya documentado arriba. Se envían los pagos realizados al momento de la venta.

### `cuotas[]` — Para crédito (`02` / `03`)

| Campo | Tipo | Requerido | Descripción |
|-------|------|-----------|-------------|
| `fecha` | string | **Sí** | Fecha de vencimiento de la cuota `YYYY-MM-DD` |
| `codigo_tipo_moneda` | string | **Sí** | `"PEN"`, `"USD"` |
| `monto` | float | **Sí** | Monto de la cuota |
| `codigo_tipo_metodo_pago` | string | No | Método de pago esperado |

### Ejemplo — Factura a crédito con cuotas

```json
{
    "serie_documento": "F001",
    "numero_documento": "#",
    "fecha_de_emision": "2026-04-18",
    "hora_de_emision": "14:30:00",
    "codigo_tipo_operacion": "0101",
    "codigo_tipo_documento": "01",
    "codigo_tipo_moneda": "PEN",
    "codigo_condicion_de_pago": "03",
    "datos_del_cliente_o_receptor": {
        "codigo_tipo_documento_identidad": "6",
        "numero_documento": "20501973522",
        "apellidos_y_nombres_o_razon_social": "EMPRESA XYZ S.A.C.",
        "codigo_pais": "PE",
        "direccion": "Av. Argentina 2458"
    },
    "cuotas": [
        {
            "fecha": "2026-05-18",
            "codigo_tipo_moneda": "PEN",
            "monto": 59
        },
        {
            "fecha": "2026-06-18",
            "codigo_tipo_moneda": "PEN",
            "monto": 59
        }
    ],
    "totales": {
        "total_operaciones_gravadas": 100,
        "total_igv": 18,
        "total_impuestos": 18,
        "total_valor": 100,
        "total_venta": 118
    },
    "items": [
        {
            "codigo_interno": "P0121",
            "descripcion": "Inca Kola 250 ml",
            "unidad_de_medida": "NIU",
            "cantidad": 2,
            "valor_unitario": 50,
            "precio_unitario": 59,
            "codigo_tipo_precio": "01",
            "codigo_tipo_afectacion_igv": "10",
            "total_base_igv": 100,
            "porcentaje_igv": 18,
            "total_igv": 18,
            "total_impuestos": 18,
            "total_valor_item": 100,
            "total_item": 118
        }
    ]
}
```

---

## Campos Adicionales del Item (detalle completo)

Además de los campos requeridos ya documentados, cada item soporta estos campos opcionales que se envían dentro del array `items[]`:

### `informacion_adicional`

```json
{
    "codigo_interno": "P001",
    "descripcion": "Producto ejemplo",
    "informacion_adicional": "Color: Rojo | Talla: M",
    "...": "..."
}
```

Se muestra en el PDF debajo de la descripción del item.

### `warehouse_id` — Stock por almacén

```json
{
    "codigo_interno": "P001",
    "warehouse_id": 2,
    "...": "..."
}
```

Indica desde qué almacén se descuenta el stock. Si no se envía, se usa el almacén del establecimiento del usuario autenticado.

> **Para Flutter offline:** Enviar el `warehouse_id` del establecimiento asociado. Se obtiene de la descarga inicial (`company` → `establishments[]` → `warehouse.id`).

### `lots[]` — Lotes y series

```json
{
    "codigo_interno": "P001",
    "lots": [
        {
            "serie": "LOTE-2026-001",
            "date": "2027-12-31",
            "quantity": 10
        }
    ],
    "...": "..."
}
```

### `descuentos[]` y `cargos[]`

```json
{
    "codigo_interno": "P001",
    "descuentos": [
        {
            "codigo_tipo_descuento": "00",
            "descripcion": "Descuento 10%",
            "porcentaje": 10,
            "monto": 10,
            "base": 100
        }
    ],
    "cargos": [
        {
            "codigo_tipo_cargo": "50",
            "descripcion": "Cargo adicional",
            "porcentaje": 0,
            "monto": 5,
            "base": 100
        }
    ],
    "...": "..."
}
```

### `datos_adicionales[]` — Atributos

```json
{
    "codigo_interno": "P001",
    "datos_adicionales": [
        {
            "codigo": "5010",
            "descripcion": "Número de placa",
            "valor": "ABC-123",
            "fecha_inicio": null,
            "fecha_fin": null,
            "duracion": null
        }
    ],
    "...": "..."
}
```

---

## Campos Adicionales del Documento

Campos opcionales a nivel raíz del payload que controlan comportamientos especiales:

| Campo | Tipo | Descripción |
|-------|------|-------------|
| `numero_orden_de_compra` | string | Número de orden de compra del cliente |
| `numero_de_placa` | string | Placa del vehículo (usado en grifos/combustibles) |
| `codigo_vendedor` | int | ID del vendedor asignado. Ref: [06-vendedores.md](06-vendedores.md) |
| `informacion_adicional` | string\|null | Info extra para PDF. Formato pipe-separated: `"Forma de pago:Efectivo\|Caja: 1"` |
| `factor_tipo_de_cambio` | float | Tipo de cambio cuando la moneda es USD. Default `1` para PEN |
| `acciones` | object | Control de envío (ver sección Factura Sin Enviar) |

### `guias[]` — Guías de remisión vinculadas

```json
{
    "guias": [
        {
            "codigo_tipo_documento": "09",
            "numero_documento": "T001-1"
        },
        {
            "codigo_tipo_documento": "31",
            "numero_documento": "V001-1"
        }
    ],
    "...": "..."
}
```

### `anticipos[]` — Pagos anticipados

```json
{
    "anticipos": [
        {
            "codigo_tipo_documento": "02",
            "numero_documento": "F001-5",
            "codigo_tipo_moneda": "PEN",
            "monto": 500
        }
    ],
    "...": "..."
}
```

### `leyendas[]` — Leyendas SUNAT

Se agregan automáticamente según el tipo de operación, pero pueden enviarse manualmente:

```json
{
    "leyendas": [
        {
            "codigo": "1000",
            "valor": "CIENTO DIECIOCHO CON 00/100 SOLES"
        },
        {
            "codigo": "2006",
            "valor": "Operación sujeta a detracción"
        }
    ]
}
```

---

## Factura de Contingencia

Para generar una factura de contingencia, debe registrar previamente las series de contingencia en el módulo **Usuarios/Locales & Series** → sección **Establecimientos**.

Las series de contingencia **empiezan con `0`** (ej: `0001`, `0F01`).

```json
{
    "serie_documento": "0001",
    "numero_documento": "#",
    "codigo_tipo_operacion": "0101",
    "codigo_tipo_documento": "01",
    "...": "resto del payload normal"
}
```

> **Para Flutter offline:** Si se detecta que no hay internet y la empresa tiene series de contingencia configuradas, usar la serie `0###` para que SUNAT acepte el envío posterior. Las series normales (`F001`, `B001`) también se pueden generar sin enviar usando `acciones.enviar_xml_firmado: false`.

---

## Factura Sin Enviar a SUNAT (modo offline del backend)

Se puede generar el documento completo (XML + PDF) sin enviarlo a SUNAT. Útil cuando el servidor no tiene internet pero el Flutter sí pudo sincronizar.

### Paso 1 — Crear sin enviar

Agregar el bloque `acciones` al payload:

```json
{
    "serie_documento": "F001",
    "numero_documento": "#",
    "codigo_tipo_operacion": "0101",
    "codigo_tipo_documento": "01",
    "acciones": {
        "enviar_xml_firmado": false
    },
    "...": "resto del payload"
}
```

El documento se crea con `state_type_id: "01"` (Registrado) en vez de `"03"` (Enviado).

### Paso 2 — Enviar posteriormente

```
POST /api/documents/send
Authorization: Bearer {token}
```

```json
{
    "external_id": "2dded172-cd17-4078-9c88-10a9b1177f2d"
}
```

**Response (200):**
```json
{
    "success": true,
    "data": {
        "number": "F001-1",
        "filename": "20538856674-01-F001-1",
        "external_id": "2dded172-cd17-4078-9c88-10a9b1177f2d"
    },
    "links": { "xml": "...", "pdf": "...", "cdr": "..." },
    "response": { "code": "0", "description": "La Factura ... ha sido aceptada" }
}
```

### Paso 3 — Actualizar estado manualmente

```
POST /api/documents/updatedocumentstatus
Authorization: Bearer {token}
```

```json
{
    "externail_id": "2dded172-cd17-4078-9c88-10a9b1177f2d",
    "state_type_id": "05"
}
```

> **Nota:** El campo se llama `externail_id` (con typo) en la API real. No es `external_id`.

**Estados disponibles:**

| Código | Estado |
|--------|--------|
| `01` | Registrado |
| `03` | Enviado |
| `05` | Aceptado |
| `07` | Observado |
| `09` | Rechazado |
| `11` | Anulado |
| `13` | Por anular |

---

## Variantes de Afectación IGV por Item

El campo `codigo_tipo_afectacion_igv` determina el tratamiento tributario de cada item:

### Gravado (código `10` - `17`)

| Código | Nombre | IGV | valor_unitario |
|--------|--------|-----|----------------|
| `10` | Gravado - Operación Onerosa | 18% | `precio_unitario / 1.18` |
| `11` | Gravado - Retiro por premio | 18% | `precio_unitario / 1.18` |
| `12` | Gravado - Retiro por donación | 18% | `precio_unitario / 1.18` |
| `13` | Gravado - Retiro | 18% | `precio_unitario / 1.18` |
| `14` | Gravado - Retiro por publicidad | 18% | `precio_unitario / 1.18` |
| `15` | Gravado - Bonificaciones | 18% | `precio_unitario / 1.18` |
| `16` | Gravado - Retiro (Gratuito) | 18% calcula pero `total_impuestos=0` | `0` (precio_referencial) |
| `17` | Gravado - Retiro por convenio colectivo | 18% | `precio_unitario / 1.18` |

### Exonerado (código `20` - `21`)

| Código | Nombre | IGV | valor_unitario |
|--------|--------|-----|----------------|
| `20` | Exonerado - Operación Onerosa | 0% | `= precio_unitario` |
| `21` | Exonerado - Gratuita | 0% | `0` |

### Inafecto (código `30` - `40`)

| Código | Nombre | IGV | valor_unitario |
|--------|--------|-----|----------------|
| `30` | Inafecto - Operación Onerosa | 0% | `= precio_unitario` |
| `31` | Inafecto - Retiro por bonificación | 0% | `0` |
| `32` | Inafecto - Retiro | 0% | `0` |
| `33` | Inafecto - Retiro por muestras médicas | 0% | `0` |
| `34` | Inafecto - Retiro por convenio colectivo | 0% | `0` |
| `35` | Inafecto - Retiro por premio | 0% | `0` |
| `36` | Inafecto - Retiro por publicidad | 0% | `0` |
| `37` | Inafecto - Transferencia gratuita | 0% | `0` |
| `40` | Exportación de bienes | 0% | `= precio_unitario` |

> **Gratuitos (códigos 11-17, 21, 31-37):** El `precio_unitario` debe ser `0`, pero se envía el valor referencial como `valor_unitario`. Se usa `codigo_tipo_precio: "02"` (valor referencial). Los totales se suman en `total_operaciones_gratuitas` en vez de `total_operaciones_gravadas`.

---

## Extensiones por Giro de Negocio

Cuando algún giro de negocio está activo (ver [28-giros-de-negocio.md](28-giros-de-negocio.md)), el payload acepta bloques adicionales opcionales:

### Grifo — `numero_de_placa` + atributo `7000`

```json
{
    "numero_de_placa": "ABC-123",
    "items": [
        {
            "codigo_interno": "COMB-95",
            "unidad_de_medida": "GLN",
            "datos_adicionales": [
                {
                    "codigo": "7000",
                    "descripcion": "Gastos Art. 37 Renta: Número de Placa",
                    "valor": "ABC-123"
                }
            ]
        }
    ]
}
```

Detalle completo: [29-grifo-placas.md](29-grifo-placas.md).

### Farmacia — Lotes `IdLoteSelected`

```json
{
    "items": [
        {
            "codigo_interno": "MED-001",
            "cantidad": 5,
            "IdLoteSelected": 102
        },
        {
            "codigo_interno": "MED-002",
            "cantidad": 60,
            "IdLoteSelected": [
                { "id": 102, "compromise_quantity": 50 },
                { "id": 101, "compromise_quantity": 10 }
            ]
        }
    ]
}
```

Detalle completo: [30-lotes-series-farmacia.md](30-lotes-series-farmacia.md).

### Series (electrónicos) — `lots[]`

```json
{
    "items": [
        {
            "codigo_interno": "CEL-001",
            "cantidad": 1,
            "lots": [
                { "id": 50, "series": "IMEI-123456789012345", "has_sale": true }
            ]
        }
    ]
}
```

### Hotel — Bloque `hotel{}`

```json
{
    "hotel": {
        "number": "12345678",
        "name": "GARCÍA LÓPEZ MARÍA",
        "identity_document_type_id": "1",
        "sex": "F",
        "age": 35,
        "civil_status": "C",
        "nacionality": "PERUANA",
        "origin": "LIMA",
        "room_number": "301",
        "date_entry": "2026-04-18",
        "time_entry": "14:00:00",
        "date_exit": "2026-04-20",
        "time_exit": "12:00:00",
        "ocupation": "INGENIERA",
        "room_type": "matrimonial",
        "guests": []
    },
    "hotel_data_persons": [
        { "number": "12345678", "name": "GARCÍA LÓPEZ MARÍA" }
    ]
}
```

Detalle completo: [31-hotel-transporte-restaurante.md](31-hotel-transporte-restaurante.md).

### Transporte — Bloque `transport{}`

```json
{
    "transport": {
        "seat_number": "15A",
        "passenger_manifest": "MAN-2026-001",
        "identity_document_type_id": "1",
        "number_identity_document": "12345678",
        "passenger_fullname": "PÉREZ GARCÍA JUAN",
        "origin_district_id": ["15", "1501", "150101"],
        "origin_address": "Terminal Terrestre Lima",
        "destinatation_district_id": ["04", "0401", "040101"],
        "destinatation_address": "Terminal Terrestre Arequipa",
        "start_date": "2026-04-20",
        "start_time": "08:00:00"
    }
}
```

### Restaurante — Propina

```json
{
    "worker_full_name_tips": "CARLOS MOZO",
    "total_tips": 15.00
}
```

La propina NO se suma al `total_venta`. Es un registro informativo en la tabla `tips`.

---

## Notas para Offline

- Para modo offline, enviar `numero_documento` con el número concreto (ej: `"90"`) en vez de `"#"`.
- El `external_id` lo genera el backend (UUID). Para idempotencia offline se usa el campo `offline_id` en `sync-batch` (ver [16-idempotencia.md](16-idempotencia.md)).
- El `filename` tiene constraint UNIQUE en BD: `{RUC}-{tipo_doc}-{serie}-{numero}`. Si se envía un duplicado, el backend retorna error 1062 que `sync-batch` maneja retornando el documento existente.
- Para ventas al contado: enviar al menos un elemento en `pagos[]`. Para crédito: enviar `cuotas[]`.
- Para detracciones: Flutter debe calcular `monto = total_venta * porcentaje / 100` y enviar el bloque `detraccion{}` completo.
- Para retención IGV: Flutter calcula `amount = total_venta * igv_retention_percentage / 100` y envía `retencion{}`.
- Contingencia: usar series que empiecen con `0`. Se registran previamente en la web → Establecimientos.
- Factura sin enviar: agregar `acciones.enviar_xml_firmado: false`. Se puede enviar a SUNAT después con `POST /api/documents/send`.
- **Giros de negocio:** Si `is_pharmacy`, descontar lotes FEFO localmente. Si grifo, agregar atributo `7000` a cada item. Si hotel/transporte, agregar bloque `hotel{}`/`transport{}`. Ver [28-giros-de-negocio.md](28-giros-de-negocio.md).
