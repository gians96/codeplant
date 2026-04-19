# 05 — Ubigeo (Departamentos / Provincias / Distritos)

> `GET /api/pro8/catalogs/ubigeo`  
> **Controller:** `Tenant\Api\CatalogApiController@ubigeo`  
> **Auth:** `Bearer {token}`  
> **Uso offline:** Descargar todo el catálogo de ubigeo peruano para crear clientes localmente sin necesidad de internet.

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
    "data": {
        "locations": [
            {
                "value": "15",
                "label": "LIMA",
                "children": [
                    {
                        "value": "1501",
                        "label": "LIMA",
                        "children": [
                            {
                                "value": "150101",
                                "label": "150101 - LIMA"
                            },
                            {
                                "value": "150102",
                                "label": "150102 - ANCON"
                            }
                        ]
                    },
                    {
                        "value": "1502",
                        "label": "BARRANCA",
                        "children": [
                            {
                                "value": "150201",
                                "label": "150201 - BARRANCA"
                            }
                        ]
                    }
                ]
            }
        ],
        "generated_at": "2026-04-18T12:00:00.000000Z"
    }
}
```

### Estructura cascada

| Nivel | Campo | Descripción | Ejemplo |
|-------|-------|-------------|---------|
| 1 | Departamento | `value` = department_id (2 dígitos) | `"15"` = LIMA |
| 2 | Provincia | `value` = province_id (4 dígitos) | `"1501"` = LIMA |
| 3 | Distrito | `value` = district_id / ubigeo (6 dígitos) | `"150101"` = LIMA |

---

## Notas para Offline

- **Descargar una sola vez** y almacenar en SQLite. El catálogo de ubigeo no cambia frecuentemente.
- Se usa al **crear clientes offline** (ver [08-clientes.md](08-clientes.md)):
  - El usuario selecciona departamento → provincia → distrito desde los datos locales
  - El `district_id` (6 dígitos) se envía como `ubigeo` en `datos_del_cliente_o_receptor` y como `district_id` en `POST /api/person`
- La estructura es un árbol cascada ideal para implementar **3 dropdowns encadenados** en Flutter:
  1. Seleccionar departamento → filtra provincias
  2. Seleccionar provincia → filtra distritos
  3. El distrito seleccionado es el `ubigeo` / `district_id`
- Si la app no tiene internet, **no puede consultar DNI/RUC** (requiere SUNAT), pero sí puede crear un cliente manualmente usando el ubigeo descargado.
