import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import 'package:thoughtecho/core/config/distribution_config.dart';
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
    tearDown(() {
      DistributionConfig.resetDebugOverrides();
      UpdateBottomSheet.debugUrlLauncher = null;
      debugDefaultTargetPlatformOverride = null;
    });

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

      final cards = tester.widgetList<Card>(find.byType(Card)).toList();
      expect(cards.length, 2);
      for (final card in cards) {
        expect(card.margin, EdgeInsets.zero);
      }

      final markdown = tester.widget<MarkdownBody>(find.byType(MarkdownBody));
      expect(markdown.styleSheet?.em?.fontStyle, FontStyle.italic);
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

      final cards = tester.widgetList<Card>(find.byType(Card)).toList();
      expect(cards.length, 1);
      expect(cards.first.margin, EdgeInsets.zero);
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

    testWidgets('标准渠道保留查看详情按钮，Play 渠道隐藏外部详情按钮并显示前往商店', (
      WidgetTester tester,
    ) async {
      // 1. 标准渠道显示“查看详情”
      DistributionConfig.debugChannelOverride = DistributionChannel.standard;
      final standardWidget = await buildTestableWidget(
        child: UpdateBottomSheet(
          versionInfo: dummyVersionInfoAvailable,
          buttons: [
            UpdateButtonConfig(
              type: UpdateButtonType.ignore,
              label: '忽略',
              onPressed: () {},
            ),
            UpdateButtonConfig(
              type: UpdateButtonType.viewDetails,
              label: '查看详情',
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
      await tester.pumpWidget(standardWidget);
      await tester.pumpAndSettle();
      expect(find.text('查看详情'), findsOneWidget);

      // 2. Play 渠道隐藏 UpdateButtonType.viewDetails
      DistributionConfig.debugChannelOverride = DistributionChannel.play;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      final appTheme = AppTheme();
      await appTheme.setThemeStyle(ThemeStyle.defaultStyle);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          theme: appTheme.createLightThemeData(),
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  UpdateBottomSheet.showWithIgnoreOption(
                    context,
                    dummyVersionInfoAvailable,
                  );
                },
                child: const Text('打开更新弹窗'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('打开更新弹窗'));
      await tester.pumpAndSettle();

      expect(find.text('查看详情'), findsNothing);
      expect(find.text('前往商店'), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('openGooglePlayStore 优先使用 market:// 协议并回退到 Play 网页链接', (
      WidgetTester tester,
    ) async {
      final launchedUris = <Uri>[];
      UpdateBottomSheet.debugUrlLauncher = (uri, {required mode}) async {
        launchedUris.add(uri);
        if (uri.scheme == 'market') {
          return false;
        }
        return true;
      };

      late BuildContext capturedContext;
      final widget = await buildTestableWidget(
        child: Builder(
          builder: (context) {
            capturedContext = context;
            return const SizedBox.shrink();
          },
        ),
      );
      await tester.pumpWidget(widget);
      await tester.pumpAndSettle();

      await UpdateBottomSheet.openGooglePlayStore(capturedContext);

      expect(
        launchedUris.map((u) => u.toString()).toList(),
        equals([
          'market://details?id=com.shangjin.thoughtecho',
          'https://play.google.com/store/apps/details?id=com.shangjin.thoughtecho',
        ]),
      );
    });
  });
}
