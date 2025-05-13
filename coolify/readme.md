# Install and coolify on Ubuntu 24.04


### Minimum Hardware Requirements Minimal installation of coolify
- CPU: 2 cores
- Memory (RAM): 2 GB
- Storage: 30 GB of free space

```
apt update
apt upgrade
```


# First install docker
## Set up Docker's apt repository.

```
## Add Docker's official GPG key:
sudo apt-get update
sudo apt-get install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

## Add the repository to Apt sources:
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
```

## Install the Docker packages.
```
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

## Run the installation script coolify will use to install docker.
```
curl -fsSL https://cdn.coollabs.io/coolify/install.sh | bash
```

### Tienes que habilitar ciertos puertos del firewall:
(obligatorio)
1. 8000(http), 
2. 6001(websocket), 
3. 6002(terminal) y 
4. 22(SSH, o un puerto personalizado) 

o haciendo lo siguiente:
```
sudo ufw allow 8000
sudo ufw allow 6001
sudo ufw allow 6002
sudo ufw allow 22
```

Otros
1.Proxy inverso: 80, 443(opcional)

o haciendo lo siguiente:
```
sudo ufw allow 80
sudo ufw allow 443
```

Ahora se puede acceder desde la url http://[IP_SERVIDOR]:8000/

1. Crear un usuario administrador(nombre, email, contraseña)
2. Si estas desplegando el PaaS en tu propio servidor, debes escoger en local
3. Nos vamos a /settings y cambiar el nombre de dominio a la que quieras que se llame tu PaaS (ejemplo: https://coolify.com , para forzar a el ssl se debe poner https:// al principio)
4. Si quieres que se redireccion a www a tu dominio, debes apuntar en tu gestor de dominios a la direccion https://coolify.com
5. En /server vamos a usar el willcard * para que las aplicaciones que se desplieguen en el PaaS puedan acceder con un subdominio personalizado como https://subdominio.coolify.com en el campo de "Wildcard Domain": ponemos https://coolify.com (con el https para forzar el ssl)
6. Se puede activar el sentinel para ver metricas de uso de la plataforma