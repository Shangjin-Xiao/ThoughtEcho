import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/media_optimization_utils.dart';

void main() {
  group('MediaOptimizationUtils', () {
    group('getMimeType', () {
      test('should return correct MIME types for known extensions', () {
        expect(MediaOptimizationUtils.getMimeType('image.jpg'), 'image/jpeg');
        expect(MediaOptimizationUtils.getMimeType('image.jpeg'), 'image/jpeg');
        expect(MediaOptimizationUtils.getMimeType('image.png'), 'image/png');
        expect(MediaOptimizationUtils.getMimeType('image.gif'), 'image/gif');
        expect(MediaOptimizationUtils.getMimeType('image.webp'), 'image/webp');
        expect(MediaOptimizationUtils.getMimeType('video.mp4'), 'video/mp4');
        expect(
          MediaOptimizationUtils.getMimeType('video.mov'),
          'video/quicktime',
        );
        expect(
          MediaOptimizationUtils.getMimeType('video.avi'),
          'video/x-msvideo',
        );
        expect(MediaOptimizationUtils.getMimeType('audio.mp3'), 'audio/mpeg');
        expect(MediaOptimizationUtils.getMimeType('audio.wav'), 'audio/wav');
        expect(MediaOptimizationUtils.getMimeType('audio.aac'), 'audio/aac');
      });

      test('should handle uppercase extensions', () {
        expect(MediaOptimizationUtils.getMimeType('IMAGE.JPG'), 'image/jpeg');
        expect(MediaOptimizationUtils.getMimeType('VIDEO.MP4'), 'video/mp4');
      });

      test('should return null for unknown extensions', () {
        expect(MediaOptimizationUtils.getMimeType('file.txt'), isNull);
        expect(MediaOptimizationUtils.getMimeType('document.pdf'), isNull);
        expect(MediaOptimizationUtils.getMimeType('unknown'), isNull);
      });

      test('should return null for empty string or no extension', () {
        expect(MediaOptimizationUtils.getMimeType(''), isNull);
        expect(
          MediaOptimizationUtils.getMimeType('filename_without_extension'),
          isNull,
        );
      });
    });

    group('estimateOptimizedSize', () {
      test('should estimate correct size for images', () {
        expect(
          MediaOptimizationUtils.estimateOptimizedSize(1000, 'image'),
          300,
        );
        expect(
          MediaOptimizationUtils.estimateOptimizedSize(1000, 'IMAGE'),
          300,
        );
      });

      test('should estimate correct size for videos', () {
        expect(
          MediaOptimizationUtils.estimateOptimizedSize(1000, 'video'),
          700,
        );
        expect(
          MediaOptimizationUtils.estimateOptimizedSize(1000, 'VIDEO'),
          700,
        );
      });

      test('should estimate correct size for audio', () {
        expect(
          MediaOptimizationUtils.estimateOptimizedSize(1000, 'audio'),
          800,
        );
        expect(
          MediaOptimizationUtils.estimateOptimizedSize(1000, 'AUDIO'),
          800,
        );
      });

      test('should return original size for unknown file types', () {
        expect(
          MediaOptimizationUtils.estimateOptimizedSize(1000, 'document'),
          1000,
        );
        expect(
          MediaOptimizationUtils.estimateOptimizedSize(1000, 'unknown'),
          1000,
        );
      });

      test('should handle zero size', () {
        expect(MediaOptimizationUtils.estimateOptimizedSize(0, 'image'), 0);
        expect(MediaOptimizationUtils.estimateOptimizedSize(0, 'video'), 0);
      });
    });
  });
}
