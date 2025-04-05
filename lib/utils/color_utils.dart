import 'package:flutter/material.dart';

MaterialColor createMaterialColor(Color color) {
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
    swatch[index] = Color.fromARGB(
      255,
      r + ((ds < 0 ? r : (255 - r)) * ds).round(),
      g + ((ds < 0 ? g : (255 - g)) * ds).round(),
      b + ((ds < 0 ? b : (255 - b)) * ds).round(),
    );
  }

  // 特别确保150色阶存在，这是secondaryColor常用的值
  if (!swatch.containsKey(150)) {
    swatch[150] = Color.fromARGB(
      255,
      (r * 0.85).round(),
      (g * 0.85).round(),
      (b * 0.85).round(),
    );
  }

  return MaterialColor(color.value, swatch);
}

Color adjustColor(Color color) {
  // 使用 color.value 替代 toARGB32
  final int newValue = color.value;
  return Color(newValue);
}

// 新增扩展方法，将 withOpacity 替换为 applyOpacity
extension ColorExtension on Color {
  Color applyOpacity(double opacity) {
    return Color.fromRGBO(red, green, blue, opacity);
  }
}
