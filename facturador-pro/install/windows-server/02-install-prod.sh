#!/bin/bash
#
# 02-install-prod.sh — Facturador Pro-8: Instalacion de produccion en WSL2
#
# Fase 2 del proceso de instalacion en Windows Server.
# Ejecutar DENTRO de WSL despues de completar 01-setup-wsl.ps1
#
# Uso:
#   curl -O https://raw.githubusercontent.com/gians96/codeplant/master/facturador-pro/install/windows-server/02-install-prod.sh
#   chmod +x 02-install-prod.sh
#   sudo ./02-install-prod.sh
#
# Features:
#   - Proxy reverso nginx (rash07/nginx-proxy:4.0) para multi-proyecto
#   - SSL wildcard con certbot (manual DNS challenge)
#   - Deteccion automatica de puertos MySQL libres
#   - Multi-proyecto (service number > 1)
#   - OPcache + JIT para maximo rendimiento
#   - Credenciales aleatorias
#

set -e

REPO_URL="https://gitlab.com/gians96/pro-8.git"
VERSION_PHP_IMAGE="8.2"
DB_FOLDER="seeders"
SCHEDULING="scheduling:8.2"
SUPERVISOR="supervisor-php:8.2"

# ─── Funciones auxiliares ─────────────────────────────────────

find_free_mysql_port() {
    local start_port=${1:-3001}
    local max_port=3999

    for port in $(seq $start_port $max_port); do
        if ! netstat -tuln 2>/dev/null | grep -q ":$port " && ! docker ps -a 2>/dev/null | grep -q "$port->3306"; then
            echo $port
            return 0
        fi
    done

    echo "ERROR: No se encontro puerto MySQL libre entre $start_port y $max_port" >&2
    return 1
}

list_occupied_ports() {
    echo "=== PUERTOS MYSQL ACTUALMENTE OCUPADOS ==="
    docker ps -a 2>/dev/null | grep mariadb | awk '{print $1, $NF}' | while read id name; do
        port=$(docker port $id 2>/dev/null | grep 3306 | head -1 | awk -F':' '{print $2}' | cut -d'-' -f1)
        if [ ! -z "$port" ]; then
            printf "  %-6s -> %s\n" "$port" "$name"
        fi
    done | sort -n
    echo "==========================================="
}

gen_password() {
    head /dev/urandom | tr -dc A-Za-z0-9 | head -c 20 ; echo ''
}

# ─── Verificar que estamos en WSL ─────────────────────────────
if ! grep -qi microsoft /proc/version 2>/dev/null; then
    echo "ADVERTENCIA: Este script esta disenado para ejecutarse dentro de WSL2."
    echo "Si estas en un servidor Linux nativo, usa install.sh en su lugar:"
    echo "  curl -O https://raw.githubusercontent.com/gians96/codeplant/master/facturador-pro/install/linux/install.sh"
    read -p "Continuar de todos modos? [s/N]: " cont
    if [ "$cont" != "s" ] && [ "$cont" != "S" ]; then
        exit 0
    fi
fi

# ─── Verificar Docker ─────────────────────────────────────────
# En WSL2 con Docker Desktop, el cliente puede heredar el contexto
# 'desktop-linux' (endpoint npipe de Windows), que rompe dentro de Linux
# con: "Failed to initialize: protocol not available" o panic del CLI.
# Fix: forzar contexto 'default' que apunta a unix:///var/run/docker.sock.
if ! docker info >/dev/null 2>&1; then
    echo "Docker no responde. Probando arreglo de contexto WSL..."
    docker context use default >/dev/null 2>&1 || true
    sleep 1
fi
if ! docker info >/dev/null 2>&1; then
    echo "Docker no esta corriendo. Intentando iniciar servicio nativo..."
    sudo service docker start 2>/dev/null || true
    sleep 3
    if ! docker info >/dev/null 2>&1; then
        echo "ERROR: No se pudo conectar con Docker."
        echo "  - Si usas Docker Desktop: activa WSL Integration y reinicia Docker Desktop"
        echo "  - Si usas Docker Engine nativo: sudo service docker start"
        echo "  - Luego en WSL: docker context use default"
        exit 1
    fi
fi
echo "Docker OK"

# ═════════════════════════════════════════════════════════════
#  PREGUNTAS AL USUARIO
# ═════════════════════════════════════════════════════════════
echo ""
echo "============================================"
echo "  FACTURADOR PRO-8 — Instalacion Produccion"
echo "  (Windows Server / WSL2)"
echo "============================================"
echo ""

# DOMINIO
read -p "Coloca tu dominio (ej: mi-empresa.com): " HOST
if [ -z "$HOST" ]; then
    echo "No ha ingresado dominio, vuelva a ejecutar el script"
    exit 1
fi

# SERVICE NUMBER
read -p "Numero de servicio [1 si es la primera instalacion]: " SERVICE_NUMBER
if [ -z "$SERVICE_NUMBER" ]; then
    SERVICE_NUMBER="1"
fi

# PUERTO MYSQL — Deteccion automatica
SUGGESTED_PORT=$((3000 + $SERVICE_NUMBER))

echo ""
list_occupied_ports
echo ""

if netstat -tuln 2>/dev/null | grep -q ":$SUGGESTED_PORT " || docker ps -a 2>/dev/null | grep -q "$SUGGESTED_PORT->3306"; then
    echo "ADVERTENCIA: El puerto $SUGGESTED_PORT (calculado: 3000 + $SERVICE_NUMBER) ya esta OCUPADO"

    FREE_PORT=$(find_free_mysql_port $SUGGESTED_PORT)

    if [ $? -eq 0 ]; then
        echo "Puerto libre encontrado: $FREE_PORT"
        read -p "Desea usar el puerto $FREE_PORT? [S/n]: " use_auto_port

        if [ "$use_auto_port" = "n" ] || [ "$use_auto_port" = "N" ]; then
            read -p "Ingrese manualmente el puerto MySQL (3001-3999): " manual_port
            if netstat -tuln 2>/dev/null | grep -q ":$manual_port " || docker ps -a 2>/dev/null | grep -q "$manual_port->3306"; then
                echo "ERROR: El puerto $manual_port tambien esta ocupado."
                exit 1
            fi
            MYSQL_PORT_HOST=$manual_port
        else
            MYSQL_PORT_HOST=$FREE_PORT
        fi
    else
        echo "ERROR: No se encontro un puerto libre automaticamente."
        exit 1
    fi
else
    echo "Puerto $SUGGESTED_PORT esta disponible"
    MYSQL_PORT_HOST=$SUGGESTED_PORT
fi

echo ""
echo "Puerto MySQL seleccionado: $MYSQL_PORT_HOST"
echo ""
sleep 2

# ═════════════════════════════════════════════════════════════
#  VARIABLES
# ═════════════════════════════════════════════════════════════

# Ruta de instalacion — ext4 nativo en WSL (HOME del usuario)
PATH_INSTALL="$HOME/proyectos"
mkdir -p "$PATH_INSTALL"

DIR=$(echo $HOST)
DIR_MODIFIED=$(echo "$DIR" | sed 's/\./_/g')

# Datos MySQL
MYSQL_USER=$(echo "$DIR" | sed 's/\./_/g')
MYSQL_PASSWORD=$(gen_password)
MYSQL_DATABASE=$(echo "$DIR" | sed 's/\./_/g')
MYSQL_ROOT_PASSWORD=$(gen_password)

# Redis
REDIS_CONTAINER_NAME="redis_${DIR_MODIFIED}"

# ═════════════════════════════════════════════════════════════
#  PRIMER SERVICIO: instalar paquetes base + proxy
# ═════════════════════════════════════════════════════════════

if [ "$SERVICE_NUMBER" = '1' ]; then
    echo "Actualizando sistema"
    apt-get -y update
    apt-get -y upgrade

    echo "Instalando paquetes necesarios"
    apt-get -y install git-core net-tools

    echo "Instalando letsencrypt"
    apt-get -y install letsencrypt
    mkdir -p $PATH_INSTALL/certs/

    echo "Configurando proxy"
    docker network create proxynet 2>/dev/null || true
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

# ═════════════════════════════════════════════════════════════
#  CLONAR Y CONFIGURAR PROYECTO
# ═════════════════════════════════════════════════════════════

if ! [ -d $PATH_INSTALL/proxy/fpms/$DIR ]; then
    echo "Clonando repositorio"
    rm -rf "$PATH_INSTALL/$DIR"
    git clone "$REPO_URL" "$PATH_INSTALL/$DIR"

    mkdir -p $PATH_INSTALL/proxy/fpms/$DIR

    # ─── Nginx config para proxy ─────────────────────────────
    cat << EOF > $PATH_INSTALL/proxy/fpms/$DIR/default
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

    # Headers de seguridad
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    # Cache de assets estaticos
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires 30d;
        add_header Cache-Control "public, immutable";
        access_log off;
    }

    error_page 404 /index.php;
    location ~ /\.ht {
        deny all;
    }
}
EOF

    # ─── Dockerfile para Nginx (config baked-in, sin bind mount) ──
    cat << 'EOFNGINXDF' > $PATH_INSTALL/proxy/fpms/$DIR/Dockerfile
FROM rash07/nginx
RUN rm -f /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default
COPY default /etc/nginx/sites-available/default
RUN ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default
EOFNGINXDF

    # ─── docker-compose.yml ──────────────────────────────────
    cat << EOF > $PATH_INSTALL/$DIR/docker-compose.yml
version: '3'

services:
    nginx_$SERVICE_NUMBER:
        build:
            context: $PATH_INSTALL/proxy/fpms/$DIR
            dockerfile: Dockerfile
        container_name: nginx_$DIR_MODIFIED
        working_dir: /var/www/html
        environment:
            VIRTUAL_HOST: $HOST, *.$HOST
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
        command: redis-server --appendonly yes --maxmemory 256mb --maxmemory-policy allkeys-lru
        volumes:
            - redisdata$SERVICE_NUMBER:/data
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

    # ─── .env ────────────────────────────────────────────────
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
    sed -i '/APP_ENV=/c\APP_ENV=production' .env

    # CACHE_DRIVER=file es CRITICO — redis_tenancy rompe CLI
    sed -i '/CACHE_DRIVER=/c\CACHE_DRIVER=file' .env
    sed -i '/QUEUE_CONNECTION=/c\QUEUE_CONNECTION=redis' .env
    sed -i "/REDIS_HOST=/c\REDIS_HOST=$REDIS_CONTAINER_NAME" .env
    sed -i '/REDIS_PASSWORD=/c\REDIS_PASSWORD=null' .env
    sed -i '/REDIS_PORT=/c\REDIS_PORT=6379' .env

    # ─── DatabaseSeeder con usuario admin ────────────────────
    ADMIN_PASSWORD=$(gen_password)
    echo "Configurando archivo para usuario administrador"
    mv "$PATH_INSTALL/$DIR/database/$DB_FOLDER/DatabaseSeeder.php" "$PATH_INSTALL/$DIR/database/$DB_FOLDER/DatabaseSeeder.php.bk"

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

    # ─── Dockerfiles con OPcache (validate_timestamps=0) ─────
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

    # ─── Levantar containers ─────────────────────────────────
    echo "Configurando proyecto"
    docker compose up -d --build

    echo "Esperando que MariaDB este listo..."
    for i in {1..60}; do
        if docker compose exec -T mariadb_$SERVICE_NUMBER mysqladmin ping -h"localhost" -uroot -p"$MYSQL_ROOT_PASSWORD" &> /dev/null; then
            echo "MariaDB esta listo"
            break
        fi
        echo "Esperando MariaDB... ($i/60)"
        sleep 2
    done

    echo "Esperando que Redis este listo..."
    for i in {1..30}; do
        if docker compose exec -T redis_$SERVICE_NUMBER redis-cli ping &> /dev/null; then
            echo "Redis esta listo"
            break
        fi
        echo "Esperando Redis... ($i/30)"
        sleep 1
    done

    echo "Esperando que los contenedores esten listos..."
    sleep 10

    docker compose exec -T fpm_$SERVICE_NUMBER rm -f composer.lock
    docker compose exec -T fpm_$SERVICE_NUMBER composer self-update
    docker compose exec -T fpm_$SERVICE_NUMBER composer install --no-dev --optimize-autoloader

    echo "Ejecutando migraciones y seeds..."
    docker compose exec -T fpm_$SERVICE_NUMBER php artisan migrate:refresh --seed --force

    docker compose exec -T fpm_$SERVICE_NUMBER php artisan key:generate
    docker compose exec -T fpm_$SERVICE_NUMBER php artisan storage:link
    docker compose exec -T fpm_$SERVICE_NUMBER git checkout .
    docker compose exec -T fpm_$SERVICE_NUMBER git config --global core.fileMode false

    rm $PATH_INSTALL/$DIR/database/$DB_FOLDER/DatabaseSeeder.php
    mv $PATH_INSTALL/$DIR/database/$DB_FOLDER/DatabaseSeeder.php.bk $PATH_INSTALL/$DIR/database/$DB_FOLDER/DatabaseSeeder.php

    # ─── Optimizar Laravel ───────────────────────────────────
    echo "Optimizando Laravel (caches + autoload)..."
    docker compose exec -T fpm_$SERVICE_NUMBER php artisan config:cache
    # IMPORTANTE: NO usar route:cache — hyn/multi-tenant necesita evaluar rutas
    # dinamicamente por hostname en cada request
    docker compose exec -T fpm_$SERVICE_NUMBER php artisan route:clear
    docker compose exec -T fpm_$SERVICE_NUMBER php artisan event:cache
    docker compose exec -T fpm_$SERVICE_NUMBER sh -c "cd /var/www/html && composer dump-autoload --classmap-authoritative 2>&1" | tail -1

    # ─── Permisos ────────────────────────────────────────────
    # El repo ya trae storage/app/tenancy/tenants y demas subcarpetas.
    # El chmod -R 777 garantiza que tanto root (comandos artisan) como
    # www-data (worker php-fpm) puedan escribir en todo storage.
    echo "Configurando permisos"
    chmod -R 777 "$PATH_INSTALL/$DIR/storage/" "$PATH_INSTALL/$DIR/bootstrap/"
    if [ -d "$PATH_INSTALL/$DIR/vendor/" ]; then
        chmod -R 777 "$PATH_INSTALL/$DIR/vendor/"
    fi
    if [ -f "$PATH_INSTALL/$DIR/script-update.sh" ]; then
        chmod +x $PATH_INSTALL/$DIR/script-update.sh
    fi

    # ─── Supervisor ──────────────────────────────────────────
    echo "Esperando que supervisor este listo..."
    sleep 5

    echo "Configurando Supervisor"
    docker compose exec -T supervisor_$SERVICE_NUMBER service supervisor start 2>/dev/null || true
    docker compose exec -T supervisor_$SERVICE_NUMBER supervisorctl reread 2>/dev/null || true
    docker compose exec -T supervisor_$SERVICE_NUMBER supervisorctl update 2>/dev/null || true
    docker compose exec -T supervisor_$SERVICE_NUMBER supervisorctl start all 2>/dev/null || true

    # ─── Instalar pro8up (reinicio seguro del stack tras reboot WSL2) ──
    # En WSL2 + Docker Desktop, tras reiniciar Windows los contenedores
    # pueden levantar (restart: always) ANTES de que WSL monte $HOME.
    # El bind mount ./ → /var/www/html queda apuntando a un directorio
    # vacio y nginx devuelve 404/502 para todos los dominios.
    # 'pro8up' hace `compose down && up -d` de proxy + todos los proyectos
    # una vez que el filesystem ya esta disponible. Idempotente.
    RESTART_SCRIPT="$PATH_INSTALL/pro8-prod-restart.sh"
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    SOURCE_RESTART="$SCRIPT_DIR/pro8-prod-restart.sh"
    if [ -f "$SOURCE_RESTART" ]; then
        cp "$SOURCE_RESTART" "$RESTART_SCRIPT"
    else
        # Fallback: descargar del repo (cuando el script se ejecuta con curl)
        curl -fsSL -o "$RESTART_SCRIPT" \
            "https://raw.githubusercontent.com/gians96/codeplant/master/facturador-pro/install/windows-server/pro8-prod-restart.sh" \
            2>/dev/null || true
    fi
    if [ -f "$RESTART_SCRIPT" ]; then
        chmod +x "$RESTART_SCRIPT"
        BASHRC="${HOME}/.bashrc"
        if [ -f "$BASHRC" ] && ! grep -q "alias pro8up=" "$BASHRC"; then
            {
                echo ""
                echo "# pro-8: reinicio seguro del stack tras reboot (WSL2 + Docker Desktop)"
                echo "alias pro8up='bash ${RESTART_SCRIPT}'"
            } >> "$BASHRC"
            echo "Alias 'pro8up' instalado en ~/.bashrc"
        fi
    fi

    # ─── Arranque automatico (systemd) ──────────────────────
    # Instala /etc/systemd/system/pro8-autostart.service para recrear el
    # stack despues de cada reinicio de Windows. Idempotente: no reinstala
    # si ya existe el unit.
    AUTOSTART_SRC="$SCRIPT_DIR/enable-autostart.sh"
    if [ ! -f /etc/systemd/system/pro8-autostart.service ]; then
        if [ ! -f "$AUTOSTART_SRC" ]; then
            curl -fsSL -o /tmp/enable-autostart.sh \
                "https://raw.githubusercontent.com/gians96/codeplant/master/facturador-pro/install/windows-server/enable-autostart.sh" \
                2>/dev/null && AUTOSTART_SRC=/tmp/enable-autostart.sh
        fi
        if [ -f "$AUTOSTART_SRC" ]; then
            echo "Configurando arranque automatico del stack (systemd)..."
            SUDO_USER="${SUDO_USER:-$(whoami)}" bash "$AUTOSTART_SRC" || \
                echo "ADVERTENCIA: no se pudo activar el arranque automatico (continuo sin abortar)"
        fi
    else
        echo "✓ Arranque automatico ya configurado (pro8-autostart.service)"
    fi

    # ─── SSL ─────────────────────────────────────────────────
    read -p "Instalar SSL gratuito? si[s] no[n]: " ssl
    if [ "$ssl" = "s" ]; then

        echo "--IMPORTANTE--"
        echo "--------------"
        echo "Copiar los TXT sin usar [ctrl+c] ya que cancelara el proceso"
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

            # Reiniciar proxy para que cargue los certs
            echo "Buscando contenedor proxy..."
            PROXY_CONTAINER=$(docker ps --filter "ancestor=rash07/nginx-proxy:4.0" --format "{{.Names}}" | head -1)

            if [ -z "$PROXY_CONTAINER" ]; then
                PROXY_CONTAINER=$(docker ps | grep -E "proxy.*proxy" | awk '{print $NF}' | head -1)
            fi

            if [ ! -z "$PROXY_CONTAINER" ]; then
                echo "Reiniciando proxy: $PROXY_CONTAINER"
                docker restart $PROXY_CONTAINER
                echo "Proxy reiniciado correctamente"
            else
                echo "No se encontro contenedor proxy para reiniciar"
                echo "Verifica manualmente con: docker ps | grep proxy"
            fi
        fi
    fi

    # ─── Resumen ─────────────────────────────────────────────
    echo ""
    echo "=============================================="
    echo "INSTALACION COMPLETADA EXITOSAMENTE"
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
    echo "=============================================="

    # Credenciales en archivo
    cat << EOF > $PATH_INSTALL/$DIR.txt
============================================
DATOS DE INSTALACION - $HOST
Generado: $(date '+%Y-%m-%d %H:%M')
============================================
Ruta del proyecto: $PATH_INSTALL/$DIR
URL: http://$HOST
Correo administrador: admin@$HOST
Contrasena administrador: $ADMIN_PASSWORD
----------------------------------------------
Acceso remoto a MySQL
Puerto: $MYSQL_PORT_HOST
Host: $(hostname -I 2>/dev/null | awk '{print $1}')
Usuario: root
Contrasena root: $MYSQL_ROOT_PASSWORD
----------------------------------------------
Redis
Host: $REDIS_CONTAINER_NAME
Puerto: 6379
Password: null
----------------------------------------------
Service Number: $SERVICE_NUMBER
Version PHP: $VERSION_PHP_IMAGE
Contenedor FPM: fpm_$DIR_MODIFIED
Contenedor MariaDB: mariadb_$DIR_MODIFIED
Contenedor Redis: $REDIS_CONTAINER_NAME
============================================

Para entrar al proyecto:
  wsl -d Ubuntu-24.04
  cd $PATH_INSTALL/$DIR

Para levantar/reiniciar:
  cd $PATH_INSTALL/$DIR
  docker compose up -d

Tras reiniciar el PC (WSL2): ejecuta en una terminal WSL nueva:
  pro8up
Esto recrea proxy + todos los proyectos para que los bind mounts
se re-resuelvan contra el filesystem ya montado.
EOF

    echo ""
    echo "Credenciales guardadas en: $PATH_INSTALL/$DIR.txt"

    # Append a data-config.txt si existe en el directorio del script
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    DATA_CONFIG="$SCRIPT_DIR/data-config.txt"
    if [ -f "$DATA_CONFIG" ]; then
        cat << EOF >> $DATA_CONFIG

# ============================================
# FASE 2 — Proyecto: $HOST
# Instalado: $(date '+%Y-%m-%d %H:%M')
# ============================================
URL: http://$HOST
Admin: admin@$HOST
Admin Password: $ADMIN_PASSWORD
MySQL Puerto: $MYSQL_PORT_HOST
MySQL Root Password: $MYSQL_ROOT_PASSWORD
Ruta: $PATH_INSTALL/$DIR
Service Number: $SERVICE_NUMBER
EOF
        echo "data-config.txt actualizado"
    fi

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
