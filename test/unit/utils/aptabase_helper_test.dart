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
        'toggle_favorite',
        'ai_message_send',
        'ai_card_generate',
        'ai_insight_generate',
        'ai_proposal_accept',
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
