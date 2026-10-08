import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/intelligent_memory_manager.dart';
import 'package:thoughtecho/utils/device_memory_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Intelligent Memory Manager Tests', () {
    late IntelligentMemoryManager manager;
    late DeviceMemoryManager deviceMemoryManager;

    setUp(() async {
      deviceMemoryManager = DeviceMemoryManager();
      manager = IntelligentMemoryManager.forTesting(
        deviceMemoryManager: deviceMemoryManager,
      );
      manager.nativeMemoryUpdateCount = 0;
      await manager.stopIntelligentMonitoring();
    });

    tearDown(() async {
      await manager.stopIntelligentMonitoring();
      manager.nativeMemoryUpdateCount = 0;
    });

    test('MemoryPressureException formats correctly', () {
      final exception = MemoryPressureException('Test pressure message');
      expect(
        exception.toString(),
        equals('MemoryPressureException: Test pressure message'),
      );
    });

    test('startIntelligentMonitoring creates native memory subscription',
        () async {
      expect(manager.nativeMemorySubscription, isNull);
      await manager.startIntelligentMonitoring();
      expect(manager.nativeMemorySubscription, isNotNull);
    });

    test('stopIntelligentMonitoring cancels subscription and sets it to null',
        () async {
      await manager.startIntelligentMonitoring();
      expect(manager.nativeMemorySubscription, isNotNull);

      await manager.stopIntelligentMonitoring();
      expect(manager.nativeMemorySubscription, isNull);
    });

    test(
        'Start/stop cycles 100 times then start results in exactly 1 active native memory listener',
        () async {
      // Perform 100 start and stop cycles
      for (int i = 0; i < 100; i++) {
        await manager.startIntelligentMonitoring();
        await manager.stopIntelligentMonitoring();
      }

      // Start once more
      await manager.startIntelligentMonitoring();
      manager.nativeMemoryUpdateCount = 0;

      // Emit a native memory status update
      deviceMemoryManager.emitMemoryStatusForTesting({'pressureLevel': 2});
      await Future.delayed(Duration.zero);

      // Verify that callback was triggered exactly 1 time
      expect(manager.nativeMemoryUpdateCount, equals(1));
    });

    test('Events emitted while monitoring is stopped do not trigger callback',
        () async {
      await manager.startIntelligentMonitoring();
      await manager.stopIntelligentMonitoring();

      manager.nativeMemoryUpdateCount = 0;
      deviceMemoryManager.emitMemoryStatusForTesting({'pressureLevel': 3});
      await Future.delayed(Duration.zero);

      expect(manager.nativeMemoryUpdateCount, equals(0));
    });
  });
}
