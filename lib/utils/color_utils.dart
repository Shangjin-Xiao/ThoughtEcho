import 'package:flutter/material.dart';

MaterialColor createMaterialColor(Color color) {
  List strengths = <double>[.05];
  Map<int, Color> swatch = <int, Color>{};
  final int r = (color.r * 255).round(),
      g = (color.g * 255).round(),
      b = (color.b * 255).round();

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

  return MaterialColor(color.toARGB32(), swatch); // 使用 toARGB32() 替代 value
}

Color adjustColor(Color color) {
  // 使用 toARGB32 替代 color.value
  final int newValue = color.toARGB32(); // 使用 toARGB32() 替代 value
  return Color(newValue);
}

// 新增扩展方法，将 withOpacity 替换为 applyOpacity
extension ColorValueExtension on Color {
  Color applyOpacity(double opacity) => Color.fromRGBO(
      (r * 255).round(), (g * 255).round(), (b * 255).round(), opacity);
}

// 新增扩展方法，将已弃用的 withOpacity 替换为安全的实现
extension ColorExtension on Color {
  /// 安全地设置颜色的透明度，替代已弃用的 withOpacity
  Color withAlpha(double opacity) => Color.fromRGBO(
      (r * 255).round(), (g * 255).round(), (b * 255).round(), opacity);
}

/// 颜色工具类
class ColorUtils {
  /// 安全地设置颜色的透明度
  ///
  /// 替代已弃用的Color.withOpacity方法
  /// 参数opacity应该在0.0到1.0之间
  static Color withOpacitySafe(Color color, double opacity) {
    // 确保opacity在有效范围内
    opacity = opacity.clamp(0.0, 1.0);

    // 创建带有新alpha值的颜色
    return color.withValues(alpha: opacity);
  }

  /// 页面 / 卡片 / 记录页 / 搜索框这四张自绘表面的取值**已经搬到
  /// `AppSurfaceTokens`**（`lib/theme/theme_style.dart`），不要在这里重新加回来。
  ///
  /// 原因：这里的算法是围绕 M3 生成色板写的（拿 surface 往白色兑、暗色写死一块
  /// 中性灰），手工色板本来就把「纸」和「卡片」两档色值给全了，兑出来的结果既不
  /// 等于色板的卡片色，暗色下更是把整套纸色换成了与色板无关的灰。表面色必须随
  /// 色板下发，两处各算一遍一定会再次走岔。material 的那套算法原样保留在
  /// `AppSurfaceTokens.fromScheme` 里，像素不变。
}
