class Icecream {
  String flavor = "Desconocido";
  double price = 4.99;
  bool sugarFree = false;
  String size = "Medium";

  Icecream({
    this.flavor = "Desconocido",
    this.price = 4.99,
    this.size = "Medium",
    this.sugarFree = false, // Named optional parameter with default value
  }); // Constructor with named optional parameter

  void charge() {
    print(
      "El precio del helado de sabor ${flavor} es \$${price} del tamaño ${size}",
    );
  }
}
