import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:thoughtecho/config/release_highlights.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/pages/release_notes_page.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/theme/app_theme.dart';
import 'package:thoughtecho/theme/theme_style.dart';
import 'package:thoughtecho/utils/theme_style_labels.dart';

import '../../test_harness.dart';

void main() {
  setUpAll(() async {
    await TestHarness.initialize();
  });

  /// 把测试视口撑到能装下整页。
  ///
  /// 这一页比手机屏幕长得多，默认视口下 `ListView` 根本不会构建屏幕外的条目——
  /// 那样 `findsNothing` 会因为「压根没渲染」而假阳性通过，测不出真正的过滤逻辑。
  void useTallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1000, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget buildApp(
    Widget page, {
    AppTheme? appTheme,
    SettingsService? settingsService,
  }) {
    final theme = appTheme ?? AppTheme();
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AppTheme>.value(value: theme),
        if (settingsService != null)
          ChangeNotifierProvider<SettingsService>.value(
            value: settingsService,
          ),
      ],
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: page,
      ),
    );
  }

  Future<SettingsService> createSettings() async {
    final settings = await SettingsService.create();
    await settings.setTelemetryEnabled(false);
    await settings.setSentryEnabled(false);
    return settings;
  }

  group('升级后展示', () {
    testWidgets('3.6.5 升上来能看到功能内容和崩溃诊断脚注', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('zh'));
      useTallSurface(tester);

      await tester.pumpWidget(
        buildApp(
          const ReleaseNotesPage.sinceUpgrade(lastSeenVersion: '3.6.5'),
          settingsService: await createSettings(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(l10n.releaseThoughterTitle), findsOneWidget);
      expect(find.text(l10n.releaseThemeTitle), findsOneWidget);
      expect(find.text(l10n.releaseDiagnosticsNotice), findsOneWidget);
      expect(find.text(l10n.releaseNotesGetStarted), findsOneWidget);
    });

    testWidgets('3.7.0 升上来不再出现崩溃诊断脚注', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('zh'));
      useTallSurface(tester);

      await tester.pumpWidget(
        buildApp(
          const ReleaseNotesPage.sinceUpgrade(lastSeenVersion: '3.7.0'),
          settingsService: await createSettings(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(l10n.releaseThoughterTitle), findsOneWidget);
      expect(find.text(l10n.releaseDiagnosticsNotice), findsNothing);
    });

    testWidgets('只跨一个版本时不标版本分段', (tester) async {
      // 页头已经写着版本号，正文里再标一遍是重复信息。
      useTallSurface(tester);

      await tester.pumpWidget(
        buildApp(
          const ReleaseNotesPage.sinceUpgrade(lastSeenVersion: '4.0.0'),
          settingsService: await createSettings(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(ReleaseHighlights.latestVersion), findsNothing);
    });
  });

  group('设置页进来看', () {
    testWidgets('列出当前版本内容，且没有「开始使用」按钮', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('zh'));
      useTallSurface(tester);

      await tester.pumpWidget(
        buildApp(
          const ReleaseNotesPage.currentRelease(),
          settingsService: await createSettings(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(l10n.releaseFootprintsTitle), findsOneWidget);
      expect(find.text(l10n.releaseDreamingTitle), findsOneWidget);
      expect(find.text(l10n.releaseNotesCurrentLede), findsOneWidget);
      expect(find.text(l10n.releaseNotesGetStarted), findsNothing);
      expect(find.text(l10n.releaseNotesViewDetailedChangelog), findsOneWidget);
    });
  });

  group('行内主题切换器', () {
    testWidgets('点一下当场换风格', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('zh'));
      final appTheme = AppTheme();
      useTallSurface(tester);
      expect(appTheme.themeStyle, ThemeStyle.defaultStyle);

      await tester.pumpWidget(
        buildApp(
          // 主题条目是 4.0.0 加的，当前版本页（仅 4.1.0）里没有，用跨版本升级页测它。
          const ReleaseNotesPage.sinceUpgrade(lastSeenVersion: '3.7.0'),
          appTheme: appTheme,
          settingsService: await createSettings(),
        ),
      );
      await tester.pumpAndSettle();

      final target = ThemeStyle.values.firstWhere(
        (style) => style != ThemeStyle.defaultStyle,
      );
      await tester.tap(find.text(themeStyleLabel(l10n, target).$1));
      await tester.pumpAndSettle();

      expect(appTheme.themeStyle, target);
    });
  });

  group('数据收集开关', () {
    testWidgets('升级说明页常驻体验改进计划开关和唯一的说明按钮', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('zh'));
      useTallSurface(tester);

      await tester.pumpWidget(
        buildApp(
          const ReleaseNotesPage.currentRelease(),
          settingsService: await createSettings(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(l10n.settingsTelemetryTitle), findsOneWidget);
      expect(find.text(l10n.settingsSentryTitle), findsOneWidget);
      expect(find.text(l10n.learnMoreDataCollection), findsOneWidget);
    });

    testWidgets('开关可以直接改体验改进计划，说明按钮能打开统一弹窗', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('zh'));
      useTallSurface(tester);
      final settings = await createSettings();

      await tester.pumpWidget(
        buildApp(
          const ReleaseNotesPage.currentRelease(),
          settingsService: settings,
        ),
      );
      await tester.pumpAndSettle();

      expect(settings.telemetryEnabled, isFalse);
      final telemetryTile = find.widgetWithText(
        SwitchListTile,
        l10n.settingsTelemetryTitle,
      );
      await tester.tap(find.descendant(
        of: telemetryTile,
        matching: find.byType(Switch),
      ));
      await tester.pumpAndSettle();
      expect(settings.telemetryEnabled, isTrue);

      await tester.tap(find.text(l10n.learnMoreDataCollection));
      await tester.pumpAndSettle();
      expect(find.text(l10n.dataCollectionDisclosureTitle), findsOneWidget);
      expect(find.text(l10n.dataCollectionDisclosureContent), findsOneWidget);

      await tester.tap(find.text(l10n.sentryDisclosureGotIt));
      await tester.pumpAndSettle();
      expect(find.text(l10n.dataCollectionDisclosureTitle), findsNothing);
    });
  });
}
