import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/widgets/motion_photo_preview_page.dart';
import 'package:video_player/video_player.dart';

void main() {
  group('Motion photo preview playback', () {
    test('auto returns to still image when playback reaches the end', () {
      final value = VideoPlayerValue(
        duration: const Duration(milliseconds: 1200),
        position: const Duration(milliseconds: 1200),
        isInitialized: true,
        isPlaying: false,
      );

      expect(shouldAutoReturnToStillImage(value), isTrue);
    });

    test('does not auto return while playback is still running', () {
      final value = VideoPlayerValue(
        duration: const Duration(milliseconds: 1200),
        position: const Duration(milliseconds: 400),
        isInitialized: true,
        isPlaying: true,
      );

      expect(shouldAutoReturnToStillImage(value), isFalse);
    });

    test('does not auto return for uninitialized or zero-duration states', () {
      final uninitialized = VideoPlayerValue.uninitialized();
      final zeroDuration = VideoPlayerValue(
        duration: Duration.zero,
        position: Duration.zero,
        isInitialized: true,
        isPlaying: false,
      );

      expect(shouldAutoReturnToStillImage(uninitialized), isFalse);
      expect(shouldAutoReturnToStillImage(zeroDuration), isFalse);
    });
  });
}
