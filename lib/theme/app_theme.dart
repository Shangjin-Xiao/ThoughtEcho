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
      return ColorScheme.fromSeed(
        seedColor: _customColor!,
        brightness: Brightness.light,
      );
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
      return ColorScheme.fromSeed(
        seedColor: _customColor!,
        brightness: Brightness.dark,
      );
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

  // 获取当前有效的主色调
  Color get effectivePrimaryColor {
    if (_useCustomColor && _customColor != null) {
      return _customColor!;
    }
    if (_useDynamicColor && _lightDynamicColorScheme != null) {
      return _lightDynamicColorScheme!.primary;
    }
    return Colors.blue;
  }

  // 判断当前是否为深色模式
  bool get isDarkMode {
    switch (_themeMode) {
      case ThemeMode.dark:
        return true;
      case ThemeMode.light:
        return false;
      case ThemeMode.system:
        // 这里需要从外部获取系统主题，暂时返回false
        return false;
    }
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

    // 更新动态颜色方案
    if (_lightDynamicColorScheme != lightScheme) {
      _lightDynamicColorScheme = lightScheme;
      changed = true;
    }

    if (_darkDynamicColorScheme != darkScheme) {
      _darkDynamicColorScheme = darkScheme;
      changed = true;
    }

    // 检查系统是否支持动态取色
    bool systemSupportsDynamicColor =
        (lightScheme != null || darkScheme != null);

    // 如果系统不支持动态取色，我们仍然保持用户的 _useDynamicColor 设置不变。
    // useDynamicColor getter 会处理实际的颜色方案回退。
    // 这样，即使用户的设备暂时无法获取动态颜色，他们“启用动态取色”的偏好设置仍然保留。
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
    final baseTheme = FlexThemeData.dark(
      colorScheme: darkColorScheme,
      useMaterial3: true,
      surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
      blendLevel: 3, // 进一步降低混合级别
      subThemesData: const FlexSubThemesData(
        blendOnLevel: 5, // 进一步降低表面颜色混合级别
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
      tones: FlexTones.material(Brightness.dark),
      visualDensity: FlexColorScheme.comfortablePlatformDensity,
    );

    // 使用主题色系的深色调，确保用户选择的颜色能够正确应用
    final colorScheme = baseTheme.colorScheme;

    return baseTheme.copyWith(
      // 使用主题色系的基础暗色背景
      scaffoldBackgroundColor: colorScheme.surface,

      // 对话框使用主题色系
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

      // 浮动操作按钮使用主题色系
      floatingActionButtonTheme: baseTheme.floatingActionButtonTheme.copyWith(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
      ),
      
      // 列表项目使用主题色系
      listTileTheme: baseTheme.listTileTheme.copyWith(
        tileColor: colorScheme.surfaceContainerLow,
      ),
    );
  }
}
