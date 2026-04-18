# FACTURADOR PRO-8 — Scripts de Instalación

## Estructura

```
facturador-pro/
├── install/
│   ├── linux/                    ← Servidor Linux (VPS/dedicado)
│   │   ├── install.sh            ← Instalador interactivo
│   │   └── updateSSL.sh          ← Renovar certificado SSL
│   └── windows-server/           ← Windows Server con WSL2
│       ├── 01-setup-wsl.ps1      ← Fase 1: WSL2 + Docker (PowerShell Admin)
│       ├── 02-install-prod.sh    ← Fase 2: Producción (proxy, SSL, multi-proyecto)
│       ├── 02-install-dev.sh     ← Fase 2: Desarrollo (sin proxy ni SSL)
│       └── README.md             ← Documentación detallada
├── README.MD                     ← Este archivo
└── TROUBLESHOOTING.md
```

---

## Instalación en Linux (VPS / Servidor dedicado)

```sh
cd /var/
curl -O https://raw.githubusercontent.com/gians96/codeplant/master/facturador-pro/install/linux/install.sh
chmod +x install.sh
sudo ./install.sh
```

El script pide dominio y número de servicio de forma interactiva.

Para agregar otro proyecto (multi-proyecto):

```sh
sudo ./install.sh
# Ingresar dominio y service number 2, 3, etc.
```

### Renovar SSL

```sh
cd /var/
curl -O https://raw.githubusercontent.com/gians96/codeplant/master/facturador-pro/install/linux/updateSSL.sh
chmod +x updateSSL.sh
./updateSSL.sh mi-dominio.com
```

---

## Instalación en Windows Server (WSL2)

Ver documentación completa en [`install/windows-server/README.md`](install/windows-server/README.md).

Resumen rápido:

```powershell
# Fase 1 — PowerShell como Administrador
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/gians96/codeplant/master/facturador-pro/install/windows-server/01-setup-wsl.ps1" -OutFile "01-setup-wsl.ps1"
powershell -ExecutionPolicy Bypass -File 01-setup-wsl.ps1

# Fase 2 — Dentro de WSL
wsl
curl -O https://raw.githubusercontent.com/gians96/codeplant/master/facturador-pro/install/windows-server/02-install-prod.sh
chmod +x 02-install-prod.sh
sudo ./02-install-prod.sh
```

---

## Actualización del proyecto

1) Agregar llave ssh al gitlab, que se crea al momento de instalar el sistema en el sevidor, buscar en el archivo `[proyecto].txt`

2) Ingresamos al terminal del docker que ejecuta el fpm para el servicio web.

```sh
docker exec -it $(docker ps -qf "name=fpm1_1") bash
```

3) Traemos cambios del repositorio

```sh
git pull origin [rama]
```

4) Ejecutamos los siguientes comandos, para actualizar cambios en la aplicación

```sh
composer install
php artisan migrate
php artisan tenancy:migrate
php artisan cache:clear
php artisan config:cache
chmod -R 777 vendor/mpdf/mpdf
```

## Migración de tenants - clientes (backup)
Primero realizamos el backup en el sistema, lo descargamos:
1) Creamos en el panel de admnistrador de usuarios (clientes), al momento de terminar todo el proceso de creacion del nuevo inquilino (Cliente), eliminamos y creamos otra vez en blanco la base de datos

```sh
drop DATABASE [BaseDatos];
CREATE DATABASE [BaseDatos];
```
2) Restauramos la base de datos que anteriormente le sacamos backup.

Si es local, en el ssh del servidor

```sh
mysql -u [user] -p [database_name] < [filename].sql
```

si es remoto

```sh
mysql -h [host] -u [user] -p [database_name] < [filename].sql
```

3) Aplicamos cambios al nuevo sistema, con las migraciones del inquilino:

```sh
docker exec [identificadordeldocker] composer install
docker exec [identificadordeldocker] php artisan migrate
docker exec [identificadordeldocker] php artisan tenancy:migrate
docker exec [identificadordeldocker] php artisan cache:clear
docker exec [identificadordeldocker] php artisan config:cache
docker exec [identificadordeldocker] chmod -R 777 vendor/mpdf/mpdf
```

4) Con acceso a SFTP, la carpeta `tenancy_cliente.zip`, lo descomprimimos y copiamos las carpetas a su respectiva ruta de archivos `[proyecto]/storage/app/tenancy/tenants/[inquilino]`


```sh
mv /[rutabackup]/tenancy/cdr [proyecto]/storage/app/tenancy/tenants/[inquilino]/cdr/
mv /[rutabackup]/tenancy/pdf [proyecto]/storage/app/tenancy/tenants/[inquilino]/pdf/
mv /[rutabackup]/tenancy/quotation [proyecto]/storage/app/tenancy/tenants/[inquilino]/quotation/
mv /[rutabackup]/tenancy/sale_note [proyecto]/storage/app/tenancy/tenants/[inquilino]/sale_note/
mv /[rutabackup]/tenancy/signed [proyecto]/storage/app/tenancy/tenants/[inquilino]/signed/
mv /[rutabackup]/tenancy/unsigned [proyecto]/storage/app/tenancy/tenants/[inquilino]/unsigned/
```
5) Luego tenemos que asignarles los siguientes permisos

```sh
sudo chown -R www-data:www-data [proyecto]/storage/app/tenancy/tenants/[inquilino]/cdr/
sudo chown -R www-data:www-data [proyecto]/storage/app/tenancy/tenants/[inquilino]/pdf/
sudo chown -R www-data:www-data [proyecto]/storage/app/tenancy/tenants/[inquilino]/quotation/
sudo chown -R www-data:www-data [proyecto]/storage/app/tenancy/tenants/[inquilino]/sale_note/
sudo chown -R www-data:www-data [proyecto]/storage/app/tenancy/tenants/[inquilino]/signed/
sudo chown -R www-data:www-data [proyecto]/storage/app/tenancy/tenants/[inquilino]/unsigned/
```
## Errores comunes:
1) Error de permiso
```
 Unable to retrieve the file_size for file at location: download_tray_xlsx/ventas_report_general_items_20251231140251-1.xlsx. {"userId":1,"exception":"[object] (League\Flysystem\UnableToRetrieveMetadata(code: 0): Unable to retrieve the file_size for file at location: download_tray_xlsx/ventas_report_general_items_20251231140251-1.xlsx. at /var/www/html/vendor/league/flysystem/src/UnableToRetrieveMetadata.php:49)
```
Comando para dar permiso necesario
```sh
chmod -R 777 /var/nt-suite/storage
```