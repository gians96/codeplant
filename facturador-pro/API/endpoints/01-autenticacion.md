# 01 — Autenticación

> `POST /api/login`  
> **Controller:** `Tenant\Api\MobileController@login`  
> **Auth:** No requerida  
> **Uso offline:** Primera llamada. Obtiene token, datos de empresa, configuración de la app y el `establishment_id` del usuario.

---

## Request

### Headers

```
Content-Type: application/json
Accept: application/json
```

### Payload

```json
{
    "email": "demo@nt-suite.pro",
    "password": "123456",
    "domain": "demo.nt-suite.pro",
    "ssl": "https://"
}
```

| Campo | Tipo | Requerido | Descripción |
|-------|------|-----------|-------------|
| `email` | string | Sí | Email del usuario |
| `password` | string | Sí | Contraseña |
| `domain` | string | Sí | Dominio del tenant (sin protocolo) |
| `ssl` | string | Sí | Protocolo: `"https://"` o `"http://"` |

---

## Response (200 OK)

```json
{
    "success": true,
    "name": "Administrador",
    "email": "demo@nt-suite.pro",
    "establishment_id": 1,
    "seriedefault": null,
    "token": "zVP9LuoaCQ3ixNXyDv7IRZxidqyxLi9kNwvkywWJMSENNu0jO0",
    "restaurant_role_id": 3,
    "restaurant_role_code": "ADM",
    "ruc": "20538856674",
    "app_logo": null,
    "app_logo_base64": "",
    "company": {
        "name": "ARTROSCOPICTRAUMA S.A.C.",
        "address": "LIMA, Lima, Lima, -",
        "phone": "-",
        "email": "demo@nt-suite.pro",
        "enable_list_product": false,
        "qr_api_enable_ws": false,
        "qr_api_url_ws": null,
        "qr_api_key_ws": null,
        "url_logo": "",
        "logo_base64": "",
        "is_business_turn_tap": 0
    },
    "app_configuration": {
        "id": 1,
        "show_image_item": true,
        "print_format_pdf": "ticket",
        "theme_color": "blue",
        "card_color": "multicolored",
        "header_waves": 0,
        "app_mode": "default",
        "direct_print": false,
        "has_igv_31556": false,
        "igv_31556_percentage": "0.105",
        "direct_send_documents_whatsapp": false
    },
    "permission_edit_item_prices": true,
    "sellerId": 1
}
```

### Campos clave para Flutter

| Campo | Tipo | Uso offline |
|-------|------|-------------|
| `token` | string | **Guardar.** Se usa como `Bearer {token}` en todos los demás endpoints |
| `establishment_id` | int | **Guardar.** Identifica la sucursal. Items y series se filtran por este ID |
| `sellerId` | int | **Guardar.** ID del vendedor para enviar en `codigo_vendedor` / `seller_id` |
| `company.name` | string | Razón social para mostrar en la app |
| `ruc` | string | RUC de la empresa para generar filenames |
| `restaurant_role_id` | int | Rol del usuario (1=Cajero, 2=Mesero, 3=Admin) |
| `restaurant_role_code` | string | Código del rol: `CAJ`, `MSR`, `ADM` |
| `app_configuration` | object | Configuración visual y de comportamiento de la app |
| `seriedefault` | string\|null | Serie por defecto del usuario (puede ser null si tiene múltiples) |

---

## Response de Error (401)

```json
{
    "success": false,
    "message": "Usuario o contraseña incorrecta"
}
```

---

## Notas para Offline

- Este endpoint **requiere conexión a internet** siempre.
- El token obtenido debe almacenarse en SQLite/SharedPreferences local.
- El `establishment_id` determina qué items, series y warehouse descargará la app.
- El `sellerId` se envía en cada comprobante como `codigo_vendedor` (documentos) o `seller_id` (notas de venta).
- Si `seriedefault` es `null`, se debe consultar `GET /api/offline/series-numbering` para obtener las series asignadas al usuario.
