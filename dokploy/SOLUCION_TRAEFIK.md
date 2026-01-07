# Solución: Traefik no está corriendo en Dokploy

## Problema Identificado

El contenedor `dokploy-traefik` no estaba en ejecución, causando errores en los logs de Dokploy:

```
Error during log cleanup: Error [ExecError]: Command execution failed: Command failed: docker exec dokploy-traefik kill -USR1 1
Error response from daemon: container 89abde4638fb06b2f97d909620b814169df2a7fefe7d5e1060d9f7fa1f091674 is not running
```

## Diagnóstico

1. **Contenedor inexistente**: El contenedor `dokploy-traefik` no existía en el sistema
   ```bash
   docker ps -a | grep traefik  # No retornó resultados
   ```

2. **No es un servicio de Docker Swarm**: A diferencia de otros componentes, Traefik se ejecuta como un contenedor standalone (no como servicio)

3. **Configuración encontrada**: La configuración de Traefik estaba intacta en `/etc/dokploy/traefik/traefik.yml`

## Solución Implementada

### Paso 1: Eliminar servicios no deseados
```bash
docker service rm estudiantes-deivis-2qfd1m estudiantes-frontend-clinica-io5f4e
```

### Paso 2: Descargar imagen de Traefik v3.0
```bash
docker pull traefik:v3.0
```

**Nota importante**: Se requiere Traefik v3.0 porque la configuración usa el provider `swarm`, que solo está disponible desde Traefik v3.x

### Paso 3: Crear el contenedor de Traefik
```bash
docker run -d \
  --name dokploy-traefik \
  --restart unless-stopped \
  --network dokploy-network \
  -p 80:80 \
  -p 443:443 \
  -p 8080:8080 \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  -v /etc/dokploy/traefik:/etc/dokploy/traefik \
  traefik:v3.0 \
  --configFile=/etc/dokploy/traefik/traefik.yml
```

### Paso 4: Reiniciar servicio de Dokploy
```bash
docker service update --force dokploy
```

## Resultado

Traefik ahora está operativo en:
- **Puerto 80**: HTTP
- **Puerto 443**: HTTPS
- **Puerto 8080**: Dashboard/API de Traefik

```bash
docker ps | grep traefik
# da7a57331462   traefik:v3.0   Up   0.0.0.0:80->80/tcp, 0.0.0.0:443->443/tcp, 0.0.0.0:8080->8080/tcp   dokploy-traefik
```

## Configuración de Traefik

La configuración se encuentra en `/etc/dokploy/traefik/traefik.yml`:

```yaml
providers:
  swarm:
    exposedByDefault: false
    watch: true
  docker:
    exposedByDefault: false
    watch: true
    network: dokploy-network
  file:
    directory: /etc/dokploy/traefik/dynamic
    watch: true

entryPoints:
  web:
    address: ':80'
  websecure:
    address: ':443'
    http3:
      advertisedPort: 443
    http:
      tls:
        certResolver: letsencrypt

api:
  insecure: true

certificatesResolvers:
  letsencrypt:
    acme:
      email: soportesistemas@undc.edu.pe
      storage: /etc/dokploy/traefik/dynamic/acme.json
      httpChallenge:
        entryPoint: web

accessLog:
  filePath: /etc/dokploy/traefik/dynamic/access.log
  format: json
  bufferingSize: 100
```

## Verificación

Para verificar que Traefik funciona correctamente:

```bash
# Ver logs de Traefik
docker logs dokploy-traefik --tail 50

# Verificar que responde
curl -I localhost:80

# Ver estado en el dashboard
curl -s localhost:8080/api/overview

# Ver todos los contenedores activos
docker ps | grep -E "(traefik|dokploy)"
```

## Notas Adicionales

- **Persistencia**: El contenedor tiene `--restart unless-stopped` para reiniciarse automáticamente
- **Permisos**: El socket de Docker está montado en modo solo lectura (`ro`) por seguridad
- **Red**: Usa la red `dokploy-network` para comunicarse con otros servicios
- **Versión crítica**: Debe ser Traefik v3.0+ para soportar Docker Swarm provider

## Si el problema se repite

Si Traefik se detiene nuevamente, ejecutar:

```bash
# Verificar si existe pero está detenido
docker ps -a | grep traefik

# Reiniciar el contenedor existente
docker start dokploy-traefik

# Si no existe, recrear con el comando del Paso 3
```

---

**Fecha de solución**: 5 de enero de 2026  
**Versión de Dokploy**: v0.26.3  
**Versión de Traefik**: v3.0
