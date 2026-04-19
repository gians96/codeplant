# 16 — Estrategia de Idempotencia

> **Problema:** Al operar offline, Flutter puede reintentar el envío de comprobantes que ya fueron procesados (por timeout, error de red, etc.), generando duplicados.

---

## Solución: `offline_id`

Cada comprobante creado offline lleva un **UUID v4 único** generado por Flutter. El backend verifica si ya existe un comprobante con ese `offline_id` antes de crearlo.

```
Flutter genera UUID → offline_id: "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
    ↓
POST /api/offline/sync-batch
    ↓
Backend: SELECT * FROM documents WHERE offline_id = ?
    ├── EXISTE → retornar datos existentes (no re-crear)
    └── NO EXISTE → crear comprobante → guardar offline_id
```

---

## Migraciones Necesarias

### 1. Migración: `documents.offline_id`

```php
<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

class AddOfflineIdToDocumentsTable extends Migration
{
    public function up()
    {
        Schema::table('documents', function (Blueprint $table) {
            $table->string('offline_id', 36)->nullable()->after('external_id');
            $table->unique('offline_id', 'documents_offline_id_unique');
        });
    }

    public function down()
    {
        Schema::table('documents', function (Blueprint $table) {
            $table->dropUnique('documents_offline_id_unique');
            $table->dropColumn('offline_id');
        });
    }
}
```

### 2. Migración: `sale_notes.offline_id`

```php
<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

class AddOfflineIdToSaleNotesTable extends Migration
{
    public function up()
    {
        Schema::table('sale_notes', function (Blueprint $table) {
            $table->string('offline_id', 36)->nullable()->after('external_id');
            $table->unique('offline_id', 'sale_notes_offline_id_unique');
        });
    }

    public function down()
    {
        Schema::table('sale_notes', function (Blueprint $table) {
            $table->dropUnique('sale_notes_offline_id_unique');
            $table->dropColumn('offline_id');
        });
    }
}
```

### 3. Migración: `dispatches.offline_id`

```php
<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

class AddOfflineIdToDispatchesTable extends Migration
{
    public function up()
    {
        Schema::table('dispatches', function (Blueprint $table) {
            $table->string('offline_id', 36)->nullable()->after('external_id');
            $table->unique('offline_id', 'dispatches_offline_id_unique');
        });
    }

    public function down()
    {
        Schema::table('dispatches', function (Blueprint $table) {
            $table->dropUnique('dispatches_offline_id_unique');
            $table->dropColumn('offline_id');
        });
    }
}
```

> **Nota:** El campo es `nullable` porque los comprobantes creados antes de la migración no tendrán `offline_id`. El UNIQUE INDEX con `nullable` funciona correctamente en MySQL (múltiples NULLs permitidos).

---

## Lógica de Verificación en OfflineSyncController

```php
private function checkOfflineIdExists(string $offlineId, string $docType): ?array
{
    if (in_array($docType, ['01', '03', '07', '08'])) {
        $document = Document::where('offline_id', $offlineId)->first();
        if ($document) {
            return [
                'id'            => $document->id,
                'number'        => $document->number_full,
                'external_id'   => $document->external_id,
                'filename'      => $document->filename,
                'state_type_id' => $document->state_type_id,
            ];
        }
    } elseif ($docType === '80') {
        $saleNote = SaleNote::where('offline_id', $offlineId)->first();
        if ($saleNote) {
            return [
                'id'          => $saleNote->id,
                'number'      => $saleNote->number_full,
                'external_id' => $saleNote->external_id,
                'filename'    => $saleNote->filename,
            ];
        }
    } elseif (in_array($docType, ['09', '31'])) {
        $dispatch = Dispatch::where('offline_id', $offlineId)->first();
        if ($dispatch) {
            return [
                'id'          => $dispatch->id,
                'number'      => $dispatch->number_full,
                'external_id' => $dispatch->external_id,
                'filename'    => $dispatch->filename,
            ];
        }
    }

    return null;
}
```

### Uso en syncBatch

```php
foreach ($request->sales as $index => $sale) {
    $offlineId = $sale['offline_id'] ?? null;
    $docType   = $sale['doc_type'];

    // ── Idempotencia: verificar si ya fue procesado ──
    if ($offlineId) {
        $existing = $this->checkOfflineIdExists($offlineId, $docType);
        if ($existing) {
            $results[] = [
                'index'         => $index,
                'success'       => true,
                'offline_id'    => $offlineId,
                'doc_type'      => $docType,
                'data'          => $existing,
                'was_duplicate' => true,
            ];
            continue; // ← No procesar, ya existe
        }
    }

    // ── Procesar normalmente ──
    try {
        $data = $this->processByDocType($sale);
        // Guardar offline_id en el registro creado
        if ($offlineId) {
            $this->saveOfflineId($data['model'], $offlineId);
        }
        $results[] = [
            'index'      => $index,
            'success'    => true,
            'offline_id' => $offlineId,
            'doc_type'   => $docType,
            'data'       => $data['response'],
        ];
    } catch (\Exception $e) {
        $results[] = [
            'index'      => $index,
            'success'    => false,
            'offline_id' => $offlineId,
            'doc_type'   => $docType,
            'error'      => $e->getMessage(),
        ];
    }
}
```

---

## Generación de UUID en Flutter

```dart
import 'package:uuid/uuid.dart';

class OfflineIdGenerator {
  static const _uuid = Uuid();
  
  /// Genera un UUID v4 único para cada comprobante offline
  static String generate() => _uuid.v4();
}

// Uso al crear un comprobante offline:
final sale = OfflineSale(
  offlineId: OfflineIdGenerator.generate(),
  docType: '80',
  data: saleNotePayload,
  createdAt: DateTime.now(),
);
```

---

## Protección contra duplicados por tipo

| Tipo | Protección nativa (BD) | `offline_id` necesario |
|------|----------------------|----------------------|
| Factura (01) | `unique_filename` constraint | Recomendado (evita retry) |
| Boleta (03) | `unique_filename` constraint | Recomendado (evita retry) |
| NC (07) | `unique_filename` constraint | Recomendado |
| ND (08) | `unique_filename` constraint | Recomendado |
| Nota de Venta (80) | **NINGUNA** | **CRÍTICO** — sin esto hay duplicados |
| Guía Remitente (09) | `unique_filename` constraint | Recomendado |
| Guía Transportista (31) | `unique_filename` constraint | Recomendado |

> **La Nota de Venta (80) es el caso más crítico** porque no tiene constraint unique en BD. Sin `offline_id`, un reintento crearía un duplicado sin error.

---

## Diagrama de Flujo

```
Flutter: crear comprobante offline
    │
    ├── Generar offline_id (UUID v4)
    ├── Guardar en SQLite local
    │
    ▼
Flutter: sincronizar (con internet)
    │
    ├── POST /api/offline/sync-batch
    │   body: { sales: [{ offline_id, doc_type, data }] }
    │
    ▼
Backend: para cada sale
    │
    ├── SELECT WHERE offline_id = ?
    │   ├── ENCONTRADO → response { success: true, was_duplicate: true, data: {...} }
    │   └── NO ENCONTRADO
    │       ├── Crear comprobante
    │       ├── UPDATE SET offline_id = ?
    │       └── response { success: true, data: {...} }
    │
    ▼
Flutter: procesar response
    │
    ├── success + was_duplicate → marcar como sincronizado
    ├── success → marcar como sincronizado, guardar external_id
    └── error → mantener en cola, mostrar error al usuario
```

---

## Notas

- El `offline_id` es **inmutable**: una vez asignado, nunca cambia. Aunque Flutter reintente N veces, siempre envía el mismo UUID para el mismo comprobante.
- El campo es `VARCHAR(36)` para UUID estándar: `xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx`.
- Los comprobantes creados por la web (sin offline) tendrán `offline_id = NULL`.
