//poner la semana id con "semana"
//poner las fecha con id "fecha"

let fecha = new Date(document.getElementById("fecha").value);
let semana = document.getElementById("semana").value;
function formatDate(date) {
  var d = new Date(date),
    month = "" + (d.getMonth() + 1),
    day = "" + d.getDate(),
    year = d.getFullYear();

  if (month.length < 2) month = "0" + month;
  if (day.length < 2) day = "0" + day;

  return [year, month, day].join("-");
}

function obtenerFecha() {
  var d = new Date(document.getElementById("fecha").value);
  d.setDate(d.getDate() + 1);
  return d;
}
function registrar() {
  setTimeout(() => {
    document.getElementById("guardar").click();
  }, 2000);
  setTimeout(() => {
    fecha.setDate(fecha.getDate() + 7);
    document.getElementById("fecha").value = formatDate(fecha);
    let semana = document.getElementById("exampleFormControlSelect1").value;
    semana++;
    document.getElementById("exampleFormControlSelect1").value = semana;
  }, 4000);
}
