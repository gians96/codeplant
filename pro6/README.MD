# PRO 6 - COMANDOS DOCKER - (ubuntu 20.04)
## Instalar el PRO 6 (docker)
Necesitamos el script que se encuentra dentro de la carpeta, llamada `install.sh`, lo copiamos y guardamos en el vps en lo siguiente:
Creamos el archivo
```sh
cd /var/
curl -O https://raw.githubusercontent.com/gians96/codeplant/master/pro6/install.sh
chmod +x install.sh

```
Aqui editamos el nombre de dominio, y ejecutamos.

```sh
./install.sh nt-suite.pro

```

Para agregar otro proyecto con otro subdominio agregar los siguientes parametros, el 2 significa que es el numero de proyecto, y el 3307 es el puerto de la base de datos.

```sh
./install.sh nt-suite.pro 2 3307

```


## Actualizar SSL (docker)
Necesitamos el script que se encuentra dentro de la carpeta, llamada `updateSSL.sh`, lo copiamos y guardamos en el vps en lo siguiente:
Creamos el archivo
```sh
cd /var/
curl -O https://github.com/gians96/codeplant/blob/master/pro6/updateSSL.sh
chmod +x updateSSL.sh
```
Aqui editamos el nombre de dominio, y ejecutamos.

```sh
./updateSSL.sh nt-suite.pro
```

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