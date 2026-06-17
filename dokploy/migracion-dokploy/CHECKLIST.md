# Checklist del día de migración

## Antes (días previos, sin downtime)
- [ ] Preguntar a Elastika si **reasignan la IP `161.132.53.113`** o tienen IP flotante.
- [ ] Si NO conservas IP: **bajar TTL de DNS a 300s** (1-2 días antes).
- [ ] Contratar GEN2 con **Ubuntu 24.04** y disco ≥ 100 GB.
- [ ] Subir scripts a ambos servidores (`scp 0*.sh undc@IP:~/` y `chmod +x ~/0*.sh`).
- [ ] **GEN2:** ejecutar `02-instalar-dokploy-EN-GEN2.sh` y confirmar que carga la UI. No configurar nada.
- [ ] **GEN1:** ejecutar `01-backup-db-EN-GEN1.sh` y copiar `~/dumps-migracion.tar.gz` a lugar seguro.

## Día D (ventana de madrugada — downtime)
- [ ] **GEN1:** `03-detener-EN-GEN1.sh`  ⟶ empieza el downtime.
- [ ] **GEN2:** `04-transferir-EN-GEN2.sh`  ⟶ esperar a que termine el rsync (~8 GB).
- [ ] **GEN2:** `05-arrancar-EN-GEN2.sh`.
- [ ] **GEN2:** entrar a `http://IP_GEN2:3000` y verificar que aparecen todos los proyectos.
- [ ] **GEN2 (UI):** Redeploy de cada app — orden: **BD → backends → frontends**.
- [ ] **DNS:** si IP nueva, apuntar registros A a la IP del GEN2.
- [ ] **GEN2:** `06-verificar-EN-GEN2.sh` y completar el checklist final.

## Después (validado)
- [ ] Probar cada dominio por HTTPS.
- [ ] Verificar datos en cada BD.
- [ ] Mantener GEN1 encendido 3-7 días como respaldo (vence **22/07/2026**).
- [ ] Cancelar GEN1 cuando todo esté OK.
- [ ] 🔒 Rotar contraseña SSH de `undc`.
- [ ] 🔒 Cerrar puertos de BD públicos con firewall.

## Plan B (si algo falla)
- Un volumen de BD no levanta → restaurar desde `~/dumps-migracion/` (los `.sql` del paso 01).
- La migración entera falla → GEN1 sigue intacto; vuelve a escalarlo: `docker service scale <svc>=1` y reapunta DNS a GEN1.

## Tiempos estimados
- Transferencia ~8 GB: 10-40 min según ancho de banda entre datacenters.
- Redeploy de 50 apps: 30-90 min (según builds).
- **Ventana total recomendada: 2-3 horas.**
