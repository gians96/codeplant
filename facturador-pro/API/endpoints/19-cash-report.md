# 19 — Reporte de Caja

> `GET /api/offline/cash-report/{cashId}`  
> **Controller:** `Modules\Offline\Http\Controllers\CashReportController@show`  
> **Auth:** `Bearer {token}`  
> **Uso offline:** Obtener resumen de ventas de una caja (después de sincronizar).

---

## Request

### Headers

```
Accept: application/json
Authorization: Bearer {token}
```

### URL

```
GET /api/offline/cash-report/4
```

---

## Response (200 OK)

```json
{
    "success": true,
    "data": {
        "cash": {
            "id": 4,
            "user_id": 1,
            "user_name": "Administrador",
            "date_opening": "2026-04-18",
            "time_opening": "08:00:00",
            "date_closed": null,
            "time_closed": null,
            "beginning_balance": 100.00,
            "final_balance": 0,
            "income": 0,
            "state": true,
            "reference_number": "restaurant"
        },
        "documents": {
            "total": 5,
            "total_amount": 523.50,
            "by_type": [
                { "document_type_id": "03", "description": "Boleta", "count": 3, "amount": 315.20 },
                { "document_type_id": "01", "description": "Factura", "count": 2, "amount": 208.30 }
            ]
        },
        "sale_notes": {
            "total": 12,
            "total_amount": 1250.00
        },
        "payments_summary": [
            { "payment_method_type_id": "01", "description": "Efectivo", "amount": 1500.00 },
            { "payment_method_type_id": "02", "description": "Tarjeta", "amount": 273.50 }
        ],
        "grand_total": 1773.50
    }
}
```

---

## Notas

- Este endpoint solo funciona **después de sincronizar** los comprobantes offline.
- `state: true` indica caja abierta, `false` caja cerrada.
- Útil para mostrar resumen antes de cerrar caja.
