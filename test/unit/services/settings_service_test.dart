/// Basic unit tests for SettingsService
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/config/release_highlights.dart';
import 'package:thoughtecho/models/ai_provider_settings.dart';
import 'package:thoughtecho/models/app_settings.dart';
import 'package:thoughtecho/services/api_service.dart';
import 'package:thoughtecho/services/mmkv_service.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/theme/app_theme.dart';
import 'package:thoughtecho/theme/theme_style.dart';
import '../../test_harness.dart';

void main() {
  group('SettingsService Tests', () {
    late SettingsService settingsService;

    setUp(() async {
      // Initialize test setup with all mocks
      await TestHarness.initialize();

      // Use the create method to properly initialize the service
      settingsService = await SettingsService.create();
    });

    tearDown(() async {
      await TestHarness.tearDown();
    });

    test('should create SettingsService instance', () {
      expect(settingsService, isNotNull);
    });

    test('should have default appSettings and themeMode', () {
      expect(settingsService.appSettings, isNotNull);
      expect(settingsService.appSettings, isA<Object>());
      expect(settingsService.themeMode, isA<ThemeMode>());
    });

    test('AppSettings should default excerpt intake to enabled', () {
      expect(AppSettings.defaultSettings().excerptIntentEnabled, isTrue);
      expect(AppSettings.fromJson(const {}).excerptIntentEnabled, isTrue);
    });

    test('AppSettings should default direct fullscreen editor toggle to false',
        () {
      expect(AppSettings.defaultSettings().skipNonFullscreenEditor, isFalse);
      expect(AppSettings.fromJson(const {}).skipNonFullscreenEditor, isFalse);
    });

    test('AppSettings should default add note dialog experiments safely', () {
      expect(AppSettings.defaultSettings().addNoteDialogAutoFocus, isTrue);
      expect(AppSettings.fromJson(const {}).addNoteDialogAutoFocus, isTrue);
      expect(
        AppSettings.defaultSettings().addNoteDialogDeferAutoMetadata,
        isFalse,
      );
      expect(
        AppSettings.fromJson(const {}).addNoteDialogDeferAutoMetadata,
        isFalse,
      );
    });

    test('AppSettings should default note-list visual experiments safely', () {
      expect(AppSettings.defaultSettings().noteListDisableCardShadows, isFalse);
      expect(
          AppSettings.fromJson(const {}).noteListDisableCardShadows, isFalse);
      expect(
        AppSettings.defaultSettings().noteListDisableBackdropBlur,
        isFalse,
      );
      expect(
        AppSettings.fromJson(const {}).noteListDisableBackdropBlur,
        isFalse,
      );
    });

    test('AppSettings should default note edit time toggle to false', () {
      expect(AppSettings.defaultSettings().showNoteEditTime, isFalse);
      expect(AppSettings.fromJson(const {}).showNoteEditTime, isFalse);
    });

    test('AppSettings should default daily quote provider to hitokoto', () {
      expect(AppSettings.defaultSettings().dailyQuoteProvider, 'hitokoto');
      expect(AppSettings.fromJson(const {}).dailyQuoteProvider, 'hitokoto');
    });

    test('AppSettings should default API Ninjas categories to empty', () {
      expect(AppSettings.defaultSettings().apiNinjasCategories, isEmpty);
      expect(AppSettings.fromJson(const {}).apiNinjasCategories, isEmpty);
    });

    test('should persist excerpt intake toggle changes', () async {
      expect(settingsService.excerptIntentEnabled, isTrue);

      await settingsService.setExcerptIntentEnabled(false);

      expect(settingsService.excerptIntentEnabled, isFalse);
      expect(settingsService.appSettings.excerptIntentEnabled, isFalse);
    });

    test('should persist and trim user nickname', () async {
      expect(settingsService.userNickname, isEmpty);

      await settingsService.setUserNickname('  阿澈  ');
      expect(settingsService.userNickname, '阿澈');

      // 重建服务才能证明称呼真的落了盘：只读当前实例等于在读内存副本，
      // 而这个值的意义就是「下次打开还在」。
      expect((await SettingsService.create()).userNickname, '阿澈');

      await settingsService.setUserNickname('');
      expect(settingsService.userNickname, isEmpty);
      expect((await SettingsService.create()).userNickname, isEmpty);
    });

    test('should persist add note dialog experiment toggles', () async {
      expect(settingsService.addNoteDialogAutoFocus, isTrue);
      expect(settingsService.addNoteDialogDeferAutoMetadata, isFalse);

      await settingsService.setAddNoteDialogAutoFocus(false);
      await settingsService.setAddNoteDialogDeferAutoMetadata(true);

      expect(settingsService.addNoteDialogAutoFocus, isFalse);
      expect(settingsService.appSettings.addNoteDialogAutoFocus, isFalse);
      expect(settingsService.addNoteDialogDeferAutoMetadata, isTrue);
      expect(
        settingsService.appSettings.addNoteDialogDeferAutoMetadata,
        isTrue,
      );
    });

    test('should persist note-list visual experiment toggles', () async {
      expect(settingsService.noteListDisableCardShadows, isFalse);
      expect(settingsService.noteListDisableBackdropBlur, isFalse);

      await settingsService.setNoteListDisableCardShadows(true);
      await settingsService.setNoteListDisableBackdropBlur(true);

      expect(settingsService.noteListDisableCardShadows, isTrue);
      expect(settingsService.appSettings.noteListDisableCardShadows, isTrue);
      expect(settingsService.noteListDisableBackdropBlur, isTrue);
      expect(settingsService.appSettings.noteListDisableBackdropBlur, isTrue);
    });

    test(
      'applyIncomingTrashSettings should ignore missing timestamp when local is newer',
      () async {
        await settingsService.setTrashRetentionDays(
          90,
          modifiedAt: DateTime.utc(2026, 3, 28, 10),
        );

        final applied = await settingsService.applyIncomingTrashSettings({
          'retention_days': 7,
        });

        expect(applied, isFalse);
        expect(settingsService.trashRetentionDays, equals(90));
        expect(
          settingsService.trashRetentionLastModified,
          equals('2026-03-28T10:00:00.000Z'),
        );
      },
    );

    test(
      'applyIncomingTrashSettings should ignore payload without retention_days',
      () async {
        await settingsService.setTrashRetentionDays(
          90,
          modifiedAt: DateTime.utc(2026, 3, 28, 10),
        );

        final applied = await settingsService.applyIncomingTrashSettings({
          'last_modified': '2026-03-29T10:00:00.000Z',
        });

        expect(applied, isFalse);
        expect(settingsService.trashRetentionDays, equals(90));
        expect(
          settingsService.trashRetentionLastModified,
          equals('2026-03-28T10:00:00.000Z'),
        );
      },
    );

    test('setTrashRetentionDays should persist modifiedAt as UTC timestamp',
        () async {
      final localTime = DateTime(2026, 3, 28, 10, 30, 0);

      await settingsService.setTrashRetentionDays(
        90,
        modifiedAt: localTime,
      );

      expect(
        settingsService.trashRetentionLastModified,
        equals(localTime.toUtc().toIso8601String()),
      );
    });

    test(
      'applyIncomingTrashSettings should ignore unparseable retention_days',
      () async {
        await settingsService.setTrashRetentionDays(
          30,
          modifiedAt: DateTime.utc(2026, 3, 28, 10),
        );

        final applied = await settingsService.applyIncomingTrashSettings({
          'retention_days': 'invalid',
          'last_modified': '2026-03-29T10:00:00.000Z',
        });

        expect(applied, isFalse);
        expect(settingsService.trashRetentionDays, equals(30));
        expect(
          settingsService.trashRetentionLastModified,
          equals('2026-03-28T10:00:00.000Z'),
        );
      },
    );

    test(
      'applyIncomingTrashSettings should ignore unsupported retention_days',
      () async {
        await settingsService.setTrashRetentionDays(
          7,
          modifiedAt: DateTime.utc(2026, 3, 28, 10),
        );

        final applied = await settingsService.applyIncomingTrashSettings({
          'retention_days': 999,
          'last_modified': '2026-03-29T10:00:00.000Z',
        });

        expect(applied, isFalse);
        expect(settingsService.trashRetentionDays, equals(7));
        expect(
          settingsService.trashRetentionLastModified,
          equals('2026-03-28T10:00:00.000Z'),
        );
      },
    );

    test(
      'applyIncomingTrashSettings should reject fractional num retention_days',
      () async {
        await settingsService.setTrashRetentionDays(
          30,
          modifiedAt: DateTime.utc(2026, 3, 28, 10),
        );

        final applied = await settingsService.applyIncomingTrashSettings({
          'retention_days': 7.9,
          'last_modified': '2026-03-29T10:00:00.000Z',
        });

        expect(applied, isFalse);
        expect(settingsService.trashRetentionDays, equals(30));
        expect(
          settingsService.trashRetentionLastModified,
          equals('2026-03-28T10:00:00.000Z'),
        );
      },
    );

    test('should persist direct fullscreen editor toggle changes', () async {
      expect(settingsService.skipNonFullscreenEditor, isFalse);

      await settingsService.setSkipNonFullscreenEditor(true);

      expect(settingsService.skipNonFullscreenEditor, isTrue);
      expect(settingsService.appSettings.skipNonFullscreenEditor, isTrue);
    });

    test('should persist note edit time toggle changes', () async {
      expect(settingsService.showNoteEditTime, isFalse);

      await settingsService.setShowNoteEditTime(true);

      expect(settingsService.showNoteEditTime, isTrue);
      expect(settingsService.appSettings.showNoteEditTime, isTrue);
    });

    test('should persist daily quote provider changes', () async {
      expect(settingsService.dailyQuoteProvider, 'hitokoto');

      await settingsService.setDailyQuoteProvider('zenquotes');

      expect(settingsService.dailyQuoteProvider, 'zenquotes');
      expect(settingsService.appSettings.dailyQuoteProvider, 'zenquotes');
    });

    test('should persist API Ninjas categories changes', () async {
      expect(settingsService.apiNinjasCategories, isEmpty);

      await settingsService.setApiNinjasCategories(
        const ['wisdom', 'success'],
      );

      expect(settingsService.apiNinjasCategories, ['wisdom', 'success']);
      expect(
        settingsService.appSettings.apiNinjasCategories,
        ['wisdom', 'success'],
      );
    });

    test('set locale with region keeps locale-native daily quote provider',
        () async {
      await settingsService.setLocale('zh_CN');

      final provider = ApiService.recommendedDailyQuoteProviderForLanguage(
        settingsService.localeCode,
      );

      expect(provider, ApiService.hitokotoProvider);
    });

    test('should persist Sentry settings changes', () async {
      // Initialize to false to ensure a consistent starting state
      await settingsService.setSentryEnabled(false);
      await settingsService.setSentryDisclosureShown(false);

      expect(settingsService.sentryEnabled, isFalse);
      expect(settingsService.sentryDisclosureShown, isFalse);

      await settingsService.setSentryEnabled(true);
      await settingsService.setSentryDisclosureShown(true);

      expect(settingsService.sentryEnabled, isTrue);
      expect(settingsService.sentryDisclosureShown, isTrue);
      expect(settingsService.appSettings.sentryEnabled, isTrue);
      expect(settingsService.appSettings.sentryDisclosureShown, isTrue);

      // Verify persistence by creating a new SettingsService instance
      final rebuiltService = await SettingsService.create();
      expect(rebuiltService.sentryEnabled, isTrue);
      expect(rebuiltService.sentryDisclosureShown, isTrue);
      expect(rebuiltService.appSettings.sentryEnabled, isTrue);
      expect(rebuiltService.appSettings.sentryDisclosureShown, isTrue);
    });

    group('全新安装默认主题风格', () {
      test('首次安装种下信笺', () async {
        // setUp 里的 create() 走的正是首次安装分支。
        expect(
          MMKVService().getString(ThemeStyle.storageKey),
          ThemeStyle.freshInstallStyle.name,
        );
        expect(ThemeStyle.freshInstallStyle, ThemeStyle.paper);
      });

      test('随后初始化的 AppTheme 读到的就是信笺', () async {
        // #513 的默认值一直没生效就败在这个顺序上：SettingsService 先跑，
        // app_installed_v2 / app_settings 已经写好，主题层再反推「是不是全新安装」
        // 只会推成老用户，于是新装用户看到的还是 material。
        final appTheme = AppTheme();
        await appTheme.initialize();
        expect(appTheme.themeStyle, ThemeStyle.paper);
      });

      test('老用户不会被种上风格', () async {
        await MMKVService().remove(ThemeStyle.storageKey);
        await MMKVService().setBool('app_installed_v2', true);

        await SettingsService.create();

        expect(MMKVService().getString(ThemeStyle.storageKey), isNull);
      });

      test('已经有风格取值时不覆盖', () async {
        // 从备份恢复出来的取值也是用户自己选的，覆盖掉就是替他改外观。
        await MMKVService().setString(
          ThemeStyle.storageKey,
          ThemeStyle.plain.name,
        );
        await MMKVService().remove('app_installed_v2');

        await SettingsService.create();

        expect(
          MMKVService().getString(ThemeStyle.storageKey),
          ThemeStyle.plain.name,
        );
      });
    });

    group('更新说明已读版本', () {
      // 存储键的字面量：这里就是要钉住它。改键名等于把所有老用户的已读记录清零，
      // 让他们重看一遍更新说明——不该悄悄发生。
      const key = 'last_seen_release_version';

      test('新装用户直接落在最新版，不会被更新说明拦住', () {
        // setUp 里的 create() 走的正是首次安装分支。
        expect(
          settingsService.lastSeenReleaseVersion,
          ReleaseHighlights.latestVersion,
        );
      });

      test('读不到已读版本时，用 sentryDisclosureShown 推基线', () async {
        // 存量用户第一次升上来就是这个状态：字段是这一版才加的，一定读不到。
        await settingsService.setSentryDisclosureShown(true);
        await MMKVService().remove(key);
        expect(
          settingsService.lastSeenReleaseVersion,
          ReleaseHighlights.sentryDisclosureVersion,
        );

        await settingsService.setSentryDisclosureShown(false);
        await MMKVService().remove(key);
        expect(
          settingsService.lastSeenReleaseVersion,
          ReleaseHighlights.earliestVersion,
        );
      });

      test('空串按「没记过」处理，同样走兜底', () async {
        await settingsService.setSentryDisclosureShown(true);
        await MMKVService().setString(key, '');

        expect(
          settingsService.lastSeenReleaseVersion,
          ReleaseHighlights.sentryDisclosureVersion,
        );
      });

      test('写入后持久化，重建服务仍读得到', () async {
        await settingsService.setLastSeenReleaseVersion('3.9.0');
        expect(settingsService.lastSeenReleaseVersion, '3.9.0');

        final rebuiltService = await SettingsService.create();
        expect(rebuiltService.lastSeenReleaseVersion, '3.9.0');
      });

      test('值没变时不写也不通知', () async {
        // 这个方法每次冷启动都会被调一次，重复通知等于每次启动白重建一遍监听者。
        await settingsService.setLastSeenReleaseVersion('4.0.0');

        var notified = 0;
        void listener() => notified++;
        settingsService.addListener(listener);
        addTearDown(() => settingsService.removeListener(listener));

        await settingsService.setLastSeenReleaseVersion('4.0.0');
        expect(notified, 0);

        await settingsService.setLastSeenReleaseVersion('4.1.0');
        expect(notified, 1);
      });
    });

    test('updateAISettings should omit apiKey from persisted MMKV JSON',
        () async {
      final aiSettings = settingsService.aiSettings.copyWith(
        apiKey: 'secret-key-123',
        model: 'gpt-4o',
      );

      await settingsService.updateAISettings(aiSettings);

      expect(settingsService.aiSettings.apiKey, isEmpty);
      expect(settingsService.aiSettings.model, equals('gpt-4o'));
    });

    test('新用户配置有效 AI 服务时应自动开启相关 AI 功能', () async {
      // Arrange
      await settingsService.setHasCompletedOnboarding(false);
      await settingsService.setReportInsightsUseAI(false);
      await settingsService.setTodayThoughtsUseAI(false);
      await settingsService.setAICardGenerationEnabled(false);

      expect(settingsService.reportInsightsUseAI, isFalse);
      expect(settingsService.todayThoughtsUseAI, isFalse);
      expect(settingsService.aiCardGenerationEnabled, isFalse);

      final multiSettings = settingsService.multiAISettings.copyWith(
        providers: [
          ...settingsService.multiAISettings.providers,
          const AIProviderSettings(
            id: 'test_provider',
            name: 'Test AI',
            apiUrl: 'https://api.openai.com/v1',
            model: 'gpt-4o',
            isEnabled: true,
          ),
        ],
      );

      // Act
      await settingsService.saveMultiAISettings(multiSettings);

      // Assert
      expect(settingsService.reportInsightsUseAI, isTrue);
      expect(settingsService.todayThoughtsUseAI, isTrue);
      expect(settingsService.aiCardGenerationEnabled, isTrue);

      final rebuiltService = await SettingsService.create();
      expect(rebuiltService.reportInsightsUseAI, isTrue);
      expect(rebuiltService.todayThoughtsUseAI, isTrue);
      expect(rebuiltService.aiCardGenerationEnabled, isTrue);
    });

    test('无效或禁用的 AI 服务不应触发自动开启 AI 功能', () async {
      // Arrange
      await settingsService.setHasCompletedOnboarding(false);
      await settingsService.setReportInsightsUseAI(false);
      await settingsService.setTodayThoughtsUseAI(false);
      await settingsService.setAICardGenerationEnabled(false);

      final disabledOrEmptySettings = settingsService.multiAISettings.copyWith(
        providers: [
          const AIProviderSettings(
            id: 'disabled_provider',
            name: 'Disabled AI',
            apiUrl: 'https://api.openai.com/v1',
            model: 'gpt-4o',
            isEnabled: false,
          ),
          const AIProviderSettings(
            id: 'empty_url_provider',
            name: 'Empty URL AI',
            apiUrl: '   ',
            model: 'gpt-4o',
            isEnabled: true,
          ),
        ],
      );

      // Act
      await settingsService.saveMultiAISettings(disabledOrEmptySettings);

      // Assert
      expect(settingsService.reportInsightsUseAI, isFalse);
      expect(settingsService.todayThoughtsUseAI, isFalse);
      expect(settingsService.aiCardGenerationEnabled, isFalse);
    });

    test('并发 saveMultiAISettings 和 setHasCompletedOnboarding 应保持状态一致',
        () async {
      // Arrange
      await settingsService.setHasCompletedOnboarding(false);
      await settingsService.setReportInsightsUseAI(false);

      final multiSettings = settingsService.multiAISettings.copyWith(
        providers: [
          ...settingsService.multiAISettings.providers,
          const AIProviderSettings(
            id: 'test_provider_concurrent',
            name: 'Test AI Concurrent',
            apiUrl: 'https://api.openai.com/v1',
            model: 'gpt-4o',
            isEnabled: true,
          ),
        ],
      );

      // Act: 并发触发
      final future1 = settingsService.saveMultiAISettings(multiSettings);
      final future2 = settingsService.setHasCompletedOnboarding(true);

      await Future.wait([future1, future2]);

      // Assert: 重建后确认内存与持久化保持最终调用的正确状态
      final rebuiltService = await SettingsService.create();
      expect(rebuiltService.hasCompletedOnboarding(), isTrue);
    });
  });
}
