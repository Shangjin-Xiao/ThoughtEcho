import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/lottie_animation_manager.dart';

void main() {
  group('LottieAnimationManager', () {
    test('getAnimationPath returns valid paths for all types', () {
      for (final type in LottieAnimationType.values) {
        final path = LottieAnimationManager.getAnimationPath(type);
        expect(path, isNotEmpty, reason: 'Path for $type should not be empty');
        expect(
          path,
          startsWith('assets/lottie/'),
          reason: 'Path for $type should start with assets/lottie/',
        );
        expect(
          path,
          endsWith('.json'),
          reason: 'Path for $type should end with .json',
        );
      }

      // Verify specific mappings
      expect(
        LottieAnimationManager.getAnimationPath(LottieAnimationType.loading),
        'assets/lottie/custom_loading.json',
      );
      expect(
        LottieAnimationManager.getAnimationPath(
          LottieAnimationType.searchLoading,
        ),
        'assets/lottie/search_loading.json',
      );
      expect(
        LottieAnimationManager.getAnimationPath(
          LottieAnimationType.weatherSearchLoading,
        ),
        'assets/lottie/weather_search_loading.json',
      );
      expect(
        LottieAnimationManager.getAnimationPath(LottieAnimationType.notFound),
        'assets/lottie/not_found.json',
      );

      // Verify other loading types default to custom_loading.json
      expect(
        LottieAnimationManager.getAnimationPath(
          LottieAnimationType.modernLoading,
        ),
        'assets/lottie/custom_loading.json',
      );
      expect(
        LottieAnimationManager.getAnimationPath(
          LottieAnimationType.pulseLoading,
        ),
        'assets/lottie/custom_loading.json',
      );
      expect(
        LottieAnimationManager.getAnimationPath(LottieAnimationType.aiThinking),
        'assets/lottie/custom_loading.json',
      );
      expect(
        LottieAnimationManager.getAnimationPath(
          LottieAnimationType.customLoading,
        ),
        'assets/lottie/custom_loading.json',
      );
    });

    test('getAnimationConfig returns correct configuration for all types', () {
      // Test default loading group
      final loadingTypes = [
        LottieAnimationType.loading,
        LottieAnimationType.modernLoading,
        LottieAnimationType.pulseLoading,
        LottieAnimationType.aiThinking,
        LottieAnimationType.customLoading,
      ];

      for (final type in loadingTypes) {
        final config = LottieAnimationManager.getAnimationConfig(type);
        expect(config.width, 80, reason: 'Width for $type should be 80');
        expect(config.height, 80, reason: 'Height for $type should be 80');
        expect(
          config.repeat,
          isTrue,
          reason: 'Repeat for $type should be true',
        );
        expect(
          config.reverse,
          isFalse,
          reason: 'Reverse for $type should be false',
        );
        expect(
          config.autoPlay,
          isTrue,
          reason: 'AutoPlay for $type should be true',
        );
        expect(
          config.semanticLabel,
          isNull,
          reason: 'SemanticLabel for $type should be null',
        );
      }

      // Test Search Loading
      final searchConfig = LottieAnimationManager.getAnimationConfig(
        LottieAnimationType.searchLoading,
      );
      expect(searchConfig.width, 360);
      expect(searchConfig.height, 360);
      expect(searchConfig.repeat, isTrue);
      expect(searchConfig.reverse, isFalse);
      expect(searchConfig.autoPlay, isTrue);
      expect(searchConfig.semanticLabel, isNull);

      // Test Weather Search Loading
      final weatherConfig = LottieAnimationManager.getAnimationConfig(
        LottieAnimationType.weatherSearchLoading,
      );
      expect(weatherConfig.width, 540);
      expect(weatherConfig.height, 540);
      expect(weatherConfig.repeat, isTrue);
      expect(weatherConfig.reverse, isFalse);
      expect(weatherConfig.autoPlay, isTrue);
      expect(weatherConfig.semanticLabel, isNull);

      // Test Not Found
      final notFoundConfig = LottieAnimationManager.getAnimationConfig(
        LottieAnimationType.notFound,
      );
      expect(notFoundConfig.width, 120);
      expect(notFoundConfig.height, 120);
      expect(notFoundConfig.repeat, isTrue);
      expect(notFoundConfig.reverse, isFalse);
      expect(notFoundConfig.autoPlay, isTrue);
      expect(notFoundConfig.semanticLabel, '未找到相关内容');
    });
  });
}
