import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mind_trace/services/database_service.dart';
import 'package:mind_trace/services/settings_service.dart';
import 'package:mind_trace/services/ai_service.dart';
import 'package:mind_trace/services/location_service.dart'; // 新增导入
import 'package:mind_trace/services/weather_service.dart'; // 新增导入
import 'package:mind_trace/theme/app_theme.dart';
import 'package:mind_trace/main.dart'; // MyApp 可能需要保持导入

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // 初始化服务
    final settingsService = await SettingsService.create();
    final databaseService = DatabaseService(); // 假设测试不需要真实数据库交互
    final locationService = LocationService(); // 创建实例
    final weatherService = WeatherService(); // 创建实例
    final appTheme = AppTheme();
    await appTheme.initialize();

    // 创建 Navigator Key
    final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => settingsService),
          ChangeNotifierProvider(create: (_) => databaseService),
          ChangeNotifierProvider(create: (_) => locationService), // 添加 Provider
          ChangeNotifierProvider(create: (_) => weatherService), // 添加 Provider
          ChangeNotifierProvider(create: (_) => appTheme),
          ChangeNotifierProxyProvider<SettingsService, AIService>(
            create: (context) => AIService(
              settingsService: context.read<SettingsService>(),
              locationService: context.read<LocationService>(), // 传入实例
              weatherService: context.read<WeatherService>(), // 传入实例
            ),
            update: (context, settings, previous) =>
                previous ?? AIService(
                  settingsService: settings,
                  locationService: context.read<LocationService>(), // 传入实例
                  weatherService: context.read<WeatherService>(), // 传入实例
                ),
          ),
        ],
        child: MyApp(navigatorKey: navigatorKey), // 传递 navigatorKey
      ),
    );

    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.byType(AppBar), findsOneWidget);
  });
}
