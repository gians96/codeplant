### para iniciar un proyecto typescript debemos instalar en modo global o en modo dev este comando

npm i typescript  -g || -D (dependencia de desarrollo)
npm i ts-node -g
## Nodemon para que se reinicie de manera autmatica al momento de realizar cambioas

npm i nodemon -g || -D (dependencia de desarrollo)

### Incializar un proyecto con Ts, crea un archivo de configuracion llamado tsconfig.json

tsc --init

### como es un proyecto de node se incicializa de esta manera, y se crea el package.json que gestiona las depenendicas y script del proyecto.

npm init -y

### Instalamos paquetes necesarios para hacer un API en el proyecto como 

npm i express cors dotenv multer mongoose

express :   Servidor http
cors    :   Permite solicitudes de diferntes endpoint
dotenv  :   Uso de Variables de entorno
multer  :   
mongoose:   ORM para la BD de Mongo DB (No SQL)

npm i @types/express @types/cors @types/dotenv @types/multer @types/mongoose -D


### Estrucutra de carpetas

-src


src     : Source, donde ira todo el codigo##

### DEPLOY ON SERVER

## Instalar NGINX, NVM y MONGO DB
# NGINX
apt update 
apt upgrade
apt nginx

# NVM
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.35.3/install.sh
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.35.3/install.sh | bash
source ~/.bashrc

Despues instalar la version de node

nvm install 1X


# MONGODB
curl -fsSL https://www.mongodb.org/static/pgp/server-4.4.asc | sudo apt-key add -

echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu focal/mongodb-org/4.4 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-4.4.list

sudo apt update

sudo apt install mongodb-org

--Si se tienen problemas realizar este comando
echo "deb http://security.ubuntu.com/ubuntu focal-security main" | sudo tee /etc/apt/sources.list.d/focal-security.list
sudo apt-get update
sudo apt-get install libssl1.1

sudo apt install mongodb-org

### INCIALIZAR MONGODB

sudo systemctl start mongod.service

sudo systemctl status mongod


en el servidor cloud abrimos el puerto en la que escucha nuestra app.


## INSTALAR PM2

npm install pm2 -g

Proxy inverso con nginx
puedes crear un nuevo archivo o modificar el default

NOTA: ln -s [RUTA/ARCHIVO RUTA]
# SSL
upstream my_nodejs_upstream {
    server 127.0.0.1:3001;
    keepalive 64;
}

server {
    listen 443 ssl;
    
    server_name www.my-website.com;
    ssl_certificate_key /etc/ssl/main.key;
    ssl_certificate     /etc/ssl/main.crt;
   
    location / {
    	proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Real-IP $remote_addr;
    	proxy_set_header Host $http_host;
        
    	proxy_http_version 1.1;
    	proxy_set_header Upgrade $http_upgrade;
    	proxy_set_header Connection "upgrade";
        
    	proxy_pass http://my_nodejs_upstream/;
    	proxy_redirect off;
    	proxy_read_timeou

# HTTP

upstream my_nodejs_app {
    server 127.0.0.1:3010;
    keepalive 64;
}

server {
    listen 80 default_server;
        listen [::]:80 default_server;
        index index.html index.htm index.nginx-debian.html;
        server_name _;
    location / {
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header Host $http_host;

        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";

        proxy_pass http://my_nodejs_app/;
        proxy_redirect off;
        proxy_read_timeout 240s;
    }
}

# Ejectuar con pm2

pm2 start ./dist/app.js

