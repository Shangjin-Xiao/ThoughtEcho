/// 偏好开关 Aptabase 统计回归测试。
///
/// 约束：只允许上报开关布尔值、固定枚举和有限数字，绝不携带用户输入内容
/// （默认作者/出处正文、标签 ID、剪贴板内容等）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/clipboard_service.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/utils/aptabase_helper.dart';

import '../../test_harness.dart';

void main() {
  group('Settings toggle tracking', () {
    late SettingsService settingsService;
    late List<Map<String, Object?>> events;

    setUp(() async {
      await TestHarness.initialize();
      settingsService = await SettingsService.create();
      events = [];
      AptabaseHelper.onTrackEventForTesting = (eventName, props) {
        events.add({'event': eventName, ...?props});
      };
    });

    tearDown(() async {
      AptabaseHelper.onTrackEventForTesting = null;
      await TestHarness.tearDown();
    });

    Map<String, Object?> lastToggle(String setting) {
      final matches = events.where(
        (e) =>
            e['event'] == 'feature_used' &&
            e['action'] == 'toggle_setting' &&
            e['setting'] == setting,
      );
      expect(matches, hasLength(1), reason: 'setting=$setting 应恰好上报一次');
      return matches.single;
    }

    Map<String, Object?> lastSelect(String setting) {
      final matches = events.where(
        (e) =>
            e['event'] == 'feature_used' &&
            e['action'] == 'select_setting' &&
            e['setting'] == setting,
      );
      expect(matches, hasLength(1), reason: 'setting=$setting 应恰好上报一次');
      return matches.single;
    }

    test('布尔偏好开关上报 toggle_setting 且只带 enabled', () async {
      await settingsService.setReportInsightsUseAI(true);
      await settingsService.setTodayThoughtsUseAI(false);
      await settingsService.setAICardGenerationEnabled(false);
      await settingsService.setPrioritizeBoldContentInCollapse(true);
      await settingsService.setShowFavoriteButton(false);
      await settingsService.setShowExactTime(true);
      await settingsService.setShowNoteEditTime(true);
      await settingsService.setEnableHiddenNotes(true);
      await settingsService.setExcerptIntentEnabled(false);
      await settingsService.setSkipNonFullscreenEditor(true);
      await settingsService.setDreamingOnIdleEnabled(false);
      await settingsService.setDreamingAfterInsightEnabled(false);
      await settingsService.setSentryEnabled(false);
      await settingsService.setSyncSkipConfirm(true);
      await settingsService.setSyncDefaultIncludeMedia(false);
      // 存量已覆盖的开关：锁住 payload 形状不漂移。
      await settingsService.setUseLocalQuotesOnly(true);
      await settingsService.setRequireBiometricForHidden(true);
      await settingsService.setAutoAttachLocation(true);
      await settingsService.setAutoAttachWeather(false);

      final expected = {
        'report_insights_ai': true,
        'today_thoughts_ai': false,
        'ai_card_generation': false,
        'prioritize_bold_content': true,
        'show_favorite_button': false,
        'show_exact_time': true,
        'show_note_edit_time': true,
        'hidden_notes': true,
        'excerpt_intent': false,
        'skip_non_fullscreen_editor': true,
        'dreaming_on_idle': false,
        'dreaming_after_insight': false,
        'sentry': false,
        'sync_skip_confirm': true,
        'sync_include_media': false,
        'local_quotes_only': true,
        'biometric_hidden': true,
        'auto_attach_location': true,
        'auto_attach_weather': false,
      };

      expect(events, hasLength(expected.length));
      expected.forEach((setting, enabled) {
        final payload = lastToggle(setting);
        // 键必须恰好这三个，多一个都算隐私泄漏面扩大。
        expect(payload.keys, {'event', 'action', 'setting', 'enabled'});
        expect(payload['enabled'], enabled);
      });
    });

    test('多选设置上报 select_setting 且 value 为固定枚举或数字', () async {
      await settingsService.setOfflineQuoteSource('allNotes');
      await settingsService.setExportFormat('pdf');
      await settingsService.setDailyQuoteProvider('zenquotes');
      await settingsService.setLocale('en');
      await settingsService.setTrashRetentionDays(90);

      expect(lastSelect('offline_quote_source')['value'], 'allNotes');
      expect(lastSelect('export_format')['value'], 'pdf');
      expect(lastSelect('daily_quote_provider')['value'], 'zenquotes');
      expect(lastSelect('locale')['value'], 'en');
      expect(lastSelect('trash_retention_days')['value'], 90);

      // 非法导出格式先归一化再上报，上报值只能是固定枚举。
      events.clear();
      await settingsService.setExportFormat('not_a_format');
      expect(lastSelect('export_format')['value'], 'card');

      // null 语言记为 system，不上报 null。
      events.clear();
      await settingsService.setLocale(null);
      expect(lastSelect('locale')['value'], 'system');
    });

    test('自由输入只上报是否填写，绝不上传内容本身', () async {
      const author = '张三私密作者名';
      const source = '某秘密出处';
      const tagIds = ['tag-id-1', 'tag-id-2'];

      await settingsService.setDefaultAuthor(author);
      await settingsService.setDefaultSource(source);
      await settingsService.setDefaultTagIds(tagIds);

      expect(lastToggle('default_author')['enabled'], isTrue);
      expect(lastToggle('default_source')['enabled'], isTrue);
      expect(lastToggle('default_tags')['enabled'], isTrue);

      for (final e in events) {
        expect(e.keys, {'event', 'action', 'setting', 'enabled'});
        for (final value in e.values) {
          final text = value.toString();
          expect(text.contains(author), isFalse);
          expect(text.contains(source), isFalse);
          for (final id in tagIds) {
            expect(text.contains(id), isFalse);
          }
        }
      }

      // 清空后上报 enabled=false，同样不带内容。
      events.clear();
      await settingsService.setDefaultAuthor(null);
      await settingsService.setDefaultAuthor('');
      await settingsService.setDefaultSource(null);
      await settingsService.setDefaultTagIds(const []);
      expect(events, hasLength(4));
      for (final e in events) {
        expect(e['enabled'], isFalse);
      }
    });

    test('剪贴板开关只上报布尔值，不触碰剪贴板内容', () {
      ClipboardService().setEnableClipboardMonitoring(true);

      expect(events, hasLength(1));
      final payload = events.single;
      expect(
        payload,
        {
          'event': 'feature_used',
          'action': 'toggle_setting',
          'setting': 'clipboard_monitoring',
          'enabled': true,
        },
      );
    });

    test('统计总开关本身不上报（自指通道）', () async {
      await settingsService.setTelemetryEnabled(true);
      await settingsService.setTelemetryEnabled(false);
      expect(events, isEmpty);
    });
  });
}
