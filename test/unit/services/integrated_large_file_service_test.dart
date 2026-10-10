import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/integrated_large_file_service.dart';
import 'package:thoughtecho/services/error_recovery_manager.dart';
import 'package:thoughtecho/services/intelligent_memory_manager.dart';
import 'package:thoughtecho/utils/app_logger.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('IntegratedLargeFileService Tests', () {
    late IntegratedLargeFileService service;
    late ErrorRecoveryManager errorRecoveryManager;
    late IntelligentMemoryManager memoryManager;

    setUp(() async {
      AppLogger.initialize();
      service = IntegratedLargeFileService();
      errorRecoveryManager = ErrorRecoveryManager();
      memoryManager = IntelligentMemoryManager();

      await service.dispose();
    });

    tearDown(() async {
      await service.dispose();
    });

    test(
        'initialize starts monitoring and initializes ErrorRecoveryManager properly',
        () async {
      expect(errorRecoveryManager.isInitialized, isFalse);
      expect(errorRecoveryManager.pressureSubscription, isNull);

      await service.initialize();

      expect(errorRecoveryManager.isInitialized, isTrue);
      expect(errorRecoveryManager.pressureSubscription, isNotNull);
      expect(memoryManager.nativeMemorySubscription, isNotNull);
    });

    test('initialize is idempotent when called multiple times', () async {
      await service.initialize();
      final sub1 = errorRecoveryManager.pressureSubscription;

      await service.initialize();
      final sub2 = errorRecoveryManager.pressureSubscription;

      expect(sub1, isNotNull);
      expect(sub1, same(sub2));
    });

    test(
        'dispose cascades to ErrorRecoveryManager and IntelligentMemoryManager',
        () async {
      await service.initialize();

      expect(errorRecoveryManager.isInitialized, isTrue);
      expect(errorRecoveryManager.pressureSubscription, isNotNull);
      expect(memoryManager.nativeMemorySubscription, isNotNull);

      await service.dispose();

      expect(errorRecoveryManager.isInitialized, isFalse);
      expect(errorRecoveryManager.pressureSubscription, isNull);
      expect(memoryManager.nativeMemorySubscription, isNull);
    });

    test('lifecycle initialize-dispose-initialize works repeatedly', () async {
      for (int i = 0; i < 3; i++) {
        await service.initialize();
        expect(errorRecoveryManager.isInitialized, isTrue);
        expect(errorRecoveryManager.pressureSubscription, isNotNull);

        await service.dispose();
        expect(errorRecoveryManager.isInitialized, isFalse);
        expect(errorRecoveryManager.pressureSubscription, isNull);
      }
    });
  });
}
