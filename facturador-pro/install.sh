#!/bin/bash

# Función para encontrar puerto MySQL libre
find_free_mysql_port() {
    local start_port=${1:-3001}
    local max_port=3999
    
    for port in $(seq $start_port $max_port); do
        if ! netstat -tuln | grep -q ":$port " && ! docker ps -a | grep -q "$port->3306"; then
            echo $port
            return 0
        fi
    done
    
    echo "ERROR: No se encontró puerto MySQL libre entre $start_port y $max_port" >&2
    return 1
}

# Función para listar puertos ocupados
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

#PREGUNTAR AL USUARIO SOBRE EL SERVICE NUMBER
read -p "Coloque su numero de servicio para instalar: (presione enter si es la primera instalacion de su servidor) " SERVICE_NUMBER

#NUMERO DE SERVICIO
if [ "$SERVICE_NUMBER" = '' ]; then
    SERVICE_NUMBER="1"
fi

#PORT DE MYSQL - DETECCIÓN AUTOMÁTICA
SUGGESTED_PORT=$((3000 + $SERVICE_NUMBER))

echo ""
list_occupied_ports
echo ""

# Verificar si el puerto sugerido está libre
if netstat -tuln | grep -q ":$SUGGESTED_PORT " || docker ps -a | grep -q "$SUGGESTED_PORT->3306"; then
    echo "⚠️  ADVERTENCIA: El puerto $SUGGESTED_PORT (calculado: 3000 + $SERVICE_NUMBER) ya está OCUPADO"
    
    # Buscar puerto libre automáticamente
    FREE_PORT=$(find_free_mysql_port $SUGGESTED_PORT)
    
    if [ $? -eq 0 ]; then
        echo "✅ Puerto libre encontrado automáticamente: $FREE_PORT"
        read -p "¿Desea usar el puerto $FREE_PORT? [S/n]: " use_auto_port
        
        if [ "$use_auto_port" = "n" ] || [ "$use_auto_port" = "N" ]; then
            read -p "Ingrese manualmente el puerto MySQL que desea usar (3001-3999): " manual_port
            
            # Validar puerto manual
            if netstat -tuln | grep -q ":$manual_port " || docker ps -a | grep -q "$manual_port->3306"; then
                echo "❌ ERROR: El puerto $manual_port también está ocupado. Abortando instalación."
                exit 1
            fi
            MYSQL_PORT_HOST=$manual_port
        else
            MYSQL_PORT_HOST=$FREE_PORT
        fi
    else
        echo "❌ ERROR: No se pudo encontrar un puerto libre automáticamente."
        exit 1
    fi
else
    echo "✅ Puerto $SUGGESTED_PORT está disponible"
    MYSQL_PORT_HOST=$SUGGESTED_PORT
fi

echo ""
echo "🔵 Puerto MySQL seleccionado: $MYSQL_PORT_HOST"
echo ""
sleep 2

#VERSION
read -p "indique versión del facturador a instalar, [1](Pro8) [2](ProX) : " version
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
#DATOS DE ACCESO MYSQL (sanitizados: puntos -> guiones bajos para nombres de BD válidos)
MYSQL_USER=$(echo "$DIR" | sed 's/\./_/g')
MYSQL_PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 20 ; echo '')
MYSQL_DATABASE=$(echo "$DIR" | sed 's/\./_/g')
MYSQL_ROOT_PASSWORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 20 ; echo '')

# DATOS PARA REDIS
DIR_MODIFIED=$(echo "$DIR" | sed 's/\./_/g')
REDIS_CONTAINER_NAME="redis_${DIR_MODIFIED}"


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

echo "✅ docker compose v2 ya instalado como plugin (docker-compose-plugin)"

echo "Instalando letsencrypt"
apt-get -y install letsencrypt
mkdir -p $PATH_INSTALL/certs/

echo "Configurando proxy"
docker network create proxynet
mkdir -p $PATH_INSTALL/proxy
cat << EOF > $PATH_INSTALL/proxy/docker-compose.yml
version: '3'

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
# Configuración de PHP para Nginx
server {
    listen 80 default_server;
    root /var/www/html/public;
    index index.html index.htm index.php;
    server_name *._;
    charset utf-8;
    server_tokens off;
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


cat << EOF > $PATH_INSTALL/$DIR/docker-compose.yml
version: '3'

services:
    nginx_$SERVICE_NUMBER:
        image: rash07/nginx
        container_name: nginx_$DIR_MODIFIED
        working_dir: /var/www/html
        environment:
            VIRTUAL_HOST: $HOST, *.$HOST
        volumes:
            - ./:/var/www/html
            - $PATH_INSTALL/proxy/fpms/$DIR:/etc/nginx/sites-available
        restart: always
    fpm_$SERVICE_NUMBER:
        image: rash07/php-fpm:$VERSION_PHP_IMAGE
        container_name: fpm_$DIR_MODIFIED
        working_dir: /var/www/html
        volumes:
            - ./:/var/www/html
        restart: always
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
    scheduling_$SERVICE_NUMBER:
        image: rash07/$SCHEDULING
        container_name: scheduling_$DIR_MODIFIED
        working_dir: /var/www/html
        volumes:
            - ./:/var/www/html
        restart: always
    supervisor_$SERVICE_NUMBER:
        image: rash07/$SUPERVISOR
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
EOF

echo "Configurando env"
cd "$PATH_INSTALL/$DIR"

sed -i "/APP_NAME=/c\APP_NAME=$HOST" .env
sed -i "/DB_DATABASE=/c\DB_DATABASE=$MYSQL_DATABASE" .env
sed -i "/DB_PASSWORD=/c\DB_PASSWORD=$MYSQL_ROOT_PASSWORD" .env
sed -i "/DB_HOST=/c\DB_HOST=mariadb_$DIR_MODIFIED" .env
sed -i "/DB_USERNAME=/c\DB_USERNAME=root" .env
sed -i "/APP_URL_BASE=/c\APP_URL_BASE=$HOST" .env
sed -i '/APP_URL=/c\APP_URL=http://${APP_URL_BASE}' .env
sed -i '/FORCE_HTTPS=/c\FORCE_HTTPS=false' .env
sed -i '/APP_DEBUG=/c\APP_DEBUG=false' .env

# NUEVAS CONFIGURACIONES PARA REDIS 🔴
sed -i '/CACHE_DRIVER=/c\CACHE_DRIVER=redis' .env
sed -i '/QUEUE_CONNECTION=/c\QUEUE_CONNECTION=redis' .env
sed -i "/REDIS_HOST=/c\REDIS_HOST=$REDIS_CONTAINER_NAME" .env
sed -i '/REDIS_PASSWORD=/c\REDIS_PASSWORD=null' .env
sed -i '/REDIS_PORT=/c\REDIS_PORT=6379' .env

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


echo "Configurando proyecto"
docker compose up -d

echo "Esperando que MariaDB esté listo..."
for i in {1..60}; do
    if docker compose exec -T mariadb_$SERVICE_NUMBER mysqladmin ping -h"localhost" -uroot -p"$MYSQL_ROOT_PASSWORD" &> /dev/null; then
        echo "✅ MariaDB está listo"
        break
    fi
    echo "Esperando MariaDB... ($i/60)"
    sleep 2
done

echo "Esperando que Redis esté listo..."
for i in {1..30}; do
    if docker compose exec -T redis_$SERVICE_NUMBER redis-cli ping &> /dev/null; then
        echo "✅ Redis está listo"
        break
    fi
    echo "Esperando Redis... ($i/30)"
    sleep 1
done

echo "Esperando que los contenedores estén listos..."
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

echo "configurando permisos"
chmod -R 777 "$PATH_INSTALL/$DIR/storage/" "$PATH_INSTALL/$DIR/bootstrap/"
if [ -d "$PATH_INSTALL/$DIR/vendor/" ]; then
    chmod -R 777 "$PATH_INSTALL/$DIR/vendor/"
fi
if [ -f "$PATH_INSTALL/$DIR/script-update.sh" ]; then
    chmod +x $PATH_INSTALL/$DIR/script-update.sh
fi

echo "Esperando que supervisor esté listo..."
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
    echo "Copiar los TXT sin usar [ctrl+c] ya que cancelará el proceso"
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

        docker compose exec -T fpm_$SERVICE_NUMBER php artisan config:cache
        docker compose exec -T fpm_$SERVICE_NUMBER php artisan cache:clear

        # Detectar nombre del contenedor proxy (compatible con todos los formatos)
        echo "🔍 Buscando contenedor proxy..."
        PROXY_CONTAINER=$(docker ps --filter "ancestor=rash07/nginx-proxy:4.0" --format "{{.Names}}" | head -1)
        
        # Si no encuentra por imagen, buscar por nombre
        if [ -z "$PROXY_CONTAINER" ]; then
            PROXY_CONTAINER=$(docker ps | grep -E "proxy.*proxy" | awk '{print $NF}' | head -1)
        fi
        
        if [ ! -z "$PROXY_CONTAINER" ]; then
            echo "🔄 Reiniciando proxy: $PROXY_CONTAINER"
            docker restart $PROXY_CONTAINER
            echo "✅ Proxy reiniciado correctamente"
        else
            echo "⚠️ No se encontró contenedor proxy para reiniciar"
            echo "   Verifica manualmente con: docker ps | grep proxy"
        fi

    fi

fi


echo ""
echo "=============================================="
echo "✅ INSTALACIÓN COMPLETADA EXITOSAMENTE"
echo "=============================================="
echo "Ruta del proyecto: $PATH_INSTALL/$DIR"
echo "URL: http://$HOST"
echo "Correo administrador: admin@$HOST"
echo "Contraseña administrador: $ADMIN_PASSWORD"
echo "----------------------------------------------"
echo "Acceso remoto a MySQL"
echo "Puerto: $MYSQL_PORT_HOST"
echo "Usuario root: root"
echo "Contraseña root: $MYSQL_ROOT_PASSWORD"
echo "----------------------------------------------"
echo "Redis"
echo "Host: $REDIS_CONTAINER_NAME"
echo "Puerto: 6379"
echo "Password: null"
echo "=============================================="

cat << EOF > $PATH_INSTALL/$DIR.txt
============================================
DATOS DE INSTALACIÓN - $HOST
============================================
Ruta del proyecto: $PATH_INSTALL/$DIR
URL: http://$HOST
Correo administrador: admin@$HOST
Contraseña administrador: $ADMIN_PASSWORD
----------------------------------------------
Acceso remoto a MySQL
Puerto: $MYSQL_PORT_HOST
Host: $(hostname -I | awk '{print $1}')
Usuario: root
Contraseña root: $MYSQL_ROOT_PASSWORD
----------------------------------------------
Redis
Host: $REDIS_CONTAINER_NAME
Puerto: 6379
Password: null
----------------------------------------------
Service Number: $SERVICE_NUMBER
Versión PHP: $VERSION_PHP_IMAGE
Contenedor FPM: fpm_$DIR_MODIFIED
Contenedor MariaDB: mariadb_$DIR_MODIFIED
Contenedor Redis: $REDIS_CONTAINER_NAME
============================================
EOF

echo ""
echo "📝 Credenciales guardadas en: $PATH_INSTALL/$DIR.txt"

else
echo "❌ ERROR: La carpeta $PATH_INSTALL/proxy/fpms/$DIR ya existe"
echo "Si desea reinstalar, elimine primero las carpetas y volúmenes existentes:"
echo ""
echo "  # Carpetas del proyecto:"
echo "  rm -rf $PATH_INSTALL/proxy/fpms/$DIR"
echo "  rm -rf $PATH_INSTALL/$DIR"
echo ""
echo "  # Volúmenes Docker (IMPORTANTE: contienen la contraseña anterior de MariaDB):"
echo "  docker volume rm ${DIR_MODIFIED}_mysqldata${SERVICE_NUMBER} ${DIR_MODIFIED}_redisdata${SERVICE_NUMBER} 2>/dev/null || true"
echo ""
echo "  # O para listar todos los volúmenes existentes:"
echo "  docker volume ls | grep $DIR_MODIFIED"
exit 1
fi