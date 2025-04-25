import 'package:flutter/material.dart';
import 'package:flex_color_scheme/flex_color_scheme.dart';
import '../utils/mmkv_ffi_fix.dart'; // 导入MMKV安全包装类

class AppTheme with ChangeNotifier {
  static const String _customColorKey = 'custom_color';
  static const String _useCustomColorKey = 'use_custom_color';
  static const String _themeModeKey = 'theme_mode';
  
  late SafeMMKV _storage;
  Color? _customColor;
  bool _useCustomColor = false;
  ColorScheme? _lightDynamicColorScheme;
  ColorScheme? _darkDynamicColorScheme;
  ThemeMode _themeMode = ThemeMode.system;
  
  // 全局圆角和阴影参数
  static const double cardRadius = 16;
  static const double dialogRadius = 20;
  static const double buttonRadius = 12;
  static const double inputRadius = 10;
  static const List<BoxShadow> defaultShadow = [
    BoxShadow(
      color: Colors.black12,
      blurRadius: 8,
      offset: Offset(0, 2),
    ),
  ];
  
  // 获取当前亮色主题的颜色方案
  ColorScheme get lightColorScheme {
    if (_useCustomColor && _customColor != null) {
      return ColorScheme.fromSeed(
        seedColor: _customColor!,
        brightness: Brightness.light,
      );
    }
    return _lightDynamicColorScheme ?? ColorScheme.fromSeed(
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
    return _darkDynamicColorScheme ?? ColorScheme.fromSeed(
      seedColor: Colors.blue,
      brightness: Brightness.dark,
    );
  }
  
  bool get useCustomColor => _useCustomColor;
  Color? get customColor => _customColor;
  ThemeMode get themeMode => _themeMode;
  
  // 初始化主题服务
  Future<void> initialize() async {
    try {
      _storage = SafeMMKV();
      await _storage.initialize();
      _loadCustomColor();
      _loadThemeMode();
      debugPrint('主题服务初始化完成: 使用自定义颜色=$_useCustomColor, 主题模式=$_themeMode');
    } catch (e) {
      debugPrint('初始化主题服务失败: $e');
      // 初始化失败时使用默认值
      _customColor = Colors.blue;
      _useCustomColor = false;
      _themeMode = ThemeMode.system;
    }
  }
  
  // 更新动态颜色方案
  void updateDynamicColorScheme(ColorScheme? lightScheme, ColorScheme? darkScheme) {
    bool changed = false;
    
    // 只在颜色方案实际变化时才更新
    if (_lightDynamicColorScheme != lightScheme) {
      _lightDynamicColorScheme = lightScheme;
      changed = true;
    }
    
    if (_darkDynamicColorScheme != darkScheme) {
      _darkDynamicColorScheme = darkScheme;
      changed = true;
    }
    
    // 只在实际发生变化时通知监听器
    if (changed) {
      notifyListeners();
    }
  }
  
  // 设置自定义颜色
  Future<void> setCustomColor(Color color) async {
    _customColor = color;
    await _storage.setInt(_customColorKey, color.value);
    notifyListeners();
  }
  
  // 切换是否使用自定义颜色
  Future<void> setUseCustomColor(bool value) async {
    _useCustomColor = value;
    await _storage.setBool(_useCustomColorKey, value);
    notifyListeners();
  }
  
  // 设置主题模式
  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await _storage.setString(_themeModeKey, mode.name);
    notifyListeners();
  }
  
  // 从持久化存储加载自定义颜色设置
  void _loadCustomColor() {
    try {
      final colorValue = _storage.getInt(_customColorKey);
      if (colorValue != null) {
        _customColor = Color(colorValue);
      }
      _useCustomColor = _storage.getBool(_useCustomColorKey) ?? false;
    } catch (e) {
      debugPrint('加载自定义颜色失败: $e');
      _customColor = Colors.blue;
      _useCustomColor = false;
    }
  }
  
  // 从持久化存储加载主题模式
  void _loadThemeMode() {
    try {
      final modeString = _storage.getString(_themeModeKey);
      if (modeString != null) {
        _themeMode = ThemeMode.values.byName(modeString);
      }
    } catch (e) {
      debugPrint('加载主题模式失败: $e');
      _themeMode = ThemeMode.system;
    }
  }
  
  // 创建亮色主题数据
  ThemeData createLightThemeData() {
    return FlexThemeData.light(
      colorScheme: lightColorScheme,
      useMaterial3: true,
      surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
      blendLevel: 7,
      subThemesData: FlexSubThemesData(
        blendOnLevel: 10,
        blendOnColors: false,
        useTextTheme: true,
        useM2StyleDividerInM3: false,
        alignedDropdown: true,
        useInputDecoratorThemeInDialogs: true,
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
      keyColors: const FlexKeyColors(
        useSecondary: true,
        useTertiary: true,
      ),
      tones: FlexTones.material(Brightness.light),
      visualDensity: FlexColorScheme.comfortablePlatformDensity,
    );
  }
  
  // 创建暗色主题数据
  ThemeData createDarkThemeData() {
    return FlexThemeData.dark(
      colorScheme: darkColorScheme,
      useMaterial3: true,
      surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
      blendLevel: 10,
      subThemesData: FlexSubThemesData(
        blendOnLevel: 15,
        useTextTheme: true,
        useM2StyleDividerInM3: false,
        alignedDropdown: true,
        useInputDecoratorThemeInDialogs: true,
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
      keyColors: const FlexKeyColors(
        useSecondary: true,
        useTertiary: true,
      ),
      tones: FlexTones.material(Brightness.dark),
      visualDensity: FlexColorScheme.comfortablePlatformDensity,
    );
  }
}