import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/app_settings.dart';

import '../../test_setup.dart';

void main() {
  setUpAll(() async {
    await setupTestEnvironment();
  });

  group('AppSettings Tests', () {
    test('defaultSettings should have expected default values', () {
      final settings = AppSettings.defaultSettings();

      expect(settings.hitokotoType, equals('a,b,c,d,e,f,g,h,i,j,k'));
      expect(settings.dailyQuoteProvider, equals('hitokoto'));
      expect(settings.apiNinjasCategories, isEmpty);
      expect(settings.clipboardMonitoringEnabled, isFalse);
      expect(settings.defaultStartPage, equals(0));
      expect(settings.hasCompletedOnboarding, isFalse);
      expect(settings.aiCardGenerationEnabled, isTrue);
      expect(settings.reportInsightsUseAI, isFalse);
      expect(settings.todayThoughtsUseAI, isTrue);
      expect(settings.prioritizeBoldContentInCollapse, isFalse);
      expect(settings.showFavoriteButton, isTrue);
      expect(settings.useLocalQuotesOnly, isFalse);
      expect(settings.localeCode, isNull);
      expect(settings.showExactTime, isFalse);
      expect(settings.showNoteEditTime, isFalse);
      expect(settings.enableHiddenNotes, isFalse);
      expect(settings.requireBiometricForHidden, isFalse);
      expect(settings.developerMode, isFalse);
      expect(settings.enableFirstOpenScrollPerfMonitor, isFalse);
      expect(settings.addNoteDialogAutoFocus, isTrue);
      expect(settings.addNoteDialogDeferAutoMetadata, isFalse);
      expect(settings.autoAttachLocation, isFalse);
      expect(settings.autoAttachWeather, isFalse);
      expect(settings.excerptIntentEnabled, isTrue);
      expect(settings.defaultAuthor, isNull);
      expect(settings.defaultSource, isNull);
      expect(settings.defaultTagIds, isEmpty);
      expect(settings.anniversaryShown, isFalse);
      expect(settings.anniversaryAnimationEnabled, isTrue);
      expect(settings.trashRetentionDays, equals(30));
      expect(settings.trashRetentionLastModified, isNull);
      expect(settings.skipNonFullscreenEditor, isFalse);
      expect(settings.offlineQuoteSource, equals('tagOnly'));
      expect(settings.sentryEnabled, isFalse);
      expect(settings.sentryDisclosureShown, isFalse);
    });

    test('toJson and fromJson should be symmetrical', () {
      final settings = AppSettings(
        hitokotoType: 'a,b',
        dailyQuoteProvider: 'zenquotes',
        apiNinjasCategories: ['wisdom'],
        clipboardMonitoringEnabled: true,
        defaultStartPage: 1,
        hasCompletedOnboarding: true,
        aiCardGenerationEnabled: false,
        reportInsightsUseAI: true,
        todayThoughtsUseAI: false,
        prioritizeBoldContentInCollapse: true,
        showFavoriteButton: false,
        useLocalQuotesOnly: true,
        localeCode: 'zh',
        showExactTime: true,
        showNoteEditTime: true,
        enableHiddenNotes: true,
        requireBiometricForHidden: true,
        developerMode: true,
        enableFirstOpenScrollPerfMonitor: true,
        addNoteDialogAutoFocus: false,
        addNoteDialogDeferAutoMetadata: true,
        autoAttachLocation: true,
        autoAttachWeather: true,
        excerptIntentEnabled: false,
        defaultAuthor: 'Author',
        defaultSource: 'Source',
        defaultTagIds: ['tag1'],
        anniversaryShown: true,
        anniversaryAnimationEnabled: false,
        trashRetentionDays: 90,
        trashRetentionLastModified: '2023-10-27T10:00:00Z',
        skipNonFullscreenEditor: true,
        offlineQuoteSource: 'all',
        sentryEnabled: true,
        sentryDisclosureShown: true,
      );

      final json = settings.toJson();
      final fromJson = AppSettings.fromJson(json);

      expect(fromJson.hitokotoType, equals(settings.hitokotoType));
      expect(fromJson.dailyQuoteProvider, equals(settings.dailyQuoteProvider));
      expect(
        fromJson.apiNinjasCategories,
        equals(settings.apiNinjasCategories),
      );
      expect(
        fromJson.clipboardMonitoringEnabled,
        equals(settings.clipboardMonitoringEnabled),
      );
      expect(fromJson.defaultStartPage, equals(settings.defaultStartPage));
      expect(
        fromJson.hasCompletedOnboarding,
        equals(settings.hasCompletedOnboarding),
      );
      expect(
        fromJson.aiCardGenerationEnabled,
        equals(settings.aiCardGenerationEnabled),
      );
      expect(
        fromJson.reportInsightsUseAI,
        equals(settings.reportInsightsUseAI),
      );
      expect(fromJson.todayThoughtsUseAI, equals(settings.todayThoughtsUseAI));
      expect(
        fromJson.prioritizeBoldContentInCollapse,
        equals(settings.prioritizeBoldContentInCollapse),
      );
      expect(fromJson.showFavoriteButton, equals(settings.showFavoriteButton));
      expect(fromJson.useLocalQuotesOnly, equals(settings.useLocalQuotesOnly));
      expect(fromJson.localeCode, equals(settings.localeCode));
      expect(fromJson.showExactTime, equals(settings.showExactTime));
      expect(fromJson.showNoteEditTime, equals(settings.showNoteEditTime));
      expect(fromJson.enableHiddenNotes, equals(settings.enableHiddenNotes));
      expect(
        fromJson.requireBiometricForHidden,
        equals(settings.requireBiometricForHidden),
      );
      expect(fromJson.developerMode, equals(settings.developerMode));
      expect(
        fromJson.enableFirstOpenScrollPerfMonitor,
        equals(settings.enableFirstOpenScrollPerfMonitor),
      );
      expect(
        fromJson.addNoteDialogAutoFocus,
        equals(settings.addNoteDialogAutoFocus),
      );
      expect(
        fromJson.addNoteDialogDeferAutoMetadata,
        equals(settings.addNoteDialogDeferAutoMetadata),
      );
      expect(fromJson.autoAttachLocation, equals(settings.autoAttachLocation));
      expect(fromJson.autoAttachWeather, equals(settings.autoAttachWeather));
      expect(
        fromJson.excerptIntentEnabled,
        equals(settings.excerptIntentEnabled),
      );
      expect(fromJson.defaultAuthor, equals(settings.defaultAuthor));
      expect(fromJson.defaultSource, equals(settings.defaultSource));
      expect(fromJson.defaultTagIds, equals(settings.defaultTagIds));
      expect(fromJson.anniversaryShown, equals(settings.anniversaryShown));
      expect(
        fromJson.anniversaryAnimationEnabled,
        equals(settings.anniversaryAnimationEnabled),
      );
      expect(fromJson.trashRetentionDays, equals(settings.trashRetentionDays));
      expect(
        fromJson.trashRetentionLastModified,
        equals(settings.trashRetentionLastModified),
      );
      expect(
        fromJson.skipNonFullscreenEditor,
        equals(settings.skipNonFullscreenEditor),
      );
      expect(fromJson.offlineQuoteSource, equals(settings.offlineQuoteSource));
      expect(fromJson.sentryEnabled, equals(settings.sentryEnabled));
      expect(fromJson.sentryDisclosureShown,
          equals(settings.sentryDisclosureShown));
    });

    test('fromJson should handle different types for trashRetentionDays', () {
      expect(
        AppSettings.fromJson({'trashRetentionDays': 7}).trashRetentionDays,
        equals(7),
      );
      expect(
        AppSettings.fromJson({'trashRetentionDays': 7.0}).trashRetentionDays,
        equals(7),
      );
      expect(
        AppSettings.fromJson({'trashRetentionDays': '90'}).trashRetentionDays,
        equals(90),
      );
      expect(
        AppSettings.fromJson({
          'trashRetentionDays': 'invalid',
        }).trashRetentionDays,
        equals(30),
      ); // fallback
      expect(
        AppSettings.fromJson({'trashRetentionDays': 15}).trashRetentionDays,
        equals(30),
      ); // invalid value normalized to default
    });

    test('fromJson should handle unsupported values', () {
      final settings = AppSettings.fromJson({
        'dailyQuoteProvider': 'invalid_provider',
        'apiNinjasCategories': ['invalid_category', 'wisdom'],
      });

      expect(settings.dailyQuoteProvider, equals('hitokoto'));
      expect(settings.apiNinjasCategories, equals(['wisdom']));
    });

    test('copyWith should update fields correctly', () {
      final settings = AppSettings.defaultSettings();
      final updated = settings.copyWith(
        hitokotoType: 'a',
        dailyQuoteProvider: 'meigen',
        clipboardMonitoringEnabled: true,
        sentryEnabled: true,
        sentryDisclosureShown: true,
      );

      expect(updated.hitokotoType, equals('a'));
      expect(updated.dailyQuoteProvider, equals('meigen'));
      expect(updated.clipboardMonitoringEnabled, isTrue);
      expect(updated.sentryEnabled, isTrue);
      expect(updated.sentryDisclosureShown, isTrue);
      expect(updated.defaultStartPage, equals(settings.defaultStartPage));
    });

    test('copyWith clear flags should set fields to null', () {
      final settings = AppSettings(
        localeCode: 'en',
        defaultAuthor: 'Me',
        defaultSource: 'My Mind',
        trashRetentionLastModified: 'some-date',
      );

      final cleared = settings.copyWith(
        clearLocale: true,
        clearDefaultAuthor: true,
        clearDefaultSource: true,
        clearTrashRetentionLastModified: true,
      );

      expect(cleared.localeCode, isNull);
      expect(cleared.defaultAuthor, isNull);
      expect(cleared.defaultSource, isNull);
      expect(cleared.trashRetentionLastModified, isNull);
    });

    test('normalizeTrashRetentionDays should return 30 for invalid values', () {
      expect(AppSettings.normalizeTrashRetentionDays(null), equals(30));
      expect(AppSettings.normalizeTrashRetentionDays(15), equals(30));
      expect(AppSettings.normalizeTrashRetentionDays(7), equals(7));
      expect(AppSettings.normalizeTrashRetentionDays(30), equals(30));
      expect(AppSettings.normalizeTrashRetentionDays(90), equals(90));
    });
  });
}
