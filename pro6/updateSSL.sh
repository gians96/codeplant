#!/bin/bash

HOST=${1:-'dominio'}
if [ "$HOST" = "dominio" ]; then
    echo no ha ingresado dominio, vuelva a ejecutar el script agregando un dominio como primer parametro
    exit 1
fi

certbot certonly --manual -d *.$HOST -d $HOST --agree-tos --no-bootstrap --manual-public-ip-logging-ok --preferred-challenges dns-01 --server https://acme-v02.api.letsencrypt.org/directory

cp /etc/letsencrypt/live/nt-suite.pro/privkey.pem /var/certs/nt-suite.pro.key
cp /etc/letsencrypt/live/nt-suite.pro/cert.pem /var/certs/nt-suite.pro.crt

docker restart proxy_proxy_1
