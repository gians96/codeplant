
# Configurar OAuth

Tenemos varios proveedores de autenticacion, por ejemplo google,  github, etc, para cada uno de ellos hay que crear una aplicacion en la plataforma de OAuth, y luego configurar la aplicacion en el PaaS, entre ellas:
1. Google
2. Github
3. Azure

## 1. Google OAuth2.0

1. Si tenemos una cuenta en firebase, podemos usar la misma, si no, creamos una cuenta en firebase
2. Habilitamos el servicio de Authentication
3. En **Metodo de acceso** agregamos un nuevo provedor `Google`
4. Nos vamos al desplegable de **Configuración del SDK web**, en el simbolo de interrogación nos va a redirigir a esta pagina `https://console.developers.google.com/apis/credentials`.
5. En **IDs de clientes de OAuth 2.0** Escogemos la opcion que nos a creado en mi caso es `Web client (auto created by Google Service)` lo selecciono
6. En **Orígenes autorizados de JavaScript** agregamos una URI, que es la url de nuestro PaaS `https://coolify.domain.com`
7. En **URIs de redireccionamiento autorizados** agregamos la url de nuestro PaaS `https://coolify.domain.com/auth/google/callback` 
8. Luego copiamos el **ID de cliente** y el **secreto del cliente**
9. En la aplicacion de coolify, en la ruta de `https://coolify.domain.com/settings/oauth` vamos a ubicar nuestro proveedor y ponemos los datos que nos hemos obtenido en el paso anterior

