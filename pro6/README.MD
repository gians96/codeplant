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

