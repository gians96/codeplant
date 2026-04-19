# 24 — Detracciones y Retención de IGV (Detalle)

> **Aplica a:** `POST /api/documents` (Facturas y Boletas)  
> **Ref código:** `DocumentTransform.php` → `detraction()`, `invoice.vue` → `changeRetention()`

---

## Descripción

Este documento detalla los campos y escenarios para detracciones (SPOT) y retención de IGV dentro de comprobantes de pago. Para la documentación base del endpoint, ver [09-boleta-factura.md](09-boleta-factura.md).

---

## 1. Detracciones (SPOT)

El **Sistema de Pago de Obligaciones Tributarias** (SPOT) obliga a detraer un porcentaje del total de la operación y depositarlo en una cuenta del Banco de la Nación del proveedor.

### ¿Cuándo aplica?

- `codigo_tipo_operacion` = `"1001"` (Operación Sujeta a Detracción)
- `codigo_tipo_operacion` = `"1004"` (Detracción - Servicios de Transporte de Carga)
- Normalmente solo para **facturas** (`"01"`), no boletas

### Catálogo de Tipos de Detracción (SUNAT Cat. 54)

| Código | Bien o Servicio | Porcentaje |
|--------|-----------------|------------|
| `001` | Azúcar y melaza de caña | 10% |
| `003` | Alcohol etílico | 10% |
| `004` | Recursos hidrobiológicos | 4% |
| `005` | Maíz amarillo duro | 4% |
| `006` | Algodón | 12% |
| `007` | Caña de azúcar | 10% |
| `008` | Madera | 4% |
| `009` | Arena y piedra | 10% |
| `010` | Residuos, desechos, etc. | 15% |
| `011` | Bienes gravados con IGV (por renuncia a exoneración) | 10% |
| `012` | Intermediación laboral | 12% |
| `014` | Carnes y despojos | 4% |
| `016` | Aceite de pescado | 10% |
| `017` | Harina de pescado | 4% |
| `019` | Arrendamiento de bienes | 10% |
| `020` | Mantenimiento y reparación | 12% |
| `021` | Movimiento de carga | 10% |
| `022` | Otros servicios empresariales | 12% |
| `023` | Leche | 4% |
| `024` | Comisión mercantil | 10% |
| `025` | Fabricación encargo | 10% |
| `026` | Servicio de transporte personas | 10% |
| `029` | Algodón en rama sin desmotar | 12% |
| `030` | Contratos construcción | 4% |
| `031` | Oro gravado con IGV | 10% |
| `032` | Páprika | 10% |
| `034` | Minerales metálicos no auríferos | 10% |
| `035` | Bienes exonerados del IGV | 1.5% |
| `036` | Oro y demás minerales | 1.5% |
| `037` | **Demás servicios gravados con IGV** | **12%** |
| `039` | Minerales no metálicos | 10% |
| `040` | Bien inmueble gravado con IGV | 4% |

> **El más común:** `"037"` — Demás servicios gravados con IGV (12%).

### Campos del bloque `detraccion` (API español)

```json
{
    "detraccion": {
        "codigo_tipo_detraccion": "037",
        "porcentaje": 12,
        "monto": 6000,
        "codigo_metodo_pago": "001",
        "cuenta_bancaria": "00-071-123456"
    }
}
```

| Campo API (español) | Campo interno (inglés) | Descripción |
|---------------------|------------------------|-------------|
| `codigo_tipo_detraccion` | `detraction_type_id` | Código del catálogo SUNAT 54 |
| `porcentaje` | `percentage` | Porcentaje de detracción |
| `monto` | `amount` | Monto calculado: `total_venta × porcentaje / 100` |
| `codigo_metodo_pago` | `payment_method_id` | `"001"` = Depósito en cuenta BN |
| `cuenta_bancaria` | `bank_account` | Nro. cuenta Banco de la Nación |

### Campos adicionales para Transporte (`1004`)

Cuando `codigo_tipo_operacion = "1004"`:

```json
{
    "detraccion": {
        "codigo_tipo_detraccion": "026",
        "porcentaje": 10,
        "monto": 5000,
        "codigo_metodo_pago": "001",
        "cuenta_bancaria": "00-071-123456",
        "detalle_viaje": "Lima a Arequipa - Carga general",
        "direccion_origen": "Av. Argentina 2458, Lima",
        "direccion_destino": "Calle San Martín 100, Arequipa",
        "ubigeo_origen": "150101",
        "ubigeo_destino": "040101",
        "valor_referencial_carga_util": 3000,
        "valor_referencial_servicio_transporte": 2000,
        "valor_referencia_carga_efectiva": 2500
    }
}
```

| Campo API (español) | Campo interno (inglés) | Descripción |
|---------------------|------------------------|-------------|
| `detalle_viaje` | `trip_detail` | Descripción del viaje |
| `direccion_origen` | `origin_address` | Dirección punto de partida |
| `direccion_destino` | `delivery_address` | Dirección punto de llegada |
| `ubigeo_origen` | `origin_location_id` | Ubigeo 6 dígitos |
| `ubigeo_destino` | `delivery_location_id` | Ubigeo 6 dígitos |
| `valor_referencial_carga_util` | `reference_value_payload` | Valor referencial carga útil |
| `valor_referencial_servicio_transporte` | `reference_value_service` | Valor referencial transporte |
| `valor_referencia_carga_efectiva` | `reference_value_effective_load` | Valor referencia carga efectiva |

### Leyendas automáticas

Al usar detracción, el backend agrega automáticamente:

```json
{
    "legends": [
        {
            "code": "2006",
            "value": "Operación sujeta a detracción"
        }
    ]
}
```

Para transporte (`1004`): `"Operación Sujeta a Detracción - Servicios de Transporte Carga"`.

---

## 2. Retención de IGV

La retención de IGV aplica cuando el **comprador es agente de retención** autorizado por SUNAT. El comprador retiene un porcentaje del IGV al momento del pago y lo deposita en SUNAT.

> **No confundir con:** El comprobante de retención (tipo `20`), que es un documento aparte. Ver [25-comprobante-retencion.md](25-comprobante-retencion.md). La retención aquí se registra **dentro** del documento (factura).

### Campos del bloque `retencion`

```json
{
    "retencion": {
        "code": "62",
        "percentage": 3,
        "amount": 3.54,
        "base": 118,
        "currency_type_id": "PEN",
        "exchange_rate": 1
    }
}
```

| Campo | Tipo | Requerido | Descripción |
|-------|------|-----------|-------------|
| `code` | string | **Sí** | `"62"` = Retención IGV (único código disponible) |
| `percentage` | float | **Sí** | Porcentaje de retención. Se toma de `config.igv_retention_percentage` (normalmente 3%) |
| `amount` | float | **Sí** | Monto de retención = `base × percentage / 100` |
| `base` | float | **Sí** | Base de retención = `total_venta` del documento |
| `currency_type_id` | string | **Sí** | `"PEN"` o `"USD"` |
| `exchange_rate` | float | No | Tipo de cambio al momento |

### Cálculo en Flutter

```dart
double base = totalVenta;
double percentage = configIgvRetentionPercentage; // ej: 3
double amount = (base * percentage / 100).roundToDouble(2);

Map<String, dynamic> retencion = {
  'code': '62',
  'percentage': percentage,
  'amount': amount,
  'base': base,
  'currency_type_id': currencyTypeId,
  'exchange_rate': exchangeRate,
};
```

### Impacto en total pendiente de pago

Cuando hay retención + condición de pago crédito (`02`/`03`):

```
total_pending_payment = total_venta - monto_retencion
```

Si la condición es contado (`01`), la retención no afecta el total a pagar directamente.

---

## 3. Ejemplo Completo — Factura con Detracción + Retención

```json
{
    "serie_documento": "F001",
    "numero_documento": "#",
    "fecha_de_emision": "2026-04-18",
    "hora_de_emision": "14:30:00",
    "codigo_tipo_operacion": "1001",
    "codigo_tipo_documento": "01",
    "codigo_tipo_moneda": "PEN",
    "fecha_de_vencimiento": "2026-05-18",
    "codigo_condicion_de_pago": "01",
    "datos_del_cliente_o_receptor": {
        "codigo_tipo_documento_identidad": "6",
        "numero_documento": "20501973522",
        "apellidos_y_nombres_o_razon_social": "EMPRESA COMPRADORA S.A.C.",
        "codigo_pais": "PE",
        "ubigeo": "150101",
        "direccion": "Av. Argentina 2458",
        "correo_electronico": "compras@empresa.com"
    },
    "detraccion": {
        "codigo_tipo_detraccion": "037",
        "porcentaje": 12,
        "monto": 1416,
        "codigo_metodo_pago": "001",
        "cuenta_bancaria": "00-071-123456"
    },
    "retencion": {
        "code": "62",
        "percentage": 3,
        "amount": 354,
        "base": 11800,
        "currency_type_id": "PEN",
        "exchange_rate": 1
    },
    "totales": {
        "total_exportacion": 0,
        "total_operaciones_gravadas": 10000,
        "total_operaciones_inafectas": 0,
        "total_operaciones_exoneradas": 0,
        "total_operaciones_gratuitas": 0,
        "total_igv": 1800,
        "total_impuestos": 1800,
        "total_valor": 10000,
        "total_venta": 11800
    },
    "items": [
        {
            "codigo_interno": "SERV001",
            "descripcion": "Servicio de consultoría",
            "unidad_de_medida": "ZZ",
            "cantidad": 1,
            "valor_unitario": 10000,
            "precio_unitario": 11800,
            "codigo_tipo_precio": "01",
            "codigo_tipo_afectacion_igv": "10",
            "total_base_igv": 10000,
            "porcentaje_igv": 18,
            "total_igv": 1800,
            "total_impuestos": 1800,
            "total_valor_item": 10000,
            "total_item": 11800
        }
    ],
    "pagos": [
        {
            "codigo_metodo_pago": "01",
            "monto": 11800
        }
    ]
}
```

---

## Notas para Offline (Flutter)

- **Detracciones:** Poco común en POS de alta rotación. Normalmente aplica a facturas de servicios. Flutter debe:
  1. Verificar si `codigo_tipo_operacion` es `1001` o `1004`
  2. Solicitar al usuario los datos de detracción (tipo, cuenta bancaria)
  3. Calcular `monto = total_venta × porcentaje / 100`
  4. Incluir bloque `detraccion{}` en el payload

- **Retención IGV:** Flutter debe:
  1. Verificar si el toggle "¿Tiene retención de IGV?" está activo
  2. Obtener `igv_retention_percentage` de la config descargada
  3. Calcular `amount = total_venta × percentage / 100`
  4. Incluir bloque `retencion{}` en el payload

- **Almacenamiento JSON:** Ambos campos (`detraction`, `retention`) se almacenan como JSON en la tabla `documents`. No están en `$fillable` de Eloquent, pero el pipeline los maneja internamente.
