import 'package:flutter_test/flutter_test.dart';

import 'package:thoughtecho/utils/aptabase_helper.dart';

void main() {
  group('AptabaseHelper', () {
    test(
        'trackEvent and trackPageView do not throw when disabled or uninitialized',
        () {
      expect(() => AptabaseHelper.trackPageView('home'), returnsNormally);
      expect(
        () => AptabaseHelper.trackEvent('test_event', {'key': 'val'}),
        returnsNormally,
      );
    });

    test('configure handles disabled gracefully', () async {
      await expectLater(
        AptabaseHelper.configure(enabled: false),
        completes,
      );
    });

    test('concurrent configure calls complete without error', () async {
      await expectLater(
        Future.wait([
          AptabaseHelper.configure(enabled: true),
          AptabaseHelper.configure(enabled: true),
        ]),
        completes,
      );
    });

    test('tracks feature_used events with action enums without throwing', () {
      const actions = [
        'create_note',
        'save_note',
        'delete_note',
        'restore_note',
        'empty_trash',
        'toggle_favorite',
        'filter_by_tag',
        'sort_changed',
        'search_performed',
        'create_tag',
        'delete_tag',
        'ai_message_send',
        'ai_card_generate',
        'ai_card_regenerate',
        'ai_insight_generate',
        'ai_insight_fallback',
        'ai_proposal_accept',
        'ai_action_analyze_source',
        'ai_action_polish',
        'ai_action_continue',
        'ai_action_analyze_content',
        'ai_action_ask_note',
        'export_text_backup',
        'restore_backup',
        'merge_backup',
        'share_card_image',
        'export_card_image',
        'webdav_sync_manual',
        'webdav_test_connection',
        'export_pdf',
        'localsend_send',
        'smart_push_test',
        'switch_theme_style',
        'switch_theme_mode',
        'switch_theme_accent',
        'toggle_setting',
        'daily_quote_copy',
        'daily_quote_save',
        'daily_quote_refresh',
        'daily_prompt_generate',
        'daily_prompt_ask',
        'ai_test_connection',
        'ai_provider_save',
      ];

      for (final action in actions) {
        final props = {'action': action};
        expect(
          () => AptabaseHelper.trackEvent('feature_used', props),
          returnsNormally,
        );

        // Verify privacy compliance: payload must strictly only contain action enum
        expect(props.keys.length, equals(1));
        expect(props.keys.first, equals('action'));
        expect(props['action'], equals(action));
      }
    });

    test('tracks page_view events across all core pages without throwing', () {
      const pages = [
        'home',
        'notes',
        'explore',
        'settings',
        'thoughter',
        'note_editor',
        'backup_restore',
        'webdav_sync',
        'trash',
        'tag_settings',
        'map_memory',
        'theme_settings',
        'smart_push_settings',
        'note_sync',
        'ai_settings',
        'agent_memory',
      ];

      for (final page in pages) {
        expect(
          () => AptabaseHelper.trackPageView(page),
          returnsNormally,
        );
      }
    });

    test('tracks enriched feature_used events with anonymous boolean metadata',
        () {
      final events = <Map<String, dynamic>>[];
      AptabaseHelper.onTrackEventForTesting = (eventName, props) {
        events.add({'event': eventName, 'props': props});
      };

      try {
        AptabaseHelper.trackEvent('feature_used', {
          'action': 'save_note',
          'has_tags': true,
          'has_weather': false,
          'has_location': true,
          'has_source': false,
        });

        AptabaseHelper.trackEvent('feature_used', {
          'action': 'ai_insight_generate',
          'is_ai': true,
          'is_empty_period': false,
        });

        AptabaseHelper.trackEvent('feature_used', {
          'action': 'ai_insight_fallback',
          'is_empty_period': true,
        });

        AptabaseHelper.trackEvent('feature_used', {
          'action': 'toggle_setting',
          'setting': 'agent_memory',
          'enabled': true,
        });

        expect(events, hasLength(4));
        expect(events[0]['props']['action'], 'save_note');
        expect(events[0]['props']['has_tags'], isTrue);
        expect(events[0]['props']['has_weather'], isFalse);
        expect(events[0]['props']['has_location'], isTrue);
        expect(events[0]['props']['has_source'], isFalse);

        expect(events[1]['props']['action'], 'ai_insight_generate');
        expect(events[1]['props']['is_ai'], isTrue);
        expect(events[1]['props']['is_empty_period'], isFalse);

        expect(events[2]['props']['action'], 'ai_insight_fallback');
        expect(events[2]['props']['is_empty_period'], isTrue);

        expect(events[3]['props']['action'], 'toggle_setting');
        expect(events[3]['props']['setting'], 'agent_memory');
        expect(events[3]['props']['enabled'], isTrue);
      } finally {
        AptabaseHelper.onTrackEventForTesting = null;
      }
    });

    test(
        'onTrackEventForTesting interceptor captures tracked events and validates privacy',
        () {
      final events = <Map<String, dynamic>>[];
      AptabaseHelper.onTrackEventForTesting = (eventName, props) {
        events.add({'event': eventName, 'props': props});
      };

      try {
        AptabaseHelper.trackEvent(
            'feature_used', {'action': 'ai_message_send'});
        AptabaseHelper.trackEvent(
            'feature_used', {'action': 'ai_card_generate'});
        AptabaseHelper.trackEvent(
            'feature_used', {'action': 'ai_insight_generate'});
        AptabaseHelper.trackEvent(
            'feature_used', {'action': 'ai_proposal_accept'});

        expect(events, hasLength(4));
        for (final item in events) {
          expect(item['event'], 'feature_used');
          final props = item['props'] as Map<String, Object>?;
          expect(props, isNotNull);
          expect(props!.keys, equals(['action']));
          expect(props['action'].toString().startsWith('ai_'), isTrue);
        }
      } finally {
        AptabaseHelper.onTrackEventForTesting = null;
      }
    });
  });
}
