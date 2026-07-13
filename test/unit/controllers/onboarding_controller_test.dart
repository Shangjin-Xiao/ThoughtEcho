import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/controllers/onboarding_controller.dart';
import 'package:thoughtecho/services/api_service.dart';

import '../../test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late OnboardingController sut;

  group('OnboardingController locale preference linkage', () {
    setUp(() async {
      await TestHarness.initialize();
      sut = OnboardingController();
    });

    tearDown(() {
      sut.dispose();
    });

    test('updates daily quote provider when onboarding language changes', () {
      sut.updatePreference('dailyQuoteProvider', ApiService.hitokotoProvider);

      sut.updatePreference('localeCode', 'ja');
      expect(
        sut.state.getPreference<String>('dailyQuoteProvider'),
        ApiService.meigenProvider,
      );

      sut.updatePreference('localeCode', 'ko');
      expect(
        sut.state.getPreference<String>('dailyQuoteProvider'),
        ApiService.koreanAdviceProvider,
      );

      sut.updatePreference('localeCode', 'en');
      expect(
        sut.state.getPreference<String>('dailyQuoteProvider'),
        ApiService.zenQuotesProvider,
      );
    });
  });
}
