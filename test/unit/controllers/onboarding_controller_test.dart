import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/controllers/onboarding_controller.dart';
import 'package:thoughtecho/services/api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OnboardingController locale preference linkage', () {
    test('updates daily quote provider when onboarding language changes', () {
      final controller = OnboardingController();

      controller.updatePreference(
          'dailyQuoteProvider', ApiService.hitokotoProvider);

      controller.updatePreference('localeCode', 'ja');
      expect(
        controller.state.getPreference<String>('dailyQuoteProvider'),
        ApiService.meigenProvider,
      );

      controller.updatePreference('localeCode', 'ko');
      expect(
        controller.state.getPreference<String>('dailyQuoteProvider'),
        ApiService.koreanAdviceProvider,
      );

      controller.updatePreference('localeCode', 'en');
      expect(
        controller.state.getPreference<String>('dailyQuoteProvider'),
        ApiService.zenQuotesProvider,
      );
    });
  });
}
