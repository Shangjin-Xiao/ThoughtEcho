import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/file_processing_fallback_manager.dart';
import 'package:thoughtecho/services/intelligent_memory_manager.dart';

void main() {
  group('MediaProcessingAdaptiveStrategy', () {
    late MediaProcessingAdaptiveStrategy strategy;

    setUp(() {
      strategy = MediaProcessingAdaptiveStrategy();
    });

    test('should return minimal strategy when memory pressure is critical', () {
      final context = MemoryContext(
        pressureLevel: 3, // Critical
        availableMemory: 100 * 1024 * 1024,
        dataSize: 1024,
        operationName: 'media_processing',
        additionalContext: {},
      );

      final result = strategy.getStrategy(context);

      expect(result.name, equals('minimal'));
    });

    test(
      'should return memory conservative strategy when memory pressure is high',
      () {
        final context = MemoryContext(
          pressureLevel: 2, // High
          availableMemory: 200 * 1024 * 1024,
          dataSize: 1024,
          operationName: 'media_processing',
          additionalContext: {},
        );

        final result = strategy.getStrategy(context);

        expect(result.name, equals('memory_conservative'));
      },
    );

    test(
      'should return memory conservative strategy when data size > 500MB',
      () {
        final context = MemoryContext(
          pressureLevel: 1, // Normal
          availableMemory: 500 * 1024 * 1024,
          dataSize: 500 * 1024 * 1024 + 1, // > 500MB
          operationName: 'media_processing',
          additionalContext: {},
        );

        final result = strategy.getStrategy(context);

        expect(result.name, equals('memory_conservative'));
      },
    );

    test(
      'should return default strategy when memory pressure is normal and data size is small',
      () {
        final context = MemoryContext(
          pressureLevel: 1, // Normal
          availableMemory: 500 * 1024 * 1024,
          dataSize: 1024, // Small
          operationName: 'media_processing',
          additionalContext: {},
        );

        final result = strategy.getStrategy(context);

        expect(result.name, equals('default'));
      },
    );
  });
}
