import 'package:flutter/material.dart';
import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppTheme with ChangeNotifier {
  static const String _customColorKey = 'custom_color';
  static const String _useCustomColorKey = 'use_custom_color';
  
  late SharedPreferences _prefs;
  Color? _customColor;
  bool _useCustomColor = false;
  ColorScheme? _dynamicColorScheme;
  
  // 获取当前主题的颜色方案
  ColorScheme? get colorScheme {
    if (_useCustomColor && _customColor != null) {
      return ColorScheme.fromSeed(
        seedColor: _customColor!,
        brightness: Brightness.light,
      );
    }
    return _dynamicColorScheme;
  }
  
  bool get useCustomColor => _useCustomColor;
  Color? get customColor => _customColor;
  
  // 初始化主题服务
  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    _loadCustomColor();
  }
  
  // 更新动态颜色方案
  void updateDynamicColorScheme(ColorScheme? scheme) {
    _dynamicColorScheme = scheme;
    notifyListeners();
  }
  
  // 设置自定义颜色
  Future<void> setCustomColor(Color color) async {
    _customColor = color;
    await _prefs.setInt(_customColorKey, color.value);
    notifyListeners();
  }
  
  // 切换是否使用自定义颜色
  Future<void> setUseCustomColor(bool value) async {
    _useCustomColor = value;
    await _prefs.setBool(_useCustomColorKey, value);
    notifyListeners();
  }
  
  // 从持久化存储加载自定义颜色设置
  void _loadCustomColor() {
    final colorValue = _prefs.getInt(_customColorKey);
    if (colorValue != null) {
      _customColor = adjustThemeColor(Color(colorValue));
    }
    _useCustomColor = _prefs.getBool(_useCustomColorKey) ?? false;
  }
  
  // 创建主题数据
  ThemeData createThemeData() {
    final scheme = colorScheme;
    if (scheme == null) {
      return FlexThemeData.light(
        scheme: FlexScheme.material,
        surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
        blendLevel: 7,
      );
    }
    
    return FlexThemeData.light(
      colorScheme: scheme,
      surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
      blendLevel: 7,
      subThemesData: const FlexSubThemesData(
        elevatedButtonSchemeColor: SchemeColor.primary,
        elevatedButtonSecondarySchemeColor: SchemeColor.onPrimary,
        cardRadius: 12,
        inputDecoratorRadius: 10,
        dialogRadius: 20,
        timePickerDialogRadius: 20,
      ),
      visualDensity: FlexColorScheme.comfortablePlatformDensity,
    );
  }
}

Color adjustThemeColor(Color color) {
  // 使用 color.alpha, color.red, color.green, color.blue（均为 int）
  return Color.fromARGB(color.alpha, color.red, color.green, color.blue);
}