# 15 — Sincronización Batch (Sync-Batch)

> `POST /api/offline/sync-batch`  
> **Controller:** `Modules\Offline\Http\Controllers\OfflineSyncController@syncBatch`  
> **Auth:** `Bearer {token}`  
> **Uso:** Enviar múltiples comprobantes creados offline en una sola petición.

---

## Descripción

El endpoint principal de sincronización. Recibe un array de comprobantes creados offline y los procesa secuencialmente. Cada comprobante se intenta crear; si falla, el error se registra individualmente sin afectar a los demás.

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
    "sales": [
        {
            "doc_type": "80",
            "offline_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
            "cash_id": 4,
            "data": {
                "document_type_id": "80",
                "prefix": "NV",
                "series_id": 10,
                "date_of_issue": "2026-04-18",
                "time_of_issue": "14:30:00",
                "customer_id": 5,
                "currency_type_id": "PEN",
                "seller_id": 1,
                "payments": [
                    {
                        "payment_method_type_id": "01",
                        "payment": 102,
                        "payment_received": 110
                    }
                ],
                "datos_del_cliente_o_receptor": {
                    "codigo_tipo_documento_identidad": "1",
                    "numero_documento": "76251607",
                    "apellidos_y_nombres_o_razon_social": "ARIAS BONIFACIO, GIANMARCOS DANIEL"
                },
                "items": [
                    {
                        "item_id": 3,
                        "item": { "id": 3, "internal_id": "FFF", "description": "Producto KG", "unit_type_id": "KGM", "sale_affectation_igv_type_id": "10", "has_igv": true, "unit_price": 102 },
                        "quantity": 1,
                        "unit_price": 102,
                        "unit_value": 86.44,
                        "total_value": 86.44,
                        "percentage_igv": 18,
                        "total_base_igv": 86.44,
                        "total_igv": 15.56,
                        "total": 102,
                        "total_taxes": 15.56,
                        "affectation_igv_type_id": "10",
                        "price_type_id": "01"
                    }
                ],
                "total_taxed": 86.44,
                "total_igv": 15.56,
                "total_taxes": 15.56,
                "total_value": 86.44,
                "subtotal": 102,
                "total": 102
            }
        },
        {
            "doc_type": "03",
            "offline_id": "b2c3d4e5-f6a7-8901-bcde-f12345678901",
            "cash_id": 4,
            "data": {
                "serie_documento": "B001",
                "numero_documento": "90",
                "fecha_de_emision": "2026-04-18",
                "hora_de_emision": "14:35:00",
                "codigo_tipo_operacion": "0101",
                "codigo_tipo_documento": "03",
                "codigo_tipo_moneda": "PEN",
                "codigo_vendedor": 1,
                "datos_del_cliente_o_receptor": {
                    "codigo_tipo_documento_identidad": "1",
                    "numero_documento": "76251607",
                    "apellidos_y_nombres_o_razon_social": "ARIAS BONIFACIO, GIANMARCOS DANIEL"
                },
                "items": [
                    {
                        "codigo_interno": "ASD",
                        "descripcion": "Precio",
                        "unidad_de_medida": "NIU",
                        "cantidad": 1,
                        "valor_unitario": 3.13,
                        "precio_unitario": 3.69,
                        "codigo_tipo_precio": "01",
                        "codigo_tipo_afectacion_igv": "10",
                        "total_base_igv": 3.13,
                        "porcentaje_igv": 18,
                        "total_igv": 0.56,
                        "total_impuestos": 0.56,
                        "total_valor_item": 3.13,
                        "total_item": 3.69
                    }
                ],
                "pagos": [
                    {
                        "codigo_metodo_pago": "01",
                        "monto": 3.69,
                        "pago_recibido": 5.00
                    }
                ],
                "totales": {
                    "total_operaciones_gravadas": 3.13,
                    "total_igv": 0.56,
                    "total_impuestos": 0.56,
                    "total_valor": 3.13,
                    "total_venta": 3.69
                }
            }
        },
        {
            "doc_type": "09",
            "offline_id": "c3d4e5f6-a7b8-9012-cdef-123456789012",
            "data": {
                "serie_documento": "T001",
                "numero_documento": "13",
                "fecha_de_emision": "2026-04-18",
                "codigo_tipo_documento": "09",
                "codigo_modo_transporte": "02",
                "codigo_motivo_traslado": "04",
                "fecha_de_traslado": "2026-04-19",
                "peso_total": 10.0,
                "unidad_peso_total": "KGM",
                "direccion_partida": { "ubigeo": "150101", "direccion": "Av. Principal 123" },
                "direccion_llegada": { "ubigeo": "150132", "direccion": "Jr. Los Olivos 456" },
                "chofer": { "codigo_tipo_documento_identidad": "1", "numero_documento": "12345678", "nombres": "JUAN PEREZ", "numero_licencia": "Q12345678" },
                "vehiculo": { "numero_de_placa": "ABC-123" },
                "datos_del_cliente_o_receptor": { "codigo_tipo_documento_identidad": "6", "numero_documento": "20552103816", "apellidos_y_nombres_o_razon_social": "AGROLIGHT PERU S.A.C." },
                "items": [
                    { "codigo_interno": "ASD", "descripcion": "Precio", "unidad_de_medida": "NIU", "cantidad": 10, "valor_unitario": 3.13, "precio_unitario": 3.69, "codigo_tipo_precio": "01", "codigo_tipo_afectacion_igv": "10", "total_base_igv": 31.3, "porcentaje_igv": 18, "total_igv": 5.63, "total_impuestos": 5.63, "total_valor_item": 31.3, "total_item": 36.93 }
                ]
            }
        }
    ]
}
```

---

## Estructura del Payload

### `sales[]` — Array de comprobantes

| Campo | Tipo | Requerido | Descripción |
|-------|------|-----------|-------------|
| `doc_type` | string | **Sí** | Código tipo: `"80"`, `"01"`, `"03"`, `"07"`, `"08"`, `"09"`, `"31"` |
| `offline_id` | string | **Sí** | UUID v4 generado por Flutter. Clave de idempotencia |
| `cash_id` | int | No | ID de la caja abierta (para registrar venta en caja) |
| `data` | object | **Sí** | Payload completo del comprobante (ver endpoints individuales) |

### Formato del `data` según `doc_type`

| `doc_type` | Formato del `data` | Referencia |
|------------|-------------------|------------|
| `"80"` | Campos en **inglés** (SaleNote) | [12-nota-venta.md](12-nota-venta.md) |
| `"01"`, `"03"` | Campos en **español** (DocumentTransform) | [09-boleta-factura.md](09-boleta-factura.md) |
| `"07"` | Campos en **español** + `codigo_tipo_nota` + `documento_afectado` | [10-nota-credito.md](10-nota-credito.md) |
| `"08"` | Campos en **español** + `codigo_tipo_nota` + `documento_afectado` | [11-nota-debito.md](11-nota-debito.md) |
| `"09"` | Campos en **español** (DispatchTransform) | [13-guia-remision-remitente.md](13-guia-remision-remitente.md) |
| `"31"` | Campos en **español** (DispatchTransform) | [14-guia-remision-transportista.md](14-guia-remision-transportista.md) |

---

## Response (200 OK)

```json
{
    "success": true,
    "message": "Sincronización completada",
    "data": {
        "results": [
            {
                "index": 0,
                "success": true,
                "offline_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
                "doc_type": "80",
                "data": {
                    "id": 25,
                    "number": "NV01-25",
                    "external_id": "4611364d-2bc8-482c-9eea-4162216d582b",
                    "filename": "NV01-25-20260418",
                    "state_type_id": "01"
                }
            },
            {
                "index": 1,
                "success": true,
                "offline_id": "b2c3d4e5-f6a7-8901-bcde-f12345678901",
                "doc_type": "03",
                "data": {
                    "id": 123,
                    "number": "B001-90",
                    "external_id": "4506ba3e-fd30-44b3-9646-603d8236a02f",
                    "filename": "20538856674-03-B001-90",
                    "state_type_id": "01"
                }
            },
            {
                "index": 2,
                "success": true,
                "offline_id": "c3d4e5f6-a7b8-9012-cdef-123456789012",
                "doc_type": "09",
                "data": {
                    "id": 45,
                    "number": "T001-13",
                    "external_id": "xyz-dispatch-uuid",
                    "filename": "20538856674-09-T001-13"
                }
            }
        ],
        "total": 3,
        "success_count": 3,
        "error_count": 0
    }
}
```

### Response con errores parciales

```json
{
    "success": true,
    "message": "Sincronización completada con errores",
    "data": {
        "results": [
            {
                "index": 0,
                "success": true,
                "offline_id": "a1b2c3d4-...",
                "doc_type": "80",
                "data": { "id": 25, "number": "NV01-25" }
            },
            {
                "index": 1,
                "success": false,
                "offline_id": "b2c3d4e5-...",
                "doc_type": "03",
                "error": "Error en la validación del documento: La serie B001 no corresponde al tipo de documento",
                "duplicate": false
            },
            {
                "index": 2,
                "success": true,
                "offline_id": "b2c3d4e5-...",
                "doc_type": "03",
                "data": { "id": 123, "number": "B001-90" },
                "was_duplicate": true
            }
        ],
        "total": 3,
        "success_count": 2,
        "error_count": 1
    }
}
```

---

## Flujo Interno del Backend

```
syncBatch(Request $request)
│
├── foreach sales as $index => $sale
│   │
│   ├── Verificar offline_id → ¿ya existe en BD?
│   │   ├── SÍ → retornar datos existentes (was_duplicate: true)
│   │   └── NO → continuar procesamiento
│   │
│   ├── switch(doc_type)
│   │   ├── "80"  → processSaleNote($sale['data'])
│   │   │          → SaleNoteController internamente
│   │   │          → Guardar offline_id en sale_notes.offline_id
│   │   │
│   │   ├── "01","03","07","08" → processDocument($sale['data'])
│   │   │          → DocumentTransform → Validation → Input
│   │   │          → Facturalo::save()
│   │   │          → Guardar offline_id en documents.offline_id
│   │   │
│   │   ├── "09"  → processDispatch($sale['data'])
│   │   │          → DispatchTransform → Validation → Input
│   │   │          → save()
│   │   │          → Guardar offline_id en dispatches.offline_id
│   │   │
│   │   └── "31"  → processDispatchCarrier($sale['data'])
│   │              → Similar a "09" pero con DispatchCarrierController
│   │              → Guardar offline_id en dispatches.offline_id
│   │
│   ├── Registrar en caja → registerInCash(cash_id, document/sale_note)
│   │   └── CashDocument::firstOrCreate() → idempotente
│   │
│   └── Agregar resultado (success/error) al array results[]
│
└── Retornar response con results[], total, success_count, error_count
```

---

## Manejo de Errores por Tipo

### Documento duplicado (filename unique constraint)

Si un documento `01`/`03`/`07`/`08` tiene un filename que ya existe, el backend:
1. Captura el error MySQL 1062 (duplicate entry)
2. Busca el documento existente por filename
3. Retorna los datos del documento existente como éxito con `was_duplicate: true`

### Nota de Venta duplicada

La tabla `sale_notes` **NO tiene constraint unique** en filename. Por eso la verificación de `offline_id` es **crítica** para evitar duplicados.

### Error de validación

Si los datos no pasan la validación (serie incorrecta, cliente no encontrado, etc.), se retorna `success: false` con el mensaje de error. Los demás comprobantes continúan procesándose.

---

## ⚠️ FIX NECESARIO — Extensión del Controller

### Estado actual

El controller `OfflineSyncController@syncBatch` solo maneja:
- `doc_type: "80"` → `processSaleNote()`
- `doc_type: "01"` / `"03"` → `processDocument()`

### Extensión necesaria

Agregar soporte para:

| `doc_type` | Método nuevo | Tabla `offline_id` |
|------------|-------------|-------------------|
| `"07"` | Reusar `processDocument()` | `documents.offline_id` |
| `"08"` | Reusar `processDocument()` | `documents.offline_id` |
| `"09"` | `processDispatch()` (nuevo) | `dispatches.offline_id` |
| `"31"` | `processDispatchCarrier()` (nuevo) | `dispatches.offline_id` |

Ver detalles de implementación en [16-idempotencia.md](16-idempotencia.md).

---

## Notas para Flutter

### Orden de sincronización

```
1. Primero: Notas de Venta (80) — sin dependencias
2. Segundo: Boletas/Facturas (01/03) — sin dependencias
3. Tercero: NC/ND (07/08) — requieren external_id del documento afectado
4. Cuarto: Guías (09/31) — independientes pero menos urgentes
```

> **NC/ND (07/08)** referencia un `external_id` que solo existe después de sincronizar el documento original. Flutter debe sincronizar facturas/boletas primero, obtener sus `external_id`, y luego sincronizar las notas de crédito/débito que los referencian.

### Retry logic

- Si un comprobante falla con error de red → reintentar todo el batch
- Si un comprobante falla con error de validación → marcarlo como error local, no reintentar
- Si un comprobante tiene `was_duplicate: true` → marcarlo como sincronizado exitosamente
- Exponential backoff: 1s, 2s, 4s, 8s, 16s (máx. 5 intentos)

### Tamaño del batch

- Recomendado: máximo **50 comprobantes** por batch
- Si hay más, dividir en múltiples llamadas
