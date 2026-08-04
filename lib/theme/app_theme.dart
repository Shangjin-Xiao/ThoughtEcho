import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flex_color_scheme/flex_color_scheme.dart';
import '../utils/mmkv_ffi_fix.dart'; // 导入MMKV安全包装类
import 'package:thoughtecho/utils/app_logger.dart';
import 'app_semantic_colors.dart';
import 'theme_style.dart';

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

  // Flutter 3.41+ variable font 字重适配（Android）
  //
  // 背景：Flutter 3.41 起 FontWeight 自动驱动 variable font wght 轴。
  // Android 12+ RobotoFlex 字形比旧静态 Roboto 更粗，导致升级后视觉变重。
  //
  // 官方建议：逐个调整 FontWeight 值达到期望视觉效果。
  // 当前状态：暂不在 theme 层做补偿（只改 theme 会导致 theme 文字和
  //   inline fontWeight 文字粗细不一致，视觉更差）。
  //   完整修复需审查全部 ~240 处 inline FontWeight 并统一调整。
  //   详见 squad/font_issue_handoff.md。
  //
  // 平台字体优化入口（目前仅 Windows 生效）
  static TextTheme _fixAndroidVariableFontWeight(
    ThemeStyleForm form,
    TextTheme base,
  ) {
    if (kIsWeb) return base;
    if (!Platform.isAndroid) return base;
    // 补偿针对的是**黑体**变粗。用衬线体的风格把 variableWeightCompensation 设 0，
    // 走这里直接返回，保留 M3 原生字重——衬线体再减重就发灰发虚了。
    // 判据是令牌取值，不是风格身份。
    if (form.variableWeightCompensation <= 0) return base;
    // Flutter 3.41+ Impeller + FontWeight 精准映射 wght 轴，Android 字体视觉变粗。
    // M3 默认字重与补偿量（补偿满强度时的取值就是括号里的结果）：
    //   body*       → w400 −50 → 350：正文/设置项偏重，降至 350 还原旧视觉
    //   titleMedium/Small → w500 −50 → 450
    //   labelLarge  → w500 −50 → 450；labelMedium/Small → w500 −100 → 400
    //   display*/headline*/titleLarge → w400 −50 → 350（大字号同样偏重）
    // FontWeight(350) 是 Flutter 3.44 支持的任意整数值，引擎映射到 wght=350。
    final strength = form.variableWeightCompensation.clamp(0.0, 1.0);
    FontWeight w(int m3Default, int delta) =>
        FontWeight((m3Default + delta * strength).round());
    final large = w(400, -50);
    final medium = w(500, -50);
    return base.copyWith(
      displayLarge: base.displayLarge?.copyWith(fontWeight: large),
      displayMedium: base.displayMedium?.copyWith(fontWeight: large),
      displaySmall: base.displaySmall?.copyWith(fontWeight: large),
      headlineLarge: base.headlineLarge?.copyWith(fontWeight: large),
      headlineMedium: base.headlineMedium?.copyWith(fontWeight: large),
      headlineSmall: base.headlineSmall?.copyWith(fontWeight: large),
      titleLarge: base.titleLarge?.copyWith(fontWeight: large),
      titleMedium: base.titleMedium?.copyWith(fontWeight: medium),
      titleSmall: base.titleSmall?.copyWith(fontWeight: medium),
      bodyLarge: base.bodyLarge?.copyWith(fontWeight: large),
      bodyMedium: base.bodyMedium?.copyWith(fontWeight: large),
      bodySmall: base.bodySmall?.copyWith(fontWeight: large),
      labelLarge: base.labelLarge?.copyWith(fontWeight: medium),
      labelMedium: base.labelMedium?.copyWith(fontWeight: w(500, -100)),
      labelSmall: base.labelSmall?.copyWith(fontWeight: w(500, -100)),
    );
  }

  /// 给整套 TextTheme 套上风格的字体族与正文行高。
  ///
  /// 手工风格指向系统自带的中文衬线体，**不打包任何字体文件**：`fontFamily` 命中不了
  /// 就沿 `fontFamilyFallback` 逐个回退，最后回落到系统默认，不会出现豆腐块。
  ///
  /// 行高只改 `body*` 三级——标题和标签用的是紧排，跟着放松会显得散。
  /// `bodyLarge` 直接取 [ThemeStyleForm.bodyLineHeight]，另外两级按同一比例缩放
  /// 各自的 M3 默认值，避免三级正文被压成同一个行高。
  ///
  /// material 风格两项都是恒等取值（`fontFamily` 为 null、行高比例为 1），像素不变。
  ///
  /// 注意与 `_createPlatformTextTheme` 的顺序：那一层给 Windows 补的是**黑体**回退链，
  /// 这一层要盖在它上面，否则 Windows 上会被雅黑抢回去。
  static TextTheme _applyStyleTypography(ThemeStyleForm form, TextTheme base) {
    final family = form.fontFamily;
    final fallback = form.fontFamilyFallback;
    final heightScale =
        form.bodyLineHeight / ThemeStyleForm.material.bodyLineHeight;
    if (family == null && heightScale == 1) return base;

    // 字体族：全级别统一换。
    TextStyle? font(TextStyle? style) => family == null
        ? style
        : style?.copyWith(fontFamily: family, fontFamilyFallback: fallback);

    // 正文：换字体族之外还要按比例放松行高。fallback 是 M3 的默认值，
    // 用于 base 没带 height 的情况。
    TextStyle? body(TextStyle? style, double m3Height) {
      final styled = font(style);
      if (heightScale == 1) return styled;
      return styled?.copyWith(height: (styled.height ?? m3Height) * heightScale);
    }

    return base.copyWith(
      displayLarge: font(base.displayLarge),
      displayMedium: font(base.displayMedium),
      displaySmall: font(base.displaySmall),
      headlineLarge: font(base.headlineLarge),
      headlineMedium: font(base.headlineMedium),
      headlineSmall: font(base.headlineSmall),
      titleLarge: font(base.titleLarge),
      titleMedium: font(base.titleMedium),
      titleSmall: font(base.titleSmall),
      bodyLarge: body(base.bodyLarge, 24 / 16),
      bodyMedium: body(base.bodyMedium, 20 / 14),
      bodySmall: body(base.bodySmall, 16 / 12),
      labelLarge: font(base.labelLarge),
      labelMedium: font(base.labelMedium),
      labelSmall: font(base.labelSmall),
    );
  }

  /// 卡片形状：手工风格用发丝边框 + 零投影来做纸的层次，Material 保持原有投影。
  ///
  /// 判据是 `borderWidth > 0` 这个**取值**，不是风格身份——将来加一套
  /// `borderWidth: 0` 的风格会自动走 Material 那条路，不需要改这里。
  static CardThemeData _styleCardTheme(
    CardThemeData base,
    ThemeStyleForm form,
    ColorScheme colorScheme,
  ) {
    if (form.borderWidth <= 0) {
      return base.copyWith(color: colorScheme.surfaceContainerLowest);
    }
    return base.copyWith(
      color: colorScheme.surfaceContainerLowest,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(form.cardRadius),
        side: BorderSide(
          color: colorScheme.outlineVariant,
          width: form.borderWidth,
        ),
      ),
    );
  }

  static const String _customColorKey = 'custom_color';
  static const String _useCustomColorKey = 'use_custom_color';
  static const String _themeModeKey = 'theme_mode';
  static const String _useDynamicColorKey = 'use_dynamic_color'; // 添加动态取色设置键
  static const String _themeStyleKey = 'theme_style';

  SafeMMKV? _storage;
  Color? _customColor;
  bool _useCustomColor = false;
  bool _useDynamicColor = true; // 默认启用动态取色
  ColorScheme? _lightDynamicColorScheme;
  ColorScheme? _darkDynamicColorScheme;
  ThemeMode _themeMode = ThemeMode.system;
  ThemeStyle _themeStyle = ThemeStyle.defaultStyle;
  bool _hasInitialized = false; // 添加标记，用于追踪是否已初始化

  // 全局圆角和阴影参数
  static const double cardRadius = 18;
  static const double dialogRadius = 24;
  static const double buttonRadius = 12;
  static const double inputRadius = 12;

  // 聊天气泡（消息气泡、思考面板、工具进度面板）不再有独立常量：
  // 三处共用 `AppShapeTokens.of(context).dialogRadius`，随主题风格变化。

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
  ColorScheme get lightColorScheme =>
      colorSchemeFor(_themeStyle, Brightness.light);

  // 获取当前暗色主题的颜色方案
  ColorScheme get darkColorScheme =>
      colorSchemeFor(_themeStyle, Brightness.dark);

  /// 任意风格在任意亮度下**应该**产出的配色，和当前生效的风格无关。
  ///
  /// 主题设置页的风格预览必须用这个，不能读 `Theme.of(context).colorScheme`：
  /// 那读到的是当前生效风格的颜色，会让 material 那一项的预览跟着已选中的
  /// 纸墨/素笺一起变色——看上去像「点一下颜色就乱跳」。
  ColorScheme colorSchemeFor(ThemeStyle style, Brightness brightness) {
    // 手工色板原样落地：不参与动态取色，也不接受自定义 seed——那两项是
    // material 风格专有的能力，套到手工色板上只会把配好的色值推翻重算。
    final palette = style.palette;
    if (palette != null) {
      return palette.forBrightness(brightness).toColorScheme(brightness);
    }
    return _generatedColorScheme(brightness);
  }

  /// 取色算法那条路：自定义 seed > 系统动态取色 > 默认蓝。
  ColorScheme _generatedColorScheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    if (_useCustomColor && _customColor != null) {
      // 直接使用用户选择的颜色，减少不必要的调整
      return ColorScheme.fromSeed(
        seedColor: _customColor!,
        brightness: brightness,
      );
    }
    // 只有在启用动态取色且有可用的动态颜色方案时才使用
    final dynamicScheme =
        isDark ? _darkDynamicColorScheme : _lightDynamicColorScheme;
    if (_useDynamicColor && dynamicScheme != null) {
      return dynamicScheme;
    }
    return isDark
        ? _buildModernDarkScheme()
        : ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.light,
          );
  }

  // 默认的现代深色方案
  ColorScheme _buildModernDarkScheme() {
    return ColorScheme.fromSeed(
      seedColor: Colors.blue,
      brightness: Brightness.dark,
    );
  }

  ThemeStyle get themeStyle => _themeStyle;
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
      _loadThemeStyle();

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
      // 初始化失败时使用默认值。风格也要一并重置：_loadThemeStyle() 可能已经成功、
      // 后面某一步才抛，那样会留下「风格是纸墨、其余全是默认值」的半新半旧状态。
      _customColor = Colors.blue;
      _useCustomColor = false;
      _useDynamicColor = true;
      _themeMode = ThemeMode.system;
      _themeStyle = ThemeStyle.defaultStyle;
    }
  }

  // 更新动态颜色方案
  void updateDynamicColorScheme(
    ColorScheme? lightScheme,
    ColorScheme? darkScheme,
  ) {
    // 直接使用系统提供的动态颜色方案，不进行紫色过滤
    ColorScheme? processedLightScheme = lightScheme;
    ColorScheme? processedDarkScheme = darkScheme;

    // 更新动态颜色方案
    if (_lightDynamicColorScheme != processedLightScheme) {
      _lightDynamicColorScheme = processedLightScheme;
      _clearThemeCache();
    }

    if (_darkDynamicColorScheme != processedDarkScheme) {
      _darkDynamicColorScheme = processedDarkScheme;
      _clearThemeCache();
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

    // DynamicColorBuilder 会在系统颜色变化时主动重建 MaterialApp，
    // 这里避免在 build 过程中再次 notifyListeners() 引发重建冲突。
  }

  // 设置自定义颜色
  Future<void> setCustomColor(Color color) async {
    if (_customColor == color) return;
    _customColor = color;
    _clearThemeCache();
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
    _clearThemeCache();
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
    _clearThemeCache();
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

  /// 设置主题风格（Material / 纸与墨 / 素笺）。
  ///
  /// 风格和亮暗、动态取色是并列的维度：切到手工色板时动态取色和自定义 seed
  /// 不会被清掉，只是暂时不生效，切回 material 时原样恢复。
  Future<void> setThemeStyle(ThemeStyle style) async {
    if (_themeStyle == style) return;
    _themeStyle = style;
    _clearThemeCache();
    // 与 setThemeMode 一致：先刷新 UI，再落盘。
    notifyListeners();

    final storage = _storage;
    if (storage == null) return;
    try {
      await storage
          .setString(_themeStyleKey, style.name)
          .timeout(const Duration(seconds: 2));
    } catch (e) {
      logWarning('保存主题风格失败: $e', source: 'AppTheme');
    }
  }

  // 设置是否使用动态取色
  Future<void> setUseDynamicColor(bool value) async {
    if (_useDynamicColor == value) return;
    _useDynamicColor = value;
    _clearThemeCache();
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

  // 从持久化存储加载主题风格
  void _loadThemeStyle() {
    try {
      _themeStyle = ThemeStyle.fromName(_storage?.getString(_themeStyleKey));
    } catch (e) {
      logDebug('加载主题风格失败: $e');
      _themeStyle = ThemeStyle.defaultStyle;
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

  ThemeData? _cachedLightThemeData;
  ThemeData? _cachedDarkThemeData;

  void _clearThemeCache() {
    _cachedLightThemeData = null;
    _cachedDarkThemeData = null;
  }

  // 创建亮色主题数据
  ThemeData createLightThemeData() {
    if (_cachedLightThemeData != null) return _cachedLightThemeData!;
    // 手工色板要原样落地：关掉 keyColors（否则 FlexColorScheme 会拿色板里的
    // primary 当种子重新推导整套色调）和表面混合（否则纸色会被强调色染上一层）。
    final generated = _themeStyle.isGenerated;
    final form = _themeStyle.form;
    final baseTheme = FlexThemeData.light(
      colorScheme: lightColorScheme,
      useMaterial3: true,
      surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
      blendLevel: generated ? 1 : 0, // 极低混合级别，使颜色非常接近白色
      subThemesData: FlexSubThemesData(
        blendOnLevel: generated ? 2 : 0, // 极低表面颜色混合级别
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
        cardRadius: form.cardRadius,
        inputDecoratorRadius: form.inputRadius,
        dialogRadius: form.dialogRadius,
        timePickerDialogRadius: form.dialogRadius,
        elevatedButtonRadius: form.buttonRadius,
        outlinedButtonRadius: form.buttonRadius,
        filledButtonRadius: form.buttonRadius,
        textButtonRadius: form.buttonRadius,
        fabRadius: form.buttonRadius,
      ),
      keyColors: generated
          ? const FlexKeyColors(useSecondary: true, useTertiary: true)
          : null,
      tones: generated ? FlexTones.material(Brightness.light) : null,
      visualDensity: FlexColorScheme.comfortablePlatformDensity,
    );

    // 使用主题色系的浅色调，确保颜色一致性
    final colorScheme = baseTheme.colorScheme;

    return _cachedLightThemeData = baseTheme.copyWith(
      // 使用主题色系的极浅背景色
      scaffoldBackgroundColor: colorScheme.surface,

      // 对话框使用主题色系
      dialogTheme: baseTheme.dialogTheme.copyWith(
        backgroundColor: colorScheme.surfaceContainerLowest,
      ),

      // 卡片使用主题色系
      cardTheme: _styleCardTheme(baseTheme.cardTheme, form, colorScheme),

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
          fontWeight: FontWeight.w400, // M3 titleLarge 默认 w400，与 textTheme 补偿一致
          fontSize: 20,
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

      // SnackBar 统一为浮动样式和 buttonRadius 圆角。
      // 过去没有配置这项，导致 46 处调用点各自手写 backgroundColor: Colors.red 兜底。
      snackBarTheme: baseTheme.snackBarTheme.copyWith(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(buttonRadius),
        ),
      ),

      // 状态语义色（M3 的 ColorScheme 只有 error，没有 success / warning）
      extensions: <ThemeExtension<dynamic>>[
        AppSemanticColors.light,
        AppShapeTokens.fromForm(form, Brightness.light),
      ],

      // Windows 平台字体优化
      textTheme: _applyStyleTypography(
        form,
        _fixAndroidVariableFontWeight(
          form,
          _createPlatformTextTheme(baseTheme.textTheme),
        ),
      ),
      primaryTextTheme: _applyStyleTypography(
        form,
        _fixAndroidVariableFontWeight(
          form,
          _createPlatformTextTheme(baseTheme.primaryTextTheme),
        ),
      ),
    );
  }

  // 创建暗色主题数据
  ThemeData createDarkThemeData() {
    if (_cachedDarkThemeData != null) return _cachedDarkThemeData!;
    final colorScheme = darkColorScheme;
    final form = _themeStyle.form;

    final baseTheme = FlexThemeData.dark(
      colorScheme: colorScheme,
      useMaterial3: true,
      surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
      blendLevel: 0, // 设置为0，避免混合修改自定义颜色
      subThemesData: FlexSubThemesData(
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
        cardRadius: form.cardRadius,
        inputDecoratorRadius: form.inputRadius,
        dialogRadius: form.dialogRadius,
        timePickerDialogRadius: form.dialogRadius,
        elevatedButtonRadius: form.buttonRadius,
        outlinedButtonRadius: form.buttonRadius,
        filledButtonRadius: form.buttonRadius,
        textButtonRadius: form.buttonRadius,
        fabRadius: form.buttonRadius,
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
    return _cachedDarkThemeData = baseTheme.copyWith(
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

      // SnackBar 统一为浮动样式和 buttonRadius 圆角，与亮色主题保持一致
      snackBarTheme: baseTheme.snackBarTheme.copyWith(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(buttonRadius),
        ),
      ),

      // 状态语义色（M3 的 ColorScheme 只有 error，没有 success / warning）
      cardTheme: _styleCardTheme(baseTheme.cardTheme, form, colorScheme),
      extensions: <ThemeExtension<dynamic>>[
        AppSemanticColors.dark,
        AppShapeTokens.fromForm(form, Brightness.dark),
      ],

      // Windows 平台字体优化
      textTheme: _applyStyleTypography(
        form,
        _fixAndroidVariableFontWeight(
          form,
          _createPlatformTextTheme(baseTheme.textTheme),
        ),
      ),
      primaryTextTheme: _applyStyleTypography(
        form,
        _fixAndroidVariableFontWeight(
          form,
          _createPlatformTextTheme(baseTheme.primaryTextTheme),
        ),
      ),
    );
  }
}
