import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/memory_optimization_helper.dart';
import 'package:thoughtecho/utils/device_memory_manager.dart';

class MockDeviceMemoryManager extends DeviceMemoryManager {
  MockDeviceMemoryManager() : super.forTesting();

  int mockMemoryPressureLevel = 0;
  int mockAvailableMemory = 100 * 1024 * 1024; // 100MB
  bool shouldThrow = false;

  int cacheClearCount = 0;
  int gcSuggestCount = 0;

  @override
  Future<int> getMemoryPressureLevel() async {
    if (shouldThrow) throw Exception('mock getMemoryPressureLevel error');
    return mockMemoryPressureLevel;
  }

  @override
  Future<int> getAvailableMemory() async {
    if (shouldThrow) throw Exception('mock getAvailableMemory error');
    return mockAvailableMemory;
  }

  @override
  void clearCache() {
    cacheClearCount++;
  }

  @override
  Future<void> suggestGarbageCollection() async {
    gcSuggestCount++;
  }
}

void main() {
  group('ProcessingStrategyExt', () {
    test('description should return correct labels', () {
      expect(ProcessingStrategy.direct.description, '直接处理');
      expect(ProcessingStrategy.chunked.description, '分块处理');
      expect(ProcessingStrategy.streaming.description, '流式处理');
      expect(ProcessingStrategy.minimal.description, '最小化处理');
    });

    test('useIsolate should return correct boolean', () {
      expect(ProcessingStrategy.direct.useIsolate, false);
      expect(ProcessingStrategy.chunked.useIsolate, false);
      expect(ProcessingStrategy.streaming.useIsolate, false);
      expect(ProcessingStrategy.minimal.useIsolate, false);
    });
  });

  group('MemoryOptimizationHelper', () {
    late MockDeviceMemoryManager mockMemoryManager;
    late MemoryOptimizationHelper helper;

    setUp(() {
      mockMemoryManager = MockDeviceMemoryManager();
      helper = MemoryOptimizationHelper.forTesting(mockMemoryManager);
    });

    group('getOptimalStrategy', () {
      test(
          'should return minimal strategy when memory pressure is critical (>=3)',
          () async {
        mockMemoryManager.mockMemoryPressureLevel = 3;
        final strategy = await helper.getOptimalStrategy(1024);
        expect(strategy, ProcessingStrategy.minimal);
      });

      test(
          'should return streaming strategy when memory pressure is high (>=2) and data > 10MB',
          () async {
        mockMemoryManager.mockMemoryPressureLevel = 2;
        final strategy = await helper.getOptimalStrategy(11 * 1024 * 1024);
        expect(strategy, ProcessingStrategy.streaming);
      });

      test(
          'should return chunked strategy when memory pressure is high (>=2) and data <= 10MB',
          () async {
        mockMemoryManager.mockMemoryPressureLevel = 2;
        final strategy = await helper.getOptimalStrategy(9 * 1024 * 1024);
        expect(strategy, ProcessingStrategy.chunked);
      });

      test('should return streaming strategy when data > availableMemory / 4',
          () async {
        mockMemoryManager.mockMemoryPressureLevel = 1;
        mockMemoryManager.mockAvailableMemory = 40 * 1024 * 1024; // 40MB
        final strategy =
            await helper.getOptimalStrategy(11 * 1024 * 1024); // > 10MB (40/4)
        expect(strategy, ProcessingStrategy.streaming);
      });

      test(
          'should return chunked strategy when data > 50MB and <= availableMemory / 4',
          () async {
        mockMemoryManager.mockMemoryPressureLevel = 1;
        mockMemoryManager.mockAvailableMemory = 400 * 1024 * 1024; // 400MB
        final strategy = await helper.getOptimalStrategy(
            60 * 1024 * 1024); // > 50MB and <= 100MB (400/4)
        expect(strategy, ProcessingStrategy.chunked);
      });

      test(
          'should return direct strategy when memory is sufficient and data is small',
          () async {
        mockMemoryManager.mockMemoryPressureLevel = 1;
        mockMemoryManager.mockAvailableMemory = 400 * 1024 * 1024; // 400MB
        final strategy = await helper
            .getOptimalStrategy(10 * 1024 * 1024); // <= 50MB and <= 100MB
        expect(strategy, ProcessingStrategy.direct);
      });

      test('should handle exceptions and fallback to chunked strategy',
          () async {
        mockMemoryManager.shouldThrow = true;
        final strategy = await helper.getOptimalStrategy(1024);
        expect(strategy, ProcessingStrategy.chunked);
      });
    });

    group('getOptimalChunkSize', () {
      test('should return correct chunk size for critical memory pressure',
          () async {
        mockMemoryManager.mockMemoryPressureLevel = 3;
        mockMemoryManager.mockAvailableMemory = 100 * 1024 * 1024;
        final size = await helper.getOptimalChunkSize(5 * 1024 * 1024);
        // base 8KB. maxSafeChunkSize (100MB/100=1MB). data < 1GB, > 1MB. clamped between 8KB and 1MB.
        expect(size, 8 * 1024);
      });

      test('should return correct chunk size for high memory pressure',
          () async {
        mockMemoryManager.mockMemoryPressureLevel = 2;
        mockMemoryManager.mockAvailableMemory = 100 * 1024 * 1024;
        final size = await helper.getOptimalChunkSize(5 * 1024 * 1024);
        // base 16KB.
        expect(size, 16 * 1024);
      });

      test('should return correct chunk size for medium memory pressure',
          () async {
        mockMemoryManager.mockMemoryPressureLevel = 1;
        mockMemoryManager.mockAvailableMemory = 100 * 1024 * 1024;
        final size = await helper.getOptimalChunkSize(5 * 1024 * 1024);
        // base 32KB.
        expect(size, 32 * 1024);
      });

      test('should return correct chunk size for normal memory pressure',
          () async {
        mockMemoryManager.mockMemoryPressureLevel = 0;
        mockMemoryManager.mockAvailableMemory = 100 * 1024 * 1024;
        final size = await helper.getOptimalChunkSize(5 * 1024 * 1024);
        // base 128KB.
        expect(size, 128 * 1024);
      });

      test('should clamp based on max safe chunk size', () async {
        mockMemoryManager.mockMemoryPressureLevel = 0; // base 128KB
        mockMemoryManager.mockAvailableMemory =
            2 * 1024 * 1024; // 2MB -> max safe is 20KB (20480 bytes)
        // Actually 2MB / 100 = 20971
        final size = await helper.getOptimalChunkSize(5 * 1024 * 1024);
        expect(size, 20971);
      });

      test('should halve chunk size for very large data (> 1GB)', () async {
        mockMemoryManager.mockMemoryPressureLevel = 0; // base 128KB
        mockMemoryManager.mockAvailableMemory = 1000 * 1024 * 1024;
        final size =
            await helper.getOptimalChunkSize(2 * 1024 * 1024 * 1024); // > 1GB
        // 128KB * 0.5 = 64KB
        expect(size, 64 * 1024);
      });

      test('should double chunk size for very small data (< 1MB)', () async {
        mockMemoryManager.mockMemoryPressureLevel = 0; // base 128KB
        mockMemoryManager.mockAvailableMemory = 1000 * 1024 * 1024;
        final size = await helper.getOptimalChunkSize(512 * 1024); // < 1MB
        // 128KB * 2 = 256KB
        expect(size, 256 * 1024);
      });

      test('should handle exceptions and fallback to 32KB', () async {
        mockMemoryManager.shouldThrow = true;
        final size = await helper.getOptimalChunkSize(1024);
        expect(size, 32 * 1024);
      });
    });

    group('shouldUseIsolate', () {
      test('should return false when memory pressure is high (>=2)', () async {
        mockMemoryManager.mockMemoryPressureLevel = 2;
        final result = await helper.shouldUseIsolate(200 * 1024 * 1024);
        expect(result, isFalse);
      });

      test('should return true when memory is normal and data > 100MB',
          () async {
        mockMemoryManager.mockMemoryPressureLevel = 1;
        final result =
            await helper.shouldUseIsolate(101 * 1024 * 1024); // > 100MB
        expect(result, isTrue);
      });

      test('should return false when memory is normal and data <= 100MB',
          () async {
        mockMemoryManager.mockMemoryPressureLevel = 1;
        final result =
            await helper.shouldUseIsolate(99 * 1024 * 1024); // <= 100MB
        expect(result, isFalse);
      });

      test('should handle exceptions and fallback to false', () async {
        mockMemoryManager.shouldThrow = true;
        final result = await helper.shouldUseIsolate(200 * 1024 * 1024);
        expect(result, isFalse);
      });
    });

    group('performOptimization', () {
      test(
          'should clear cache and suggest GC when memory pressure is critical (>=3)',
          () async {
        mockMemoryManager.mockMemoryPressureLevel = 3;
        await helper.performOptimization();
        expect(mockMemoryManager.cacheClearCount, 1);
        expect(mockMemoryManager.gcSuggestCount, 1);
      });

      test('should do nothing when memory pressure is not critical (<3)',
          () async {
        mockMemoryManager.mockMemoryPressureLevel = 2;
        await helper.performOptimization();
        expect(mockMemoryManager.cacheClearCount, 0);
        expect(mockMemoryManager.gcSuggestCount, 0);
      });

      test('should handle exceptions without crashing', () async {
        mockMemoryManager.shouldThrow = true;
        await helper.performOptimization();
        expect(mockMemoryManager.cacheClearCount, 0);
      });
    });

    group('monitorAndOptimize', () {
      test(
          'should trigger performOptimization logic when memory pressure is critical (>=3)',
          () async {
        mockMemoryManager.mockMemoryPressureLevel = 3;
        await helper.monitorAndOptimize();
        expect(mockMemoryManager.cacheClearCount, 1);
        expect(mockMemoryManager.gcSuggestCount, 1);
      });

      test(
          'should not trigger performOptimization logic when memory pressure < 2',
          () async {
        mockMemoryManager.mockMemoryPressureLevel = 1;
        await helper.monitorAndOptimize();
        expect(mockMemoryManager.cacheClearCount, 0);
        expect(mockMemoryManager.gcSuggestCount, 0);
      });

      test(
          'should not trigger cache clear or gc suggest when memory pressure is 2',
          () async {
        mockMemoryManager.mockMemoryPressureLevel = 2;
        await helper.monitorAndOptimize();
        expect(mockMemoryManager.cacheClearCount, 0);
        expect(mockMemoryManager.gcSuggestCount, 0);
      });

      test('should handle exceptions without crashing', () async {
        mockMemoryManager.shouldThrow = true;
        await helper.monitorAndOptimize();
        expect(mockMemoryManager.cacheClearCount, 0);
      });
    });
  });
}
