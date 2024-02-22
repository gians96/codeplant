## install nvm

wget -qO- https://raw.githubusercontent.com/creationix/nvm/v0.39.3/install.sh | bash


source ~/.profile
nvm --version
nvm install 20

npm i
npm run build
npx prisma migrate dev

## install mysql server

apt install mysql-server

###BD
	Create databases
	server_cron
	server_cron_shadow

sudo nano /etc/mysql/mysql.conf.d/mysqld.cnf
CREATE USER 'user'@'%' IDENTIFIED BY 'user';
GRANT ALL ON *.* TO 'user'@'%' WITH GRANT OPTION;


## PM2

npm install pm2 -g

pm2 start ./dist/app.js

pm2 startup [id]
pm2 save


# NGINX
## HTTP

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
## HTTPS

### cerbot
sudo apt install snapd
sudo snap install --classic certbot
sudo ln -s /snap/bin/certbot /usr/bin/certbot
sudo certbot --nginx

