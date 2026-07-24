import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/platform_helper_web.dart';

void main() {
  group('PlatformHelper (Web)', () {
    test('isAndroid returns false', () {
      expect(PlatformHelper.isAndroid, isFalse);
    });

    test('isIOS returns false', () {
      expect(PlatformHelper.isIOS, isFalse);
    });

    test('isWindows returns false', () {
      expect(PlatformHelper.isWindows, isFalse);
    });

    test('isMacOS returns false', () {
      expect(PlatformHelper.isMacOS, isFalse);
    });

    test('isLinux returns false', () {
      expect(PlatformHelper.isLinux, isFalse);
    });

    test('getCpuArchitecture returns web', () async {
      final architecture = await PlatformHelper.getCpuArchitecture();
      expect(architecture, 'web');
    });
  });
}
