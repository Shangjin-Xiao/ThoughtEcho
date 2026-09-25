import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/motion_photo_utils_base.dart';

void main() {
  group('MotionPhotoInfo', () {
    test('calculates videoLength correctly', () {
      final info = MotionPhotoInfo(videoStart: 100, videoEnd: 500);
      expect(info.videoLength, 400);
    });

    test('handles zero length correctly', () {
      final info = MotionPhotoInfo(videoStart: 500, videoEnd: 500);
      expect(info.videoLength, 0);
    });

    test('handles negative length safely (though technically invalid)', () {
      final info = MotionPhotoInfo(videoStart: 500, videoEnd: 100);
      expect(info.videoLength, -400);
    });
  });
}
