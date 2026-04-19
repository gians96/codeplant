# 28 — Giros de Negocio

> `GET /api/offline/business-turns`  
> **Auth:** `Bearer {token}`

---

## Descripción

Pro-8 soporta 5 giros de negocio que modifican el comportamiento del POS, la facturación, los reportes y los campos adicionales de los comprobantes. Flutter debe descargar la configuración al iniciar sesión y adaptar la UI según los giros activos.

---

## Giros Disponibles

| ID | value | name | Impacto principal |
|----|-------|------|-------------------|
| 1 | `hotel` | Hoteles | Bloque `hotel{}` en documentos (datos huésped, habitación) |
| 2 | `transport` | Empresa de transporte de pasajeros | Bloque `transport{}` en documentos (asiento, origen/destino) |
| 3 | `restaurant` | Restaurantes | Campo propina (`worker_full_name_tips`, `total_tips`) |
| 4 | `tap` | Grifos | Campo `plate_number`, atributo `7000` en items |
| 5 | `pharmacy` | Farmacia | Lotes, vencimiento, DIGEMID, registro sanitario |

> **Un tenant puede tener VARIOS giros activos simultáneamente** (ej: un minimarket que es grifo y farmacia a la vez).

---

## Endpoint

```
GET /api/offline/business-turns
Authorization: Bearer {token}
```

### Response (200 OK)

```json
{
    "success": true,
    "data": {
        "turns": [
            { "id": 1, "value": "hotel", "name": "Hoteles", "active": false },
            { "id": 2, "value": "transport", "name": "Empresa de transporte de pasajeros", "active": false },
            { "id": 3, "value": "restaurant", "name": "Restaurantes", "active": false },
            { "id": 4, "value": "tap", "name": "Grifos", "active": true },
            { "id": 5, "value": "pharmacy", "name": "Farmacia", "active": true }
        ],
        "is_pharmacy": true,
        "restaurant_tip_factor": 0,
        "configuration_taps": {
            "save_plates_client": true
        },
        "hotel_tables": {
            "identity_document_types": [
                { "id": "1", "description": "DNI" },
                { "id": "4", "description": "Carnet de extranjería" },
                { "id": "7", "description": "Pasaporte" }
            ],
            "sexes": [
                { "id": "M", "description": "Masculino" },
                { "id": "F", "description": "Femenino" }
            ],
            "civil_statuses": [
                { "id": "S", "description": "Soltero" },
                { "id": "C", "description": "Casado" },
                { "id": "V", "description": "Viudo" },
                { "id": "D", "description": "Divorciado" }
            ],
            "room_types": [
                { "id": "single", "description": "Simple" },
                { "id": "matrimonial", "description": "Matrimonial" },
                { "id": "double", "description": "Doble" },
                { "id": "triple", "description": "Triple" }
            ]
        },
        "pharmacy": {
            "cod_digemid": "E1234567"
        }
    }
}
```

### Campos de la respuesta

| Campo | Tipo | Descripción |
|-------|------|-------------|
| `turns[]` | array | Todos los giros con su estado `active` |
| `is_pharmacy` | bool | Shortcut de `turns[4].active`. Controla UI de farmacia |
| `restaurant_tip_factor` | int | Factor de propina sugerida (%). Normalmente 10 |
| `configuration_taps` | object | Configuración específica de grifos |
| `configuration_taps.save_plates_client` | bool | Si se deben guardar placas asociadas a cada cliente |
| `hotel_tables` | object | Catálogos para el formulario de hotel |
| `pharmacy.cod_digemid` | string | Código DIGEMID de la empresa (para exportes) |

> **Nota:** Los `hotel_tables` se envían aunque `hotel` no esté activo — Flutter los cachea para no tener que pedirlos después.

---

## Uso en Flutter

### Al iniciar sesión (después del login)

```dart
// 1. Descargar giros de negocio
final turns = await api.get('/api/offline/business-turns');

// 2. Guardar en SharedPreferences / SQLite
prefs.setString('business_turns', jsonEncode(turns['data']));

// 3. Al abrir POS, verificar giros activos
bool isGrifo = turns['data']['turns'].firstWhere((t) => t['value'] == 'tap')['active'];
bool isFarmacia = turns['data']['is_pharmacy'];
bool isHotel = turns['data']['turns'].firstWhere((t) => t['value'] == 'hotel')['active'];
bool isTransporte = turns['data']['turns'].firstWhere((t) => t['value'] == 'transport')['active'];
bool isRestaurante = turns['data']['turns'].firstWhere((t) => t['value'] == 'restaurant')['active'];
```

### Adaptación de UI

| Giro activo | UI que se muestra |
|-------------|-------------------|
| `tap` (grifo) | Campo obligatorio "Placa" al facturar. Ver [29-grifo-placas.md](29-grifo-placas.md) |
| `pharmacy` (farmacia) | Selector de lote al agregar item con `lots_enabled`. Alertas de vencimiento. Ver [30-lotes-series-farmacia.md](30-lotes-series-farmacia.md) |
| `hotel` | Botón "Datos de reserva" en detalle de factura. Ver [31-hotel-transporte-restaurante.md](31-hotel-transporte-restaurante.md) |
| `transport` | Botón "Datos de transporte". Ver [31-hotel-transporte-restaurante.md](31-hotel-transporte-restaurante.md) |
| `restaurant` | Campo "Propina" al cobrar (con `restaurant_tip_factor`% sugerido) |

---

## Notas para Offline

- **Descarga única por sesión:** Los giros raramente cambian. Descargar al login es suficiente. Opcional: re-sincronizar cada cierre de caja.
- **Valores offline:** Si el dispositivo no tiene conexión al momento del login, usar los giros cacheados en la última sesión.
- **Cambios en tiempo real:** Si un administrador cambia los giros desde la web mientras Flutter está offline, los cambios se reflejarán en la próxima descarga. No hay push notification.
- **Combinaciones comunes:**
  - Grifo + Farmacia (minimarket de grifo con botica)
  - Restaurante + Hotel (hotel con restaurante)
  - Solo Farmacia (boticas)
  - Solo Grifo (estaciones puras)

---

## Relación con otros invariantes

Los giros modifican la UI y el payload, **no** la lógica de series por usuario ni el filtrado de items. Es decir:

- Un vendedor con serie `B001` asignada sigue viendo sólo `B001` aunque el giro farmacia esté activo.
- Los lotes/stock siguen filtrándose por el warehouse del establecimiento del usuario.

Ver [33-validacion-contrato-offline.md](33-validacion-contrato-offline.md) para los 4 invariantes del contrato offline.
