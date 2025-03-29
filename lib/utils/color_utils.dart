import 'package:flutter/material.dart';

MaterialColor createMaterialColor(Color color) {
  // 确保color不为null，如果为null则使用默认蓝色
  color = color ?? Colors.blue;
  
  List strengths = <double>[.05];
  Map<int, Color> swatch = <int, Color>{};
  final int r = color.red, g = color.green, b = color.blue;

  for (int i = 1; i < 10; i++) {
    strengths.add(0.1 * i);
  }
  
  // 确保所有关键色阶都被定义，特别是150
  for (var strength in strengths) {
    final double ds = 0.5 - strength;
    final int index = (strengths.indexOf(strength) * 100) + 50;
    swatch[index] = Color.fromRGBO(
      r + ((ds < 0 ? r : (255 - r)) * ds).round(),
      g + ((ds < 0 ? g : (255 - g)) * ds).round(),
      b + ((ds < 0 ? b : (255 - b)) * ds).round(),
      1,
    );
  }
  
  // 特别确保150色阶存在，这是secondaryColor常用的值
  if (!swatch.containsKey(150)) {
    swatch[150] = Color.fromRGBO(
      (r * 0.85).round(),
      (g * 0.85).round(),
      (b * 0.85).round(),
      1,
    );
  }
  
  return MaterialColor(color.value, swatch);
}