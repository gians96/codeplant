# 07 — Caja (Apertura, Cierre y Verificación)

> **Uso offline:** Gestión de caja para controlar turnos de venta. Cada comprobante se asocia a la caja abierta del usuario.

---

## 1. Verificar Caja Abierta

> `GET /api/cash/opening_cash`  
> **Controller:** `Tenant\Api\CashController@opening_cash`

### Response — Caja abierta

```json
{
    "success": true,
    "message": "Verificar si existe caja abierta",
    "data": {
        "cash_id": 4,
        "description": "REF 2026-04-18 (Administrador)"
    }
}
```

### Response — Sin caja abierta

```json
{
    "success": false,
    "message": "Verificar si existe caja abierta",
    "data": {
        "cash_id": null,
        "description": ""
    }
}
```

| Campo | Tipo | Descripción |
|-------|------|-------------|
| `success` | bool | `true` si hay caja abierta, `false` si no |
| `data.cash_id` | int\|null | ID de la caja abierta. Se usa en `POST /api/cash/cash_document` |
| `data.description` | string | Referencia de la caja |

---

## 2. Aperturar Caja

> `POST /api/cash/open`  
> **Controller:** `Tenant\CashController@store`

### Payload

```json
{
    "id": null,
    "beginning_balance": 12,
    "date_closed": null,
    "date_opening": null,
    "final_balance": 0,
    "income": 0,
    "reference_number": "restaurant",
    "state": true,
    "time_closed": null,
    "time_opening": null,
    "user_id": 0
}
```

| Campo | Tipo | Requerido | Descripción |
|-------|------|-----------|-------------|
| `id` | int\|null | No | `null` para nueva caja. Si se pasa ID, actualiza existente |
| `beginning_balance` | float | **Sí** | Monto inicial en caja (saldo de apertura) |
| `reference_number` | string | No | Referencia: `"restaurant"` o libre |
| `state` | bool | No | `true` = abierta |

> Los campos `date_opening`, `time_opening` los asigna el backend automáticamente.

### Response (200 OK)

```json
{
    "success": true,
    "message": "Caja aperturada con éxito",
    "data": {
        "cash_id": 4
    }
}
```

---

## 3. Cerrar Caja

> `GET /api/cash/close/{cash_id}`  
> **Controller:** `Tenant\Api\CashController@close`

### URL

```
GET /api/cash/close/4
```

### Response — Éxito

```json
{
    "success": true,
    "message": "Caja cerrada con éxito"
}
```

### Response — Error (mesas abiertas)

```json
{
    "success": false,
    "message": "No se puede cerrar caja , existe mesas abiertas."
}
```

> El backend suma todos los documentos y notas de venta asociados a la caja, calcula el `final_balance`, y cierra.

---

## 4. Verificar Caja Específica

> `GET /api/cash/opening_cash_check/{cash_id}`  
> **Controller:** `Tenant\Api\CashController@opening_cash_check`

### Response

```json
{
    "success": true,
    "message": "Verificar si existe caja abierta",
    "data": {
        "cash_id": 4,
        "description": "REF 2026-04-18 (Administrador)"
    }
}
```

---

## 5. Asociar Venta a Caja

> `POST /api/cash/cash_document`  
> **Controller:** `Tenant\Api\CashController@cash_document`

### Payload

```json
{
    "cash_id": 4,
    "document_id": null,
    "sale_note_id": 25
}
```

| Campo | Tipo | Descripción |
|-------|------|-------------|
| `cash_id` | int | ID de la caja abierta |
| `document_id` | int\|null | ID del documento (Boleta/Factura/NC/ND). Mutualmente excluyente con `sale_note_id` |
| `sale_note_id` | int\|null | ID de la nota de venta. Mutualmente excluyente con `document_id` |
| `quotation_id` | int\|null | ID de cotización (opcional) |

> Se envía **uno** de los tres: `document_id`, `sale_note_id`, o `quotation_id`.

### Response

```json
{
    "success": true,
    "message": "Venta con éxito"
}
```

### Idempotencia

El backend usa `CashDocument::firstOrCreate()`, por lo que enviar el mismo `cash_id + document_id/sale_note_id` varias veces **no crea duplicados**.

---

## Notas para Offline

- **Apertura de caja** puede hacerse offline. Almacenar el `cash_id` local y sincronizar después.
- **Cada venta creada offline** debe guardarse con su `cash_id` local para asociarla al sincronizar.
- Al usar `sync-batch`, el backend **asocia automáticamente** cada comprobante a la caja activa del usuario (vía `registerInCash()`), por lo que no es necesario llamar `POST /api/cash/cash_document` por separado al sincronizar.
- **Cierre de caja** requiere que todos los comprobantes pendientes se hayan sincronizado primero.
