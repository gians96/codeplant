# 14 — Guía de Remisión Transportista

> `POST /api/dispatch-carrier`  
> **Controller:** `Modules\Dispatch\Http\Controllers\Api\DispatchCarrierController@store`  
> **Middleware:** `input.request:dispatch,api`  
> **Auth:** `Bearer {token}`  
> **Código tipo:** `"31"`

---

## Descripción

La guía de remisión del transportista la emite la **empresa de transporte** que traslada los bienes. A diferencia de la guía del remitente, incluye datos del remitente y destinatario como terceros, y puede tener vehículos secundarios.

---

## Payload

```json
{
    "serie_documento": "V001",
    "numero_documento": "#",
    "fecha_de_emision": "2026-04-18",
    "hora_de_emision": "07:00:00",
    "codigo_tipo_documento": "31",
    "observaciones": "Traslado de mercadería",
    "codigo_modo_transporte": "01",
    "codigo_motivo_traslado": "01",
    "descripcion_motivo_traslado": "Venta",
    "fecha_de_traslado": "2026-04-19",
    "indicador_de_transbordo": false,
    "unidad_peso_total": "KGM",
    "peso_total": 50.0,
    "numero_de_bultos": 5,
    "direccion_partida": {
        "ubigeo": "150101",
        "direccion": "Av. Principal 123, Lima",
        "codigo_del_domicilio_fiscal": "0000"
    },
    "direccion_llegada": {
        "ubigeo": "040101",
        "direccion": "Jr. Mercaderes 456, Arequipa",
        "codigo_del_domicilio_fiscal": null
    },
    "datos_remitente": {
        "codigo_tipo_documento_identidad": "6",
        "descripcion_tipo_documento_identidad": "RUC",
        "numero_documento": "20538856674",
        "apellidos_y_nombres_o_razon_social": "ARTROSCOPICTRAUMA S.A.C."
    },
    "datos_destinatario": {
        "codigo_tipo_documento_identidad": "6",
        "descripcion_tipo_documento_identidad": "RUC",
        "numero_documento": "20552103816",
        "apellidos_y_nombres_o_razon_social": "AGROLIGHT PERU S.A.C."
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
        "certificado_habilitacion_vehicular": "HAB-001"
    },
    "vehiculo_secundario": [
        {
            "numero_de_placa": "DEF-456",
            "modelo": "Carreta",
            "marca": "FACCHINI",
            "certificado_habilitacion_vehicular": null
        }
    ],
    "chofer_secundario": [
        {
            "codigo_tipo_documento_identidad": "1",
            "numero_documento": "87654321",
            "nombres": "PEDRO GOMEZ RUIZ",
            "numero_licencia": "Q87654321",
            "telefono": "999777666"
        }
    ],
    "pagador_flete": {
        "indicador_pagador_flete": "Remitente",
        "codigo_tipo_documento_identidad": "6",
        "descripcion_tipo_documento_identidad": "RUC",
        "numero": "20538856674",
        "nombres": "ARTROSCOPICTRAUMA S.A.C."
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

## Campos Específicos del Transportista (diferentes a Remitente)

### `datos_remitente` — Quien envía la mercadería

| Campo | Tipo | Requerido | Descripción |
|-------|------|-----------|-------------|
| `codigo_tipo_documento_identidad` | string | **Sí** | `"6"` RUC, `"1"` DNI |
| `descripcion_tipo_documento_identidad` | string | No | `"RUC"`, `"DNI"` |
| `numero_documento` | string | **Sí** | Número de documento |
| `apellidos_y_nombres_o_razon_social` | string | **Sí** | Razón social |

### `datos_destinatario` — Quien recibe la mercadería

Misma estructura que `datos_remitente`.

### `vehiculo_secundario[]` (máx. 2)

Misma estructura que `vehiculo`. Para vehículos adicionales (semirremolques, carretas).

### `chofer_secundario[]` (máx. 2)

Misma estructura que `chofer`. Para choferes adicionales.

### `pagador_flete` — Quien paga el transporte

| Campo | Tipo | Descripción |
|-------|------|-------------|
| `indicador_pagador_flete` | string | `"Remitente"`, `"Destinatario"`, `"Tercero"` |
| `codigo_tipo_documento_identidad` | string | Tipo doc del pagador |
| `descripcion_tipo_documento_identidad` | string | Descripción tipo doc |
| `numero` | string | Número de documento |
| `nombres` | string | Razón social / nombre |

### Diferencias con Guía Remitente

| Aspecto | Remitente (09) | Transportista (31) |
|---------|---------------|-------------------|
| Serie | T001 | V001 |
| `datos_del_cliente_o_receptor` | **Sí** (el destinatario) | No (usa `datos_destinatario`) |
| `transportista` | **Sí** (empresa de transporte) | No (es la propia empresa) |
| `datos_remitente` | No | **Sí** (quien envía) |
| `datos_destinatario` | No | **Sí** (quien recibe) |
| `vehiculo_secundario` | No | **Sí** (máx. 2) |
| `chofer_secundario` | No | **Sí** (máx. 2) |
| `pagador_flete` | No | **Sí** |

---

## Response (200 OK)

```json
{
    "success": true,
    "data": {
        "number": "V001-5",
        "filename": "20538856674-31-V001-5",
        "external_id": "uuid-guia-transportista"
    }
}
```

---

## Endpoints Adicionales

| Método | Endpoint | Descripción |
|--------|----------|-------------|
| `GET` | `/api/dispatch-carrier/records` | Listar guías de transportista (paginado) |

---

## Notas para Offline

- Mismas consideraciones que la guía remitente: firma digital y envío SUNAT se procesan al sincronizar.
- Los datos de remitente y destinatario se pueden llenar offline usando el catálogo de clientes descargado.
- Los vehículos secundarios son opcionales (para semirremolques).
