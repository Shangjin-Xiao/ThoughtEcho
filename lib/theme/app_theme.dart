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
      // 使用自定义颜色时，确保在浅色模式下也不会产生紫色调
      final colorScheme = ColorScheme.fromSeed(
        seedColor: _customColor!,
        brightness: Brightness.light,
      );

      // 如果生成的颜色方案包含明显的紫色调，进行调整
      if (_hasPurpleTint(colorScheme.primary)) {
        // 使用更安全的颜色生成方式，避免紫色调
        return ColorScheme.fromSeed(
          seedColor: _customColor!,
          brightness: Brightness.light,
          // 强制使用更保守的调色策略
        ).copyWith(
          // 确保主要颜色不会太偏紫
          primary: _adjustPurpleTint(_customColor!, Brightness.light),
          secondary: _adjustPurpleTint(_customColor!, Brightness.light)
              .withValues(alpha: 0.8),
          tertiary: _adjustPurpleTint(_customColor!, Brightness.light)
              .withValues(alpha: 0.6),
        );
      }

      return colorScheme;
    }
    // 只有在启用动态取色且有可用的动态颜色方案时才使用
    if (_useDynamicColor && _lightDynamicColorScheme != null) {
      return _lightDynamicColorScheme!;
    }
    return ColorScheme.fromSeed(
      seedColor: Colors.blue,
      brightness: Brightness.light,
    );
  }

  // 获取当前暗色主题的颜色方案
  ColorScheme get darkColorScheme {
    if (_useCustomColor && _customColor != null) {
      // 使用自定义颜色时，确保在深色模式下不会产生紫色调
      final colorScheme = ColorScheme.fromSeed(
        seedColor: _customColor!,
        brightness: Brightness.dark,
      );

      // 如果生成的颜色方案包含明显的紫色调，进行调整
      if (_hasPurpleTint(colorScheme.primary)) {
        // 使用更安全的颜色生成方式，避免紫色调
        return ColorScheme.fromSeed(
          seedColor: _customColor!,
          brightness: Brightness.dark,
          // 强制使用更保守的调色策略
        ).copyWith(
          // 确保主要颜色不会太偏紫
          primary: _adjustPurpleTint(_customColor!, Brightness.dark),
          secondary: _adjustPurpleTint(_customColor!, Brightness.dark)
              .withValues(alpha: 0.8),
          tertiary: _adjustPurpleTint(_customColor!, Brightness.dark)
              .withValues(alpha: 0.6),
        );
      }

      return colorScheme;
    }
    // 只有在启用动态取色且有可用的动态颜色方案时才使用
    if (_useDynamicColor && _darkDynamicColorScheme != null) {
      return _darkDynamicColorScheme!;
    }
    return ColorScheme.fromSeed(
      seedColor: Colors.blue,
      brightness: Brightness.dark,
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

  // 判断颜色是否包含明显的紫色调
  bool _hasPurpleTint(Color color) {
    final hsl = HSLColor.fromColor(color);
    // 紫色在色相环上的范围大约是270-330度
    // 另外，饱和度高的紫色也可能有问题
    final hue = hsl.hue;
    final saturation = hsl.saturation;

    // 如果色相在紫色范围内且饱和度较高，认为是紫色调
    if ((hue >= 270 && hue <= 330) && saturation > 0.3) {
      return true;
    }

    // 另外检查RGB值，如果蓝色分量明显高于红色和绿色，也可能是紫色调
    if (color.b > color.r * 1.2 &&
        color.b > color.g * 1.2 &&
        saturation > 0.2) {
      return true;
    }

    return false;
  }

  // 调整紫色调的颜色，使其更适合深色主题
  Color _adjustPurpleTint(Color color, Brightness brightness) {
    final hsl = HSLColor.fromColor(color);

    if (_hasPurpleTint(color)) {
      // 如果是紫色调，将其调整为更安全的颜色
      // 降低饱和度或改变色相
      final adjustedHue = (hsl.hue + 30) % 360; // 向蓝色方向调整
      final adjustedSaturation = hsl.saturation * 0.7; // 降低饱和度

      return HSLColor.fromAHSL(
        hsl.alpha,
        adjustedHue,
        adjustedSaturation,
        hsl.lightness,
      ).toColor();
    }

    return color;
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

    // 处理动态颜色方案，过滤掉紫色调
    ColorScheme? processedLightScheme = lightScheme;
    ColorScheme? processedDarkScheme = darkScheme;

    if (lightScheme != null && _hasPurpleTint(lightScheme.primary)) {
      processedLightScheme = lightScheme.copyWith(
        primary: _adjustPurpleTint(lightScheme.primary, Brightness.light),
        secondary: _adjustPurpleTint(lightScheme.secondary, Brightness.light),
        tertiary: _adjustPurpleTint(lightScheme.tertiary, Brightness.light),
      );
      logDebug('检测到动态亮色方案包含紫色调，已自动调整');
    }

    if (darkScheme != null && _hasPurpleTint(darkScheme.primary)) {
      processedDarkScheme = darkScheme.copyWith(
        primary: _adjustPurpleTint(darkScheme.primary, Brightness.dark),
        secondary: _adjustPurpleTint(darkScheme.secondary, Brightness.dark),
        tertiary: _adjustPurpleTint(darkScheme.tertiary, Brightness.dark),
      );
      logDebug('检测到动态暗色方案包含紫色调，已自动调整');
    }

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

  // 创建暗色主题数据
  ThemeData createDarkThemeData() {
    final bool usingCustom = _useCustomColor && _customColor != null;
    final baseTheme = FlexThemeData.dark(
      colorScheme: darkColorScheme,
      useMaterial3: true,
      surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
      blendLevel: 0,
      subThemesData: const FlexSubThemesData(
        blendOnLevel: 0,
        blendOnColors: false,
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
      // 当使用自定义主色时关闭次/三色自动调和，避免某些动态调和链条残留导致偏紫
      // 同时确保颜色方案本身已经过紫色调调整
      keyColors: usingCustom
          ? const FlexKeyColors(useSecondary: false, useTertiary: false)
          : const FlexKeyColors(useSecondary: true, useTertiary: true),
      tones: FlexTones.material(Brightness.dark),
      visualDensity: FlexColorScheme.comfortablePlatformDensity,
    );

    // 使用主题色系的深色调，确保用户选择的颜色能够正确应用
    final colorScheme = baseTheme.colorScheme;

    return baseTheme.copyWith(
      // 使用主题色系的基础暗色背景
      scaffoldBackgroundColor: colorScheme.surface,

      // 对话框使用主题色系，确保不会出现紫色调
      dialogTheme: baseTheme.dialogTheme.copyWith(
        backgroundColor: colorScheme.surfaceContainerLow,
      ),

      // 卡片使用主题色系
      cardTheme: baseTheme.cardTheme.copyWith(
        color: colorScheme.surfaceContainerLow,
      ),

      // 底部表单使用主题色系
      bottomSheetTheme: baseTheme.bottomSheetTheme.copyWith(
        backgroundColor: colorScheme.surfaceContainer,
      ),

      // 抽屉使用主题色系
      drawerTheme: baseTheme.drawerTheme.copyWith(
        backgroundColor: colorScheme.surfaceContainerLow,
      ),

      // AppBar使用略深的色调，增强标题区分度
      appBarTheme: baseTheme.appBarTheme.copyWith(
        backgroundColor: colorScheme.surfaceContainerHigh,
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
        backgroundColor: colorScheme.surfaceContainer,
      ),

      // 浮动操作按钮使用主题色系，确保主色调正确应用
      floatingActionButtonTheme: baseTheme.floatingActionButtonTheme.copyWith(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
      ),

      // 列表项目使用主题色系，避免紫色块状感
      listTileTheme: baseTheme.listTileTheme.copyWith(
        // 设为透明，避免 ListTile 再叠加一层带主色调的 surfaceContainerLow 造成紫色块状感
        tileColor: Colors.transparent,
      ),
    );
  }
}
