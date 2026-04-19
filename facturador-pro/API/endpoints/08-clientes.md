# 08 — Clientes (Consulta, Creación y Búsqueda)

> **Uso offline:** Consultar DNI/RUC (requiere internet), crear clientes manualmente con ubigeo local (sin internet), y buscar en el catálogo descargado.

---

## 1. Consultar DNI

> `GET /api/service/dni/{number}`  
> **Controller:** `Tenant\Api\ServiceController@dni`  
> **Requiere:** Conexión a internet (consulta SUNAT/RENIEC)

### Response (200 OK)

```json
{
    "success": true,
    "data": {
        "name": "QUINO ARROYO, MARIO EDISON",
        "trade_name": "",
        "location_id": [null, null, null],
        "address": "",
        "department_id": null,
        "province_id": null,
        "district_id": null,
        "condition": "",
        "state": ""
    },
    "time": 0.063
}
```

---

## 2. Consultar RUC

> `GET /api/service/ruc/{number}`  
> **Controller:** `Tenant\Api\ServiceController@ruc`  
> **Requiere:** Conexión a internet (consulta SUNAT)

### Response (200 OK)

```json
{
    "success": true,
    "data": {
        "name": "AGROLIGHT PERU S.A.C.",
        "trade_name": "",
        "address": "PJ. JORGE BASADRE NRO. 158",
        "location_id": ["15", "1501", "150101"],
        "condition": "HABIDO",
        "state": "ACTIVO",
        "is_agent_retention": false
    },
    "time": 0.074
}
```

### Campos

| Campo | Tipo | Descripción |
|-------|------|-------------|
| `name` | string | Razón social o nombre completo |
| `trade_name` | string | Nombre comercial |
| `address` | string | Dirección fiscal |
| `location_id` | array | `[department_id, province_id, district_id]` |
| `condition` | string | Condición SUNAT: `HABIDO`, `NO HABIDO` |
| `state` | string | Estado SUNAT: `ACTIVO`, `BAJA`, etc. |
| `is_agent_retention` | bool | Si es agente de retención (solo RUC) |

---

## 3. Crear Cliente

> `POST /api/person`  
> **Controller:** `Tenant\Api\MobileController@person`  
> **Auth:** `Bearer {token}`

### Payload

```json
{
    "id": null,
    "type": "customers",
    "identity_document_type_id": "6",
    "number": "20552103816",
    "name": "AGROLIGHT PERU S.A.C.",
    "trade_name": "",
    "country_id": "PE",
    "department_id": "15",
    "province_id": "1501",
    "district_id": "150101",
    "address": "PJ. JORGE BASADRE NRO. 158 URB. POP LA UNIVERSAL 2DA ET.",
    "telephone": null,
    "email": null,
    "condition": "HABIDO",
    "state": "ACTIVO",
    "perception_agent": false,
    "percentage_perception": 0,
    "more_address": []
}
```

| Campo | Tipo | Requerido | Descripción |
|-------|------|-----------|-------------|
| `id` | int\|null | No | `null` para crear, ID para actualizar |
| `type` | string | **Sí** | `"customers"` para clientes, `"suppliers"` para proveedores |
| `identity_document_type_id` | string | **Sí** | `"0"`=Sin doc, `"1"`=DNI, `"6"`=RUC, `"4"`=Carnet extranjería, `"7"`=Pasaporte |
| `number` | string | **Sí** | Número de documento |
| `name` | string | **Sí** | Razón social o nombre completo (APELLIDOS, NOMBRES para DNI) |
| `trade_name` | string | No | Nombre comercial |
| `country_id` | string | No | Código país: `"PE"` |
| `department_id` | string\|null | No | ID departamento (2 dígitos). Usar ubigeo descargado |
| `province_id` | string\|null | No | ID provincia (4 dígitos) |
| `district_id` | string\|null | No | ID distrito/ubigeo (6 dígitos) |
| `address` | string\|null | No | Dirección fiscal |
| `telephone` | string\|null | No | Teléfono |
| `email` | string\|null | No | Email |
| `perception_agent` | bool | No | Si es agente de percepción |
| `percentage_perception` | float | No | Porcentaje de percepción |
| `more_address` | array | No | Direcciones adicionales |

### Response (200 OK)

```json
{
    "success": true,
    "msg": "Cliente registrado con éxito",
    "data": {
        "id": 10,
        "description": "AGROLIGHT PERU S.A.C.",
        "name": "AGROLIGHT PERU S.A.C.",
        "number": "20552103816",
        "identity_document_type_id": "6",
        "identity_document_type_code": "6",
        "address": "PJ. JORGE BASADRE NRO. 158 URB. POP LA UNIVERSAL 2DA ET.",
        "email": null,
        "telephone": null,
        "country_id": "PE",
        "district_id": "150101",
        "selected": false
    }
}
```

---

## 4. Buscar Clientes

> `GET /api/document/search-customers?input={query}`  
> **Controller:** `Tenant\Api\MobileController@searchCustomers`

Busca por nombre o número de documento. Retorna array de clientes.

---

## Flujo Offline para Clientes

### Con internet

```
1. Usuario ingresa DNI/RUC
2. GET /api/service/dni/{number} o /api/service/ruc/{number}
3. Datos llegan prellenados
4. POST /api/person → crea cliente en backend
5. Usar el ID retornado en comprobantes
```

### Sin internet (modo offline)

```
1. Usuario ingresa DNI/RUC manualmente
2. NO se puede consultar SUNAT → usuario escribe nombre y dirección manualmente
3. Seleccionar ubigeo desde los datos descargados (ver 05-ubigeo.md):
   Departamento → Provincia → Distrito
4. Guardar cliente localmente en SQLite con un ID temporal negativo
5. Al crear el comprobante offline, usar datos_del_cliente_o_receptor con los datos ingresados
6. Al sincronizar (sync-batch), el backend:
   a. Crea el cliente automáticamente si no existe (force_create_if_not_exist = true para NV)
   b. Para Boleta/Factura: DocumentValidation busca o crea la persona por número de documento
```

### Mapeo de tipos de documento de identidad

| Código | Tipo | Longitud |
|--------|------|----------|
| `0` | Sin documento | - |
| `1` | DNI | 8 dígitos |
| `4` | Carnet de extranjería | 12 caracteres |
| `6` | RUC | 11 dígitos |
| `7` | Pasaporte | variable |
| `A` | Cédula diplomática | variable |

### Reglas por tipo de comprobante

| Comprobante | Tipos de doc. identidad permitidos |
|------------|-----------------------------------|
| **Boleta** (03) | `0` (sin doc, montos ≤ 700), `1` (DNI), `4`, `7`, `A` |
| **Factura** (01) | `6` (RUC) obligatorio |
| **Nota de Venta** (80) | Cualquiera |
| **Guía de Remisión** | `1` (DNI), `6` (RUC) |
