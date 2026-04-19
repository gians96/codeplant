# 02 — Datos de Empresa

> `GET /api/company`  
> **Controller:** `Tenant\Api\CompanyController@record`  
> **Auth:** `Bearer {token}`  
> **Uso offline:** Descarga inicial de series, clientes, establecimientos, métodos de pago y destinos de pago. Se almacena localmente.

---

## Request

### Headers

```
Accept: application/json
Authorization: Bearer {token}
```

### Parámetros

Ninguno.

---

## Response (200 OK)

```json
{
    "series": [
        {
            "id": 1,
            "document_type_id": "01",
            "number": "F001",
            "establishment_id": 1,
            "contingency": false,
            "disabled": false
        },
        {
            "id": 2,
            "document_type_id": "03",
            "number": "B001",
            "establishment_id": 1,
            "contingency": false,
            "disabled": false
        },
        {
            "id": 10,
            "document_type_id": "80",
            "number": "NV01",
            "establishment_id": 1,
            "contingency": false,
            "disabled": false
        }
    ],
    "establishments": [
        {
            "id": 1,
            "description": "Oficina Principal",
            "country_id": "PE",
            "department_id": "15",
            "province_id": "1501",
            "district_id": "150101",
            "address": "Dirección principal",
            "phone": "999999999",
            "email": "demo@nt-suite.pro",
            "code": "0000",
            "trade_address": null,
            "web_address": null,
            "aditional_information": null,
            "customer_id": null
        }
    ],
    "company": {
        "id": 1,
        "identity_document_type_id": "6",
        "number": "20538856674",
        "name": "ARTROSCOPICTRAUMA S.A.C.",
        "trade_name": "ARTROSCOPICTRAUMA S.A.C.",
        "soap_send_id": "01",
        "soap_type_id": "01",
        "logo": null,
        "operation_amazonia": 0,
        "title_web": "Facturación Electrónica"
    },
    "customers": [
        {
            "id": 1,
            "identity_document_type_id": "0",
            "identity_document_type_code": "0",
            "number": "0",
            "name": "CLIENTES VARIOS",
            "address": null,
            "email": null,
            "telephone": null,
            "country_id": "PE",
            "district_id": null,
            "selected": false,
            "telefono": null
        }
    ],
    "payment_method_types": [
        {
            "id": "01",
            "description": "Efectivo",
            "has_card_brand": false,
            "number_days": null,
            "disabled": false,
            "is_cash": true
        },
        {
            "id": "02",
            "description": "Tarjeta de crédito",
            "has_card_brand": true,
            "number_days": null,
            "disabled": false,
            "is_cash": false
        }
    ],
    "payment_destinations": [
        {
            "id": 1,
            "description": "Caja general",
            "is_default": true
        }
    ],
    "tags": []
}
```

---

## Campos Detallados

### `series[]`

| Campo | Tipo | Descripción |
|-------|------|-------------|
| `id` | int | ID de la serie |
| `document_type_id` | string | Código tipo documento: `01`, `03`, `07`, `08`, `09`, `31`, `80` |
| `number` | string | Código de serie: `F001`, `B001`, `NV01`, `T001`, etc. |
| `establishment_id` | int | ID del establecimiento al que pertenece |
| `contingency` | bool | Si es serie de contingencia |
| `disabled` | bool | `true` si el usuario NO tiene asignada esta serie |

> **Importante:** Las series vienen filtradas por el `establishment_id` del usuario. El campo `disabled` indica si el usuario tiene asignada esa serie. Para modo offline, **usar solo las series con `disabled: false`**.

### `customers[]`

| Campo | Tipo | Descripción |
|-------|------|-------------|
| `id` | int | ID del cliente (para `customer_id` en nota de venta) |
| `identity_document_type_id` | string | `0`=Sin doc, `1`=DNI, `6`=RUC |
| `identity_document_type_code` | string | Mismo valor para compatibilidad |
| `number` | string | Número de documento |
| `name` | string | Razón social o nombre completo |
| `address` | string\|null | Dirección |
| `email` | string\|null | Email |
| `telephone` | string\|null | Teléfono |
| `country_id` | string | Código país (PE) |
| `district_id` | string\|null | Código ubigeo distrito |

> Se descargan hasta **2000 clientes** ordenados por nombre. Para buscar más, usar `GET /api/document/search-customers?input={query}`.

### `payment_method_types[]`

| Campo | Tipo | Descripción |
|-------|------|-------------|
| `id` | string | Código del método de pago |
| `description` | string | Nombre legible |
| `has_card_brand` | bool | Si requiere marca de tarjeta |
| `number_days` | int\|null | Días para pago diferido |
| `disabled` | bool | Si está deshabilitado |
| `is_cash` | bool | Si es pago en efectivo (para caja) |

### `payment_destinations[]`

| Campo | Tipo | Descripción |
|-------|------|-------------|
| `id` | int | ID del destino de pago |
| `description` | string | Nombre del destino |
| `is_default` | bool | Si es el destino por defecto |

---

## Notas para Offline

- **Almacenar todo localmente** en SQLite al momento de la descarga inicial.
- Las `series` aquí son una vista general. Para numeración offline con `last_number`, usar `GET /api/offline/series-numbering` (ver [04-series-numeracion.md](04-series-numeracion.md)).
- Los `customers` son el catálogo base. Se pueden crear clientes nuevos offline (ver [08-clientes.md](08-clientes.md)).
- Los `payment_method_types` se necesitan para los `pagos[]` de boleta/factura y los `payments[]` de nota de venta.
- El `company.soap_type_id` indica el modo SUNAT: `01` = Producción, `02` = Beta/Demo.
