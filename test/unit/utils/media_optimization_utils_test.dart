import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/media_optimization_utils.dart';

void main() {
  group('MediaOptimizationUtils Pure Functions', () {
    group('getMimeType', () {
      test('returns correct mime type for images', () {
        expect(MediaOptimizationUtils.getMimeType('test.jpg'), 'image/jpeg');
        expect(MediaOptimizationUtils.getMimeType('TEST.JPEG'), 'image/jpeg');
        expect(MediaOptimizationUtils.getMimeType('image.png'), 'image/png');
        expect(
            MediaOptimizationUtils.getMimeType('animation.gif'), 'image/gif');
        expect(MediaOptimizationUtils.getMimeType('photo.webp'), 'image/webp');
      });

      test('returns correct mime type for videos', () {
        expect(MediaOptimizationUtils.getMimeType('video.mp4'), 'video/mp4');
        expect(
            MediaOptimizationUtils.getMimeType('movie.mov'), 'video/quicktime');
        expect(
            MediaOptimizationUtils.getMimeType('clip.avi'), 'video/x-msvideo');
      });

      test('returns correct mime type for audio', () {
        expect(MediaOptimizationUtils.getMimeType('sound.mp3'), 'audio/mpeg');
        expect(MediaOptimizationUtils.getMimeType('record.wav'), 'audio/wav');
        expect(MediaOptimizationUtils.getMimeType('music.aac'), 'audio/aac');
      });

      test('returns null for unknown extensions', () {
        expect(MediaOptimizationUtils.getMimeType('document.pdf'), isNull);
        expect(MediaOptimizationUtils.getMimeType('text.txt'), isNull);
        expect(MediaOptimizationUtils.getMimeType('file_without_ext'), isNull);
      });
    });

    group('estimateOptimizedSize', () {
      test('estimates image size reduction (approx 70% reduction, 30% left)',
          () {
        const originalSize = 1000;
        expect(
            MediaOptimizationUtils.estimateOptimizedSize(originalSize, 'image'),
            300);
        expect(
            MediaOptimizationUtils.estimateOptimizedSize(originalSize, 'IMAGE'),
            300);
      });

      test('estimates video size reduction (approx 30% reduction, 70% left)',
          () {
        const originalSize = 1000;
        expect(
            MediaOptimizationUtils.estimateOptimizedSize(originalSize, 'video'),
            700);
      });

      test('estimates audio size reduction (approx 20% reduction, 80% left)',
          () {
        const originalSize = 1000;
        expect(
            MediaOptimizationUtils.estimateOptimizedSize(originalSize, 'audio'),
            800);
      });

      test('returns original size for unknown file types', () {
        const originalSize = 1000;
        expect(
            MediaOptimizationUtils.estimateOptimizedSize(
                originalSize, 'document'),
            1000);
        expect(
            MediaOptimizationUtils.estimateOptimizedSize(
                originalSize, 'unknown'),
            1000);
      });
    });

    group('hasEnoughMemoryForFile', () {
      test('returns true for files within safe limits', () {
        expect(MediaOptimizationUtils.hasEnoughMemoryForFile(1024), isTrue);
      });

      test('returns false for excessively large files', () {
        expect(MediaOptimizationUtils.hasEnoughMemoryForFile(100 * 1024 * 1024),
            isFalse);
      });
    });
  });
}
