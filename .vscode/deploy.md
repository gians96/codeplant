INSTALL HEROKU

Hacer el ultimo commmit y despues crear el build


npm run build
npm run start

//estos son las variables de entornos que remplazan a los .env
heroku config:set HOST=0.0.0.0
heroku config:set NODE_ENV=production