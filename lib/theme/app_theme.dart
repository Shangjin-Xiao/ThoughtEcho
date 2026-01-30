import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flex_color_scheme/flex_color_scheme.dart';
import '../utils/mmkv_ffi_fix.dart'; // 导入MMKV安全包装类
import 'package:thoughtecho/utils/app_logger.dart';

class AppTheme with ChangeNotifier {
  // Windows 平台字体配置
  // 使用 Microsoft YaHei UI 作为首选字体，它在 Windows 上对各种字重支持更好
  static const List<String> _windowsFontFamilyFallback = [
    'Microsoft YaHei UI', // Windows 10/11 优化的雅黑字体
    'Microsoft YaHei', // 标准微软雅黑
    'PingFang SC', // macOS 苹方（兼容性）
    'Noto Sans SC', // Google 思源黑体
    'sans-serif',
  ];

  // 获取当前平台的字体回退列表
  static List<String>? get platformFontFamilyFallback {
    if (kIsWeb) return null;
    if (Platform.isWindows) return _windowsFontFamilyFallback;
    return null; // 其他平台使用系统默认
  }

  // 创建适配 Windows 的 TextTheme
  // Windows 上中文字体的字重渲染可能不一致，通过统一配置解决
  static TextTheme _createPlatformTextTheme(TextTheme base) {
    if (kIsWeb || !Platform.isWindows) return base;

    // Windows 平台：为所有文本样式添加字体回退
    return base.copyWith(
      displayLarge: base.displayLarge?.copyWith(
        fontFamilyFallback: _windowsFontFamilyFallback,
      ),
      displayMedium: base.displayMedium?.copyWith(
        fontFamilyFallback: _windowsFontFamilyFallback,
      ),
      displaySmall: base.displaySmall?.copyWith(
        fontFamilyFallback: _windowsFontFamilyFallback,
      ),
      headlineLarge: base.headlineLarge?.copyWith(
        fontFamilyFallback: _windowsFontFamilyFallback,
      ),
      headlineMedium: base.headlineMedium?.copyWith(
        fontFamilyFallback: _windowsFontFamilyFallback,
      ),
      headlineSmall: base.headlineSmall?.copyWith(
        fontFamilyFallback: _windowsFontFamilyFallback,
      ),
      titleLarge: base.titleLarge?.copyWith(
        fontFamilyFallback: _windowsFontFamilyFallback,
      ),
      titleMedium: base.titleMedium?.copyWith(
        fontFamilyFallback: _windowsFontFamilyFallback,
      ),
      titleSmall: base.titleSmall?.copyWith(
        fontFamilyFallback: _windowsFontFamilyFallback,
      ),
      bodyLarge: base.bodyLarge?.copyWith(
        fontFamilyFallback: _windowsFontFamilyFallback,
      ),
      bodyMedium: base.bodyMedium?.copyWith(
        fontFamilyFallback: _windowsFontFamilyFallback,
      ),
      bodySmall: base.bodySmall?.copyWith(
        fontFamilyFallback: _windowsFontFamilyFallback,
      ),
      labelLarge: base.labelLarge?.copyWith(
        fontFamilyFallback: _windowsFontFamilyFallback,
      ),
      labelMedium: base.labelMedium?.copyWith(
        fontFamilyFallback: _windowsFontFamilyFallback,
      ),
      labelSmall: base.labelSmall?.copyWith(
        fontFamilyFallback: _windowsFontFamilyFallback,
      ),
    );
  }
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
      // 使用与浅色模式一致的方法，确保自定义颜色正确应用
      return ColorScheme.fromSeed(
        seedColor: _customColor!,
        brightness: Brightness.dark,
      );
    }

    if (_useDynamicColor && _darkDynamicColorScheme != null) {
      return _darkDynamicColorScheme!;
    }

    return _buildModernDarkScheme();
  }

  // 默认的现代深色方案
  ColorScheme _buildModernDarkScheme() {
    return ColorScheme.fromSeed(
      seedColor: Colors.blue,
      brightness: Brightness.dark,
    );
  }

  bool get useCustomColor => _useCustomColor;
  Color? get customColor => _customColor;
  ThemeMode get themeMode => _themeMode;

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
    if (_customColor == color) return;
    _customColor = color;
    // 先刷新UI，避免持久化卡住导致“怎么点都没反应”
    notifyListeners();

    final storage = _storage;
    if (storage == null) return;
    try {
      await storage
          .setInt(_customColorKey, color.toARGB32())
          .timeout(const Duration(seconds: 2));
    } catch (e) {
      logWarning('保存自定义主题色失败: $e', source: 'AppTheme');
    }
  }

  // 切换是否使用自定义颜色
  Future<void> setUseCustomColor(bool value) async {
    if (_useCustomColor == value) return;
    _useCustomColor = value;
    // 先刷新UI，避免持久化卡住导致无响应
    notifyListeners();

    final storage = _storage;
    if (storage == null) return;
    try {
      await storage
          .setBool(_useCustomColorKey, value)
          .timeout(const Duration(seconds: 2));
    } catch (e) {
      logWarning('保存“使用自定义主题色”开关失败: $e', source: 'AppTheme');
    }
  }

  // 设置主题模式
  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    // 先刷新UI，避免存储层偶发卡顿/异常导致“怎么点都没反应”
    notifyListeners();

    final storage = _storage;
    if (storage == null) return;
    try {
      await storage
          .setString(_themeModeKey, mode.name)
          .timeout(const Duration(seconds: 2));
    } catch (e) {
      logWarning('保存主题模式失败: $e', source: 'AppTheme');
    }
  }

  // 设置是否使用动态取色
  Future<void> setUseDynamicColor(bool value) async {
    if (_useDynamicColor == value) return;
    _useDynamicColor = value;
    // 先刷新UI，避免持久化卡住导致无响应
    notifyListeners();

    final storage = _storage;
    if (storage == null) return;
    try {
      await storage
          .setBool(_useDynamicColorKey, value)
          .timeout(const Duration(seconds: 2));
    } catch (e) {
      logWarning('保存“动态取色”开关失败: $e', source: 'AppTheme');
    }
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
        // 开关、复选框、单选按钮使用主题色
        switchSchemeColor: SchemeColor.primary,
        switchThumbSchemeColor: SchemeColor.onPrimary,
        checkboxSchemeColor: SchemeColor.primary,
        radioSchemeColor: SchemeColor.primary,
        // 滑块使用主题色
        sliderBaseSchemeColor: SchemeColor.primary,
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

      // Windows 平台字体优化
      textTheme: _createPlatformTextTheme(baseTheme.textTheme),
      primaryTextTheme: _createPlatformTextTheme(baseTheme.primaryTextTheme),
    );
  }

  // 创建暗色主题数据
  ThemeData createDarkThemeData() {
    final colorScheme = darkColorScheme;

    final baseTheme = FlexThemeData.dark(
      colorScheme: colorScheme,
      useMaterial3: true,
      surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
      blendLevel: 0, // 设置为0，避免混合修改自定义颜色
      subThemesData: const FlexSubThemesData(
        blendOnLevel: 0, // 设置为0，避免修改自定义颜色
        blendOnColors: false, // 禁用颜色混合
        useMaterial3Typography: true,
        useM2StyleDividerInM3: false,
        alignedDropdown: true,
        useInputDecoratorThemeInDialogs: true,
        interactionEffects: true, // 启用交互效果，确保控件使用主题色
        tintedDisabledControls: true, // 禁用状态也使用主题色调
        // 按钮颜色配置
        elevatedButtonSchemeColor: SchemeColor.primary,
        elevatedButtonSecondarySchemeColor: SchemeColor.onPrimary,
        // 开关、复选框、单选按钮使用主题色
        switchSchemeColor: SchemeColor.primary,
        switchThumbSchemeColor: SchemeColor.onPrimary,
        checkboxSchemeColor: SchemeColor.primary,
        radioSchemeColor: SchemeColor.primary,
        // 滑块使用主题色
        sliderBaseSchemeColor: SchemeColor.primary,
        // SegmentedButton 使用主题色
        segmentedButtonSchemeColor: SchemeColor.primary,
        // FilterChip 使用主题色
        chipSchemeColor: SchemeColor.primary,
        chipSelectedSchemeColor: SchemeColor.primaryContainer,
        // 圆角配置
        cardRadius: cardRadius,
        inputDecoratorRadius: inputRadius,
        dialogRadius: dialogRadius,
        timePickerDialogRadius: dialogRadius,
        outlinedButtonRadius: buttonRadius,
        filledButtonRadius: buttonRadius,
        textButtonRadius: buttonRadius,
        fabRadius: buttonRadius,
      ),
      // 禁用 keyColors 以防止重新生成颜色方案覆盖我们的自定义颜色
      // keyColors: const FlexKeyColors(
      //   useSecondary: true,
      //   useTertiary: true,
      // ),
      // tones: FlexTones.material(Brightness.dark),
      visualDensity: FlexColorScheme.comfortablePlatformDensity,
    );

    // 返回主题，确保使用原始的colorScheme，并额外配置控件主题
    return baseTheme.copyWith(
      colorScheme: colorScheme, // 重新应用原始colorScheme，确保自定义颜色不被修改
      // 显式配置 Switch 主题，确保使用自定义主题色
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.onPrimary;
          }
          return colorScheme.outline;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.primary;
          }
          return colorScheme.surfaceContainerHighest;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.transparent;
          }
          return colorScheme.outline;
        }),
      ),
      // 显式配置 Checkbox 主题
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.primary;
          }
          return Colors.transparent;
        }),
        checkColor: WidgetStateProperty.all(colorScheme.onPrimary),
      ),
      // 显式配置 Radio 主题
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.primary;
          }
          return colorScheme.onSurfaceVariant;
        }),
      ),
      // 显式配置 Slider 主题
      sliderTheme: SliderThemeData(
        activeTrackColor: colorScheme.primary,
        thumbColor: colorScheme.primary,
        inactiveTrackColor: colorScheme.primary.withValues(alpha: 0.3),
      ),
      // 显式配置 SegmentedButton 主题
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return colorScheme.secondaryContainer;
            }
            return Colors.transparent;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return colorScheme.onSecondaryContainer;
            }
            return colorScheme.onSurface;
          }),
          side: WidgetStateProperty.all(BorderSide(color: colorScheme.outline)),
        ),
      ),
      // 显式配置 FilterChip/Chip 主题
      chipTheme: ChipThemeData(
        backgroundColor: colorScheme.surfaceContainerHighest,
        selectedColor: colorScheme.secondaryContainer,
        labelStyle: TextStyle(color: colorScheme.onSurface),
        secondaryLabelStyle: TextStyle(color: colorScheme.onSecondaryContainer),
        checkmarkColor: colorScheme.onSecondaryContainer,
        side: BorderSide(color: colorScheme.outline),
      ),
      // 显式配置 IconButton 主题
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return colorScheme.onSurface.withValues(alpha: 0.38);
            }
            return colorScheme.onSurfaceVariant;
          }),
        ),
      ),
      // 显式配置 TextButton 主题
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return colorScheme.onSurface.withValues(alpha: 0.38);
            }
            return colorScheme.primary;
          }),
        ),
      ),
      // 显式配置 ElevatedButton 主题
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return colorScheme.onSurface.withValues(alpha: 0.12);
            }
            return colorScheme.primary;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return colorScheme.onSurface.withValues(alpha: 0.38);
            }
            return colorScheme.onPrimary;
          }),
        ),
      ),
      // 显式配置 FilledButton 主题
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return colorScheme.onSurface.withValues(alpha: 0.12);
            }
            return colorScheme.primary;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return colorScheme.onSurface.withValues(alpha: 0.38);
            }
            return colorScheme.onPrimary;
          }),
        ),
      ),
      // 显式配置 OutlinedButton 主题
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return colorScheme.onSurface.withValues(alpha: 0.38);
            }
            return colorScheme.primary;
          }),
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return BorderSide(
                color: colorScheme.onSurface.withValues(alpha: 0.12),
              );
            }
            return BorderSide(color: colorScheme.outline);
          }),
        ),
      ),
      // 浮动操作按钮使用主题色系
      floatingActionButtonTheme: baseTheme.floatingActionButtonTheme.copyWith(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
      ),
      // 配置输入框装饰主题
      inputDecorationTheme: baseTheme.inputDecorationTheme.copyWith(
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(inputRadius),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
        floatingLabelStyle: TextStyle(color: colorScheme.primary),
      ),
      // 配置进度指示器颜色
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colorScheme.primary,
        circularTrackColor: colorScheme.primary.withValues(alpha: 0.2),
        linearTrackColor: colorScheme.primary.withValues(alpha: 0.2),
      ),

      // Windows 平台字体优化
      textTheme: _createPlatformTextTheme(baseTheme.textTheme),
      primaryTextTheme: _createPlatformTextTheme(baseTheme.primaryTextTheme),
    );
  }
}
