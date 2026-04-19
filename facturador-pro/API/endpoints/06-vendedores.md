# 06 — Vendedores Disponibles

> `GET /api/restaurant/available-sellers`  
> **Controller:** `Modules\Restaurant\Http\Controllers\RestaurantConfigurationController@getSellers`  
> **Auth:** `Bearer {token}`  
> **Uso offline:** Obtiene la lista de vendedores activos para asignar a cada comprobante.

---

## Request

### Headers

```
Accept: application/json
Authorization: Bearer {token}
```

---

## Response (200 OK)

```json
{
    "success": true,
    "message": "Vendedores disponibles",
    "data": [
        {
            "id": 1,
            "name": "Administrador",
            "email": "demo@nt-suite.pro",
            "establishment": null
        },
        {
            "id": 2,
            "name": "Vendedor 1",
            "email": "vendedor1@nt-suite.pro",
            "establishment": null
        }
    ]
}
```

### Campos

| Campo | Tipo | Descripción |
|-------|------|-------------|
| `id` | int | ID del usuario/vendedor. Se usa como `codigo_vendedor` o `seller_id` en comprobantes |
| `name` | string | Nombre del vendedor |
| `email` | string | Email del vendedor |
| `establishment` | object\|null | Establecimiento asociado (puede ser null) |

---

## Lógica del Backend

```php
// Solo usuarios activos con rol de restaurante asignado
User::where('active', 1)
    ->where('restaurant_role_id', '<>', null)
    ->select('id', 'name', 'email')
    ->get();
```

> Solo retorna usuarios que tienen `restaurant_role_id` asignado (Cajero, Mesero o Admin).

---

## Notas para Offline

- Almacenar localmente para permitir seleccionar vendedor al crear comprobantes.
- El `id` del vendedor se envía como:
  - `"codigo_vendedor": 1` en Boleta/Factura/NC/ND (`POST /api/documents`)
  - `"seller_id": 1` en Nota de Venta (`POST /api/sale-note`)
- Si la app es single-user, usar directamente el `sellerId` obtenido en el login.
