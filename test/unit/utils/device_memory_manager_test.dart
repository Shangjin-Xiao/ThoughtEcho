import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/device_memory_manager.dart';

// Create a subclass to mock getMemoryUsageRatio
class TestDeviceMemoryManager extends DeviceMemoryManager {
  TestDeviceMemoryManager() : super.forTesting();

  double mockRatio = 0.5;
  bool shouldThrow = false;

  @override
  Future<double> getMemoryUsageRatio() async {
    if (shouldThrow) {
      throw Exception('Mock Usage Ratio Error');
    }
    return mockRatio;
  }
}

void main() {
  late TestDeviceMemoryManager manager;

  setUp(() {
    manager = TestDeviceMemoryManager();
  });

  group('DeviceMemoryManager getOptimalChunkSize', () {
    group('Memory Pressure Tests', () {
      test('High memory pressure (usageRatio > 0.8) should use 8KB base',
          () async {
        manager.mockRatio = 0.9;
        var size = await manager.getOptimalChunkSize(50 * 1024 * 1024);
        expect(size, 8 * 1024);
      });

      test(
          'Medium memory pressure (0.6 < usageRatio <= 0.8) should use 16KB base',
          () async {
        manager.mockRatio = 0.7;
        var size = await manager.getOptimalChunkSize(50 * 1024 * 1024);
        expect(size, 16 * 1024);
      });

      test(
          'Normal memory pressure (0.3 <= usageRatio <= 0.6) should use 64KB base',
          () async {
        manager.mockRatio = 0.5;
        var size = await manager.getOptimalChunkSize(50 * 1024 * 1024);
        expect(size, 64 * 1024);
      });

      test('Low memory pressure (usageRatio < 0.3) should use 128KB base',
          () async {
        manager.mockRatio = 0.2;
        var size = await manager.getOptimalChunkSize(50 * 1024 * 1024);
        expect(size, 128 * 1024);
      });
    });

    group('Boundary Condition Tests', () {
      test('usageRatio exact boundaries', () async {
        // High pressure boundary
        manager.mockRatio = 0.8;
        var size = await manager.getOptimalChunkSize(50 * 1024 * 1024);
        expect(size, 16 * 1024); // 0.8 is NOT > 0.8, it falls to > 0.6 (Medium)

        manager.mockRatio = 0.8001;
        size = await manager.getOptimalChunkSize(50 * 1024 * 1024);
        expect(size, 8 * 1024); // > 0.8 (High)

        // Medium pressure boundary
        manager.mockRatio = 0.6;
        size = await manager.getOptimalChunkSize(50 * 1024 * 1024);
        expect(
            size, 64 * 1024); // 0.6 is NOT > 0.6, it falls to default (Normal)

        manager.mockRatio = 0.6001;
        size = await manager.getOptimalChunkSize(50 * 1024 * 1024);
        expect(size, 16 * 1024); // > 0.6 (Medium)

        // Low pressure boundary
        manager.mockRatio = 0.3;
        size = await manager.getOptimalChunkSize(50 * 1024 * 1024);
        expect(
            size, 64 * 1024); // 0.3 is NOT < 0.3, it falls to default (Normal)

        manager.mockRatio = 0.2999;
        size = await manager.getOptimalChunkSize(50 * 1024 * 1024);
        expect(size, 128 * 1024); // < 0.3 (Low)
      });

      test('fileSize exact boundaries', () async {
        manager.mockRatio = 0.5; // Normal pressure, base 64KB

        // > 1GB boundary
        var size = await manager
            .getOptimalChunkSize(1024 * 1024 * 1024); // exactly 1GB
        expect(size, 64 * 1024); // Not > 1GB, stays 64KB

        size =
            await manager.getOptimalChunkSize(1024 * 1024 * 1024 + 1); // > 1GB
        expect(size, 16 * 1024); // Adjusts to min(64KB, 16KB) = 16KB

        // < 10MB boundary
        size =
            await manager.getOptimalChunkSize(10 * 1024 * 1024); // exactly 10MB
        expect(size, 64 * 1024); // Not < 10MB, stays 64KB

        size =
            await manager.getOptimalChunkSize(10 * 1024 * 1024 - 1); // < 10MB
        expect(size, 64 * 1024); // Adjusts to max(64KB, 64KB) = 64KB

        // Test < 10MB with medium pressure (base 16KB) to see the max() effect
        manager.mockRatio = 0.7; // Medium pressure, base 16KB
        size =
            await manager.getOptimalChunkSize(10 * 1024 * 1024 - 1); // < 10MB
        expect(size, 64 * 1024); // Adjusts to max(16KB, 64KB) = 64KB
      });
    });

    group('File Size Adjustment Tests', () {
      test('Large file (> 1GB) adjusts chunk size to min(base, 16KB)',
          () async {
        // Normal pressure (base 64KB) -> min(64KB, 16KB) = 16KB
        manager.mockRatio = 0.5;
        var size = await manager.getOptimalChunkSize(2 * 1024 * 1024 * 1024);
        expect(size, 16 * 1024);

        // High pressure (base 8KB) -> min(8KB, 16KB) = 8KB
        manager.mockRatio = 0.9;
        size = await manager.getOptimalChunkSize(2 * 1024 * 1024 * 1024);
        expect(size, 8 * 1024);
      });

      test('Small file (< 10MB) adjusts chunk size to max(base, 64KB)',
          () async {
        // Medium pressure (base 16KB) -> max(16KB, 64KB) = 64KB
        manager.mockRatio = 0.75;
        var size = await manager.getOptimalChunkSize(5 * 1024 * 1024);
        expect(size, 64 * 1024);

        // Low pressure (base 128KB) -> max(128KB, 64KB) = 128KB
        manager.mockRatio = 0.2;
        size = await manager.getOptimalChunkSize(5 * 1024 * 1024);
        expect(size, 128 * 1024);
      });
    });

    test('handles errors fallback gracefully', () async {
      manager.shouldThrow = true;
      // If getMemoryUsageRatio throws before the catch block in getOptimalChunkSize intercepts it,
      // the catch block returns 32KB.
      var size = await manager.getOptimalChunkSize(50 * 1024 * 1024);
      expect(size, 32 * 1024);
    });
  });
}
