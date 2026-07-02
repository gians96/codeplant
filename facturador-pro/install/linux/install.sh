#!/bin/bash

# Funcion para encontrar puerto MySQL libre
find_free_mysql_port() {
    local start_port=${1:-3001}
    local max_port=3999

    for port in $(seq $start_port $max_port); do
        if ! netstat -tuln | grep -q ":$port " && ! docker ps -a | grep -q "$port->3306"; then
            echo $port
            return 0
        fi
    done

    echo "ERROR: No se encontro puerto MySQL libre entre $start_port y $max_port" >&2
    return 1
}

# Funcion para listar puertos ocupados
list_occupied_ports() {
    echo "=== PUERTOS MYSQL ACTUALMENTE OCUPADOS ==="
    docker ps -a | grep mariadb | awk '{print $1, $NF}' | while read id name; do
        port=$(docker port $id 2>/dev/null | grep 3306 | head -1 | awk -F':' '{print $2}' | cut -d'-' -f1)
        if [ ! -z "$port" ]; then
            printf "  %-6s -> %s\n" "$port" "$name"
        fi
    done | sort -n
    echo "==========================================="
}

#PREGUNTAR AL USUARIO SOBRE HOST
read -p "Coloca tu dominio: " HOST

#DOMINIO
if [ "$HOST" = "" ]; then
    echo "No ha ingresado dominio, vuelva a ejecutar el script agregando un dominio"
    exit 1
fi
if [[ "$HOST" == ws.* ]]; then
    echo "ERROR: ingresa el dominio raiz (ej: nt-suite.com). ws.$HOST queda reservado para WebSocket."
    exit 1
fi

#PREGUNTAR AL USUARIO SOBRE EL SERVICE NUMBER
read -p "Coloque su numero de servicio para instalar: (presione enter si es la primera instalacion de su servidor) " SERVICE_NUMBER

#NUMERO DE SERVICIO
if [ "$SERVICE_NUMBER" = '' ]; then
    SERVICE_NUMBER="1"
fi

#PORT DE MYSQL - DETECCION AUTOMATICA
SUGGESTED_PORT=$((3000 + $SERVICE_NUMBER))

echo ""
list_occupied_ports
echo ""

# Verificar si el puerto sugerido esta libre
if netstat -tuln | grep -q ":$SUGGESTED_PORT " || docker ps -a | grep -q "$SUGGESTED_PORT->3306"; then
    echo "ADVERTENCIA: El puerto $SUGGESTED_PORT (calculado: 3000 + $SERVICE_NUMBER) ya esta OCUPADO"

    # Buscar puerto libre automaticamente
    FREE_PORT=$(find_free_mysql_port $SUGGESTED_PORT)

    if [ $? -eq 0 ]; then
        echo "OK Puerto libre encontrado automaticamente: $FREE_PORT"
        read -p "Desea usar el puerto $FREE_PORT? [S/n]: " use_auto_port

        if [ "$use_auto_port" = "n" ] || [ "$use_auto_port" = "N" ]; then
            read -p "Ingrese manualmente el puerto MySQL que desea usar (3001-3999): " manual_port

            # Validar puerto manual
            if netstat -tuln | grep -q ":$manual_port " || docker ps -a | grep -q "$manual_port->3306"; then
                echo "ERROR: El puerto $manual_port tambien esta ocupado. Abortando instalacion."
                exit 1
            fi
            MYSQL_PORT_HOST=$manual_port
        else
            MYSQL_PORT_HOST=$FREE_PORT
        fi
    else
        echo "ERROR: No se pudo encontrar un puerto libre automaticamente."
        exit 1
    fi
else
    echo "OK Puerto $SUGGESTED_PORT esta disponible"
    MYSQL_PORT_HOST=$SUGGESTED_PORT
fi

echo ""
echo "Puerto MySQL seleccionado: $MYSQL_PORT_HOST"
echo ""
sleep 2

#VERSION
read -p "indique version del facturador a instalar, [1](Pro8) [2](ProX) : " version
if [ "$version" = '1' ]; then
    VERSION_PHP_IMAGE="8.2"
    DB_FOLDER="seeders"
    SCHEDULING="scheduling:8.2"
    SUPERVISOR="supervisor-php:8.2"
    PROYECT='https://gitlab.com/gians96/pro-8.git'

elif [ "$version" = '2' ]; then
    VERSION_PHP_IMAGE="8.2"
    DB_FOLDER="seeders"
    SCHEDULING="scheduling:8.2"
    SUPERVISOR="supervisor-php:8.2"
    PROYECT='https://git.buho.la/facturaloperu/facturador/pro-x.git'
else
    echo "No ha ingresado una version correcta del facturador"
    exit 1
fi

#RUTA DE INSTALACION (RUTA ACTUAL DEL SCRIPT)
PATH_INSTALL=$(echo $PWD)
#NOMBRE DE CARPETA
DIR=$(echo $HOST)
#DATOS DE ACCESO MYSQL (sanitizados: puntos -> guiones bajos para nombres de BD validos)
MYSQL_USER=$(echo "$DIR" | sed 's/\./_/g')
MYSQL_PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 20 ; echo '')
MYSQL_DATABASE=$(echo "$DIR" | sed 's/\./_/g')
MYSQL_ROOT_PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 20 ; echo '')

# DATOS PARA REDIS
DIR_MODIFIED=$(echo "$DIR" | sed 's/\./_/g')
REDIS_CONTAINER_NAME="redis_${DIR_MODIFIED}"

# DATOS PARA LARAVEL BROADCASTING / SOKETI
SOKETI_CONTAINER_NAME="soketi_${DIR_MODIFIED}"
SOKETI_CLIENT_HOST="ws.${HOST}"
PUSHER_APP_ID="vendemaster${SERVICE_NUMBER}"
PUSHER_APP_KEY=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 20 ; echo '')
PUSHER_APP_SECRET=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 20 ; echo '')


if [ "$SERVICE_NUMBER" = '1' ]; then
echo "Actualizando sistema"
apt-get -y update
apt-get -y upgrade

echo "Instalando git"
apt-get -y install git-core


echo "Instalando docker"
apt-get -y install apt-transport-https ca-certificates curl gnupg-agent software-properties-common gnupg lsb-release
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/$(. /etc/os-release; echo "$ID")/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$(. /etc/os-release; echo "$ID") $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get -y update
apt-get -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl start docker
systemctl enable docker

echo "OK docker compose v2 ya instalado como plugin (docker-compose-plugin)"

echo "Instalando letsencrypt"
apt-get -y install letsencrypt
mkdir -p $PATH_INSTALL/certs/

echo "Configurando proxy"
docker network create proxynet
mkdir -p $PATH_INSTALL/proxy
cat << EOF > $PATH_INSTALL/proxy/docker-compose.yml
services:
    proxy:
        image: rash07/nginx-proxy:4.0
        ports:
            - "80:80"
            - "443:443"
        volumes:
            - ./../certs:/etc/nginx/certs
            - /var/run/docker.sock:/tmp/docker.sock:ro
        restart: always
        privileged: true
networks:
    default:
        external:
            name: proxynet

EOF

cd $PATH_INSTALL/proxy
docker compose up -d

mkdir -p $PATH_INSTALL/proxy/fpms
fi

echo "Configurando $DIR"

if ! [ -d $PATH_INSTALL/proxy/fpms/$DIR ]; then
echo "Cloning the repository"
rm -rf "$PATH_INSTALL/$DIR"
git clone "$PROYECT" "$PATH_INSTALL/$DIR"

mkdir -p $PATH_INSTALL/proxy/fpms/$DIR

cat << EOF > $PATH_INSTALL/proxy/fpms/$DIR/default
# Configuracin de PHP para Nginx
server {
    listen 80 default_server;
    root /var/www/html/public;
    index index.html index.htm index.php;
    server_name *._;
    charset utf-8;
    server_tokens off;
    set \$redirect_scheme \$http_x_forwarded_proto;
    if (\$redirect_scheme = "") { set \$redirect_scheme \$scheme; }
    if (\$host = "www.$HOST") {
        return 301 \$redirect_scheme://$HOST\$request_uri;
    }
    location = /favicon.ico {
        log_not_found off;
        access_log off;
    }
    location = /robots.txt {
        log_not_found off;
        access_log off;
    }
    location / {
        try_files \$uri \$uri/ /index.php\$is_args\$args;
    }
    # Compatibilidad: los clientes nuevos usan wss://$SOKETI_CLIENT_HOST/app.
    location /app {
        proxy_pass http://$SOKETI_CONTAINER_NAME:6001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 600s;
        proxy_send_timeout 600s;
    }
    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass fpm_$DIR_MODIFIED:9000;
        fastcgi_read_timeout 3600;
    }
    error_page 404 /index.php;
    location ~ /\.ht {
        deny all;
    }
}
EOF

# --- Dockerfile para Nginx (config baked-in, sin bind mount) --
cat << 'EOFNGINXDF' > $PATH_INSTALL/proxy/fpms/$DIR/Dockerfile
FROM rash07/nginx
RUN rm -f /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default
COPY default /etc/nginx/sites-available/default
RUN ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default
EOFNGINXDF

cat << EOF > $PATH_INSTALL/$DIR/docker-compose.yml
services:
    nginx_$SERVICE_NUMBER:
        build:
            context: $PATH_INSTALL/proxy/fpms/$DIR
            dockerfile: Dockerfile
        container_name: nginx_$DIR_MODIFIED
        working_dir: /var/www/html
        environment:
            VIRTUAL_HOST: $HOST, www.$HOST, *.$HOST
            VIRTUAL_PORT: "80"
            VIRTUAL_PROTO: "http"
            CERT_NAME: "$HOST"
        volumes:
            - ./:/var/www/html
        restart: always
        depends_on:
            fpm_$SERVICE_NUMBER:
                condition: service_healthy
        healthcheck:
            test: ["CMD-SHELL", "service nginx status || exit 1"]
            interval: 30s
            timeout: 5s
            retries: 3
            start_period: 10s
    fpm_$SERVICE_NUMBER:
        build:
            context: ./docker/php-fpm
            dockerfile: Dockerfile
        container_name: fpm_$DIR_MODIFIED
        working_dir: /var/www/html
        volumes:
            - ./:/var/www/html
        restart: always
        healthcheck:
            test: ["CMD-SHELL", "kill -0 1 2>/dev/null && grep -q ':2328' /proc/net/tcp /proc/net/tcp6 2>/dev/null"]
            interval: 30s
            timeout: 5s
            retries: 3
            start_period: 15s
    mariadb_$SERVICE_NUMBER:
        image: mariadb:10.5.6
        container_name: mariadb_$DIR_MODIFIED
        environment:
            - MYSQL_USER=\${MYSQL_USER}
            - MYSQL_PASSWORD=\${MYSQL_PASSWORD}
            - MYSQL_DATABASE=\${MYSQL_DATABASE}
            - MYSQL_ROOT_PASSWORD=\${MYSQL_ROOT_PASSWORD}
            - MYSQL_PORT_HOST=\${MYSQL_PORT_HOST}
        volumes:
            - mysqldata$SERVICE_NUMBER:/var/lib/mysql
            - ./docker/mariadb/my.cnf:/etc/mysql/conf.d/custom.cnf:ro
        ports:
            - "\${MYSQL_PORT_HOST}:3306"
        restart: always
    redis_$SERVICE_NUMBER:
        image: redis:alpine
        container_name: redis_$DIR_MODIFIED
        command: redis-server --appendonly yes
        volumes:
            - redisdata$SERVICE_NUMBER:/data
        restart: always
    soketi_$SERVICE_NUMBER:
        image: quay.io/soketi/soketi:1.6-16-debian
        container_name: $SOKETI_CONTAINER_NAME
        environment:
            - SOKETI_DEBUG=0
            - SOKETI_DEFAULT_APP_ID=\${PUSHER_APP_ID}
            - SOKETI_DEFAULT_APP_KEY=\${PUSHER_APP_KEY}
            - SOKETI_DEFAULT_APP_SECRET=\${PUSHER_APP_SECRET}
            - VIRTUAL_HOST=$SOKETI_CLIENT_HOST
            - VIRTUAL_PORT=6001
            - VIRTUAL_PROTO=http
            - CERT_NAME=$HOST
        restart: always
    scheduling_$SERVICE_NUMBER:
        build:
            context: ./docker/scheduling
            dockerfile: Dockerfile
        container_name: scheduling_$DIR_MODIFIED
        working_dir: /var/www/html
        volumes:
            - ./:/var/www/html
        restart: always
    supervisor_$SERVICE_NUMBER:
        build:
            context: ./docker/supervisor
            dockerfile: Dockerfile
        container_name: supervisor_$DIR_MODIFIED
        working_dir: /var/www/html
        volumes:
            - ./:/var/www/html
            - ./supervisor.conf:/etc/supervisor/conf.d/supervisor.conf
        restart: always

networks:
    default:
        external:
            name: proxynet

volumes:
    redisdata$SERVICE_NUMBER:
        driver: "local"
    mysqldata$SERVICE_NUMBER:
        driver: "local"

EOF

cp $PATH_INSTALL/$DIR/.env.example $PATH_INSTALL/$DIR/.env

cat << EOF >> $PATH_INSTALL/$DIR/.env


MYSQL_USER=$MYSQL_USER
MYSQL_PASSWORD=$MYSQL_PASSWORD
MYSQL_DATABASE=$MYSQL_DATABASE
MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD
MYSQL_PORT_HOST=$MYSQL_PORT_HOST
PUSHER_APP_ID=$PUSHER_APP_ID
PUSHER_APP_KEY=$PUSHER_APP_KEY
PUSHER_APP_SECRET=$PUSHER_APP_SECRET
EOF

echo "Configurando env"
cd "$PATH_INSTALL/$DIR"

set_env_var() {
    local key="$1"
    local value="$2"
    if grep -q "^${key}=" .env; then
        sed -i "/^${key}=/c\\${key}=${value}" .env
    else
        echo "${key}=${value}" >> .env
    fi
}

sed -i "/APP_NAME=/c\APP_NAME=$HOST" .env
sed -i "/DB_DATABASE=/c\DB_DATABASE=$MYSQL_DATABASE" .env
sed -i "/DB_PASSWORD=/c\DB_PASSWORD=$MYSQL_ROOT_PASSWORD" .env
sed -i "/DB_HOST=/c\DB_HOST=mariadb_$DIR_MODIFIED" .env
sed -i "/DB_USERNAME=/c\DB_USERNAME=root" .env
sed -i "/APP_URL_BASE=/c\APP_URL_BASE=$HOST" .env
sed -i '/APP_URL=/c\APP_URL=http://${APP_URL_BASE}' .env
sed -i '/FORCE_HTTPS=/c\FORCE_HTTPS=false' .env
sed -i '/APP_DEBUG=/c\APP_DEBUG=false' .env

# CONFIGURACIONES DE REDIS  CACHE_DRIVER=file es CRITICO (redis_tenancy rompe CLI)
sed -i '/CACHE_DRIVER=/c\CACHE_DRIVER=file' .env
sed -i '/QUEUE_CONNECTION=/c\QUEUE_CONNECTION=redis' .env
sed -i "/REDIS_HOST=/c\REDIS_HOST=$REDIS_CONTAINER_NAME" .env
sed -i '/REDIS_PASSWORD=/c\REDIS_PASSWORD=null' .env
sed -i '/REDIS_PORT=/c\REDIS_PORT=6379' .env

set_env_var "BROADCAST_DRIVER" "pusher"
set_env_var "PUSHER_APP_ID" "$PUSHER_APP_ID"
set_env_var "PUSHER_APP_KEY" "$PUSHER_APP_KEY"
set_env_var "PUSHER_APP_SECRET" "$PUSHER_APP_SECRET"
set_env_var "PUSHER_APP_CLUSTER" "mt1"
set_env_var "PUSHER_HOST" "$SOKETI_CONTAINER_NAME"
set_env_var "PUSHER_PORT" "6001"
set_env_var "PUSHER_SCHEME" "http"
set_env_var "PUSHER_CLIENT_HOST" "$SOKETI_CLIENT_HOST"
set_env_var "PUSHER_CLIENT_PORT" "443"
set_env_var "PUSHER_CLIENT_SCHEME" "https"

ADMIN_PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 10 ; echo '')
echo "Configurando archivo para usuario administrador"
mv "$PATH_INSTALL/$DIR/database/$DB_FOLDER/DatabaseSeeder.php" "$PATH_INSTALL/$DIR/database/$DB_FOLDER/DatabaseSeeder.php.bk"

# DatabaseSeeder - escrito con python3 para evitar problemas de CRLF/heredoc
SEEDER_FILE="$PATH_INSTALL/$DIR/database/$DB_FOLDER/DatabaseSeeder.php"
python3 -c "
content = '''<?php
namespace Database\Seeders;

use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\DB;

class DatabaseSeeder extends Seeder
{
    public function run(): void
    {
        DB::table(\"users\")->insert([
            \"name\" => \"Admin Instrador\",
            \"email\" => \"admin@$HOST\",
            \"password\" => bcrypt(\"$ADMIN_PASSWORD\"),
            \"created_at\" => now(),
            \"updated_at\" => now(),
        ]);

        DB::table(\"plan_documents\")->insert([
            [\"id\" => 1, \"description\" => \"Facturas, boletas, notas de debito y credito, resumenes y anulaciones\"],
            [\"id\" => 2, \"description\" => \"Guias de remision\"],
            [\"id\" => 3, \"description\" => \"Retenciones\"],
            [\"id\" => 4, \"description\" => \"Percepciones\"]
        ]);

        DB::table(\"plans\")->insert([
            \"name\" => \"Ilimitado\",
            \"pricing\" => 99,
            \"limit_users\" => 0,
            \"limit_documents\" => 0,
            \"plan_documents\" => json_encode([1, 2, 3, 4]),
            \"locked\" => true,
            \"created_at\" => now(),
            \"updated_at\" => now(),
        ]);
    }
}
'''
with open('$SEEDER_FILE', 'w', newline='\n') as f:
    f.write(content)
"


echo "Generando Dockerfiles con OPcache..."

mkdir -p "$PATH_INSTALL/$DIR/docker/php-fpm"
cat > "$PATH_INSTALL/$DIR/docker/php-fpm/Dockerfile" << EOFFPM
FROM rash07/php-fpm:$VERSION_PHP_IMAGE
RUN docker-php-ext-install opcache
COPY opcache.ini /usr/local/etc/php/conf.d/opcache.ini
EOFFPM

cat > "$PATH_INSTALL/$DIR/docker/php-fpm/opcache.ini" << 'EOFOC'
[opcache]
opcache.enable=1
opcache.enable_cli=0
opcache.memory_consumption=256
opcache.interned_strings_buffer=32
opcache.max_accelerated_files=20000
opcache.validate_timestamps=0
opcache.revalidate_freq=0
opcache.save_comments=1
opcache.fast_shutdown=1
opcache.jit_buffer_size=128M
opcache.jit=1255
EOFOC

mkdir -p "$PATH_INSTALL/$DIR/docker/scheduling"
cat > "$PATH_INSTALL/$DIR/docker/scheduling/Dockerfile" << EOFSCHED
FROM rash07/$SCHEDULING
RUN docker-php-ext-install opcache
COPY opcache-cli.ini /usr/local/etc/php/conf.d/opcache.ini
EOFSCHED

cat > "$PATH_INSTALL/$DIR/docker/scheduling/opcache-cli.ini" << 'EOFCLI'
[opcache]
opcache.enable=1
opcache.enable_cli=1
opcache.memory_consumption=128
opcache.interned_strings_buffer=16
opcache.max_accelerated_files=20000
opcache.validate_timestamps=0
opcache.save_comments=1
EOFCLI

mkdir -p "$PATH_INSTALL/$DIR/docker/supervisor"
cat > "$PATH_INSTALL/$DIR/docker/supervisor/Dockerfile" << EOFSUP
FROM rash07/$SUPERVISOR
RUN docker-php-ext-install opcache
COPY opcache-cli.ini /usr/local/etc/php/conf.d/opcache.ini
EOFSUP

cat > "$PATH_INSTALL/$DIR/docker/supervisor/opcache-cli.ini" << 'EOFCLI2'
[opcache]
opcache.enable=1
opcache.enable_cli=1
opcache.memory_consumption=128
opcache.interned_strings_buffer=16
opcache.max_accelerated_files=20000
opcache.validate_timestamps=0
opcache.save_comments=1
EOFCLI2

mkdir -p "$PATH_INSTALL/$DIR/docker/mariadb"
cat > "$PATH_INSTALL/$DIR/docker/mariadb/my.cnf" << 'EOFMYCNF'
[mysqld]
innodb_buffer_pool_size         = 2G
innodb_buffer_pool_instances    = 4
innodb_log_file_size            = 256M
innodb_flush_log_at_trx_commit  = 2
max_connections                 = 200
tmp_table_size                  = 64M
max_heap_table_size             = 64M
query_cache_type                = 0
query_cache_size                = 0
table_open_cache                = 2000
thread_cache_size               = 16
character-set-server            = utf8mb4
collation-server                = utf8mb4_unicode_ci
EOFMYCNF

echo "Configurando proyecto"
docker compose up -d --build

echo "Esperando que MariaDB este listo..."
for i in {1..60}; do
    if docker compose exec -T mariadb_$SERVICE_NUMBER mysqladmin ping -h"localhost" -uroot -p"$MYSQL_ROOT_PASSWORD" &> /dev/null; then
        echo "OK MariaDB esta listo"
        break
    fi
    echo "Esperando MariaDB... ($i/60)"
    sleep 2
done

echo "Esperando que Redis este listo..."
for i in {1..30}; do
    if docker compose exec -T redis_$SERVICE_NUMBER redis-cli ping &> /dev/null; then
        echo "OK Redis esta listo"
        break
    fi
    echo "Esperando Redis... ($i/30)"
    sleep 1
done

echo "Esperando que los contenedores esten listos..."
sleep 10

docker compose exec -T fpm_$SERVICE_NUMBER rm -f composer.lock
docker compose exec -T fpm_$SERVICE_NUMBER composer self-update
docker compose exec -T fpm_$SERVICE_NUMBER composer install

echo "Ejecutando migraciones y seeds..."
docker compose exec -T fpm_$SERVICE_NUMBER php artisan migrate:refresh --seed --force

docker compose exec -T fpm_$SERVICE_NUMBER php artisan key:generate
docker compose exec -T fpm_$SERVICE_NUMBER php artisan storage:link
docker compose exec -T fpm_$SERVICE_NUMBER git checkout .
docker compose exec -T fpm_$SERVICE_NUMBER git config --global core.fileMode false

rm $PATH_INSTALL/$DIR/database/$DB_FOLDER/DatabaseSeeder.php
mv $PATH_INSTALL/$DIR/database/$DB_FOLDER/DatabaseSeeder.php.bk $PATH_INSTALL/$DIR/database/$DB_FOLDER/DatabaseSeeder.php

echo "Optimizando Laravel (caches + autoload)..."
docker compose exec -T fpm_$SERVICE_NUMBER php artisan config:cache
# IMPORTANTE: NO usar route:cache  hyn/multi-tenant necesita evaluar rutas
# dinamicamente por hostname en cada request (if $hostname en web.php)
docker compose exec -T fpm_$SERVICE_NUMBER php artisan route:clear
docker compose exec -T fpm_$SERVICE_NUMBER php artisan event:cache
docker compose exec -T fpm_$SERVICE_NUMBER sh -c "cd /var/www/html && composer dump-autoload --classmap-authoritative 2>&1" | tail -1

echo "configurando permisos"
chmod -R 777 "$PATH_INSTALL/$DIR/storage/" "$PATH_INSTALL/$DIR/bootstrap/"
if [ -d "$PATH_INSTALL/$DIR/vendor/" ]; then
    chmod -R 777 "$PATH_INSTALL/$DIR/vendor/"
fi
if [ -f "$PATH_INSTALL/$DIR/script-update.sh" ]; then
    chmod +x $PATH_INSTALL/$DIR/script-update.sh
fi

echo "Esperando que supervisor este listo..."
sleep 5

echo "configurando Supervisor"
docker compose exec -T supervisor_$SERVICE_NUMBER service supervisor start 2>/dev/null || true
docker compose exec -T supervisor_$SERVICE_NUMBER supervisorctl reread 2>/dev/null || true
docker compose exec -T supervisor_$SERVICE_NUMBER supervisorctl update 2>/dev/null || true
docker compose exec -T supervisor_$SERVICE_NUMBER supervisorctl start all 2>/dev/null || true

#SSL
read -p "instalar SSL gratuito? si[s] no[n]: " ssl
if [ "$ssl" = "s" ]; then

    echo "--IMPORTANTE--"
    echo "--------------"
    echo "Copiar los TXT sin usar [ctrl+c] ya que cancelar el proceso"
    echo "Ingresar correo electronico y aceptar las preguntas"
    echo "--------------"

    certbot certonly --manual -d *.$HOST -d $HOST --agree-tos --no-bootstrap --manual-public-ip-logging-ok --preferred-challenges dns-01 --server https://acme-v02.api.letsencrypt.org/directory

    echo "Configurando certbot"

    if ! [ -f /etc/letsencrypt/live/$HOST/privkey.pem ]; then

        echo "No se ha generado el certificado gratuito"
    else

        sed -i '/APP_URL=/c\APP_URL=https://${APP_URL_BASE}' .env
        sed -i '/FORCE_HTTPS=/c\FORCE_HTTPS=true' .env

        cp /etc/letsencrypt/live/$HOST/privkey.pem $PATH_INSTALL/certs/$HOST.key
        cp /etc/letsencrypt/live/$HOST/fullchain.pem $PATH_INSTALL/certs/$HOST.crt
        cp /etc/letsencrypt/live/$HOST/privkey.pem $PATH_INSTALL/certs/$SOKETI_CLIENT_HOST.key
        cp /etc/letsencrypt/live/$HOST/fullchain.pem $PATH_INSTALL/certs/$SOKETI_CLIENT_HOST.crt

        docker compose exec -T fpm_$SERVICE_NUMBER php artisan config:cache
        docker compose exec -T fpm_$SERVICE_NUMBER php artisan cache:clear

        # Detectar nombre del contenedor proxy (compatible con todos los formatos)
        echo "-> Buscando contenedor proxy..."
        PROXY_CONTAINER=$(docker ps --filter "ancestor=rash07/nginx-proxy:4.0" --format "{{.Names}}" | head -1)

        # Si no encuentra por imagen, buscar por nombre
        if [ -z "$PROXY_CONTAINER" ]; then
            PROXY_CONTAINER=$(docker ps | grep -E "proxy.*proxy" | awk '{print $NF}' | head -1)
        fi

        if [ ! -z "$PROXY_CONTAINER" ]; then
            echo "-> Reiniciando proxy: $PROXY_CONTAINER"
            docker restart $PROXY_CONTAINER
            echo "OK Proxy reiniciado correctamente"
        else
            echo "ADVERTENCIA: No se encontro contenedor proxy para reiniciar"
            echo "   Verifica manualmente con: docker ps | grep proxy"
        fi

    fi

fi


echo ""
echo "=============================================="
echo "OK INSTALACION COMPLETADA EXITOSAMENTE"
echo "=============================================="
echo "Ruta del proyecto: $PATH_INSTALL/$DIR"
echo "URL: http://$HOST"
echo "Correo administrador: admin@$HOST"
echo "Contrasena administrador: $ADMIN_PASSWORD"
echo "----------------------------------------------"
echo "Acceso remoto a MySQL"
echo "Puerto: $MYSQL_PORT_HOST"
echo "Usuario root: root"
echo "Contrasena root: $MYSQL_ROOT_PASSWORD"
echo "----------------------------------------------"
echo "Redis"
echo "Host: $REDIS_CONTAINER_NAME"
echo "Puerto: 6379"
echo "Password: null"
echo "----------------------------------------------"
echo "Broadcasting"
echo "Soketi interno: $SOKETI_CONTAINER_NAME:6001"
echo "WebSocket cliente: wss://$SOKETI_CLIENT_HOST/app/{key}"
echo "Subdominio reservado: $SOKETI_CLIENT_HOST (no crear tenant 'ws')"
echo "=============================================="

cat << EOF > $PATH_INSTALL/$DIR.txt
============================================
DATOS DE INSTALACION - $HOST
============================================
Ruta del proyecto: $PATH_INSTALL/$DIR
URL: http://$HOST
Correo administrador: admin@$HOST
Contrasena administrador: $ADMIN_PASSWORD
----------------------------------------------
Acceso remoto a MySQL
Puerto: $MYSQL_PORT_HOST
Host: $(hostname -I | awk '{print $1}')
Usuario: root
Contrasena root: $MYSQL_ROOT_PASSWORD
----------------------------------------------
Redis
Host: $REDIS_CONTAINER_NAME
Puerto: 6379
Password: null
----------------------------------------------
Broadcasting
Soketi interno: $SOKETI_CONTAINER_NAME:6001
WebSocket cliente: wss://$SOKETI_CLIENT_HOST/app/{key}
Subdominio reservado: $SOKETI_CLIENT_HOST (no crear tenant 'ws')
----------------------------------------------
Service Number: $SERVICE_NUMBER
Version PHP: $VERSION_PHP_IMAGE
Contenedor FPM: fpm_$DIR_MODIFIED
Contenedor MariaDB: mariadb_$DIR_MODIFIED
Contenedor Redis: $REDIS_CONTAINER_NAME
Contenedor Soketi: $SOKETI_CONTAINER_NAME
============================================
EOF

echo ""
echo "Credenciales guardadas en: $PATH_INSTALL/$DIR.txt"

else
echo "ERROR: La carpeta $PATH_INSTALL/proxy/fpms/$DIR ya existe"
echo "Si desea reinstalar, elimine primero las carpetas y volumenes existentes:"
echo ""
echo "  # Carpetas del proyecto:"
echo "  rm -rf $PATH_INSTALL/proxy/fpms/$DIR"
echo "  rm -rf $PATH_INSTALL/$DIR"
echo ""
echo "  # Volumenes Docker (IMPORTANTE: contienen la contrasena anterior de MariaDB):"
echo "  docker volume rm ${DIR_MODIFIED}_mysqldata${SERVICE_NUMBER} ${DIR_MODIFIED}_redisdata${SERVICE_NUMBER} 2>/dev/null || true"
echo ""
echo "  # O para listar todos los volumenes existentes:"
echo "  docker volume ls | grep $DIR_MODIFIED"
exit 1
fi
