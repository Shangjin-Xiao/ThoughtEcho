import 'package:flutter/material.dart';
import 'package:flex_color_scheme/flex_color_scheme.dart';
import '../utils/mmkv_ffi_fix.dart'; // 导入MMKV安全包装类
import 'package:thoughtecho/utils/app_logger.dart';

class AppTheme with ChangeNotifier {
  static const String _customColorKey = 'custom_color';
  static const String _useCustomColorKey = 'use_custom_color';
  static const String _themeModeKey = 'theme_mode';
  static const String _useDynamicColorKey = 'use_dynamic_color'; // 添加动态取色设置键

  SafeMMKV? _storage;
  Color? _customColor;
  bool _useCustomColor = false;
  bool _useDynamicColor = true; // 默认启用动态取色
  ColorScheme? _lightDynamicColorScheme;
  ColorScheme? _darkDynamicColorScheme;
  ThemeMode _themeMode = ThemeMode.system;
  bool _hasInitialized = false; // 添加标记，用于追踪是否已初始化

  // 全局圆角和阴影参数
  static const double cardRadius = 18;
  static const double dialogRadius = 24;
  static const double buttonRadius = 12;
  static const double inputRadius = 12;

  // 多层次阴影效果
  static const List<BoxShadow> defaultShadow = [
    BoxShadow(
      color: Color(0x14000000), // black08 equivalent
      blurRadius: 12,
      offset: Offset(0, 4),
      spreadRadius: -2,
    ),
    BoxShadow(
      color: Color(0x0A000000), // black04 equivalent
      blurRadius: 24,
      offset: Offset(0, 8),
      spreadRadius: -4,
    ),
  ];

  // 轻量级阴影（用于悬浮状态）
  static const List<BoxShadow> lightShadow = [
    BoxShadow(
      color: Color(0x0F000000), // black06 equivalent
      blurRadius: 8,
      offset: Offset(0, 2),
      spreadRadius: -1,
    ),
  ];

  // 悬停状态阴影（Material Design 悬浮效果）
  static const List<BoxShadow> hoverShadow = [
    BoxShadow(
      color: Color(0x1A000000), // black10 equivalent
      blurRadius: 16,
      offset: Offset(0, 6),
      spreadRadius: -2,
    ),
    BoxShadow(
      color: Color(0x0D000000), // black05 equivalent
      blurRadius: 32,
      offset: Offset(0, 12),
      spreadRadius: -6,
    ),
  ];

  // 强调状态阴影（用于激活或选中状态）
  static const List<BoxShadow> accentShadow = [
    BoxShadow(
      color: Color(0x1F000000), // black12 equivalent
      blurRadius: 20,
      offset: Offset(0, 8),
      spreadRadius: -4,
    ),
    BoxShadow(
      color: Color(0x14000000), // black08 equivalent
      blurRadius: 40,
      offset: Offset(0, 16),
      spreadRadius: -8,
    ),
  ];

  // 获取是否启用动态取色
  bool get useDynamicColor {
    // 只有在系统支持动态取色时才返回true
    if (_lightDynamicColorScheme == null && _darkDynamicColorScheme == null) {
      return false;
    }
    return _useDynamicColor;
  }

  // 获取当前亮色主题的颜色方案
  ColorScheme get lightColorScheme {
    if (_useCustomColor && _customColor != null) {
      // 直接使用用户选择的颜色，减少不必要的调整
      logDebug('使用自定义颜色(浅色模式): ${_customColor!.toARGB32().toRadixString(16)}');
      return ColorScheme.fromSeed(
        seedColor: _customColor!,
        brightness: Brightness.light,
      );
    }
    // 只有在启用动态取色且有可用的动态颜色方案时才使用
    if (_useDynamicColor && _lightDynamicColorScheme != null) {
      logDebug('使用动态颜色(浅色模式)');
      return _lightDynamicColorScheme!;
    }
    logDebug('使用默认蓝色(浅色模式)');
    return ColorScheme.fromSeed(
      seedColor: Colors.blue,
      brightness: Brightness.light,
    );
  }

  // 获取当前暗色主题的颜色方案
  ColorScheme get darkColorScheme {
    if (_useCustomColor && _customColor != null) {
      logDebug('使用自定义颜色(深色模式): ${_customColor!.toARGB32().toRadixString(16)}');
      // 使用Material Design规范的深色模式颜色生成
      final userColor = _customColor!;
      
      // 为深色模式优化用户颜色
      final primaryDark = _optimizeColorForDarkMode(userColor);
      final secondaryDark = _generateSecondaryColor(userColor, Brightness.dark);
      final tertiaryDark = _generateTertiaryColor(userColor, Brightness.dark);
      
      return ColorScheme.dark(
        primary: primaryDark,
        onPrimary: _getOnColor(primaryDark, Brightness.dark),
        primaryContainer: _generateContainerColor(primaryDark, Brightness.dark, 0.3),
        onPrimaryContainer: _getOnContainerColor(primaryDark, Brightness.dark),
        
        secondary: secondaryDark,
        onSecondary: _getOnColor(secondaryDark, Brightness.dark),
        secondaryContainer: _generateContainerColor(secondaryDark, Brightness.dark, 0.2),
        onSecondaryContainer: _getOnContainerColor(secondaryDark, Brightness.dark),
        
        tertiary: tertiaryDark,
        onTertiary: _getOnColor(tertiaryDark, Brightness.dark),
        tertiaryContainer: _generateContainerColor(tertiaryDark, Brightness.dark, 0.25),
        onTertiaryContainer: _getOnContainerColor(tertiaryDark, Brightness.dark),
        
        error: const Color(0xFFEF5350),
        onError: Colors.white,
        errorContainer: const Color(0xFF451A1A),
        onErrorContainer: const Color(0xFFFFCDD2),
        
        surface: const Color(0xFF000000), // 保持OLED友好的纯黑背景
        onSurface: const Color(0xFFF5F5F5), // 提高文本对比度和可读性
        surfaceContainerHighest: const Color(0xFF2A2A2A),
        surfaceContainerHigh: const Color(0xFF1F1F1F),
        surfaceContainerLowest: const Color(0xFF000000),
        onSurfaceVariant: const Color(0xFFE0E0E0), // 提高变体文本的可读性
        outline: const Color(0xFF4A4A4A), // 改进边框颜色对比度
        outlineVariant: const Color(0xFF3A3A3A), // 变体边框颜色
        shadow: const Color(0xFF000000),
        scrim: const Color(0xFF000000),
        surfaceBright: const Color(0xFF3A3A3A),
        surfaceDim: const Color(0xFF121212),
      );
    }

    if (_useDynamicColor && _darkDynamicColorScheme != null) {
      logDebug('使用动态颜色(深色模式)');
      return _darkDynamicColorScheme!;
    }

    logDebug('使用默认蓝色(深色模式)');
    return _buildModernDarkScheme();
  }

  // 为深色模式优化颜色
  Color _optimizeColorForDarkMode(Color color) {
    // 调整颜色以在深色背景上更好看，提高对比度和可读性
    HSLColor hsl = HSLColor.fromColor(color);
    
    // 在深色模式下，需要调整饱和度和亮度以确保更好的对比度
    final double adjustedSaturation = (hsl.saturation * 1.1 + 0.1).clamp(0.0, 1.0);
    final double adjustedLightness = (hsl.lightness * 0.7 + 0.15).clamp(0.0, 1.0);
    
    return hsl
        .withSaturation(adjustedSaturation)
        .withLightness(adjustedLightness)
        .toColor();
  }

  // 生成次色
  Color _generateSecondaryColor(Color primary, Brightness brightness) {
    HSLColor primaryHSL = HSLColor.fromColor(primary);
    if (brightness == Brightness.dark) {
      // 深色模式下，次色是主色的变体，保持协调性
      return primaryHSL.withHue(
        (primaryHSL.hue + 60) % 360  // 色相偏移60度
      ).withSaturation(
        (primaryHSL.saturation * 0.7).clamp(0.0, 1.0)
      ).withLightness(
        (primaryHSL.lightness * 0.6 + 0.2).clamp(0.0, 1.0)
      ).toColor();
    } else {
      return primaryHSL.withLightness(
        (primaryHSL.lightness * 0.7 + 0.15).clamp(0.0, 1.0)
      ).toColor();
    }
  }

  // 生成第三色
  Color _generateTertiaryColor(Color primary, Brightness brightness) {
    HSLColor primaryHSL = HSLColor.fromColor(primary);
    if (brightness == Brightness.dark) {
      // 深色模式下，第三色也基于主色但有不同的色相
      return primaryHSL.withHue(
        (primaryHSL.hue + 120) % 360  // 色相偏移120度
      ).withSaturation(
        (primaryHSL.saturation * 0.6).clamp(0.0, 1.0)
      ).withLightness(
        (primaryHSL.lightness * 0.6 + 0.25).clamp(0.0, 1.0)
      ).toColor();
    } else {
      return primaryHSL.withHue(
        (primaryHSL.hue + 120) % 360
      ).toColor();
    }
  }

  // 生成容器颜色
  Color _generateContainerColor(Color baseColor, Brightness brightness, double alpha) {
    if (brightness == Brightness.dark) {
      // 深色模式下创建合适的容器颜色
      return baseColor.withValues(alpha: alpha);
    } else {
      return baseColor.withValues(alpha: alpha);
    }
  }

  // 获取在指定颜色上的文本颜色
  Color _getOnColor(Color backgroundColor, Brightness brightness) {
    if (brightness == Brightness.dark) {
      // 深色模式下的文本颜色策略：更精确的对比度计算
      final double luminance = backgroundColor.computeLuminance();
      if (luminance > 0.6) {
        return Colors.black; // 非常亮的背景使用纯黑文本
      } else if (luminance > 0.3) {
        return Colors.black87; // 亮背景使用深灰文本
      } else if (luminance > 0.15) {
        return Colors.grey.shade800; // 中等亮度背景使用中性色
      } else if (luminance > 0.05) {
        return Colors.grey.shade200; // 较暗背景使用浅色文本
      } else {
        return Colors.white; // 非常暗背景使用纯白文本
      }
    } else {
      // 浅色模式下的文本颜色策略
      final double luminance = backgroundColor.computeLuminance();
      if (luminance > 0.7) {
        return Colors.black; // 非常亮的背景使用黑色文本
      } else if (luminance > 0.4) {
        return Colors.black87; // 亮背景使用深灰文本
      } else if (luminance > 0.15) {
        return Colors.grey.shade800; // 中等亮度背景使用中性色
      } else {
        return Colors.white; // 暗背景使用白色文本
      }
    }
  }

  // 获取容器上的文本颜色
  Color _getOnContainerColor(Color containerColor, Brightness brightness) {
    if (brightness == Brightness.dark) {
      // 深色模式下，容器颜色通常比较亮，使用更精细的颜色选择逻辑
      final double luminance = containerColor.computeLuminance();
      if (luminance > 0.7) {
        return Colors.black; // 非常亮的容器使用纯黑文本
      } else if (luminance > 0.4) {
        return Colors.black87; // 亮容器使用深灰文本
      } else if (luminance > 0.2) {
        return Colors.grey.shade800; // 中等亮度容器使用中性色
      } else if (luminance > 0.1) {
        return Colors.grey.shade300; // 较暗容器使用浅灰文本
      } else {
        return Colors.white; // 非常暗容器使用纯白文本
      }
    } else {
      // 浅色模式下的容器文本颜色策略
      final double luminance = containerColor.computeLuminance();
      if (luminance > 0.8) {
        return Colors.black; // 非常亮的容器使用黑色文本
      } else if (luminance > 0.5) {
        return Colors.black87; // 亮容器使用深灰文本
      } else if (luminance > 0.2) {
        return Colors.grey.shade800; // 中等亮度容器使用中性色
      } else {
        return Colors.white; // 暗容器使用白色文本
      }
    }
  }

  // 现代深色方案 - OLED优化设计，提高对比度和可读性
  ColorScheme _buildModernDarkScheme() {
    // 使用OLED友好的纯黑背景，节省电量，同时确保良好的对比度
    return ColorScheme.dark(
      primary: const Color(0xFF64B5F6), // 更柔和的蓝色，保持足够对比度
      onPrimary: const Color(0xFF000000), // 纯黑文本，在亮背景上清晰可见
      primaryContainer: const Color(0xFF1E3A5F), // 更深的蓝色容器，确保文字可读性
      onPrimaryContainer: const Color(0xFFB3E5FC), // 浅色文本，在深蓝背景上清晰
      
      secondary: const Color(0xFF81C784), // 柔和的绿色，在深色背景下可见
      onSecondary: const Color(0xFF000000), // 纯黑文本
      secondaryContainer: const Color(0xFF1B3E23), // 深绿色容器
      onSecondaryContainer: const Color(0xFFCCFFCC), // 浅色文本，在深绿背景上清晰
      
      tertiary: const Color(0xFFCE93D8), // 柔和的紫色，保持良好的视觉效果
      onTertiary: const Color(0xFF000000), // 纯黑文本
      tertiaryContainer: const Color(0xFF3D1944), // 深紫色容器，确保对比度
      onTertiaryContainer: const Color(0xFFE1BEE7), // 浅色文本，在深紫背景上清晰
      
      error: const Color(0xFFEF5350), // 柔和的红色，在深色背景下可见
      errorContainer: const Color(0xFF451A1A), // 深红色容器，提高对比度
      onError: const Color(0xFF000000), // 纯黑文本
      onErrorContainer: const Color(0xFFFFCDD2), // 浅色文本，在深红背景上清晰
      
      surface: const Color(0xFF000000), // 纯黑背景 - OLED优化
      onSurface: const Color(0xFFF5F5F5), // 改进的浅色文本，提高对比度和可读性
      surfaceContainerHighest: const Color(0xFF2A2A2A), // 改进的几乎纯黑的表面，更好的层次感
      surfaceContainerHigh: const Color(0xFF1F1F1F), // 改进的非常深的深灰，提高对比度
      surfaceContainerLowest: const Color(0xFF000000), // 纯黑表面
      onSurfaceVariant: const Color(0xFFE0E0E0), // 改进的变体文本，提高可读性
      
      outline: const Color(0xFF4A4A4A), // 改进的边框颜色，提供更好的视觉分离
      outlineVariant: const Color(0xFF3A3A3A), // 变体边框颜色
      
      shadow: const Color(0xFF000000), // 纯黑阴影
      scrim: const Color(0xFF000000), // 纯黑幕布
      
      surfaceBright: const Color(0xFF3A3A3A), // 改进的亮表面，提供更好的层次感
      surfaceDim: const Color(0xFF121212), // 改进的暗表面，确保足够对比度
    );
  }

  bool get useCustomColor => _useCustomColor;
  Color? get customColor => _customColor;
  ThemeMode get themeMode => _themeMode;

  // 强制刷新主题，确保所有UI组件正确更新
  void forceRefreshTheme() {
    logDebug(
        '强制刷新主题: 自定义颜色=$_useCustomColor, 动态取色=$_useDynamicColor, 主题模式=$_themeMode');
    notifyListeners();
  }

  /// 检查当前主题是否为深色模式（考虑系统偏好）
  bool isCurrentlyDarkMode(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    if (_themeMode == ThemeMode.dark) return true;
    if (_themeMode == ThemeMode.light) return false;
    return brightness == Brightness.dark;
  }

  /// 获取适合深色模式的增强颜色
  /// 提供深色模式下更好的对比度和可读性
  Color getEnhancedDarkModeColor(BuildContext context, Color baseColor) {
    final isDark = isCurrentlyDarkMode(context);
    if (!isDark) return baseColor;

    // 深色模式下对颜色进行优化
    HSLColor hsl = HSLColor.fromColor(baseColor);
    return hsl
        .withSaturation((hsl.saturation * 1.1).clamp(0.0, 1.0))
        .withLightness((hsl.lightness * 0.8 + 0.2).clamp(0.0, 1.0))
        .toColor();
  }

  // 判断当前是否为深色模式
  bool get isDarkMode {
    // 仅根据用户显式选择返回，ThemeMode.system 的实际亮度应由外部通过 MediaQuery/Theme.of 来判断；
    // 这里返回一个“偏好”状态：只有显式设为 dark 才视为 true。
    if (_themeMode == ThemeMode.dark) return true;
    if (_themeMode == ThemeMode.light) return false;
    // system 模式下不做武断判断，交给使用方基于上下文判断；提供一个保守值 false
    return false;
  }

  // 获取适合当前主题的文本颜色
  Color getTextColor(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return brightness == Brightness.dark ? Colors.white : Colors.black87;
  }

  // 获取适合当前主题的次要文本颜色
  Color getSecondaryTextColor(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return brightness == Brightness.dark ? Colors.white70 : Colors.black54;
  }

  // 初始化主题服务
  Future<void> initialize() async {
    if (_hasInitialized) return; // 防止重复初始化

    try {
      _storage = SafeMMKV();
      await _storage!.initialize();
      _loadCustomColor();
      _loadThemeMode();

      // 首次运行时，不读取存储的设置，保持默认开启
      if (_storage!.containsKey(_useDynamicColorKey)) {
        _loadDynamicColorSettings();
      } else {
        // 首次运行，设置默认值
        await _storage!.setBool(_useDynamicColorKey, true);
        _useDynamicColor = true; // 确保内存中的值也同步更新
      }

      _hasInitialized = true;
      logDebug(
        '主题服务初始化完成: 使用自定义颜色=$_useCustomColor, 使用动态取色=$_useDynamicColor, 主题模式=$_themeMode',
      );
    } catch (e) {
      logDebug('初始化主题服务失败: $e');
      // 初始化失败时使用默认值
      _customColor = Colors.blue;
      _useCustomColor = false;
      _useDynamicColor = true;
      _themeMode = ThemeMode.system;
    }
  }

  // 更新动态颜色方案
  void updateDynamicColorScheme(
    ColorScheme? lightScheme,
    ColorScheme? darkScheme,
  ) {
    bool changed = false;

    // 直接使用系统提供的动态颜色方案，不进行紫色过滤
    ColorScheme? processedLightScheme = lightScheme;
    ColorScheme? processedDarkScheme = darkScheme;

    // 更新动态颜色方案
    if (_lightDynamicColorScheme != processedLightScheme) {
      _lightDynamicColorScheme = processedLightScheme;
      changed = true;
    }

    if (_darkDynamicColorScheme != processedDarkScheme) {
      _darkDynamicColorScheme = processedDarkScheme;
      changed = true;
    }

    // 检查系统是否支持动态取色
    bool systemSupportsDynamicColor =
        (processedLightScheme != null || processedDarkScheme != null);

    // 如果系统不支持动态取色，我们仍然保持用户的 _useDynamicColor 设置不变。
    // useDynamicColor getter 会处理实际的颜色方案回退。
    // 这样，即使用户的设备暂时无法获取动态颜色，他们"启用动态取色"的偏好设置仍然保留。
    // 当设备后续能够获取动态颜色时，应用将自动采用。
    if (!systemSupportsDynamicColor && _useDynamicColor) {
      // 仅在调试时打印信息，不再修改 _useDynamicColor 或持久化状态
      logDebug('系统不支持动态取色，但用户已启用动态取色。将使用回退颜色方案。');
      // changed 标志不需要在这里设置，因为 _useDynamicColor 的状态没有改变
      // 颜色方案的实际变化由 lightColorScheme/darkColorScheme getter 处理
    }

    // 如果系统支持动态取色，但用户之前因为不支持而被设置为false，
    // 并且他们最初的意图是使用动态取色（例如，通过存储中的_useDynamicColorKey判断），
    // 此时可以考虑是否要自动重新启用。但为了简单和可预测性，
    // 用户的显式设置（通过UI开关）应该优先。
    // 目前的逻辑是：如果用户在UI上启用了动态取色，即使之前获取失败，
    // 只要现在获取成功，就会使用动态颜色。

    // 只在实际发生变化时通知监听器
    if (changed) {
      notifyListeners();
    }
  }

  // 设置自定义颜色
  Future<void> setCustomColor(Color color) async {
    _customColor = color;
    await _storage?.setInt(
      _customColorKey,
      color.toARGB32(),
    ); // MODIFIED (reverted as .value is correct for ARGB)
    notifyListeners();
  }

  // 切换是否使用自定义颜色
  Future<void> setUseCustomColor(bool value) async {
    _useCustomColor = value;
    await _storage?.setBool(_useCustomColorKey, value);
    notifyListeners();
  }

  // 设置主题模式
  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await _storage?.setString(_themeModeKey, mode.name);
    notifyListeners();
  }

  // 设置是否使用动态取色
  Future<void> setUseDynamicColor(bool value) async {
    _useDynamicColor = value;
    await _storage?.setBool(_useDynamicColorKey, value);
    notifyListeners();
  }

  // 从持久化存储加载自定义颜色设置
  void _loadCustomColor() {
    try {
      final colorValue = _storage?.getInt(_customColorKey);
      if (colorValue != null) {
        _customColor = Color(
          colorValue,
        ); // This is correct for reconstructing Color from ARGB int
      }
      _useCustomColor = _storage?.getBool(_useCustomColorKey) ?? false;
    } catch (e) {
      logDebug('加载自定义颜色失败: $e');
      _customColor = Colors.blue;
      _useCustomColor = false;
    }
  }

  // 从持久化存储加载主题模式
  void _loadThemeMode() {
    try {
      final modeString = _storage?.getString(_themeModeKey);
      if (modeString != null) {
        _themeMode = ThemeMode.values.byName(modeString);
      }
    } catch (e) {
      logDebug('加载主题模式失败: $e');
      _themeMode = ThemeMode.system;
    }
  }

  // 从持久化存储加载动态取色设置
  void _loadDynamicColorSettings() {
    try {
      final useDynamic = _storage?.getBool(_useDynamicColorKey);
      if (useDynamic != null) {
        _useDynamicColor = useDynamic;
      }
    } catch (e) {
      logDebug('加载动态取色设置失败: $e');
      _useDynamicColor = true; // 默认启用
    }
  }

  // 创建亮色主题数据
  ThemeData createLightThemeData() {
    final baseTheme = FlexThemeData.light(
      colorScheme: lightColorScheme,
      useMaterial3: true,
      surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
      blendLevel: 1, // 极低混合级别，使颜色非常接近白色
      subThemesData: const FlexSubThemesData(
        blendOnLevel: 2, // 极低表面颜色混合级别
        blendOnColors: true,
        useMaterial3Typography: true,
        useM2StyleDividerInM3: true,
        alignedDropdown: true,
        useInputDecoratorThemeInDialogs: true,
        interactionEffects: true,
        tintedDisabledControls: true,
        elevatedButtonSchemeColor: SchemeColor.primary,
        elevatedButtonSecondarySchemeColor: SchemeColor.onPrimary,
        cardRadius: cardRadius,
        inputDecoratorRadius: inputRadius,
        dialogRadius: dialogRadius,
        timePickerDialogRadius: dialogRadius,
        outlinedButtonRadius: buttonRadius,
        filledButtonRadius: buttonRadius,
        textButtonRadius: buttonRadius,
        fabRadius: buttonRadius,
      ),
      keyColors: const FlexKeyColors(useSecondary: true, useTertiary: true),
      tones: FlexTones.material(Brightness.light),
      visualDensity: FlexColorScheme.comfortablePlatformDensity,
    );

    // 使用主题色系的浅色调，确保颜色一致性
    final colorScheme = baseTheme.colorScheme;

    return baseTheme.copyWith(
      // 使用主题色系的极浅背景色
      scaffoldBackgroundColor: colorScheme.surface,

      // 对话框使用主题色系
      dialogTheme: baseTheme.dialogTheme.copyWith(
        backgroundColor: colorScheme.surfaceContainerLowest,
      ),

      // 卡片使用主题色系
      cardTheme: baseTheme.cardTheme.copyWith(
        color: colorScheme.surfaceContainerLowest,
      ),

      // 底部表单使用主题色系
      bottomSheetTheme: baseTheme.bottomSheetTheme.copyWith(
        backgroundColor: colorScheme.surfaceContainerLowest,
      ),

      // 抽屉使用主题色系
      drawerTheme: baseTheme.drawerTheme.copyWith(
        backgroundColor: colorScheme.surface,
      ),

      // AppBar使用稍深的主题色调，增强标题区分度
      appBarTheme: baseTheme.appBarTheme.copyWith(
        backgroundColor: colorScheme.surfaceContainerLow,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: baseTheme.appBarTheme.titleTextStyle?.copyWith(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w600, // 增强标题字重
          fontSize: 20, // 适当增大字号
        ),
      ),

      // 导航栏使用主题色系
      navigationBarTheme: baseTheme.navigationBarTheme.copyWith(
        backgroundColor: colorScheme.surfaceContainerLowest,
      ),

      // 浮动操作按钮使用主题色系
      floatingActionButtonTheme: baseTheme.floatingActionButtonTheme.copyWith(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
      ),

      // 列表项目使用透明背景，以继承Card的颜色
      listTileTheme: baseTheme.listTileTheme.copyWith(
        tileColor: Colors.transparent,
      ),
    );
  }

  // 创建深色主题数据 - 重新设计
  ThemeData createDarkThemeData() {    // 获取实际使用的颜色方案（包含自定义颜色）
    final actualColorScheme = darkColorScheme;
    
    // 直接使用 ThemeData 避免 FlexThemeData 的颜色干扰
    final baseTheme = ThemeData(
      useMaterial3: true,
      colorScheme: actualColorScheme,
      brightness: Brightness.dark,
    );
    
    // 确保使用完整的自定义颜色方案
    final colorScheme = actualColorScheme;

    return baseTheme.copyWith(
      // 使用OLED友好的纯黑背景
      scaffoldBackgroundColor: colorScheme.surface,

      // 对话框使用接近黑色的深色
      dialogTheme: baseTheme.dialogTheme.copyWith(
        backgroundColor: colorScheme.surfaceContainerHighest,
      ),

      // 卡片使用接近黑色的深色
      cardTheme: baseTheme.cardTheme.copyWith(
        color: colorScheme.surfaceContainerLowest,
        elevation: 1, // 降低阴影以配合深色背景
      ),

      // 底部表单使用接近黑色的深色
      bottomSheetTheme: baseTheme.bottomSheetTheme.copyWith(
        backgroundColor: colorScheme.surfaceContainerHighest,
      ),

      // 抽屉使用纯黑背景
      drawerTheme: baseTheme.drawerTheme.copyWith(
        backgroundColor: colorScheme.surface,
      ),

      // AppBar使用接近黑色的深色
      appBarTheme: baseTheme.appBarTheme.copyWith(
        backgroundColor: colorScheme.surfaceContainerHigh,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        titleTextStyle: baseTheme.appBarTheme.titleTextStyle?.copyWith(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w600,
          fontSize: 20,
        ),
      ),

      // 导航栏使用纯黑背景
      navigationBarTheme: baseTheme.navigationBarTheme.copyWith(
        backgroundColor: colorScheme.surface,
      ),

      // 浮动操作按钮使用主色
      floatingActionButtonTheme: baseTheme.floatingActionButtonTheme.copyWith(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        elevation: 6,
      ),

      // 列表项目使用透明背景
      listTileTheme: baseTheme.listTileTheme.copyWith(
        tileColor: Colors.transparent,
      ),

      // 按钮主题优化
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primaryContainer,
          foregroundColor: colorScheme.onPrimaryContainer,
          elevation: 2,
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.primary,
          side: BorderSide(color: colorScheme.outline, width: 1.5),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colorScheme.primary,
        ),
      ),

      // 输入框主题优化
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(inputRadius),
          borderSide: BorderSide(color: colorScheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(inputRadius),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(inputRadius),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(inputRadius),
          borderSide: BorderSide(color: colorScheme.error),
        ),
      ),

      // Switch主题优化
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith<Color>((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.primary;
          }
          return colorScheme.onSurfaceVariant;
        }),
        trackColor: WidgetStateProperty.resolveWith<Color>((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.primaryContainer;
          }
          return colorScheme.surfaceContainerHighest;
        }),
      ),

      // 进度条主题优化
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colorScheme.primary,
        linearTrackColor: colorScheme.surfaceContainerHighest,
        circularTrackColor: Colors.transparent,
      ),
    );
  }
}
