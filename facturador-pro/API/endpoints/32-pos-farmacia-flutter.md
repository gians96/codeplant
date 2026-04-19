# 32 — POS Farmacia Flutter (Diseño)

> Diseño funcional y flujo para la app Flutter especializada en farmacia.  
> Complementa [30-lotes-series-farmacia.md](30-lotes-series-farmacia.md).

---

## Objetivo

Proporcionar un POS offline-first optimizado para venta de medicamentos, con manejo de lotes, control de vencimientos, trazabilidad DIGEMID y flujos rápidos para el vendedor.

---

## 1. Requisitos Funcionales

### Críticos
- ✅ **Venta con selección automática de lote (FEFO)** — El operador no elige lotes manualmente a menos que lo necesite
- ✅ **Alerta de productos próximos a vencer** — Al inicio de turno y al agregar item
- ✅ **Búsqueda rápida** — Por código DIGEMID, nombre, código interno, principio activo
- ✅ **Trabajo 100% offline** — La farmacia puede estar en zonas sin conectividad estable
- ✅ **Precio regulado DIGEMID** — Mostrar precio máximo oficial junto al precio de venta

### Deseables
- ⚡ Sugerir genéricos/alternativos cuando un medicamento está agotado
- ⚡ Historial de compras del paciente (para medicamentos crónicos)
- ⚡ Receta médica: escanear/adjuntar imagen al comprobante
- ⚡ Control de venta restringida (antibióticos, controlados)

---

## 2. Arquitectura Offline

### Stack sugerido

```
┌─────────────────────────────────────────┐
│ UI Layer (Flutter Widgets)              │
├─────────────────────────────────────────┤
│ Business Logic (Riverpod / Bloc)        │
├─────────────────────────────────────────┤
│ Repository Layer                         │
│  ├─ ItemRepository                       │
│  ├─ LotRepository                        │
│  ├─ DocumentRepository                   │
│  └─ SyncRepository                       │
├─────────────────────────────────────────┤
│ Data Sources                             │
│  ├─ Local: Drift/Isar (SQLite)           │
│  └─ Remote: Dio (REST API)               │
└─────────────────────────────────────────┘
```

### Schema SQLite local (mínimo)

```sql
-- items (descargados desde /api/document/search-items)
CREATE TABLE items (
  id INTEGER PRIMARY KEY,
  internal_id TEXT,
  description TEXT,
  cod_digemid TEXT,
  sanitary TEXT,
  unit_type_id TEXT,
  sale_unit_price DECIMAL(12,4),
  lots_enabled BOOLEAN,
  series_enabled BOOLEAN,
  stock DECIMAL(12,4),
  synced_at DATETIME
);

-- item_lots_group (desde /api/offline/item-lots-group)
CREATE TABLE item_lots_group (
  id INTEGER PRIMARY KEY,
  item_id INTEGER,
  code TEXT,
  quantity DECIMAL(12,4),
  date_of_due DATE,
  synced_at DATETIME,
  FOREIGN KEY (item_id) REFERENCES items(id)
);

-- pending_documents (documentos emitidos offline)
CREATE TABLE pending_documents (
  offline_id TEXT PRIMARY KEY,
  payload JSON,
  status TEXT,  -- pending|synced|rejected
  error_message TEXT,
  created_at DATETIME,
  synced_at DATETIME
);

-- lot_compromises (stock local comprometido por docs pendientes)
CREATE TABLE lot_compromises (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  offline_id TEXT,
  lot_id INTEGER,
  quantity DECIMAL(12,4),
  FOREIGN KEY (offline_id) REFERENCES pending_documents(offline_id)
);
```

### Sincronización

| Momento | Acción |
|---------|--------|
| Login | `GET /api/offline/business-turns`, `GET /api/document/search-items`, `GET /api/offline/item-lots-group` |
| Al iniciar turno | Re-sync lotes (`/api/offline/item-lots-group`) |
| Cada 5-10 min (con red) | Enviar `pending_documents` por `POST /api/offline/sync-batch` |
| Al cerrar turno | Sync final + reporte de cierre |

---

## 3. Flujos Principales

### Flujo A — Venta rápida con FEFO automático

```
┌───────────────────────────────────────────────┐
│ 1. Pantalla POS                                │
│    [Barra búsqueda]  [Carrito]  [Cliente]      │
└───────────────────────────────────────────────┘
                    │
                    ▼
┌───────────────────────────────────────────────┐
│ 2. Buscar "paracetamol"                        │
│    Resultados filtrados por:                   │
│     - description LIKE                         │
│     - cod_digemid                              │
│     - internal_id                              │
└───────────────────────────────────────────────┘
                    │
                    ▼
┌───────────────────────────────────────────────┐
│ 3. Tap en item → Cantidad (default 1)          │
│                                                │
│    Flutter automáticamente:                    │
│    - Busca lotes disponibles ordenados FEFO    │
│    - Asigna cantidad al/los lote(s) más        │
│      próximos a vencer                         │
│    - Descuenta localmente (lot.quantity -= x)  │
│    - Genera IdLoteSelected                     │
│                                                │
│    Indicador visual: "🟡 Vence 15/12/2026"     │
└───────────────────────────────────────────────┘
                    │
                    ▼
┌───────────────────────────────────────────────┐
│ 4. Agregar más items (repite paso 2-3)         │
└───────────────────────────────────────────────┘
                    │
                    ▼
┌───────────────────────────────────────────────┐
│ 5. Cobrar:                                     │
│    - Tipo comprobante: Ticket / Boleta /       │
│      Factura / Nota de venta                   │
│    - Método de pago                            │
│    - Cliente (opcional en boleta genérica)     │
│                                                │
│    Flutter genera:                             │
│    - offline_id = UUID v4                      │
│    - numero_documento = # (backend asigna)     │
│    - Payload completo con items + lotes        │
└───────────────────────────────────────────────┘
                    │
                    ▼
┌───────────────────────────────────────────────┐
│ 6. Imprimir ticket local + guardar pendiente   │
│    Sync en background cuando hay red           │
└───────────────────────────────────────────────┘
```

### Flujo B — Selección manual de lote

Cuando el operador necesita elegir un lote específico (ej: cliente pide un lote puntual):

```
1. Agregar item → tap en el icono 📦 "Lotes"
2. Modal con lista de lotes:
   ┌──────────────────────────────────────┐
   │ LOT-2026-001  Stock: 50   🟢 Vence 06/2027
   │ LOT-2026-002  Stock: 30   🟡 Vence 12/2026
   │ LOT-2026-003  Stock: 20   🔴 Vence 06/2026
   └──────────────────────────────────────┘
3. Tap en lote → agrega con ese lot_id
```

### Flujo C — Alerta de próximos a vencer

Al iniciar el turno y cada hora:

```
┌───────────────────────────────────────────────┐
│ 🔔 Productos próximos a vencer                 │
│                                                │
│  🔴 Paracetamol 500mg (LOT-001) — Vence en     │
│     15 días — Stock: 20                        │
│  🟡 Ibuprofeno 400mg (LOT-005) — Vence en      │
│     60 días — Stock: 100                       │
│                                                │
│  [Ver todos]  [Aplicar descuento liquidación] │
└───────────────────────────────────────────────┘
```

Códigos de color:
- 🔴 Rojo: < 30 días
- 🟡 Amarillo: 30-90 días
- 🟢 Verde: > 90 días

### Flujo D — Sincronización

```dart
// Cada 5 min (si hay conexión)
Timer.periodic(Duration(minutes: 5), (_) async {
    if (!await hasConnection()) return;
    
    final pending = await db.getPendingDocuments();
    if (pending.isEmpty) return;
    
    // Enviar en batch (ver 19-sincronizacion-batch.md)
    final response = await api.post('/api/offline/sync-batch', {
        'documents': pending.map((d) => d.payload).toList()
    });
    
    for (final result in response['data']['results']) {
        if (result['success']) {
            await db.markAsSynced(result['offline_id'], result['document_id']);
        } else {
            await db.markAsRejected(result['offline_id'], result['error']);
            notifyOperator('Error en doc ${result['offline_id']}: ${result['error']}');
        }
    }
    
    // Re-sync lotes para reflejar cambios del servidor
    await syncLots();
});
```

---

## 4. Componentes UI clave

### Componente: `ItemCard`

```
┌────────────────────────────────────────────┐
│ Paracetamol 500mg x 10 tab                 │
│ DIGEMID: E1234567   Cod: MED-001           │
│                                            │
│ Stock: 250  •  3 lotes                     │
│ 🟡 Lote próx: LOT-002 (vence 12/2026)      │
│                                            │
│ S/. 5.00  [Max DIGEMID: S/. 6.50]          │
│                                            │
│                            [AGREGAR +]     │
└────────────────────────────────────────────┘
```

### Componente: `CartItem`

```
┌────────────────────────────────────────────┐
│ Paracetamol 500mg x 10 tab          [🗑]   │
│ 📦 LOT-002 × 3                             │
│                                            │
│ [-] 3 [+]          S/. 15.00               │
└────────────────────────────────────────────┘
```

### Pantalla principal (layout)

```
┌───────────────────────────────────────────────┐
│ ⚡ Farmacia POS      🔔 3    👤 Usuario    ≡  │
├───────────────────────────────────────────────┤
│ 🔍 Buscar producto...                         │
├────────────────────┬──────────────────────────┤
│                    │                          │
│   Lista items      │   Carrito                │
│   filtrados        │                          │
│                    │   - Item 1 × 2           │
│   [ItemCard]       │   - Item 2 × 1           │
│   [ItemCard]       │                          │
│   [ItemCard]       │   Subtotal: 25.00        │
│                    │   IGV:       4.50        │
│                    │   TOTAL:    29.50        │
│                    │                          │
│                    │   [  COBRAR  ]           │
└────────────────────┴──────────────────────────┘
```

---

## 5. Endpoints usados por POS Farmacia

| Endpoint | Uso | Frecuencia |
|----------|-----|------------|
| `POST /api/login` | Autenticación | 1 vez (sesión larga) |
| `GET /api/offline/business-turns` | Config + catálogos hotel | Login |
| `GET /api/document/search-items` | Descargar catálogo items | Login + bajo demanda |
| `GET /api/offline/item-lots-group` | Descargar lotes | Login + cada turno |
| `GET /api/offline/stock` | Stock actualizado | Cada turno |
| `GET /api/offline/series-numbering` | Series y correlativos | Login |
| `POST /api/offline/sync-batch` | Enviar batch de docs | Cada 5 min |
| `POST /api/document/search-customers` | Buscar clientes | On-demand |
| `GET /api/offline/plates/{id}` | (Si además es grifo) | On-demand |

---

## 6. Validaciones antes de emitir

```dart
bool validateSale() {
    // 1. Carrito no vacío
    if (cart.isEmpty) return error('Carrito vacío');
    
    // 2. Cada item con lotes asignados
    for (final cartItem in cart) {
        if (cartItem.item.lotsEnabled) {
            final total = cartItem.lotSelection
                .fold<double>(0, (sum, l) => sum + l.quantity);
            if (total != cartItem.quantity) {
                return error('Falta asignar lotes en ${cartItem.item.description}');
            }
        }
    }
    
    // 3. Cliente válido según tipo de comprobante
    if (docType == '01' && customer.idType != '6') {
        return error('Factura requiere RUC');
    }
    
    // 4. Método de pago seleccionado
    if (paymentMethod == null) return error('Seleccione método de pago');
    
    return ok();
}
```

---

## 7. Manejo de errores específicos farmacia

| Error backend | Mensaje Flutter | Acción |
|---------------|-----------------|--------|
| "El lote X no tiene suficiente stock" | "Stock del lote insuficiente. Re-sincronizando..." | Re-sync lotes y recalcular FEFO |
| "El producto X no tiene lotes disponibles" | "Producto agotado" | Marcar item como no vendible localmente |
| Item `lots_enabled=true` pero `IdLoteSelected` vacío | (Validación local) | Forzar selección antes de cobrar |
| Registro sanitario vencido | (Alerta visual) | Permitir venta pero mostrar warning |

---

## 8. Configuración recomendada

```json
{
    "fefo_automatic": true,
    "expiration_warning_days": 90,
    "expiration_critical_days": 30,
    "show_digemid_max_price": true,
    "allow_sale_below_digemid": true,
    "print_receipt_on_emit": true,
    "sync_interval_minutes": 5,
    "auto_sync_on_connection": true,
    "require_customer_for_antibiotics": true
}
```

Guardar en `SharedPreferences`. Modificable desde un panel de configuración del admin.

---

## 9. KPIs sugeridos para dashboard

- Stock vencido: cantidad y valor
- Top 10 productos próximos a vencer
- Ventas por operador + propina (si además es restaurant/bar)
- Rotación por lote (FEFO vs FIFO)
- Productos con ruptura de stock (0 unidades)
- Alertas de registro sanitario vencido

Estos KPIs requieren llamadas a endpoints de reportes, no están cubiertos por el offline.

---

## 10. Checklist de implementación

- [ ] Login + descarga giros → detectar `is_pharmacy=true`
- [ ] Descargar items + lotes
- [ ] Pantalla POS con búsqueda
- [ ] ItemCard con info DIGEMID
- [ ] FEFO automático al agregar
- [ ] Modal de selección manual de lote
- [ ] Alertas de vencimiento
- [ ] Validación previa a emisión
- [ ] Emisión offline con `offline_id`
- [ ] Impresión ticket local
- [ ] Sync batch automático
- [ ] Manejo de errores y reintentos
- [ ] Cierre de turno con reporte
- [ ] Modo grifo+farmacia combinado (minimarket)
