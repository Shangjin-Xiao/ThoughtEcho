import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/app_scroll_behavior.dart';

void main() {
  group('AppScrollBehavior Tests', () {
    test('AppScrollBehavior contains mouse in dragDevices', () {
      const behavior = AppScrollBehavior();
      final devices = behavior.dragDevices;

      expect(devices.contains(PointerDeviceKind.mouse), isTrue);
      expect(devices.contains(PointerDeviceKind.touch), isTrue);
      expect(devices.contains(PointerDeviceKind.trackpad), isTrue);
      expect(devices.contains(PointerDeviceKind.stylus), isTrue);
      expect(devices.contains(PointerDeviceKind.invertedStylus), isTrue);
    });
  });
}
