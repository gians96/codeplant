# 31 — Hotel, Transporte y Restaurante

> **Giros:** `hotel` (1), `transport` (2), `restaurant` (3)  
> **Auth:** `Bearer {token}`

---

## Descripción

Estos tres giros **no tienen endpoints dedicados**. Se integran como **bloques adicionales en el payload de `POST /api/documents`**:

- **Hotel:** Bloque `hotel{}` + campos `hotel_data_persons`, `hotel_rent_id`
- **Transporte:** Bloque `transport{}`
- **Restaurante:** Campos `worker_full_name_tips` + `total_tips`

El documento se crea normalmente; al persistirse, Pro-8 crea automáticamente los registros relacionados (`DocumentHotel`, `DocumentTransport`, `Tip`).

---

## 1. Hotel

### Modelo `DocumentHotel`

**Tabla:** `document_hotels` (relación 1:1 con `documents`)

| Campo | Tipo | Descripción | Requerido |
|-------|------|-------------|-----------|
| `document_id` | int | FK → documents | ✅ auto |
| `number` | string | Número de documento huésped | ✅ |
| `name` | string | Nombre completo del huésped | ✅ |
| `identity_document_type_id` | string | Tipo doc. identidad (1=DNI, 4=CE, 7=Pasaporte) | ✅ |
| `sex` | enum | `M` o `F` | ✅ |
| `age` | int | Edad | ✅ |
| `civil_status` | enum | `S`, `C`, `V`, `D` | ✅ |
| `nacionality` | string | Nacionalidad | ✅ |
| `origin` | string | Ciudad de origen | ✅ |
| `room_number` | string | Número de habitación | ✅ |
| `date_entry` | date | Fecha de ingreso (Y-m-d) | ✅ |
| `time_entry` | time | Hora de ingreso (H:i:s) | ✅ |
| `date_exit` | date | Fecha de salida | ✅ |
| `time_exit` | time | Hora de salida | ✅ |
| `ocupation` | string | Ocupación | ✅ |
| `room_type` | enum | `single`, `matrimonial`, `double`, `triple` | ✅ |
| `guests` | JSON | Array de acompañantes | ❌ |

### Campos adicionales a nivel `Document`

| Campo | Tipo | Descripción |
|-------|------|-------------|
| `hotel_data_persons` | JSON | Snapshot de datos huésped + acompañantes (reporte) |
| `hotel_rent_id` | int | FK opcional a reserva/renta |

### Payload

```json
{
    "serie_documento": "F001",
    "numero_documento": "#",
    "codigo_tipo_documento": "01",
    "...": "resto del documento",
    "hotel": {
        "number": "12345678",
        "name": "GARCÍA LÓPEZ MARÍA",
        "identity_document_type_id": "1",
        "sex": "F",
        "age": 35,
        "civil_status": "C",
        "nacionality": "PERUANA",
        "origin": "LIMA",
        "room_number": "301",
        "date_entry": "2026-04-18",
        "time_entry": "14:00:00",
        "date_exit": "2026-04-20",
        "time_exit": "12:00:00",
        "ocupation": "INGENIERA",
        "room_type": "matrimonial",
        "guests": [
            {
                "number": "87654321",
                "name": "GARCÍA LÓPEZ JUAN",
                "identity_document_type_id": "1",
                "age": 10,
                "sex": "M"
            }
        ]
    },
    "hotel_data_persons": [
        { "number": "12345678", "name": "GARCÍA LÓPEZ MARÍA" },
        { "number": "87654321", "name": "GARCÍA LÓPEZ JUAN" }
    ]
}
```

### Catálogos (desde `GET /api/offline/business-turns`)

Ver bloque `hotel_tables` en [28-giros-de-negocio.md](28-giros-de-negocio.md):
- `identity_document_types`
- `sexes`
- `civil_statuses`
- `room_types`

### Validaciones (ref: `DocumentHotelRequest.php`)

```php
'number' => 'required|string|max:20',
'name' => 'required|string|max:500',
'identity_document_type_id' => 'required|string|max:2',
'sex' => 'required|in:M,F',
'age' => 'required|integer',
'civil_status' => 'required|in:S,C,V,D',
'room_type' => 'required|in:single,matrimonial,double,triple',
'date_entry' => 'required|date_format:Y-m-d',
'date_exit' => 'required|date_format:Y-m-d',
```

---

## 2. Transporte

### Modelo `DocumentTransport`

**Tabla:** `document_transports` (relación 1:1 con `documents`)

| Campo | Tipo | Descripción |
|-------|------|-------------|
| `document_id` | int | FK → documents |
| `seat_number` | string | Número de asiento |
| `passenger_manifest` | string | Manifiesto de pasajeros |
| `identity_document_type_id` | string | Tipo doc. pasajero |
| `number_identity_document` | string | Número doc. pasajero |
| `passenger_fullname` | string | Nombre completo del pasajero |
| `origin_district_id` | JSON | Array `[dep_id, prov_id, dist_id]` |
| `origin_address` | string | Dirección de origen |
| `destinatation_district_id` | JSON | Array `[dep_id, prov_id, dist_id]` |
| `destinatation_address` | string | Dirección de destino |
| `start_date` | date | Fecha de inicio viaje |
| `start_time` | time | Hora de inicio viaje |

> **Nota:** Los campos `origin_district_id` y `destinatation_district_id` tienen accessor/mutator JSON. Se envían como array de 3 strings (departamento, provincia, distrito). Internamente se guardan como JSON.

### Payload

```json
{
    "serie_documento": "B001",
    "numero_documento": "#",
    "...": "resto del documento",
    "transport": {
        "seat_number": "15A",
        "passenger_manifest": "MAN-2026-001",
        "identity_document_type_id": "1",
        "number_identity_document": "12345678",
        "passenger_fullname": "PÉREZ GARCÍA JUAN",
        "origin_district_id": ["15", "1501", "150101"],
        "origin_address": "Terminal Terrestre Lima",
        "destinatation_district_id": ["04", "0401", "040101"],
        "destinatation_address": "Terminal Terrestre Arequipa",
        "start_date": "2026-04-20",
        "start_time": "08:00:00"
    }
}
```

### Catálogos de ubigeo

```
GET /bussiness_turns/tables/transports
```

Retorna departamentos, provincias, distritos (tabla `districts`). Flutter puede descargarlos una sola vez y cachearlos (son ~1,800 distritos, ~150KB).

Alternativamente, usar el endpoint offline existente:
```
GET /api/pro8/districts
```

### Validaciones (ref: `DocumentTransportRequest.php`)

```php
'seat_number' => 'nullable|string|max:100',
'passenger_manifest' => 'nullable|string|max:100',
'identity_document_type_id' => 'required|string|max:2',
'number_identity_document' => 'required|string|max:20',
'passenger_fullname' => 'required|string|max:500',
'origin_district_id' => 'required|array|size:3',
'destinatation_district_id' => 'required|array|size:3',
'start_date' => 'required|date_format:Y-m-d',
'start_time' => 'required|date_format:H:i:s',
```

---

## 3. Restaurante (Propina)

### Modelo `Tip`

**Tabla:** `tips` (polimórfica morphOne con `Document` y `SaleNote`)

| Campo | Tipo | Descripción |
|-------|------|-------------|
| `soap_type_id` | string(2) | Tipo SOAP (01=producción, 02=pruebas) |
| `date` | date | Fecha propina |
| `origin_date_of_issue` | date | Fecha emisión del comprobante origen |
| `origin_id` | int | ID polimórfico |
| `origin_type` | string | Clase polimórfica (`Modules\Document\Models\Document`) |
| `worker_full_name` | string | Nombre del trabajador que recibe la propina |
| `total` | decimal(12,2) | Monto de la propina |

### Payload

Solo **2 campos simples** a nivel raíz del documento:

```json
{
    "serie_documento": "B001",
    "numero_documento": "#",
    "...": "resto del documento",
    "worker_full_name_tips": "MARÍA LÓPEZ",
    "total_tips": 10.50
}
```

### Comportamiento

Al crear el documento, Pro-8 automáticamente:
1. Crea un registro en `tips` asociado polimórficamente al documento
2. Guarda `worker_full_name = "MARÍA LÓPEZ"` y `total = 10.50`

**La propina NO se suma al total del documento.** Es un campo informativo para control interno del restaurante y reportes de propinas por mozo.

### Configuración sugerida

Desde `GET /api/offline/business-turns`:
```json
{
    "restaurant_tip_factor": 10
}
```

Flutter puede calcular y sugerir: `propina_sugerida = total_venta * restaurant_tip_factor / 100`

El usuario puede aceptar, modificar o dejar en 0.

---

## 4. Ejemplo Combinado — Hotel + Restaurante

Un hotel que también tiene restaurante puede emitir una factura con AMBOS bloques:

```json
{
    "serie_documento": "F001",
    "numero_documento": "#",
    "fecha_de_emision": "2026-04-19",
    "codigo_tipo_documento": "01",
    "datos_del_cliente_o_receptor": {
        "codigo_tipo_documento_identidad": "6",
        "numero_documento": "20123456789",
        "apellidos_y_nombres_o_razon_social": "EMPRESA S.A.C."
    },
    "items": [
        {
            "codigo_interno": "HAB-MAT",
            "descripcion": "Habitación matrimonial (2 noches)",
            "cantidad": 2,
            "valor_unitario": 169.49,
            "precio_unitario": 200,
            "...": "..."
        },
        {
            "codigo_interno": "REST-001",
            "descripcion": "Cena buffet",
            "cantidad": 1,
            "valor_unitario": 42.37,
            "precio_unitario": 50,
            "...": "..."
        }
    ],
    "totales": {
        "total_venta": 450
    },
    "hotel": {
        "number": "12345678",
        "name": "GARCÍA LÓPEZ MARÍA",
        "identity_document_type_id": "1",
        "sex": "F",
        "age": 35,
        "civil_status": "C",
        "nacionality": "PERUANA",
        "origin": "LIMA",
        "room_number": "301",
        "date_entry": "2026-04-17",
        "time_entry": "14:00:00",
        "date_exit": "2026-04-19",
        "time_exit": "12:00:00",
        "ocupation": "INGENIERA",
        "room_type": "matrimonial"
    },
    "worker_full_name_tips": "CARLOS MOZO",
    "total_tips": 15.00
}
```

---

## 5. Flujo en Flutter

### Al crear venta — Hotel

```
1. Usuario agrega items (habitación, servicios)
2. Antes de cobrar → botón "Datos huésped"
3. Formulario hotel{}:
   - Datos huésped principal (requerido)
   - Huéspedes adicionales (opcional, array guests[])
4. Validar y agregar al payload
5. Emitir normalmente
```

### Al crear venta — Transporte

```
1. Usuario selecciona ruta/servicio
2. Formulario transport{}:
   - Asiento, manifiesto
   - Datos pasajero
   - Origen → cascada ubigeos (depto → prov → dist)
   - Destino → cascada ubigeos
   - Fecha/hora de viaje
3. Validar y agregar al payload
```

### Al cobrar — Restaurante

```
1. Al pulsar "Cobrar":
2. Mostrar modal:
   - Total: S/. 85.00
   - Propina sugerida (10%): S/. 8.50 [editable]
   - Mozo: [dropdown trabajadores / texto libre]
3. Flutter añade:
   - worker_full_name_tips
   - total_tips
```

---

## 6. Notas para Offline

### Almacenamiento local

Los 3 giros son 100% **payload-based**. No requieren sincronización previa:
- Flutter guarda el bloque en el JSON del documento pendiente
- Al sincronizar con `/api/documents`, el bloque viaja dentro del payload

### Catálogos a cachear

| Giro | Catálogo | Fuente | Tamaño |
|------|----------|--------|--------|
| Hotel | `hotel_tables` | `/api/offline/business-turns` | ~1 KB |
| Transporte | `districts` | `/api/pro8/districts` | ~150 KB |
| Restaurante | Trabajadores | `/api/pro8/users` o local | ~5 KB |

### Validación offline

Como Flutter no tiene acceso al `DocumentHotelRequest`/`DocumentTransportRequest`, debe **replicar las reglas** en el cliente:

```dart
// Hotel
if (turns.isHotel) {
    if (hotel.number.isEmpty) return 'Documento huésped requerido';
    if (!['M', 'F'].contains(hotel.sex)) return 'Sexo inválido';
    if (!['S','C','V','D'].contains(hotel.civilStatus)) return 'Estado civil inválido';
    if (!['single','matrimonial','double','triple'].contains(hotel.roomType)) return 'Tipo habitación inválido';
}

// Transporte
if (turns.isTransport) {
    if (transport.originDistrictId.length != 3) return 'Ubigeo origen incompleto';
    if (transport.destinatationDistrictId.length != 3) return 'Ubigeo destino incompleto';
}
```

### Manejo de errores de sync

Si el backend rechaza por datos inválidos (ej: `date_entry` > `date_exit`), el documento falla con:
```json
{
    "success": false,
    "message": "La fecha de salida debe ser posterior a la fecha de entrada"
}
```

Flutter marca el documento como "rejected" y lo presenta al operador para corrección (ver [18-errores-y-codigos.md](18-errores-y-codigos.md)).

### Referencias código backend

| Archivo | Línea | Función |
|---------|-------|---------|
| `app/CoreFacturalo/Inputs/DocumentInput.php` | 145 | Mapeo hotel |
| `app/CoreFacturalo/Inputs/DocumentInput.php` | 146 | Mapeo transport |
| `app/CoreFacturalo/Inputs/DocumentInput.php` | 748 | Mapeo tip (restaurant) |
| `app/CoreFacturalo/Transform/DocumentTransform.php` | 75 | Transform hotel |
| `app/CoreFacturalo/Transform/DocumentTransform.php` | 76 | Transform transport |
| `app/CoreFacturalo/Facturalo.php` | 160 | `$document->hotel()->create()` |
| `app/CoreFacturalo/Facturalo.php` | 161 | `$document->transport()->create()` |
