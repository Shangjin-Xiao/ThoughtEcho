import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:thoughtecho/services/storage_management_service.dart';

import '../../test_harness.dart';

void main() {
  setUp(() async {
    await TestHarness.initialize();
  });

  group('StorageManagementService 测试', () {
    test('formatBytes 应该正确格式化字节大小', () {
      expect(StorageStats.formatBytes(0), '0 B');
      expect(StorageStats.formatBytes(512), '512 B');
      expect(StorageStats.formatBytes(1024), '1.00 KB');
      expect(StorageStats.formatBytes(1536), '1.50 KB');
      expect(StorageStats.formatBytes(1024 * 1024), '1.00 MB');
      expect(StorageStats.formatBytes(1024 * 1024 * 1024), '1.00 GB');
      expect(StorageStats.formatBytes(1536 * 1024 * 1024), '1.50 GB');
    });

    test('StorageStats totalSize 应该正确计算总大小', () {
      final stats = StorageStats(
        mainDatabaseSize: 1024,
        logDatabaseSize: 2048,
        aiDatabaseSize: 512,
        mediaFilesSize: 4096,
        cacheSize: 256,
        mediaBreakdown: MediaFilesBreakdown(
          imagesSize: 2048,
          videosSize: 1536,
          audiosSize: 512,
          imagesCount: 5,
          videosCount: 2,
          audiosCount: 1,
        ),
      );

      expect(stats.totalSize, 1024 + 2048 + 512 + 4096 + 256);
    });

    test('MediaFilesBreakdown 应该正确存储媒体文件统计', () {
      final breakdown = MediaFilesBreakdown(
        imagesSize: 1024 * 1024,
        videosSize: 5 * 1024 * 1024,
        audiosSize: 512 * 1024,
        imagesCount: 10,
        videosCount: 2,
        audiosCount: 3,
      );

      expect(breakdown.imagesSize, 1024 * 1024);
      expect(breakdown.videosSize, 5 * 1024 * 1024);
      expect(breakdown.audiosSize, 512 * 1024);
      expect(breakdown.imagesCount, 10);
      expect(breakdown.videosCount, 2);
      expect(breakdown.audiosCount, 3);
    });

    test('getStorageStats 应该返回有效的统计信息', () async {
      final stats = await StorageManagementService.getStorageStats();

      expect(stats, isNotNull);
      expect(stats.mainDatabaseSize, greaterThanOrEqualTo(0));
      expect(stats.logDatabaseSize, greaterThanOrEqualTo(0));
      expect(stats.aiDatabaseSize, greaterThanOrEqualTo(0));
      expect(stats.mediaFilesSize, greaterThanOrEqualTo(0));
      expect(stats.cacheSize, greaterThanOrEqualTo(0));
      expect(stats.totalSize, greaterThanOrEqualTo(0));
      expect(stats.mediaBreakdown, isNotNull);
    });

    test('getAppDataDirectory 应该返回有效的路径', () async {
      final dataDir = await StorageManagementService.getAppDataDirectory();

      expect(dataDir, isNotNull);
      expect(dataDir, isNotEmpty);
      expect(dataDir, isA<String>());

      // 路径应该是绝对路径
      expect(path.isAbsolute(dataDir), isTrue);
    });

    test('clearCache 应该能够安全执行（无异常）', () async {
      final clearedBytes = await StorageManagementService.clearCache();
      expect(clearedBytes, greaterThanOrEqualTo(0));
    });

    test('cleanupOrphanFiles 应该能够安全执行（无异常）', () async {
      final orphanCount = await StorageManagementService.cleanupOrphanFiles();
      expect(orphanCount, greaterThanOrEqualTo(0));
    });

    test('数据模型应该正确处理零值', () {
      final stats = StorageStats(
        mainDatabaseSize: 0,
        logDatabaseSize: 0,
        aiDatabaseSize: 0,
        mediaFilesSize: 0,
        cacheSize: 0,
        mediaBreakdown: MediaFilesBreakdown(
          imagesSize: 0,
          videosSize: 0,
          audiosSize: 0,
          imagesCount: 0,
          videosCount: 0,
          audiosCount: 0,
        ),
      );

      expect(stats.totalSize, 0);
      expect(StorageStats.formatBytes(stats.totalSize), '0 B');
    });

    test('formatBytes 应该处理大数值', () {
      const petabyte = 1024 * 1024 * 1024 * 1024 * 1024;
      final result = StorageStats.formatBytes(petabyte);

      expect(result, contains('GB'));
      expect(result, isNotEmpty);
    });
  });
}
