import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/database_platform_init.dart';

void main() {
  group('DatabasePlatformInit', () {
    setUp(() {
      DatabasePlatformInit.resetForTesting();
    });

    test('initialize sets _isInitialized to true', () {
      expect(DatabasePlatformInit.isInitialized, isFalse);
      DatabasePlatformInit.initialize();
      expect(DatabasePlatformInit.isInitialized, isTrue);
    });

    test('initialize handles multiple calls gracefully', () {
      DatabasePlatformInit.initialize();
      expect(DatabasePlatformInit.isInitialized, isTrue);
      DatabasePlatformInit.initialize();
      expect(DatabasePlatformInit.isInitialized, isTrue);
    });
  });
}
