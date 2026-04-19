# 26 — Envío Diferido y Actualización de Estado

> **Endpoints:**  
> `POST /api/documents/send`  
> `POST /api/documents/updatedocumentstatus`  
> **Auth:** `Bearer {token}`

---

## Descripción

Cuando se crea un documento con `acciones.enviar_xml_firmado: false`, el documento queda en estado **Registrado** (`01`) sin enviarse a SUNAT. Estos endpoints permiten enviarlo después y actualizar su estado manualmente.

Ref detalle: [09-boleta-factura.md](09-boleta-factura.md) → sección "Factura Sin Enviar a SUNAT".

---

## 1. Enviar Documento a SUNAT

```
POST /api/documents/send
Authorization: Bearer {token}
Content-Type: application/json
```

### Payload

```json
{
    "external_id": "2dded172-cd17-4078-9c88-10a9b1177f2d"
}
```

| Campo | Tipo | Requerido | Descripción |
|-------|------|-----------|-------------|
| `external_id` | string (UUID) | **Sí** | UUID del documento retornado al crearlo |

### Response (200 OK)

```json
{
    "success": true,
    "data": {
        "number": "F001-122",
        "filename": "20538856674-01-F001-122",
        "external_id": "2dded172-cd17-4078-9c88-10a9b1177f2d"
    },
    "links": {
        "xml": "https://demo.nt-suite.pro/downloads/document/xml/2dded172...",
        "pdf": "https://demo.nt-suite.pro/downloads/document/pdf/2dded172...",
        "cdr": "https://demo.nt-suite.pro/downloads/document/cdr/2dded172..."
    },
    "response": {
        "code": "0",
        "description": "La Factura F001-122 ha sido aceptada"
    }
}
```

### Response Error

```json
{
    "success": false,
    "message": "El documento ya fue enviado anteriormente"
}
```

> **Nota:** Si el documento ya fue enviado (estado `03` o superior), el endpoint retorna error. No es idempotente.

---

## 2. Actualizar Estado de Documento

```
POST /api/documents/updatedocumentstatus
Authorization: Bearer {token}
Content-Type: application/json
```

### Payload

```json
{
    "externail_id": "2dded172-cd17-4078-9c88-10a9b1177f2d",
    "state_type_id": "05"
}
```

> **⚠️ IMPORTANTE:** El campo se llama `externail_id` (con typo). NO es `external_id`. Este es un typo histórico de la API que se mantiene por retrocompatibilidad.

| Campo | Tipo | Requerido | Descripción |
|-------|------|-----------|-------------|
| `externail_id` | string (UUID) | **Sí** | UUID del documento (con typo: `externail`) |
| `state_type_id` | string | **Sí** | Nuevo código de estado |

### Estados disponibles

| Código | Estado | Descripción |
|--------|--------|-------------|
| `01` | Registrado | Creado pero no enviado a SUNAT |
| `03` | Enviado | Enviado a SUNAT (esperando respuesta) |
| `05` | Aceptado | Aceptado por SUNAT |
| `07` | Observado | Aceptado con observaciones por SUNAT |
| `09` | Rechazado | Rechazado por SUNAT |
| `11` | Anulado | Documento anulado |
| `13` | Por anular | En proceso de anulación (Resumen de Anulados) |

### Response (200 OK)

```json
{
    "success": true,
    "message": "Estado del documento actualizado correctamente"
}
```

---

## Flujo Completo de Envío Diferido

```
┌──────────────────────────────────────────────────────┐
│ Paso 1: Crear documento sin enviar                    │
│                                                       │
│ POST /api/documents                                   │
│ {                                                     │
│   "acciones": { "enviar_xml_firmado": false },        │
│   "...resto del payload..."                           │
│ }                                                     │
│ → state_type_id: "01" (Registrado)                    │
│ → Retorna external_id                                 │
└───────────────────────┬──────────────────────────────┘
                        │
                        ▼
┌──────────────────────────────────────────────────────┐
│ Paso 2: Enviar a SUNAT cuando haya conexión           │
│                                                       │
│ POST /api/documents/send                              │
│ { "external_id": "2dded172-..." }                     │
│ → Si aceptado: state_type_id: "05"                    │
│ → Si rechazado: state_type_id: "09"                   │
└───────────────────────┬──────────────────────────────┘
                        │
                        ▼ (opcional)
┌──────────────────────────────────────────────────────┐
│ Paso 3: Actualizar estado manualmente                 │
│                                                       │
│ POST /api/documents/updatedocumentstatus              │
│ { "externail_id": "2dded172-...", "state_type_id": "05" } │
│ → Solo si se necesita forzar un estado específico     │
└──────────────────────────────────────────────────────┘
```

---

## Notas para Offline (Flutter)

### Cuándo usar envío diferido

1. **Servidor sin internet:** El Flutter sincronizó el comprobante al servidor vía WiFi local, pero el servidor no tiene internet para enviar a SUNAT. Crear con `acciones.enviar_xml_firmado: false`.
2. **Pre-generación:** Se desea generar el PDF localmente (para imprimir ticket) sin esperar respuesta de SUNAT.

### Cuándo NO usar envío diferido

1. **Flutter offline puro:** Si Flutter no tiene conexión al servidor, el comprobante se almacena en SQLite local. Al sincronizar con `sync-batch`, el servidor lo crea Y lo envía a SUNAT automáticamente (sin necesidad de `acciones`).
2. **Operación normal:** Si el servidor tiene internet, no hay razón para no enviar.

### Flujo recomendado post-sync

```
sync-batch → para cada documento creado:
  1. Si external_id existe y state_type_id === "01":
     → Flutter puede llamar POST /api/documents/send para enviar a SUNAT
  2. Después de enviar, verificar el estado con la respuesta
  3. Si hay error de SUNAT, almacenar el external_id para retry posterior
```

### Campos a almacenar en SQLite (Flutter)

Para cada documento sincronizado:

| Campo | Descripción |
|-------|-------------|
| `external_id` | UUID del documento en el servidor |
| `state_type_id` | Estado actual (`01`, `03`, `05`, etc.) |
| `number` | Número del documento (ej: `F001-122`) |
| `needs_send` | Flag local: `true` si se creó con `enviar_xml_firmado: false` |
