import 'dart:io';

import 'package:dart_application_1/IceCream.dart';
import 'package:dart_application_1/dart_application_1.dart'
    as dart_application_1;

void main(List<String> arguments) {
  var chocolate = Icecream();
  chocolate.flavor = "Chocolate";
  chocolate.charge();
}

void exampleFunction() {
  var name = "Gianmarcos";
  var age = 31;
  var total = 10 + 0.5;

  name = "Otro nombre";
  var isActive = true;

  print(
    'Hola Mundo desde Dart          ' +
        name +
        age.toString() +
        total.toString() +
        isActive.toString(),
  );

  //Interpolación
  print('Hola Mundo desde Dart $name $age $total $isActive');

  //Declaracion de variables con tipos primitivos
  String lastName = "Apellido";
  int year = 1992;
  double height = 1.75;
  bool isMarried = false;

  print(
    'Hola $name $lastName, naciste en $year, mides $height mts y tu estado civil es: $isMarried',
  );

  // Declaracion de constantes
  const pi = 3.1416; // se evalúa en tiempo de compilación
  print(pi);
  //tipos finales
  final String country = "Perú"; // se evalúa en tiempo de ejecución
  print(country.trim());
  print(country.toUpperCase());

  //Declaracion de variables dinámicas
  dynamic variable = "Hola";
  print(variable);
  variable = 100;
  print(variable);
  variable = true;
  print(variable);

  //Conversiones

  String number = "123";
  int parsedNumber = int.parse(number);
  print("El numero es $parsedNumber");

  int numerToString = 456;
  String convertedString = numerToString.toString();
  print("El numero convertido es $convertedString");

  String toDoubleString = "12.34";
  double parsedDouble = double.parse(toDoubleString);
  print("El numero double es $parsedDouble");

  //Declaracion de listas
  List<String> fruits = ['Manzana', 'Banana', 'Naranja'];
  print(fruits);
  fruits.add('Mango');
  print(fruits);
  fruits.length;
  fruits.removeAt(0);
  print(fruits);

  var vegetables = ["Lechuga", "Tomate", "Zanahoria"];
  print(vegetables);
  vegetables.add("Pepino");
  vegetables.length;
  vegetables.addAll(fruits);

  vegetables.remove("Tomate");
  vegetables.removeAt(1);
  vegetables[2] = "Aguacate";
  vegetables.insert(8, " Cebolla");

  Set<String> uniqueFruits = {'Manzana', 'Banana', 'Naranja'};
  uniqueFruits.add('Banana'); // No se añadirá, ya que es un conjunto
  print(uniqueFruits);
  uniqueFruits.clear(); // Elimina todos los elementos del conjunto
  uniqueFruits.contains(
    "Manzana",
  ); // Devuelve true si el conjunto contiene el elemento

  //Declaracion de mapas
  Map<String, dynamic> person = {
    'name': 'Gianmarcos',
    'age': 31,
    'isActive': true,
  };
  print(person);

  // Acceso a los valores del mapa
  print(person['name']);
  print(person['age']);
  print(person['isActive']);

  // listas de objetos
  List<Map<String, dynamic>> people = [
    {'name': 'Gianmarcos', 'age': 31},
    {'name': 'Ana', 'age': 25},
    {'name': 'Luis', 'age': 28},
  ];
  print(people);
  // Acceso a los valores de la lista de objetos
  print(people[0]['name']);
  print(people[1]['age']);
  // busqueda de un objeto en la lista
  var personFound = people.firstWhere((person) => person['name'] == 'Ana');
  print(personFound);
  print(personFound['name']);

  int a = 2;

  a++;
  print(a);
  a += 3;
  print(a);
  print("Suma despues de la linea ${a++}");
  print("Suma antes de la linea ${++a}");

  /*Comentario*/
  // Otra forma de imprimir
  if (age > 18) {
    print("El usuario es mayor de edad");
  } else {
    print("El usuario no es mayor de edad");
  }
  // Operador ternario
  (age > 18)
      ? print("El usuario es mayor de edad")
      : print("El usuario no es mayor de edad");

  for (var i = 0; i < 5; i++) {
    print(i);
  }
  print("Introduce el dia de la semana (1-7):");
  int semana = int.parse(stdin.readLineSync()!);
  switch (semana) {
    case 1:
      print("Lunes");
      break;
    case 2:
      print("Martes");
      break;
    case 3:
      print("Miércoles");
      break;
    case 4:
      print("Jueves");
      break;
    case 5:
      print("Viernes");
      break;
    case 6:
      print("Sábado");
      break;
    case 7:
      print("Domingo");
      break;
    default:
      print("Número de día inválido");
  }
  // grreting("Gianmarcos");
  optionalParameters("firstName");
  optionalName(0, age: 25);
}

void grreting(String name) {
  print("Hola $name");
}

int calculate() {
  return 6 * 7;
}

String getWelcomeMessage(String name) {
  return "Bienvenido $name";
}

bool isEven(int number) {
  return number % 2 == 0;
}

/*diferencia entre los dos tipos de parámetros opcionales con {} y []
//es que los parámetros con {} son parámetros con nombre,
// lo que significa que al llamar a la función, se debe especificar el nombre del parámetro.
//Mientras que los parámetros con [] son parámetros posicionales opcionales,
//lo que significa que se deben proporcionar en el orden en que se definen en la función.
 Parámetros opcionales
 */
String optionalParameters(String firstName, [String? lastName]) {
  if (lastName != null) {
    return "Hola $firstName $lastName";
  } else {
    return "Hola $firstName";
  }
}

// Parámetros con nombre y valores por defecto
String optionalName(int unused, {String name = "Desconocido", int age = -1}) {
  return "Hola $name, tu edad es $age";
}

// Parámetros con nombre obligatorios
String optionalRequired({required String name, required int age}) {
  return "Hola $name, tu edad es $age";
}

int suma(int a, int b) => a + b;

void mapExample() {
  Map<String, int> scores = {'Alice': 90, 'Bob': 85, 'Charlie': 92};

  print(scores['Alice']); // Acceder a un valor por su clave
  scores['David'] = 88; // Agregar un nuevo par clave-valor
  scores.update(
    'Bob',
    (value) => 95,
  ); // Actualizar el valor asociado a una clave existente
  scores.remove('Charlie'); // Eliminar un par clave-valor

  scores.addAll({
    'Eve': 91,
    'Frank': 87,
  }); // Agregar múltiples pares clave-valor

  print(scores.values); // Obtener todas las claves
  print(scores.keys); // Obtener todos los valores
  print("---");
  print(scores.entries); // Obtener todas las entradas (pares clave-valor)

  scores.containsKey('Alice'); // Verificar si una clave existe
  scores.containsValue(90); // Verificar si un valor existe
  // scores.forEach((name, score) {
  //   print('$name: $score');
  // });
  scores.clear(); // Eliminar todos los pares clave-valor
}

void listLoop() {
  List<int> numbers = [1, 2, 3, 4, 5];
  for (var number in numbers) {
    print(number);
  }

  for (var i = 0; i < numbers.length; i++) {
    print(numbers[i]);
  }

  // numbers.forEach((number) {
  //   print(number);
  // });
}

void mapLoop() {
  Map<String, int> numbers = {
    'one': 1,
    'two': 2,
    'three': 3,
    'four': 4,
    'five': 5,
  };

  for (var entry in numbers.entries) {
    print('${entry.key}: ${entry.value}');
  }

  numbers.forEach((key, value) {
    print('$key: $value');
  });
}

void setLoop() {
  Set<int> numbers = {1, 2, 3, 4, 5};

  for (var number in numbers) {
    print(number);
  }

  for (var i = 0; i < numbers.length; i++) {
    print(numbers.elementAt(i));
  }

  numbers.forEach(print);
}

void nullability() {
  String? nullableString = "Nombre";
  nullableString = "";
  nullableString = null;
  if (nullableString != null) {
    print("Hola $nullableString");
    //print(nullableString?.length); // Usando el operador de acceso seguro
  }

  // String noNullString = nullableString!; // se usa el operador de aserción nula
  // print("Hola $noNullString");

  //Mejor poner un operador por si es null
  print("Hola ${nullableString ?? "Invitado"}");
  nullableString ??= "Invitado"; // Operador de asignación nula

  int? example = 13;
  example = null;
  print(example ?? 0); // Operador de coalescencia nula
}
