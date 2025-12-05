/// Unit tests for FeatureGuide model localization
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/feature_guide.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';

// Shared constant for all guide IDs used in tests
const _allGuideIds = [
  'homepage_daily_quote',
  'note_page_filter',
  'note_page_favorite',
  'note_page_expand',
  'editor_metadata',
  'editor_toolbar_usage',
  'add_note_fullscreen_button',
  'settings_preferences',
  'settings_startup',
  'settings_theme',
];

void main() {
  group('FeatureGuide Localization Tests', () {
    testWidgets(
        'should return localized Chinese title for homepage_daily_quote',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('zh'),
            Locale('en'),
          ],
          home: Builder(
            builder: (BuildContext context) {
              final title = FeatureGuide.getLocalizedTitle(
                context,
                'homepage_daily_quote',
              );
              final description = FeatureGuide.getLocalizedDescription(
                context,
                'homepage_daily_quote',
              );

              expect(title, equals('每日一言小技巧'));
              expect(description, contains('单击可快速复制内容'));

              return const SizedBox();
            },
          ),
        ),
      );
    });

    testWidgets(
        'should return localized English title for homepage_daily_quote',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('zh'),
            Locale('en'),
          ],
          home: Builder(
            builder: (BuildContext context) {
              final title = FeatureGuide.getLocalizedTitle(
                context,
                'homepage_daily_quote',
              );
              final description = FeatureGuide.getLocalizedDescription(
                context,
                'homepage_daily_quote',
              );

              expect(title, equals('Daily Quote Tips'));
              expect(description, contains('Single tap to copy content'));

              return const SizedBox();
            },
          ),
        ),
      );
    });

    testWidgets('should return localized Chinese titles for all guide IDs',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('zh'),
            Locale('en'),
          ],
          home: Builder(
            builder: (BuildContext context) {
              for (final guideId in _allGuideIds) {
                final title = FeatureGuide.getLocalizedTitle(context, guideId);
                final description =
                    FeatureGuide.getLocalizedDescription(context, guideId);

                // Verify that titles and descriptions are not empty
                expect(title.isNotEmpty, isTrue,
                    reason: 'Title for $guideId should not be empty');
                expect(description.isNotEmpty, isTrue,
                    reason: 'Description for $guideId should not be empty');
              }

              return const SizedBox();
            },
          ),
        ),
      );
    });

    testWidgets('should return localized English titles for all guide IDs',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('zh'),
            Locale('en'),
          ],
          home: Builder(
            builder: (BuildContext context) {
              for (final guideId in _allGuideIds) {
                final title = FeatureGuide.getLocalizedTitle(context, guideId);
                final description =
                    FeatureGuide.getLocalizedDescription(context, guideId);

                // Verify that titles and descriptions are not empty
                expect(title.isNotEmpty, isTrue,
                    reason: 'Title for $guideId should not be empty');
                expect(description.isNotEmpty, isTrue,
                    reason: 'Description for $guideId should not be empty');
              }

              return const SizedBox();
            },
          ),
        ),
      );
    });

    testWidgets('should return empty string for unknown guide ID',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('zh'),
            Locale('en'),
          ],
          home: Builder(
            builder: (BuildContext context) {
              final title =
                  FeatureGuide.getLocalizedTitle(context, 'unknown_guide_id');
              final description = FeatureGuide.getLocalizedDescription(
                  context, 'unknown_guide_id');

              expect(title, equals(''));
              expect(description, equals(''));

              return const SizedBox();
            },
          ),
        ),
      );
    });

    test('FeatureGuideConfig should have correct placement and offset', () {
      final config = FeatureGuide.configs['homepage_daily_quote'];

      expect(config, isNotNull);
      expect(config!.placement, equals(FeatureGuidePlacement.above));
      expect(config.offset, isNull);
    });

    test('FeatureGuideConfig should handle offset correctly', () {
      final config = FeatureGuide.configs['editor_toolbar_usage'];

      expect(config, isNotNull);
      expect(config!.placement, equals(FeatureGuidePlacement.below));
      expect(config.offset, equals(const Offset(0, 8)));
    });

    test('All guide IDs should have corresponding configs', () {
      for (final guideId in _allGuideIds) {
        expect(FeatureGuide.configs.containsKey(guideId), isTrue,
            reason: 'Config for $guideId should exist');
      }
    });
  });
}
