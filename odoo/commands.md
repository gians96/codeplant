# Configuración del entorno para Odoo 18.0 con PostgreSQL y Node.js (Python 3.13)

git clone https://github.com/odoo/odoo.git

# Crear entorno virtual
python -m venv venv
.\venv\Scripts\Activate.ps1

# Instalar dependencias de Python (ORDEN CORRECTO)
pip install setuptools==68.0.0 wheel==0.37.1
pip install --only-binary=all lxml==6.0.1
pip install -r requirements.txt

# Instalar rl-renderPM funcional (ejecutar script personalizado)
.\install_rl_renderPM_final.ps1

# Base de datos PostgreSQL
docker run --name postgres-container-odoo -e POSTGRES_USER=uodoo -e POSTGRES_PASSWORD=uodoo -e POSTGRES_DB=bdodoo -p 5432:5432 -d postgres:17  

# Instalar dependencias de Node.js
npm install -g rtlcss

# Verificar que todo funciona
python odoo-bin --version

# Cargar la base de datos cuando no está inicializada
python odoo-bin -r uodoo -w uodoo --addons-path=addons -d bdodoo -i base

# Iniciar Odoo normalmente
python odoo-bin -r uodoo -w uodoo --addons-path=addons -d bdodoo

# Puerto para ejecutar Odoo
http://localhost:8069/

# Crear modulos
python odoo-bin scaffold school modules

# Ejecutar proyecto y que lea la carpeta de los modulos
python odoo-bin -r uodoo -w uodoo --addons-path=addons,modules -d bdodoo

# Instalar el modulo school directamente
python odoo-bin -r uodoo -w uodoo --addons-path=addons,modules -d bdodoo -i school

Activas el modo desarrollador y actualizas los modulos
``python odoo-bin -r uodoo -w uodoo --addons-path=addons,modules -d bdodoo --dev=reload,qweb,werkzeug,xml``