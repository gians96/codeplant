# PRO 6 - COMANDOS DOCKER
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

