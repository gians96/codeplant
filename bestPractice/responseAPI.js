res.status(200).send({ status: "OK", data: { msg: "" } });

res.status(400).send({ status: "FAILED", data: { msg: "" } }); //no existe usuario, page, ruta
res.status(400).send({ status: "DANGER", data: { msg: "" } });//error del servidor, no ha podido realizarse 


