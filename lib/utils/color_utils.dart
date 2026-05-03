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
    (r * 255).round(),
    (g * 255).round(),
    (b * 255).round(),
    opacity,
  );
}

// 新增扩展方法，将已弃用的 withOpacity 替换为安全的实现
extension ColorExtension on Color {
  /// 安全地设置颜色的透明度，替代已弃用的 withOpacity
  Color withAlpha(double opacity) => Color.fromRGBO(
    (r * 255).round(),
    (g * 255).round(),
    (b * 255).round(),
    opacity,
  );
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

  /// 获取页面背景色
  ///
  /// 根据主题亮度返回合适的背景色：
  /// - 浅色模式：82%不透明度的surface叠加到白色上（更深一点）
  /// - 深色模式：使用原始surface颜色
  ///
  /// [surfaceColor] 主题的surface颜色
  /// [brightness] 当前主题亮度
  static Color getPageBackgroundColor(
    Color surfaceColor,
    Brightness brightness,
  ) {
    if (brightness == Brightness.dark) {
      return surfaceColor;
    }
    // 浅色模式：82%不透明的surface叠加到白色上，让背景更接近主题色
    return Color.alphaBlend(withOpacitySafe(surfaceColor, 0.82), Colors.white);
  }

  /// 获取卡片背景色（用于一言框等卡片）
  ///
  /// 根据主题亮度返回合适的卡片背景色：
  /// - 浅色模式：surface向白色方向混合8%，同步加深与页面背景保持配合
  /// - 深色模式：使用原始surface颜色
  ///
  /// [surfaceColor] 主题的surface颜色
  /// [brightness] 当前主题亮度
  static Color getCardBackgroundColor(
    Color surfaceColor,
    Brightness brightness,
  ) {
    if (brightness == Brightness.dark) {
      return surfaceColor;
    }
    // 浅色模式：surface向白色偏移8%，比页面背景稍深形成突出层次
    return Color.lerp(surfaceColor, Colors.white, 0.08) ?? surfaceColor;
  }

  /// 获取记录列表背景色
  ///
  /// 根据主题亮度返回合适的记录列表背景色：
  /// - 浅色模式：30%不透明度的surface叠加到白色上
  /// - 深色模式：使用较浅的灰色（提升可读性）
  ///
  /// [surfaceColor] 主题的surface颜色
  /// [brightness] 当前主题亮度
  static Color getNoteListBackgroundColor(
    Color surfaceColor,
    Brightness brightness,
  ) {
    if (brightness == Brightness.dark) {
      // 深色模式：使用较浅的灰色作为背景，与深色记录项形成对比
      return const Color(0xFF2A2A2A);
    }
    // 浅色模式：30%不透明的surface叠加到白色上，产生极浅的主题色背景
    return Color.alphaBlend(withOpacitySafe(surfaceColor, 0.3), Colors.white);
  }

  /// 获取搜索框背景色（比卡片更浅）
  ///
  /// 根据主题亮度返回合适的搜索框背景色：
  /// - 浅色模式：surface向白色方向混合4%，比一言框更浅与背景搭配
  /// - 深色模式：使用比surface稍浅的颜色
  ///
  /// [surfaceColor] 主题的surface颜色
  /// [brightness] 当前主题亮度
  static Color getSearchBoxBackgroundColor(
    Color surfaceColor,
    Brightness brightness,
  ) {
    if (brightness == Brightness.dark) {
      // 深色模式：比surface稍浅一点
      return Color.lerp(surfaceColor, Colors.white, 0.05) ?? surfaceColor;
    }
    // 浅色模式：surface向白色偏移4%，比一言框更浅，更好融入背景
    return Color.lerp(surfaceColor, Colors.white, 0.04) ?? surfaceColor;
  }
}
