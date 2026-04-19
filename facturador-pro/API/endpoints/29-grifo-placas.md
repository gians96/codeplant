# 29 — Grifos: Placas de Vehículos

> **Giro:** `tap` (id=4) — Grifos  
> **Auth:** `Bearer {token}`

---

## Descripción

Cuando el giro **Grifos** está activo, cada factura/boleta puede asociarse a una placa de vehículo. Esto es un requisito para que los clientes puedan deducir el gasto de combustible (Art. 37 del Reglamento de la Ley del Impuesto a la Renta).

La placa se registra en **dos lugares**:

1. **A nivel de documento** — Campo `plate_number` en `Document` / `SaleNote`
2. **A nivel de item** — Como atributo `7000` en el item del documento (se incluye en el XML SUNAT)

---

## 1. Placa en el Payload del Documento

### Campo `numero_de_placa`

Se agrega a nivel raíz del payload de `POST /api/documents`:

```json
{
    "serie_documento": "F001",
    "numero_documento": "#",
    "codigo_tipo_documento": "01",
    "...": "resto del payload",
    "numero_de_placa": "ABC-123"
}
```

| Campo API (español) | Campo interno | Descripción |
|---------------------|---------------|-------------|
| `numero_de_placa` | `plate_number` | Placa del vehículo (max 10 caracteres) |

---

## 2. Placa como Atributo del Item

Para que la placa aparezca en el XML SUNAT (requerido para deducción de gasto), se envía como atributo del item con código `7000`:

```json
{
    "items": [
        {
            "codigo_interno": "COMB-95",
            "descripcion": "Gasolina 95 Octanos",
            "unidad_de_medida": "GLN",
            "cantidad": 10,
            "valor_unitario": 16.94,
            "precio_unitario": 20,
            "codigo_tipo_afectacion_igv": "10",
            "datos_adicionales": [
                {
                    "codigo": "7000",
                    "descripcion": "Gastos Art. 37 Renta: Número de Placa",
                    "valor": "ABC-123"
                }
            ],
            "...": "resto del item"
        }
    ]
}
```

### Códigos de atributos de placa

| Código | Descripción | Uso |
|--------|-------------|-----|
| `7000` | Gastos Art. 37 Renta: Número de Placa | Venta de combustible (grifos) |
| `5010` | Número de placa | Uso general |

> **Grifo estándar:** Usar `7000`. Flutter debe agregar automáticamente este atributo a cada item cuando el giro Grifo está activo.

### ¿GLN o GLL?

- `GLN` — Galón (unidad estándar SUNAT)
- `GLL` — Galón (variante usada en reportes internos)

Usar **GLN** para compatibilidad SUNAT.

---

## 3. Placas por Cliente (`save_plates_client`)

Cuando `configuration_taps.save_plates_client` es `true` (ver [28-giros-de-negocio.md](28-giros-de-negocio.md)), cada cliente tiene una lista de placas asociadas (registradas en tabla `plates`).

### GET placas por cliente

```
GET /api/offline/plates/{person_id}
Authorization: Bearer {token}
```

**Response (200):**
```json
{
    "success": true,
    "data": [
        { "id": 15, "person_id": 42, "value": "ABC-123" },
        { "id": 16, "person_id": 42, "value": "XYZ-987" }
    ]
}
```

> **Nota:** La tabla `plates` tiene solo 2 columnas: `person_id` y `value` (la placa). No hay descripción libre.

### POST guardar placa

```
POST /api/offline/plates
Authorization: Bearer {token}
Content-Type: application/json
```

**Payload:**
```json
{
    "person_id": 42,
    "value": "ABC-123"
}
```

**Response (200):**
```json
{
    "success": true,
    "data": {
        "id": 15,
        "person_id": 42,
        "value": "ABC-123"
    }
}
```

---

## 4. Ejemplo Completo — Boleta de Grifo

```json
{
    "serie_documento": "B001",
    "numero_documento": "#",
    "fecha_de_emision": "2026-04-19",
    "hora_de_emision": "10:30:00",
    "codigo_tipo_operacion": "0101",
    "codigo_tipo_documento": "03",
    "codigo_tipo_moneda": "PEN",
    "numero_de_placa": "ABC-123",
    "datos_del_cliente_o_receptor": {
        "codigo_tipo_documento_identidad": "1",
        "numero_documento": "12345678",
        "apellidos_y_nombres_o_razon_social": "PÉREZ GARCÍA JUAN",
        "direccion": "Av. Lima 123"
    },
    "totales": {
        "total_operaciones_gravadas": 169.49,
        "total_igv": 30.51,
        "total_impuestos": 30.51,
        "total_valor": 169.49,
        "total_venta": 200
    },
    "items": [
        {
            "codigo_interno": "COMB-95",
            "descripcion": "Gasolina 95 Octanos",
            "unidad_de_medida": "GLN",
            "cantidad": 10,
            "valor_unitario": 16.9492,
            "precio_unitario": 20,
            "codigo_tipo_precio": "01",
            "codigo_tipo_afectacion_igv": "10",
            "total_base_igv": 169.49,
            "porcentaje_igv": 18,
            "total_igv": 30.51,
            "total_impuestos": 30.51,
            "total_valor_item": 169.49,
            "total_item": 200,
            "datos_adicionales": [
                {
                    "codigo": "7000",
                    "descripcion": "Gastos Art. 37 Renta: Número de Placa",
                    "valor": "ABC-123"
                }
            ]
        }
    ],
    "pagos": [
        {
            "codigo_metodo_pago": "01",
            "monto": 200
        }
    ]
}
```

---

## 5. Flujo en Flutter POS Grifo

```
┌──────────────────────────────────────────────┐
│ 1. Al iniciar venta:                          │
│    - Pedir placa (campo obligatorio)          │
│    - Si `save_plates_client=true` y cliente   │
│      ya seleccionado → mostrar dropdown de    │
│      placas guardadas                         │
└──────────────────────────────────────────────┘
                    │
                    ▼
┌──────────────────────────────────────────────┐
│ 2. Al agregar items:                          │
│    - Por cada item, agregar automáticamente:  │
│      datos_adicionales: [{                    │
│        codigo: "7000",                        │
│        descripcion: "Gastos Art. 37 Renta:    │
│                      Número de Placa",        │
│        valor: form.plate_number               │
│      }]                                       │
└──────────────────────────────────────────────┘
                    │
                    ▼
┌──────────────────────────────────────────────┐
│ 3. Al emitir comprobante:                     │
│    - Enviar numero_de_placa a nivel doc       │
│    - Cada item lleva su atributo 7000         │
└──────────────────────────────────────────────┘
                    │
                    ▼
┌──────────────────────────────────────────────┐
│ 4. Post-sync (opcional):                      │
│    - Si save_plates_client=true y la placa    │
│      no existía: POST /api/offline/plates     │
│      para guardarla para uso futuro           │
└──────────────────────────────────────────────┘
```

---

## Validaciones

### Frontend (Flutter)

```dart
// Al cobrar
if (businessTurns.isGrifo && plateNumber.isEmpty) {
    showError('Debe ingresar la placa del vehículo');
    return;
}

// Formato común (sin validación estricta — SUNAT acepta varios)
// Perú: AAA-###, AAA-#### (máx 10 chars)
final plateRegex = RegExp(r'^[A-Z0-9]{3}-[A-Z0-9]{3,4}$');
```

### Backend

- No hay validación estricta de formato en el backend.
- Se guarda en `documents.plate_number` como string.
- Se replica como atributo `7000` en `document_items` si el frontend lo envía.

---

## Notas para Offline

- **Las placas son datos locales:** No requieren sincronización inmediata. Flutter puede mantener un catálogo local de placas por cliente en SQLite.
- **Sync diferido:** Al sincronizar el batch, el backend ya recibe `numero_de_placa` en el payload, no es necesario llamar a POST /plates.
- **`POST /api/offline/plates` es opcional:** Solo para casos donde el operador explícitamente quiera registrar una placa nueva sin asociarla a una venta inmediata.
- **Búsqueda por placa:** Flutter puede indexar placas localmente para búsqueda rápida en el POS (mostrar "Última venta: 2026-04-18 Placa: ABC-123").
