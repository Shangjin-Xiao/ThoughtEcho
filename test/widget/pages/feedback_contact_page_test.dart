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
          ChangeNotifierProvider<SettingsService>.value(value: settingsService),
          ChangeNotifierProvider<AppTheme>.value(value: AppTheme()),
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

    testWidgets(
      'renders calm summary by default and reveals details only on tap',
      (tester) async {
        useTallSurface(tester);
        await tester.pumpWidget(buildApp());
        await tester.pumpAndSettle();

        final l10n = await AppLocalizations.delegate.load(const Locale('zh'));

        expect(find.text(l10n.settingsSentryTitle), findsOneWidget);
        expect(find.text(l10n.settingsSentryDesc), findsOneWidget);
        expect(find.text(l10n.settingsTelemetryTitle), findsOneWidget);
        expect(find.text(l10n.settingsTelemetryDesc), findsOneWidget);
        expect(find.text(l10n.learnMoreDataCollection), findsOneWidget);
        expect(find.text(l10n.dataCollectionExpandDetails), findsNWidgets(2));

        // Detailed bullet lists are collapsed by default.
        expect(find.text(l10n.settingsSentryDetail), findsNothing);
        expect(find.text(l10n.settingsTelemetryDetail), findsNothing);

        // Tap first "See what's included" toggle to expand Sentry details.
        await tester.tap(find.text(l10n.dataCollectionExpandDetails).first);
        await tester.pumpAndSettle();

        expect(find.text(l10n.settingsSentryDetail), findsOneWidget);
        expect(find.text(l10n.settingsTelemetryDetail), findsNothing);
        expect(find.text(l10n.dataCollectionCollapseDetails), findsOneWidget);

        // Tap collapse toggle to hide details again.
        await tester.tap(find.text(l10n.dataCollectionCollapseDetails));
        await tester.pumpAndSettle();

        expect(find.text(l10n.settingsSentryDetail), findsNothing);
      },
    );

    testWidgets(
      'shows user-friendly privacy dialog without developer source links and dismisses',
      (tester) async {
        useTallSurface(tester);
        await tester.pumpWidget(buildApp());
        await tester.pumpAndSettle();

        final l10n = await AppLocalizations.delegate.load(const Locale('zh'));

        final button = find.text(l10n.learnMoreDataCollection);
        expect(button, findsOneWidget);
        await tester.tap(button);
        await tester.pumpAndSettle();

        expect(find.text(l10n.dataCollectionDisclosureTitle), findsOneWidget);
        expect(find.text(l10n.dataCollectionDisclosureContent), findsOneWidget);
        expect(find.text(l10n.viewPrivacyPolicy), findsOneWidget);
        expect(find.textContaining('脱敏源码'), findsNothing);
        expect(find.textContaining('Aptabase 源码'), findsNothing);

        await tester.tap(find.text(l10n.sentryDisclosureGotIt));
        await tester.pumpAndSettle();

        expect(find.text(l10n.dataCollectionDisclosureTitle), findsNothing);
      },
    );

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

      await tester.tap(
        find.descendant(of: telemetryTile, matching: find.byType(Switch)),
      );
      await tester.pumpAndSettle();

      expect(settingsService.telemetryEnabled, isTrue);
    });
  });
}
