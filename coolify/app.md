
# Configuración de una aplicacion y despliegue

Para crear una aplicacion, vamos a la ruta de `https://domain.com/project` y escogemos el proyecto que queremos desplegar, luego vamos a la pestaña **"Apps"** y pulsamos en **"New App"**. Para
Escogemos de nuestro repositorio de github la opcion

Tenemos la opcion de un github privado o publico, para aplicaciones de:
1. Nuxt
2. Express
3. Nestjs


## 1. Aplicacion de Nuxt

### General

1. **Name(*):**&emsp;&emsp;&emsp;Nombre de la aplicacion 
2. **Build Pack(*):**&emsp;Nixpacks
3. **Domains(*):**  &emsp;   `https://[app].coolify.com/` (ponemos el https:// para forzar el ssl y el subdominio)
4. **Direction:**&emsp;&emsp;Podemos escoger opcion para redirect a www o no

### Docker Registry
###### no informations 

### Build

1. **Install Command:** si modificas esto, usas el nixpacks

```	bash
npm install
```

2. **Build Command:** Hace el Build de la aplicacion
```	bash
npm run build
```

3. **Start Command:** Ejecuta la aplicacion
```	bash
node .output/server/index.mjs
```

## 2. Aplicacion de Express(nodejs)

#### No olvidar de agregar la `.env` que son las variables de entorno, la base de datos crea un usuario y una ruta de red interna en el docker, la cual se puede usar para el uso local dentro de la aplicacion

### General

1. **Name(*):**&emsp;&emsp;&emsp;API SIJE
2. **Build Pack(*):**&emsp;Nixpacks
3. **Domains(*):**&emsp;&emsp;`https://[api-sije].coolify.com/` (ponemos el https:// para forzar el ssl y el subdominio)
4. **Direction:**&emsp;&emsp;Podemos escoger opcion para redirect a www o no

### Docker Registry
###### *no information*

### Build

1. **Install Command:** si modificas esto, usas el nixpacks

```	bash
npm install
```

2. **Build Command:** Hace el Build de la aplicacion
```	bash
npx prisma migrate deploy && npx prisma generate && npm run build
```

3. **Start Command:** Ejecuta la aplicacion
```	bash
node ./dist/app.js
```