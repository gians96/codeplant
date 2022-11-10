#Para visualizar el url del repositorio
git remote -v

#Cambiar la ruta del repositorio
git remote set-url origin https://gitlab.com/otro_usuario/otro_repositorio.git

Descargar rama remota de una repo
git branch -a
git pull origin [namebranch]




### Nuevo git
git init
git add README.md
git commit -m "first commit"
git branch -M main
git remote add origin https://github.com/gians96/template-api-rest-ts.git
git push -u origin main