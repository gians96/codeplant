# 13 — Guía de Remisión Remitente

> `POST /api/dispatches`  
> **Controller:** `Tenant\Api\DispatchController@store`  
> **Middleware:** `input.request:dispatch,api` (transforma campos español → inglés)  
> **Auth:** `Bearer {token}`  
> **Código tipo:** `"09"`

---

## Descripción

La guía de remisión del remitente documenta el **traslado de bienes** desde un punto de partida hasta un destino. Se emite cuando la empresa es quien envía la mercadería.

---

## Payload

```json
{
    "serie_documento": "T001",
    "numero_documento": "#",
    "fecha_de_emision": "2026-04-18",
    "hora_de_emision": "08:00:00",
    "codigo_tipo_documento": "09",
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
    "observaciones": "Traslado de mercadería por venta",
    "codigo_modo_transporte": "01",
    "codigo_motivo_traslado": "01",
    "descripcion_motivo_traslado": "Venta",
    "fecha_de_traslado": "2026-04-19",
    "indicador_de_transbordo": false,
    "unidad_peso_total": "KGM",
    "peso_total": 25.5,
    "numero_de_bultos": 3,
    "numero_de_contenedor": null,
    "direccion_partida": {
        "ubigeo": "150101",
        "direccion": "Av. Principal 123, Lima",
        "codigo_del_domicilio_fiscal": "0000"
    },
    "direccion_llegada": {
        "ubigeo": "150132",
        "direccion": "Jr. Los Olivos 456, San Juan de Lurigancho",
        "codigo_del_domicilio_fiscal": null
    },
    "transportista": {
        "codigo_tipo_documento_identidad": "6",
        "numero_documento": "20100130204",
        "apellidos_y_nombres_o_razon_social": "TRANSPORTES LIMA S.A.C.",
        "numero_mtc": "123456"
    },
    "chofer": {
        "codigo_tipo_documento_identidad": "1",
        "numero_documento": "12345678",
        "nombres": "JUAN PEREZ GARCIA",
        "numero_licencia": "Q12345678",
        "telefono": "999888777"
    },
    "vehiculo": {
        "numero_de_placa": "ABC-123",
        "modelo": "HINO 500",
        "marca": "HINO",
        "certificado_habilitacion_vehicular": null
    },
    "items": [
        {
            "codigo_interno": "ASD",
            "descripcion": "Precio",
            "unidad_de_medida": "NIU",
            "cantidad": 10,
            "valor_unitario": 3.13,
            "precio_unitario": 3.69,
            "codigo_tipo_precio": "01",
            "codigo_tipo_afectacion_igv": "10",
            "total_base_igv": 31.3,
            "porcentaje_igv": 18,
            "total_igv": 5.63,
            "total_impuestos": 5.63,
            "total_valor_item": 31.3,
            "total_item": 36.93
        }
    ]
}
```

---

## Campos del Payload

### Cabecera

| Campo | Tipo | Requerido | Descripción |
|-------|------|-----------|-------------|
| `serie_documento` | string | **Sí** | Serie de guía: `"T001"` |
| `numero_documento` | string | **Sí** | `"#"` auto-numerar o número concreto |
| `fecha_de_emision` | string | **Sí** | `YYYY-MM-DD` |
| `hora_de_emision` | string | **Sí** | `HH:mm:ss` |
| `codigo_tipo_documento` | string | **Sí** | `"09"` Guía Remitente |
| `observaciones` | string | No | Observaciones |
| `codigo_modo_transporte` | string | **Sí** | `"01"` Transporte público, `"02"` Transporte privado |
| `codigo_motivo_traslado` | string | **Sí** | Ver tabla de motivos |
| `descripcion_motivo_traslado` | string | No | Descripción del motivo |
| `fecha_de_traslado` | string | **Sí** | Fecha inicio del traslado `YYYY-MM-DD` |
| `indicador_de_transbordo` | bool | No | Si hay transbordo |
| `unidad_peso_total` | string | **Sí** | Unidad de peso: `"KGM"` (kilos), `"TNE"` (toneladas) |
| `peso_total` | float | **Sí** | Peso total de la carga |
| `numero_de_bultos` | int | No | Cantidad de bultos |
| `numero_de_contenedor` | string\|null | No | Número de contenedor |

### `direccion_partida` (origen)

| Campo | Tipo | Requerido | Descripción |
|-------|------|-----------|-------------|
| `ubigeo` | string | **Sí** | Código ubigeo (6 dígitos) |
| `direccion` | string | **Sí** | Dirección completa (máx. 100 caracteres) |
| `codigo_del_domicilio_fiscal` | string\|null | No | Código establecimiento SUNAT |

### `direccion_llegada` (destino)

Misma estructura que `direccion_partida`.

### `transportista`

| Campo | Tipo | Requerido | Descripción |
|-------|------|-----------|-------------|
| `codigo_tipo_documento_identidad` | string | **Sí** | `"6"` (RUC) para empresas |
| `numero_documento` | string | **Sí** | RUC del transportista |
| `apellidos_y_nombres_o_razon_social` | string | **Sí** | Razón social |
| `numero_mtc` | string | No | Número de registro MTC |

> Solo requerido si `codigo_modo_transporte = "01"` (transporte público).

### `chofer`

| Campo | Tipo | Requerido | Descripción |
|-------|------|-----------|-------------|
| `codigo_tipo_documento_identidad` | string | **Sí** | `"1"` (DNI) |
| `numero_documento` | string | **Sí** | DNI del chofer |
| `nombres` | string | **Sí** | Nombre completo |
| `numero_licencia` | string | **Sí** | Número de licencia de conducir |
| `telefono` | string | No | Teléfono del chofer |

### `vehiculo`

| Campo | Tipo | Requerido | Descripción |
|-------|------|-----------|-------------|
| `numero_de_placa` | string | **Sí** | Placa del vehículo |
| `modelo` | string | No | Modelo del vehículo |
| `marca` | string | No | Marca del vehículo |
| `certificado_habilitacion_vehicular` | string\|null | No | TUC |

### Motivos de Traslado (`codigo_motivo_traslado`)

| Código | Descripción |
|--------|-------------|
| `01` | Venta |
| `02` | Compra |
| `03` | Venta con entrega a terceros |
| `04` | Traslado entre establecimientos |
| `08` | Importación |
| `09` | Exportación |
| `13` | Otros |
| `14` | Venta sujeta a confirmación |
| `17` | Traslado emisor itinerante |
| `18` | Traslado a zona primaria |
| `19` | Compra con entrega a terceros |

### `items[]`

Misma estructura de items que Boleta/Factura (ver [09-boleta-factura.md](09-boleta-factura.md#items)).

---

## Response (200 OK)

```json
{
    "success": true,
    "data": {
        "number": "T001-12",
        "filename": "20538856674-09-T001-12",
        "external_id": "abc-def-123"
    }
}
```

---

## Endpoints Adicionales

| Método | Endpoint | Descripción |
|--------|----------|-------------|
| `POST` | `/api/dispatches/send` | Enviar guía a SUNAT por `external_id` |
| `POST` | `/api/dispatches/status_ticket` | Consultar estado del ticket en SUNAT |
| `GET` | `/api/dispatches/tables` | Tablas auxiliares (modos transporte, motivos, etc.) |
| `GET` | `/api/dispatches/records` | Listar guías emitidas (paginado) |

---

## Notas para Offline

- **La guía requiere firma digital y envío a SUNAT (GRE 2.0).** Al crear offline, se almacena localmente y se procesa al sincronizar.
- Las direcciones de partida/llegada usan ubigeo del catálogo descargado (ver [05-ubigeo.md](05-ubigeo.md)).
- Validaciones estrictas del backend: `delivery.address` y `origin.address` son **requeridos** y máx. 100 caracteres.
- Para offline, enviar `numero_documento` con número concreto basado en `series-numbering`.
