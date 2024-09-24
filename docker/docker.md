
sudo apt update

sudo apt install apt-transport-https ca-certificates curl software-properties-common

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update

apt-cache policy docker-ce

sudo apt install docker-ce

sudo systemctl status docker

## Para permitir que tu usuario ejecute comandos Docker sin necesidad de usar sudo, añade tu usuario al grupo docker:

sudo usermod -aG docker $USER

## Reinicia tu sesión de usuario o ejecuta el siguiente comando para aplicar los cambios:
su - $USER

# Docker images
# Crea la imagen
docker build -t docker-scrapping .

## Listar imagenes

docker images

## Eliminar 
docker rmi nombre_de_la_imagen_o_ID
docker rmi -f nombre_de_la_imagen_o_ID

# Manejo de contenedores
## Muestra todos los contenedores
docker ps -a

## Muestra los contenedores activos
docker ps



## Crea el contenedor y se ejecuta con parametros de variables de entorno, el docker-scrapping es el nombre de la imagen
docker run --name scrapping_undc -e host_undc='112' -e user_undc='asd' -e password_undc='asd' -e database_undc='asd' docker-scrapping 

## Stop, start de conetendores
docker stop scrapping_undc
docker start scrapping_undc

## eliminar contenedor
docker rm scrapping_undc
docker rm -f scrapping_undc

# UNINSTALL DOCKER
dpkg -l | grep -i docker

sudo apt-get purge -y docker-engine docker docker.io docker-ce docker-ce-cli docker-compose-plugin
sudo apt-get autoremove -y --purge docker-engine docker docker.io docker-ce docker-compose-plugin

sudo rm -rf /var/lib/docker /etc/docker
sudo rm /etc/apparmor.d/docker
sudo groupdel docker
sudo rm -rf /var/run/docker.sock
sudo rm -rf /var/lib/containerd

