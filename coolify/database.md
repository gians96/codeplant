# Create a database expose it to the web

Para crear podemos ir a coolify en la ruta de https://domain.com/projects, escoges tu proyecto y luego agregas un nuevo recurso (+New), en el buscador buscamos la base de datos correspondiente y creamos una nueva base de datos.
En la configuracion de la base de datos ponemos lo siguiente en General:
1. Name: Name del recurso (esta puede ser un Gestor de base de datos compartida)
2. Image: Escogemos la imagen(version) de la base de datos que queremos usar
3. Normal user: Usuario que se usara para la conexion a la base de datos (para la base de datos que se creara, mas no acceso a todo el gestor de base de datos), tambien dentro de la red de docker se puede usar este usuario para acceder a la base de datos  
4. Initial Database : Nombre de la base de datos que se creara, y solo el usuario "Normal user" podra acceder a ella
5. Network > Ports Mappings : Puerto de la base de datos expuesta al exterior y puerto dentro del docker, por ejemplo 3306:3306
6. Network > MySQL URL (internal): URL de la base de datos, por ejemplo `mysql://[usuario]:[contraseña]@[rutadockerdondesencuentra]:3306[puerto]/coolify[basedatos]`


