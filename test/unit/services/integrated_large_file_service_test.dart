import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/integrated_large_file_service.dart';
import 'package:thoughtecho/utils/app_logger.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('IntegratedLargeFileService Tests', () {
    late IntegratedLargeFileService service;

    setUp(() async {
      AppLogger.initialize();
      service = IntegratedLargeFileService();
      await service.dispose();
    });

    tearDown(() async {
      await service.dispose();
    });

    test(
        'initialize starts monitoring and error recovery manager in correct order',
        () async {
      expect(service.isInitialized, isFalse);

      await service.initialize();

      expect(service.isInitialized, isTrue);
      expect(service.errorRecoveryManager.isInitialized, isTrue);
      expect(service.errorRecoveryManager.pressureSubscription, isNotNull);
    });

    test('initialize is idempotent when called multiple times', () async {
      await service.initialize();
      expect(service.isInitialized, isTrue);

      // Duplicate initialize call
      await service.initialize();
      expect(service.isInitialized, isTrue);
      expect(service.errorRecoveryManager.isInitialized, isTrue);
    });

    test(
        'dispose cascades dispose calls to ErrorRecoveryManager and IntelligentMemoryManager',
        () async {
      await service.initialize();
      expect(service.isInitialized, isTrue);
      expect(service.errorRecoveryManager.isInitialized, isTrue);
      expect(service.errorRecoveryManager.pressureSubscription, isNotNull);

      await service.dispose();

      expect(service.isInitialized, isFalse);
      expect(service.errorRecoveryManager.isInitialized, isFalse);
      expect(service.errorRecoveryManager.pressureSubscription, isNull);
    });

    test('re-initialization after dispose works correctly', () async {
      await service.initialize();
      await service.dispose();

      expect(service.isInitialized, isFalse);

      await service.initialize();
      expect(service.isInitialized, isTrue);
      expect(service.errorRecoveryManager.isInitialized, isTrue);
      expect(service.errorRecoveryManager.pressureSubscription, isNotNull);
    });
  });
}
