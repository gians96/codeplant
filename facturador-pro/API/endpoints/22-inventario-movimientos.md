# 22 — Inventario: Movimientos de Stock

> `POST /api/inventory/transaction`  
> **Auth:** `Bearer {token}`

---

## Descripción

Endpoint para registrar movimientos de inventario (ingresos y salidas) independientes de ventas. Las ventas descuentan stock automáticamente (ver [23-stock-por-establecimiento.md](23-stock-por-establecimiento.md)). Este endpoint es para ajustes manuales: recepciones de mercadería, mermas, transferencias, etc.

---

## 1. Ingreso de Stock

```
POST /api/inventory/transaction
Authorization: Bearer {token}
Content-Type: application/json
```

### Payload

```json
{
    "type": "input",
    "inventory_transaction_id": "03",
    "item_code": "PROD001",
    "quantity": 100,
    "warehouse_id": 1
}
```

### Campos

| Campo | Tipo | Requerido | Descripción |
|-------|------|-----------|-------------|
| `type` | string | **Sí** | `"input"` = Ingreso |
| `inventory_transaction_id` | string | **Sí** | Código del tipo de transacción (ver tabla abajo) |
| `item_code` | string | **Sí** | `internal_id` del producto |
| `quantity` | float | **Sí** | Cantidad a ingresar |
| `warehouse_id` | int | **Sí** | ID del almacén destino |

### Response (200 OK)

```json
{
    "succes": true,
    "message": "Ingreso registrado correctamente"
}
```

> **Nota:** La API retorna `succes` (sin doble `s`) en la respuesta real. Es un typo del backend.

---

## 2. Salida de Stock

```
POST /api/inventory/transaction
Authorization: Bearer {token}
Content-Type: application/json
```

### Payload

```json
{
    "type": "output",
    "inventory_transaction_id": "03",
    "item_code": "PROD001",
    "quantity": 3,
    "warehouse_id": 1
}
```

### Campos

| Campo | Tipo | Requerido | Descripción |
|-------|------|-----------|-------------|
| `type` | string | **Sí** | `"output"` = Salida |
| `inventory_transaction_id` | string | **Sí** | Código del tipo de transacción |
| `item_code` | string | **Sí** | `internal_id` del producto |
| `quantity` | float | **Sí** | Cantidad a retirar |
| `warehouse_id` | int | **Sí** | ID del almacén origen |

### Response (200 OK)

```json
{
    "succes": true,
    "message": "Salida registrada correctamente"
}
```

---

## Tipos de Transacción de Inventario

### Ingresos (`type: "input"`)

| Código | Descripción |
|--------|-------------|
| `02` | Compra Nacional |
| `03` | Producción |
| `05` | Transferencia entre almacenes |
| `07` | Devolución |
| `09` | Inventario inicial |
| `99` | Otros |

### Salidas (`type: "output"`)

| Código | Descripción |
|--------|-------------|
| `01` | Venta |
| `03` | Consumo interno |
| `05` | Transferencia entre almacenes |
| `07` | Merma / Desmedro |
| `99` | Otros |

---

## Notas para Offline

- **Las ventas NO requieren este endpoint.** Al emitir un comprobante (boleta/factura/nota de venta), el stock se descuenta automáticamente via Model Events del backend. Ver [23-stock-por-establecimiento.md](23-stock-por-establecimiento.md).
- **Este endpoint es para ajustes manuales:** recepción de mercadería, mermas, transferencias entre almacenes.
- **Para Flutter offline:** Se puede registrar un movimiento de inventario al sincronizar, pero es un caso poco común en operación POS. Los movimientos de inventario normalmente se hacen desde la web.
- **`item_code` = `internal_id`:** Usar el código interno del producto, no el ID numérico.
- **`warehouse_id`:** Obtenerlo de la descarga de datos de empresa → `establishments[].warehouse.id`.
