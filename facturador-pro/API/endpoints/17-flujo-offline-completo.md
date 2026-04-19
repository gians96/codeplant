# 17 — Flujo Offline Completo (End-to-End)

> Guía paso a paso del ciclo de vida completo de la app Flutter en modo offline.

---

## Fase 1: Descarga Inicial (requiere internet)

```
┌─────────────────────────────────────────────────┐
│  1. LOGIN                                       │
│  POST /api/login                                │
│  → token, establishment_id, sellerId            │
│  → Guardar en SharedPreferences                 │
│                                                 │
│  2. DESCARGA DE DATOS BASE                      │
│  GET /api/company → series, clientes, pagos     │
│  GET /api/sellnow/items → catálogo productos    │
│  GET /api/sellnow/categories → categorías       │
│  GET /api/pro8/catalogs/ubigeo → ubigeo         │
│  GET /api/restaurant/available-sellers           │
│  → Guardar todo en SQLite local                 │
│                                                 │
│  3. SERIES CON NUMERACIÓN                       │
│  GET /api/offline/series-numbering              │
│  → series + last_number                         │
│  → Guardar en SQLite                            │
│                                                 │
│  4. VERIFICAR / ABRIR CAJA                      │
│  GET /api/cash/opening_cash                     │
│  → Si no hay caja: POST /api/cash/open          │
│  → Guardar cash_id en SharedPreferences         │
└─────────────────────────────────────────────────┘
```

**Tabla SQLite local sugerida:**

| Tabla | Datos | Fuente |
|-------|-------|--------|
| `items` | Productos con stock y precios | `/api/sellnow/items` |
| `categories` | Categorías de productos | `/api/sellnow/categories` |
| `customers` | Clientes | `/api/company` → customers |
| `series` | Series con last_number | `/api/offline/series-numbering` |
| `payment_methods` | Métodos de pago | `/api/company` → payment_method_types |
| `ubigeo` | Departamentos/provincias/distritos | `/api/pro8/catalogs/ubigeo` |
| `sellers` | Vendedores | `/api/restaurant/available-sellers` |
| `offline_queue` | Comprobantes pendientes de sync | Generados localmente |
| `config` | Token, establishment_id, sellerId, cash_id | Login + apertura caja |

---

## Fase 2: Operación Offline (sin internet)

### Crear Nota de Venta

```
1. Seleccionar cliente (de SQLite) o crear nuevo manualmente
2. Agregar items del catálogo local
3. Calcular impuestos localmente (ver fórmulas en 09-boleta-factura.md)
4. Seleccionar método de pago
5. Generar:
   - offline_id = UUID v4 (uuid package)
   - serie = de series locales (doc_type "80")
   - number = last_number + 1 → actualizar last_number en SQLite
6. Guardar en tabla offline_queue:
   {
     offline_id: "uuid",
     doc_type: "80",
     cash_id: local_cash_id,
     status: "pending",
     data: { ...payload completo... },
     created_at: "2026-04-18T14:30:00"
   }
7. Mostrar comprobante al usuario (impresión local si tiene impresora BT)
```

### Crear Boleta / Factura

```
Mismo flujo que Nota de Venta, con:
- doc_type: "03" o "01"
- Payload en formato español (DocumentTransform)
- Para factura: cliente debe tener RUC
- number = last_number + 1 de la serie correspondiente
```

### Crear NC / ND

```
- Solo si el documento original YA fue sincronizado y tiene external_id
- doc_type: "07" o "08"
- Incluir documento_afectado.external_id
- Si el original NO fue sincronizado → no permitir crear NC/ND (mostrar mensaje)
```

### Crear Guía de Remisión

```
- doc_type: "09" o "31"
- Usar ubigeo local para direcciones
- number = last_number + 1 de la serie T001 / V001
```

---

## Fase 3: Sincronización (al recuperar internet)

```
┌────────────────────────────────────────────────────────┐
│  DETECCIÓN DE CONECTIVIDAD                             │
│  connectivity_plus package → onConnectivityChanged     │
│                                                        │
│  1. OBTENER PENDIENTES                                 │
│  SELECT * FROM offline_queue                           │
│  WHERE status = 'pending'                              │
│  ORDER BY created_at ASC                               │
│                                                        │
│  2. ORDENAR POR PRIORIDAD                              │
│  a. Notas de Venta (80)          ← sin dependencias   │
│  b. Boletas/Facturas (01/03)     ← sin dependencias   │
│  c. NC/ND (07/08)                ← dependen de b      │
│  d. Guías (09/31)                ← independientes      │
│                                                        │
│  3. ENVIAR BATCH                                       │
│  POST /api/offline/sync-batch                          │
│  body: { sales: [...primeros 50 pendientes...] }       │
│                                                        │
│  4. PROCESAR RESPUESTA                                 │
│  Para cada result:                                     │
│    success=true  → UPDATE status='synced',             │
│                    guardar external_id, number          │
│    was_duplicate → UPDATE status='synced'              │
│    success=false → UPDATE status='error',              │
│                    guardar error_message                │
│                                                        │
│  5. SI HAY NC/ND PENDIENTES                            │
│  → Ahora los documentos originales tienen external_id  │
│  → Actualizar documento_afectado.external_id           │
│  → Enviar siguiente batch con NC/ND                    │
│                                                        │
│  6. REPETIR hasta que offline_queue esté vacía         │
└────────────────────────────────────────────────────────┘
```

---

## Fase 4: Post-Sincronización

```
1. ACTUALIZAR SERIES
   GET /api/offline/series-numbering
   → Actualizar last_number en SQLite (el backend puede haber avanzado)

2. ACTUALIZAR STOCK (opcional)
   GET /api/sellnow/items
   → Refrescar stock local

3. CIERRE DE CAJA (cuando el usuario lo decida)
   → Verificar que offline_queue está vacía
   → GET /api/cash/close/{cash_id}
```

---

## Diagrama de Estados del Comprobante Offline

```
                    ┌──────────┐
                    │ CREADO   │  (offline, en SQLite)
                    │ pending  │
                    └────┬─────┘
                         │
                    ┌────▼─────┐
                    │ ENVIANDO │  (en sync-batch)
                    │ syncing  │
                    └────┬─────┘
                         │
              ┌──────────┼──────────┐
              │          │          │
         ┌────▼────┐ ┌──▼───┐ ┌───▼────┐
         │ SYNCED  │ │DUPLIC│ │ ERROR  │
         │ synced  │ │synced│ │ error  │
         └─────────┘ └──────┘ └───┬────┘
                                  │
                             ┌────▼────┐
                             │ RETRY?  │
                             │ pending │  (reintentar con backoff)
                             └─────────┘
```

---

## Manejo de Conflictos de Numeración

### Escenario: Dos dispositivos del mismo vendedor

No debería ocurrir si cada vendedor tiene su propia serie asignada. Pero si ocurre:

1. Dispositivo A crea `B001-90` offline
2. Dispositivo B crea `B001-90` online (mientras A está sin internet)
3. Dispositivo A sincroniza:
   - Backend intenta crear `B001-90` → Error 1062 (duplicate filename)
   - `findExistingDocumentFromError()` busca `B001-90` existente
   - Compara: si los datos coinciden → retorna como éxito
   - Si no coinciden → error (el vendedor debe revisar)

### Prevención

- **Asignar series únicas por vendedor** (Vendedor A = B001, Vendedor B = B002)
- **No compartir series entre dispositivos** del mismo vendedor
- Usar `numero_documento` con el número local calculado (no `"#"`)

---

## Checklist de Implementación Flutter

- [ ] SQLite schema con tablas: items, customers, series, payment_methods, ubigeo, sellers, offline_queue, config
- [ ] Generación de UUID v4 para offline_id
- [ ] Auto-incremento local de numeración por serie
- [ ] Cálculo de impuestos (IGV 18%, exonerado, inafecto)
- [ ] Detección de conectividad (connectivity_plus)
- [ ] Sync queue con priorización por tipo de documento
- [ ] Retry con exponential backoff (1s, 2s, 4s, 8s, 16s)
- [ ] Manejo de `was_duplicate` como éxito
- [ ] Actualización de external_id para NC/ND pendientes
- [ ] Impresión local (Bluetooth/WiFi printer)
- [ ] Refresco de series/stock post-sync
