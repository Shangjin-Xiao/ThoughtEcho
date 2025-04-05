import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/services/ai_service.dart';
import 'package:thoughtecho/theme/app_theme.dart';
import 'package:thoughtecho/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // 初始化服务
    final settingsService = await SettingsService.create();
    final databaseService = DatabaseService();
    final appTheme = AppTheme();
    await appTheme.initialize();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => settingsService),
          ChangeNotifierProvider(create: (_) => databaseService),
          ChangeNotifierProvider(create: (_) => appTheme),
          ChangeNotifierProxyProvider<SettingsService, AIService>(
            create:
                (context) =>
                    AIService(settingsService: context.read<SettingsService>()),
            update:
                (context, settings, previous) =>
                    previous ?? AIService(settingsService: settings),
          ),
        ],
        child: const MyApp(),
      ),
    );

    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.byType(AppBar), findsOneWidget);
  });
}
