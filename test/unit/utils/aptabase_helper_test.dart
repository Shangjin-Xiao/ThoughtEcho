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
  });
}
