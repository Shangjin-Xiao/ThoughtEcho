import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/pages/feedback_contact_page.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/theme/app_theme.dart';

import '../../test_harness.dart';

void main() {
  group('FeedbackContactPage Widget Tests', () {
    late SettingsService settingsService;

    setUp(() async {
      await TestHarness.initialize();
      settingsService = await SettingsService.create();
    });

    tearDown(() async {
      await TestHarness.tearDown();
    });

    void useTallSurface(WidgetTester tester) {
      tester.view.physicalSize = const Size(1000, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    Widget buildApp() {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsService>.value(
            value: settingsService,
          ),
          ChangeNotifierProvider<AppTheme>.value(
            value: AppTheme(),
          ),
        ],
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: FeedbackContactPage(),
        ),
      );
    }

    testWidgets('renders Sentry and Telemetry tiles and disclosure buttons',
        (tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      final l10n = await AppLocalizations.delegate.load(const Locale('zh'));

      expect(find.text(l10n.settingsSentryTitle), findsOneWidget);
      expect(find.text(l10n.settingsTelemetryTitle), findsOneWidget);
      expect(find.text(l10n.learnMoreDataCollection), findsNWidgets(2));
    });

    testWidgets(
        'shows unified data collection details dialog covering both Sentry and Aptabase and dismisses',
        (tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      final l10n = await AppLocalizations.delegate.load(const Locale('zh'));

      // Tap the first "查看收集详情与脱敏源码" (from Sentry tile)
      final buttons = find.text(l10n.learnMoreDataCollection);
      await tester.tap(buttons.first);
      await tester.pumpAndSettle();

      // Verify dialog is shown explaining both Sentry and Aptabase
      expect(find.text(l10n.dataCollectionDisclosureTitle), findsOneWidget);
      expect(find.text(l10n.dataCollectionDisclosureContent), findsOneWidget);
      expect(find.text(l10n.viewSentrySourceCode), findsOneWidget);
      expect(find.text(l10n.viewAptabaseSourceCode), findsOneWidget);
      expect(find.text(l10n.viewPrivacyPolicy), findsOneWidget);

      // Dismiss dialog
      await tester.tap(find.text(l10n.sentryDisclosureGotIt));
      await tester.pumpAndSettle();

      expect(find.text(l10n.dataCollectionDisclosureTitle), findsNothing);

      // Tap the second "查看收集详情与脱敏源码" (from Telemetry tile)
      await tester.tap(buttons.last);
      await tester.pumpAndSettle();

      // Verify dialog also shows the same comprehensive explanation
      expect(find.text(l10n.dataCollectionDisclosureTitle), findsOneWidget);
      expect(find.text(l10n.dataCollectionDisclosureContent), findsOneWidget);
      expect(find.text(l10n.viewSentrySourceCode), findsOneWidget);
      expect(find.text(l10n.viewAptabaseSourceCode), findsOneWidget);
      expect(find.text(l10n.viewPrivacyPolicy), findsOneWidget);

      // Dismiss dialog
      await tester.tap(find.text(l10n.sentryDisclosureGotIt));
      await tester.pumpAndSettle();

      expect(find.text(l10n.dataCollectionDisclosureTitle), findsNothing);
    });

    testWidgets('toggling telemetry switches preference value', (tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(settingsService.telemetryEnabled, isFalse);

      final l10n = await AppLocalizations.delegate.load(const Locale('zh'));
      final telemetryTile = find.widgetWithText(
        SwitchListTile,
        l10n.settingsTelemetryTitle,
      );
      expect(telemetryTile, findsOneWidget);

      // Tap the switch
      await tester.tap(find.descendant(
        of: telemetryTile,
        matching: find.byType(Switch),
      ));
      await tester.pumpAndSettle();

      expect(settingsService.telemetryEnabled, isTrue);
    });
  });
}
