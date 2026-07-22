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
    test(
        'calculates correctly based on different memory pressure and file sizes',
        () async {
      // 1. High memory pressure (usageRatio > 0.8) -> base = 8KB
      manager.mockRatio = 0.9;
      var size = await manager.getOptimalChunkSize(50 * 1024 * 1024);
      expect(size, 8 * 1024);

      // 2. Medium memory pressure (0.6 < usageRatio <= 0.8) -> base = 16KB
      manager.mockRatio = 0.7;
      size = await manager.getOptimalChunkSize(50 * 1024 * 1024);
      expect(size, 16 * 1024);

      // 3. Normal memory pressure (0.3 <= usageRatio <= 0.6) -> base = 64KB
      manager.mockRatio = 0.5;
      size = await manager.getOptimalChunkSize(50 * 1024 * 1024);
      expect(size, 64 * 1024);

      // 4. Low memory pressure (usageRatio < 0.3) -> base = 128KB
      manager.mockRatio = 0.2;
      size = await manager.getOptimalChunkSize(50 * 1024 * 1024);
      expect(size, 128 * 1024);

      // 5. File size adjustments: Large file (> 1GB)
      // Ratio 0.5 (base 64KB) -> large file -> min(64KB, 16KB) = 16KB
      manager.mockRatio = 0.5;
      size = await manager.getOptimalChunkSize(2 * 1024 * 1024 * 1024);
      expect(size, 16 * 1024);

      // Large file with high pressure (base 8KB) -> min(8KB, 16KB) = 8KB
      manager.mockRatio = 0.9;
      size = await manager.getOptimalChunkSize(2 * 1024 * 1024 * 1024);
      expect(size, 8 * 1024);

      // 6. File size adjustments: Small file (< 10MB)
      // Ratio 0.75 (base 16KB) -> small file -> max(16KB, 64KB) = 64KB
      manager.mockRatio = 0.75;
      size = await manager.getOptimalChunkSize(5 * 1024 * 1024);
      expect(size, 64 * 1024);

      // Small file with low pressure (base 128KB) -> max(128KB, 64KB) = 128KB
      manager.mockRatio = 0.2;
      size = await manager.getOptimalChunkSize(5 * 1024 * 1024);
      expect(size, 128 * 1024);
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
