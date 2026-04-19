# 27 — Contingencia

> **Aplica a:** `POST /api/documents` (Facturas y Boletas)  
> **Series:** `0001`, `0F01`, etc. (prefijo `0`)

---

## Descripción

Los comprobantes de contingencia son documentos electrónicos que se emiten cuando existe una interrupción del servicio (caída de SUNAT, sin internet prolongado, fallas de sistema). SUNAT los acepta como válidos siempre que:

1. Las series estén registradas como series de contingencia
2. Se envíen a SUNAT dentro del plazo permitido (7 días calendario)
3. Se declare el motivo de contingencia

---

## Requisito Previo: Series de Contingencia

Las series de contingencia deben registrarse previamente en la web:

**Ruta:** Administración → Usuarios/Locales & Series → Establecimientos → Series

Las series de contingencia **empiezan con `0`**:

| Tipo documento | Serie regular | Serie contingencia |
|----------------|---------------|--------------------|
| Factura (01) | F001, F002 | 0001, 0F01 |
| Boleta (03) | B001, B002 | 0001, 0B01 |

> **Para Flutter:** Las series de contingencia se obtienen de `GET /api/offline/series-numbering`. Se identifican porque su código empieza con `0` (cero).

---

## Payload de Factura de Contingencia

El payload es **idéntico** al de una factura normal (ver [09-boleta-factura.md](09-boleta-factura.md)), solo cambia la `serie_documento`:

```json
{
    "serie_documento": "0001",
    "numero_documento": "#",
    "fecha_de_emision": "2026-04-18",
    "hora_de_emision": "14:30:00",
    "codigo_tipo_operacion": "0101",
    "codigo_tipo_documento": "01",
    "codigo_tipo_moneda": "PEN",
    "datos_del_cliente_o_receptor": {
        "codigo_tipo_documento_identidad": "6",
        "numero_documento": "20501973522",
        "apellidos_y_nombres_o_razon_social": "EMPRESA XYZ S.A.C.",
        "codigo_pais": "PE",
        "ubigeo": "150101",
        "direccion": "Av. Argentina 2458"
    },
    "totales": {
        "total_operaciones_gravadas": 100,
        "total_igv": 18,
        "total_impuestos": 18,
        "total_valor": 100,
        "total_venta": 118
    },
    "items": [
        {
            "codigo_interno": "P0121",
            "descripcion": "Inca Kola 250 ml",
            "unidad_de_medida": "NIU",
            "cantidad": 2,
            "valor_unitario": 50,
            "precio_unitario": 59,
            "codigo_tipo_precio": "01",
            "codigo_tipo_afectacion_igv": "10",
            "total_base_igv": 100,
            "porcentaje_igv": 18,
            "total_igv": 18,
            "total_impuestos": 18,
            "total_valor_item": 100,
            "total_item": 118
        }
    ],
    "pagos": [
        {
            "codigo_metodo_pago": "01",
            "monto": 118
        }
    ]
}
```

### Diferencias con documento normal

| Aspecto | Normal | Contingencia |
|---------|--------|--------------|
| `serie_documento` | `"F001"`, `"B001"` | `"0001"`, `"0F01"` |
| Envío a SUNAT | Inmediato | Diferido (se puede enviar después) |
| Plazo de envío | Al momento | 7 días calendario |
| Numeración | Backend auto-numera (`"#"`) | Backend auto-numera (`"#"`) |

---

## Flujo de Contingencia desde Flutter

### Detección de contingencia

```
┌──────────────────────────────────────────┐
│ Flutter detecta que NO hay internet       │
│ y el servidor NO es accesible             │
│                                           │
│ → Modo offline puro (SQLite local)        │
│ → Usar series de contingencia (0xxx)      │
│   para SUNAT                              │
│ → O usar series normales con              │
│   acciones.enviar_xml_firmado: false      │
└──────────────────────────────────────────┘
```

### Cuándo usar contingencia vs envío diferido

| Escenario | Solución | Serie | acciones |
|-----------|----------|-------|----------|
| Sin internet, sin acceso al servidor | **Contingencia** | `0001` | No aplica (va a SQLite local) |
| Con acceso al servidor pero servidor sin internet | **Envío diferido** | `F001` | `enviar_xml_firmado: false` |
| Con internet pero SUNAT caído | **Contingencia** o envío diferido | `0001` o `F001` | Opcional |

### Flujo completo

```
1. Flutter sin conexión:
   → Guardar comprobante en SQLite local
   → Usar serie_documento: "0001" (contingencia)
   → Asignar numero_documento local (ej: "90")
   → Asignar offline_id (UUID local)

2. Cuando hay conexión:
   → POST /api/offline/sync-batch
   → El batch envía con serie "0001"
   → Backend crea el documento con serie de contingencia
   → Backend envía a SUNAT automáticamente
   → Si SUNAT rechaza por fecha, retorna error individual

3. Si SUNAT rechaza:
   → El comprobante se marca con state_type_id: "09"
   → Flutter almacena para retry o intervención manual
```

---

## Boleta de Contingencia

Mismo concepto que factura, pero con `codigo_tipo_documento: "03"`:

```json
{
    "serie_documento": "0001",
    "numero_documento": "#",
    "codigo_tipo_operacion": "0101",
    "codigo_tipo_documento": "03",
    "codigo_tipo_moneda": "PEN",
    "datos_del_cliente_o_receptor": {
        "codigo_tipo_documento_identidad": "1",
        "numero_documento": "12345678",
        "apellidos_y_nombres_o_razon_social": "CLIENTE NATURAL"
    },
    "...": "resto del payload idéntico a boleta normal"
}
```

> **Boletas de contingencia:** Comparten la misma serie que las facturas de contingencia si la serie es genérica (`0001`). Si se quieren series separadas, registrar `0F01` para facturas y `0B01` para boletas.

---

## Notas para Offline (Flutter)

- **Detección de contingencia:** Flutter debe implementar lógica para detectar cuándo usar serie de contingencia:
  1. Sin internet → contingencia
  2. Con internet pero SUNAT caído → contingencia (el servidor puede informar este estado)
  3. Con internet y SUNAT ok → serie normal

- **Selección de serie:** Al abrir la pantalla de emisión, si el modo es contingencia, filtrar las series disponibles para mostrar solo las que empiezan con `0`.

- **Numeración offline:** En modo contingencia + offline, Flutter asigna el `numero_documento` localmente (obtener el siguiente de `series-numbering` al inicio del turno, luego incrementar localmente). Al sincronizar, si hay conflicto de numeración, `sync-batch` maneja el error.

- **Plazo SUNAT:** Los comprobantes de contingencia deben enviarse a SUNAT dentro de 7 días calendario. Flutter puede mostrar alertas si hay documentos pendientes de contingencia que se acercan al plazo.

- **No confundir con envío diferido:** Contingencia es una serie especial reconocida por SUNAT. Envío diferido (`acciones.enviar_xml_firmado: false`) es una funcionalidad del sistema que genera el XML sin enviarlo. Pueden combinarse: usar serie de contingencia + envío diferido.
