# 04 — Series y Numeración Offline

> `GET /api/offline/series-numbering`  
> **Controller:** `Modules\Offline\Http\Controllers\SeriesNumberingController@index`  
> **Auth:** `Bearer {token}`  
> **Uso offline:** Obtiene las series del usuario con su última numeración para que Flutter asigne números localmente.

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
    "data": [
        {
            "id": 1,
            "document_type_id": "01",
            "number": "F001",
            "last_number": 145,
            "disabled": false,
            "contingency": false
        },
        {
            "id": 2,
            "document_type_id": "03",
            "number": "B001",
            "last_number": 89,
            "disabled": false,
            "contingency": false
        },
        {
            "id": 10,
            "document_type_id": "80",
            "number": "NV01",
            "last_number": 234,
            "disabled": false,
            "contingency": false
        },
        {
            "id": 15,
            "document_type_id": "09",
            "number": "T001",
            "last_number": 12,
            "disabled": false,
            "contingency": false
        }
    ]
}
```

### Campos

| Campo | Tipo | Descripción |
|-------|------|-------------|
| `id` | int | ID de la serie en BD |
| `document_type_id` | string | Código tipo documento: `01`, `03`, `07`, `08`, `09`, `31`, `80` |
| `number` | string | Código de serie: `F001`, `B001`, `NV01`, `T001`, etc. |
| `last_number` | int | Último número usado en esa serie. Flutter debe continuar desde `last_number + 1` |
| `disabled` | bool | Si la serie está deshabilitada |
| `contingency` | bool | Si es serie de contingencia |

---

## Lógica de Numeración Local en Flutter

```
Para cada comprobante creado offline:
  1. Obtener la serie correspondiente al tipo de documento
  2. nuevo_numero = last_number + 1
  3. Actualizar last_number localmente en SQLite
  4. Usar ese número en el payload del comprobante
```

### Ejemplo:

```
Serie B001 (Boleta), last_number = 89
→ Primera boleta offline: B001-90
→ Segunda boleta offline: B001-91
→ Tercera boleta offline: B001-92
```

---

## Asignación de Series por Usuario

Las series se asignan por usuario en la configuración "Config. Documentos" del módulo de usuarios. Hay 3 escenarios:

### 1. Sin asignación (vacío)

El usuario no tiene series asignadas → recibe **todas** las series del establecimiento.

### 2. Modo simple (1 tipo + 1 serie)

El usuario tiene `document_id` y `series_id` asignados → solo esa serie está habilitada.

| Campo en `users` | Descripción |
|-------------------|-------------|
| `document_id` | Tipo de documento por defecto (ej: `01`) |
| `series_id` | Serie asignada (ej: `F001`) |

### 3. Modo múltiple

El usuario tiene `multiple_default_document_types = true` → puede tener N pares tipo/serie asignados en la tabla `user_default_document_types`:

| user_id | document_type_id | series_id |
|---------|-----------------|-----------|
| 5 | 01 | 1 (F001) |
| 5 | 03 | 2 (B001) |
| 5 | 80 | 10 (NV01) |

> **Cada vendedor tiene su propia serie.** Si Vendedor A tiene `B001` y Vendedor B tiene `B002`, cada uno numera de forma independiente y no hay conflicto.

---

## ⚠️ FIX NECESARIO — Estado Actual vs. Esperado

### Estado actual del controller

```php
// SeriesNumberingController.php (actual)
$series = Series::where('establishment_id', $establishmentId)->get();
// ↑ Devuelve TODAS las series del establecimiento, sin filtrar por usuario
// ↑ Solo calcula last_number para doc_type '01', '03', '80'
```

### Problemas identificados

| # | Problema | Impacto |
|---|---------|---------|
| 1 | No filtra por series asignadas al usuario | Un vendedor podría ver/usar series de otro vendedor |
| 2 | No soporta `document_type_id` `07`, `08` | No se puede numerar NC/ND offline |
| 3 | No soporta `document_type_id` `09`, `31` | No se puede numerar guías offline |
| 4 | Para `09`/`31` consulta tabla `documents` | Debería consultar tabla `dispatches` |

### Fix propuesto

```php
// SeriesNumberingController.php (corregido)
public function index(Request $request)
{
    $user = $request->user();
    $establishmentId = $user->establishment_id;

    // ── 1. Filtrar series por usuario ──
    if ($user->multiple_default_document_types && $user->default_document_types->isNotEmpty()) {
        // Modo múltiple: solo series asignadas
        $seriesIds = $user->default_document_types->pluck('series_id');
        $series = Series::whereIn('id', $seriesIds)
            ->where('establishment_id', $establishmentId)
            ->get();
    } elseif ($user->series_id) {
        // Modo simple: solo la serie asignada
        $series = Series::where('id', $user->series_id)
            ->where('establishment_id', $establishmentId)
            ->get();
    } else {
        // Sin asignación: todas las del establecimiento
        $series = Series::where('establishment_id', $establishmentId)->get();
    }

    // ── 2. Obtener última numeración por tipo ──
    $result = $series->map(function ($serie) {
        $lastNumber = 0;

        if (in_array($serie->document_type_id, ['01', '03', '07', '08'])) {
            // Documentos (Factura, Boleta, NC, ND) → tabla documents
            $lastNumber = Document::getLastNumberBySerie($serie->number);
        } elseif ($serie->document_type_id === '80') {
            // Nota de Venta → tabla sale_notes
            $last = SaleNote::where('series', $serie->number)
                ->orderBy('number', 'desc')
                ->value('number');
            $lastNumber = $last ?? 0;
        } elseif (in_array($serie->document_type_id, ['09', '31'])) {
            // Guías de Remisión → tabla dispatches
            $last = Dispatch::where('series', $serie->number)
                ->orderBy('number', 'desc')
                ->value('number');
            $lastNumber = $last ?? 0;
        }

        return [
            'id'               => $serie->id,
            'document_type_id' => $serie->document_type_id,
            'number'           => $serie->number,
            'last_number'      => (int) $lastNumber,
            'disabled'         => (bool) $serie->disabled,
            'contingency'      => (bool) $serie->contingency,
        ];
    });

    return response()->json([
        'success' => true,
        'data'    => $result->values(),
    ]);
}
```

**Imports adicionales necesarios:**
```php
use App\Models\Tenant\Dispatch;
use App\Models\Tenant\UserDefaultDocumentType;
```

Ver detalle completo del fix en [18-fix-series-numbering.md](18-fix-series-numbering.md).

---

## Notas para Offline

- **Llamar este endpoint después del login** para obtener las series actualizadas con su última numeración.
- Almacenar `last_number` localmente y autoincrementar con cada comprobante creado.
- Al sincronizar con `sync-batch`, el backend **puede reasignar el número** si hubo un conflicto (ej: otro dispositivo usó el mismo número mientras estaba offline). El response del sync devuelve el `number` final asignado.
- La clave `numero_documento: "#"` en los payloads de documentos indica al backend que **auto-numere**. Para modo offline, Flutter debe enviar el número concreto (ej: `"numero_documento": "90"`).
