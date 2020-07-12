para iniciar un nuevo proyecto solo se realiza una vez
git init
-----------------
git add [nombrearchivo]    ( se puede decir de esta manera o de todos los archivos mediante)
git add .               (marca todos los archivos para guardar)

para que los archivos no tomen encuenta algunas  librerias que siempre se usa y que no
debemos subir al repo por cuestiones de version, librerias cambios etc se crea un archivo llamado
.gitignorete archivo le pasamos el nombre de la carpeta a ignorar

--------------------------
git status -s
muestra a los estados de los archivos add en para su envio al local
--------------------------
git commit -m "mensaje"  
es par aenviar al repo local de todos los archivos marcados con el comando git add 
es necesario poner un mensaje o comentario de los cambios que se ha realizado

NOTA si hemos olvidado hacer un cambio y ya habiamos puesto un commit podemos usar
git commit --amend
-------------------------
git
Creamos un nuevo repositorio en la nube en esta caso sera en github lo cuales pasamos el parametro
de todas maneras esta parte esta en el mismo repositorio de github al momento de crearlo
git remote add origin https://github.com/gians96/b-node-example.git
--------------------------

para enviar al repositorio de github
git push -u origin master

-------------------------
la segunda vez para enviar a github
git push 
git pull        comparar archivos en github y trae archivos en nuestro archivos locales
------------------------ 
TAG
Tag para versionar  nuestra app cuando llegue a un punto en especifico de desarrollo
git tag ver1.0 -m "Version 1.0"

para subir el tag en git hub
git push --tags
---------------------------------
para ver en console lo que se ha echo en nuestro historial de cambios
git log --oneline

muestra archivos que han sido modificado
git diff
---------------------------------
para pasar ir al momento del cambio en el historial de cambios mediante este comando
git reset --hard [el codigo mostrado en log --oneline]
git reset [el codigo mostrado en log --oneline]    elimina el commit realizado



-------------------------------------------------------------
BRANCH

lineas de tiempo paralela que despues queremos juntar
--------------------------------------------------------------
git branch (muestra las ramas que existen y el * muestra en que rama estamos trabajando)
git branch [nombreramba] (crea una nueva rama )
git checkout [nombre de la rama creada] (vamos a seleccionar la rama para poder trabajar en ella)

para simplimicar el numero de comandos se utiliza estossss

git checkout -b [nombrerama] (crea la rama y selecciona)

para renombrar el nombre de una rama

git branch -m [nombreramaantes] [nombreramadespues]

git branch -a nos muestra tanto las ramas locales como las remotas

para eliminar una rama

git branch -d [nombrerama]
-----------------------
HEROKU
-----------------------
trabajar con heroku es un ambiente o servidor establecido para publicar nuestro proyectos

para iniciar neceistamos instalar heroku cli descargar la misma pagina
(reinicar)
lo siguiente es el comando
heroku login

de alli establecer en que proyecto se va a guardar en heroku, donde ya previamente abremos creado uno.
 para establecer la ruta de conexicon
heroku git:remote -a [nombre del proyecto]

con esto podremos mandar lo ya contenido en el commit local

git push heroku master

modificacion new branch1

nuevmodi gigit new-sdasdasranch2
x

git log --oneline --decorate --graph --all