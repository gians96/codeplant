# 18 — Fix: SeriesNumberingController

> **Archivo:** `modules/Offline/Http/Controllers/SeriesNumberingController.php`  
> **Prioridad:** Alta — Afecta directamente la operación offline.

---

## Problemas Identificados

| # | Problema | Impacto |
|---|---------|---------|
| 1 | No filtra series por usuario autenticado | Un vendedor ve/usa series de otro vendedor |
| 2 | Solo soporta doc_type `01`, `03`, `80` | No se puede obtener numeración para NC (07), ND (08), guías (09, 31) |
| 3 | Consulta tabla `documents` para todos los tipos | Para guías (09/31), el `last_number` debe venir de tabla `dispatches` |
| 4 | No usa `getLastNumberBySerie` consistentemente | Para `80` hace query manual; para `09`/`31` no existe query |

---

## Código Actual (con problemas)

```php
public function index(Request $request)
{
    $user = $request->user();
    $establishmentId = $user->establishment_id;

    // ❌ Problema 1: Trae TODAS las series del establecimiento
    $series = Series::where('establishment_id', $establishmentId)->get();

    $result = $series->map(function ($serie) {
        $lastNumber = 0;

        // ❌ Problema 2: Solo maneja 01, 03, 80
        if (in_array($serie->document_type_id, ['01', '03'])) {
            $lastNumber = Document::getLastNumberBySerie($serie->number);
        } elseif ($serie->document_type_id == '80') {
            $last = SaleNote::where('series', $serie->number)
                ->orderBy('number', 'desc')
                ->first();
            $lastNumber = $last ? $last->number : 0;
        }
        // ❌ Problema 3: Tipos 07, 08, 09, 31 quedan con last_number = 0

        return [
            'id' => $serie->id,
            'document_type_id' => $serie->document_type_id,
            'number' => $serie->number,
            'last_number' => (int) $lastNumber,
            'disabled' => (bool) $serie->disabled,
            'contingency' => (bool) $serie->contingency,
        ];
    });

    return response()->json([
        'success' => true,
        'data' => $result->values(),
    ]);
}
```

---

## Código Corregido

```php
<?php

namespace Modules\Offline\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Models\Tenant\Document;
use App\Models\Tenant\Dispatch;
use App\Models\Tenant\SaleNote;
use App\Models\Tenant\Series;
use Illuminate\Http\Request;

class SeriesNumberingController extends Controller
{
    public function index(Request $request)
    {
        $user = $request->user();
        $establishmentId = $user->establishment_id;

        // ── 1. Filtrar series por usuario ──
        $series = $this->getSeriesForUser($user, $establishmentId);

        // ── 2. Calcular última numeración por tipo ──
        $result = $series->map(function ($serie) {
            return [
                'id'               => $serie->id,
                'document_type_id' => $serie->document_type_id,
                'number'           => $serie->number,
                'last_number'      => $this->getLastNumber($serie),
                'disabled'         => (bool) $serie->disabled,
                'contingency'      => (bool) $serie->contingency,
            ];
        });

        return response()->json([
            'success' => true,
            'data'    => $result->values(),
        ]);
    }

    /**
     * Obtener series filtradas según la asignación del usuario.
     * - Modo múltiple: solo series del pivot user_default_document_types
     * - Modo simple: solo la serie asignada en users.series_id
     * - Sin asignación: todas las del establecimiento
     */
    private function getSeriesForUser($user, int $establishmentId)
    {
        if ($user->multiple_default_document_types
            && $user->default_document_types->isNotEmpty()) {
            // Modo múltiple
            $seriesIds = $user->default_document_types->pluck('series_id')->filter();
            return Series::whereIn('id', $seriesIds)
                ->where('establishment_id', $establishmentId)
                ->get();
        }

        if ($user->series_id) {
            // Modo simple
            return Series::where('id', $user->series_id)
                ->where('establishment_id', $establishmentId)
                ->get();
        }

        // Sin asignación → todas las del establecimiento
        return Series::where('establishment_id', $establishmentId)->get();
    }

    /**
     * Obtener el último número usado en una serie,
     * consultando la tabla correcta según el tipo de documento.
     */
    private function getLastNumber($serie): int
    {
        $docType = $serie->document_type_id;
        $seriesNumber = $serie->number;

        // Factura, Boleta, NC, ND → tabla documents
        if (in_array($docType, ['01', '03', '07', '08'])) {
            return (int) Document::getLastNumberBySerie($seriesNumber);
        }

        // Nota de Venta → tabla sale_notes
        if ($docType === '80') {
            return (int) (SaleNote::where('series', $seriesNumber)
                ->orderBy('number', 'desc')
                ->value('number') ?? 0);
        }

        // Guía Remitente, Guía Transportista → tabla dispatches
        if (in_array($docType, ['09', '31'])) {
            return (int) (Dispatch::where('series', $seriesNumber)
                ->orderBy('number', 'desc')
                ->value('number') ?? 0);
        }

        return 0;
    }
}
```

---

## Cambios Realizados

| # | Cambio | Líneas afectadas |
|---|--------|-----------------|
| 1 | Extraer `getSeriesForUser()` que filtra por modo múltiple, simple o sin asignación | Nuevo método |
| 2 | Extraer `getLastNumber()` que consulta la tabla correcta según `document_type_id` | Nuevo método |
| 3 | Agregar soporte para `07`, `08` → tabla `documents` | `getLastNumber()` |
| 4 | Agregar soporte para `09`, `31` → tabla `dispatches` | `getLastNumber()` |
| 5 | Import de `Dispatch` model | Use statement |

---

## Import Necesario

Si `Dispatch` no está importado:

```php
use App\Models\Tenant\Dispatch;
```

---

## Test Manual

```bash
# 1. Usuario con modo múltiple (varias series asignadas)
curl -H "Authorization: Bearer {token}" \
  https://demo.nt-suite.pro/api/offline/series-numbering

# Esperado: solo las series asignadas al usuario en user_default_document_types

# 2. Usuario con modo simple (1 serie)
# Esperado: solo esa serie

# 3. Usuario sin asignación
# Esperado: todas las series del establecimiento

# 4. Verificar que doc_type 09/31 retornan last_number correcto
# Comparar con: SELECT MAX(number) FROM dispatches WHERE series = 'T001'
```

---

## Consideraciones

- El método `Document::getLastNumberBySerie()` ya existe y funciona para `01`, `03`, `07`, `08` (todos usan tabla `documents`).
- `Dispatch` **no tiene** `getLastNumberBySerie()`, por eso se hace la query directa.
- Si se desea, se puede agregar `Dispatch::getLastNumberBySerie()` como método estático para consistencia.
- La relación `$user->default_document_types` ya existe en `User.php` como `hasMany(UserDefaultDocumentType::class)`.
