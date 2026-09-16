import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/services/version_check_service.dart';
import 'package:thoughtecho/theme/app_theme.dart';
import 'package:thoughtecho/theme/theme_style.dart';
import 'package:thoughtecho/widgets/update_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final dummyVersionInfoAvailable = VersionInfo(
    hasUpdate: true,
    currentVersion: '1.0.0',
    latestVersion: '1.1.0',
    releaseNotes: '### 更新内容\n- 修复一些 Bug',
    downloadUrl: 'https://example.com/download',
    publishedAt: DateTime(2025, 1, 1),
  );

  final dummyVersionInfoLatest = VersionInfo(
    hasUpdate: false,
    currentVersion: '1.0.0',
    latestVersion: '1.0.0',
    releaseNotes: '',
    downloadUrl: '',
    publishedAt: DateTime(2025, 1, 1),
  );

  Future<Widget> buildTestableWidget({
    required Widget child,
    ThemeStyle style = ThemeStyle.defaultStyle,
  }) async {
    final appTheme = AppTheme();
    await appTheme.setThemeStyle(style);
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      theme: appTheme.createLightThemeData(),
      home: Scaffold(
        body: Builder(
          builder: (context) => child,
        ),
      ),
    );
  }

  group('UpdateBottomSheet Widget Tests', () {
    testWidgets('渲染有更新可用的对话框', (WidgetTester tester) async {
      final widget = await buildTestableWidget(
        child: UpdateBottomSheet(
          versionInfo: dummyVersionInfoAvailable,
          buttons: [
            UpdateButtonConfig(
              type: UpdateButtonType.ignore,
              label: '忽略',
              onPressed: () {},
            ),
            UpdateButtonConfig(
              type: UpdateButtonType.update,
              label: '立即更新',
              onPressed: () {},
            ),
          ],
        ),
      );
      await tester.pumpWidget(widget);
      await tester.pumpAndSettle();

      expect(find.text('发现新版本'), findsOneWidget);
      expect(find.text('1.0.0'), findsOneWidget);
      expect(find.text('1.1.0'), findsOneWidget);
      expect(find.text('忽略'), findsOneWidget);
      expect(find.text('立即更新'), findsOneWidget);

      final badgeFinder = find.ancestor(
        of: find.text('1.1.0'),
        matching: find.byType(Container),
      );
      final container = tester.widget<Container>(badgeFinder.first);
      final decoration = container.decoration as BoxDecoration;
      final borderRadius = decoration.borderRadius as BorderRadius;
      expect(borderRadius.topLeft.x, 12.0);
    });

    testWidgets('渲染已是最新版本的对话框', (WidgetTester tester) async {
      final widget = await buildTestableWidget(
        child: UpdateBottomSheet(
          versionInfo: dummyVersionInfoLatest,
          showNoUpdateMessage: true,
          buttons: const [],
        ),
      );
      await tester.pumpWidget(widget);
      await tester.pumpAndSettle();

      expect(find.text('已是最新版本'), findsOneWidget);
      expect(find.text('确定'), findsOneWidget);
    });

    testWidgets('验证纸墨风格下 AppShapeTokens 圆角应用正常', (WidgetTester tester) async {
      final widget = await buildTestableWidget(
        style: ThemeStyle.paper,
        child: UpdateBottomSheet(
          versionInfo: dummyVersionInfoAvailable,
          buttons: const [],
        ),
      );
      await tester.pumpWidget(widget);
      await tester.pumpAndSettle();

      expect(find.byType(UpdateBottomSheet), findsOneWidget);

      final badgeFinder = find.ancestor(
        of: find.text('1.1.0'),
        matching: find.byType(Container),
      );
      final container = tester.widget<Container>(badgeFinder.first);
      final decoration = container.decoration as BoxDecoration;
      final borderRadius = decoration.borderRadius as BorderRadius;
      expect(borderRadius.topLeft.x, 4.0);
    });
  });
}
