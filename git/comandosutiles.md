# Comandos Útiles de Git

## Configuración de Repositorios

### Visualizar la URL del repositorio
```bash
git remote -v
```

### Cambiar la ruta del repositorio
```bash
git remote set-url origin https://gitlab.com/otro_usuario/otro_repositorio.git
```

## Trabajar con Ramas

### Descargar rama remota de un repositorio
```bash
# Listar todas las ramas (locales y remotas)
git branch -a

# Descargar y hacer checkout de una rama específica
git pull origin [namebranch]
```

## Inicializar un Nuevo Repositorio

### Crear un repositorio desde cero
```bash
git init
git add README.md
git commit -m "first commit"
git branch -M main
git remote add origin https://github.com/gians96/template-api-rest-ts.git
git push -u origin main
```