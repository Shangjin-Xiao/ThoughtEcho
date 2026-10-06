import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/services/database_schema_manager.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/media_cleanup_service.dart';
import 'package:thoughtecho/services/media_reference_service.dart';

import '../../test_harness.dart';

class _ThrowingPathProvider extends PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async {
    throw Exception('Disk I/O failure');
  }

  @override
  Future<String?> getTemporaryPath() async {
    throw Exception('Disk I/O failure');
  }

  @override
  Future<String?> getApplicationSupportPath() async {
    throw Exception('Disk I/O failure');
  }

  @override
  Future<String?> getLibraryPath() async {
    throw Exception('Disk I/O failure');
  }

  @override
  Future<List<String>?> getExternalStoragePaths(
      {StorageDirectory? type}) async {
    throw Exception('Disk I/O failure');
  }

  @override
  Future<String?> getExternalStoragePath() async {
    throw Exception('Disk I/O failure');
  }

  @override
  Future<String?> getDownloadsPath() async {
    throw Exception('Disk I/O failure');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late DatabaseService dbService;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await TestHarness.initialize();
    DatabaseService.clearTestDatabase();

    dbService = DatabaseService();
    final appDocsDir = TestHarness.applicationDocumentsDirectory;
    final dbPath = path.join(appDocsDir.path, 'thoughtecho.db');
    db = await databaseFactory.openDatabase(dbPath);

    final schemaManager = DatabaseSchemaManager();
    await schemaManager.createTables(db);

    DatabaseService.setTestDatabase(db);
    MediaReferenceService.setDatabaseForTesting(db);
    await dbService.init();

    MediaCleanupService.dispose();
  });

  tearDown(() async {
    MediaCleanupService.dispose();
    MediaReferenceService.clearDatabaseForTesting();
    DatabaseService.clearTestDatabase();
    await db.close();
    await DatabaseService.closeDatabase();
    await TestHarness.tearDown();
  });

  group('MediaCleanupService Initialization & Lifecycle', () {
    test('initialize 和 dispose 幂等管理服务生命周期状态', () async {
      // 静态服务状态只能从行为侧验证：两次 initialize 后任务仍可执行，
      // dispose 后重新 initialize 不会抛错
      await MediaCleanupService.initialize();
      await MediaCleanupService.initialize();

      MediaCleanupService.dispose();
      await MediaCleanupService.initialize();

      final results = await MediaCleanupService.performPeriodicCleanup();
      expect(results, isNot(containsPair('error', 1)));
    });
  });

  group('MediaCleanupService.performPeriodicCleanup', () {
    test('定期清理成功执行并返回 expiredTempFiles 与 orphanFiles 统计信息', () async {
      final appDocsDir = TestHarness.applicationDocumentsDirectory;

      // 1 个过期临时文件（mtime 超过 24 小时）
      final tempDir =
          Directory(path.join(appDocsDir.path, 'temp_media', 'temp_images'));
      await tempDir.create(recursive: true);
      final expiredFile = File(path.join(tempDir.path, 'expired.png'));
      await expiredFile.writeAsString('stale');
      await expiredFile.setLastModified(
        DateTime.now().subtract(const Duration(hours: 25)),
      );

      // 1 个孤儿媒体文件（磁盘上存在但无任何引用）
      final imagesDir =
          Directory(path.join(appDocsDir.path, 'media', 'images'));
      await imagesDir.create(recursive: true);
      final orphanFile = File(path.join(imagesDir.path, 'orphan.png'));
      await orphanFile.writeAsString('orphan_bytes');

      final results = await MediaCleanupService.performPeriodicCleanup();

      expect(results['expiredTempFiles'], equals(1));
      expect(results['orphanFiles'], equals(1));
      expect(expiredFile.existsSync(), isFalse);
      expect(orphanFile.existsSync(), isFalse);
    });
  });

  group('MediaCleanupService.performFullCleanup', () {
    test('dryRun = true 模式下获取清理前统计且不破坏真实文件', () async {
      final appDocsDir = TestHarness.applicationDocumentsDirectory;
      final tempMediaDir =
          Directory(path.join(appDocsDir.path, 'temp_media', 'temp_images'));
      await tempMediaDir.create(recursive: true);

      final tempFile = File(path.join(tempMediaDir.path, 'dummy_temp.png'));
      await tempFile.writeAsString('temp_content');

      final results =
          await MediaCleanupService.performFullCleanup(dryRun: true);

      expect(results['tempFilesCleared'], equals(1)); // 探测到 1 个临时文件
      expect(results['orphanFilesCleared'], equals(0));
      expect(results.containsKey('beforeStats'), isTrue);
      expect(results.containsKey('afterStats'),
          isFalse); // dryRun 模式不计算 afterStats
      expect(tempFile.existsSync(), isTrue); // 文件未被删除
    });

    test('dryRun = false 模式下清理临时文件与孤儿文件并计算节省空间', () async {
      final appDocsDir = TestHarness.applicationDocumentsDirectory;
      final tempMediaDir =
          Directory(path.join(appDocsDir.path, 'temp_media', 'temp_images'));
      await tempMediaDir.create(recursive: true);

      final tempFile = File(path.join(tempMediaDir.path, 'dummy_temp.png'));
      await tempFile.writeAsString('temp_content_for_cleanup');

      final results =
          await MediaCleanupService.performFullCleanup(dryRun: false);

      expect(results['tempFilesCleared'], equals(1));
      expect(results.containsKey('beforeStats'), isTrue);
      expect(results.containsKey('afterStats'), isTrue);
      expect(results.containsKey('spaceSavedMB'), isTrue);
      expect(tempFile.existsSync(), isFalse); // 临时文件已被成功清理
    });
  });

  group('MediaCleanupService.migrateExistingNotes', () {
    test('成功同步现有笔记的媒体引用并检测孤儿文件', () async {
      final quote = Quote(
        id: 'note_migrate_1',
        content: '带有图片的笔记',
        deltaContent: '[{"insert":{"image":"media/images/test_mig.jpg"}}]',
        date: DateTime.now().toIso8601String(),
      );
      await dbService.addQuote(quote);

      final appDocsDir = TestHarness.applicationDocumentsDirectory;
      final imgFile =
          File(path.join(appDocsDir.path, 'media', 'images', 'test_mig.jpg'));
      await imgFile.parent.create(recursive: true);
      await imgFile.writeAsString('migrated_image_bytes');

      final results = await MediaCleanupService.migrateExistingNotes();

      expect(results['migratedQuotes'], equals(1));
      expect(results.containsKey('beforeStats'), isTrue);
      expect(results.containsKey('afterStats'), isTrue);

      // 验证媒体引用已被建立
      final refCount = await MediaReferenceService.getReferenceCount(
          'media/images/test_mig.jpg');
      expect(refCount, equals(1));
    });

    test('当底库/存储异常时迁移过程平滑降级并返回结果结构', () async {
      // 先放入一条带媒体引用的笔记，确保 migratedQuotes == 0 是降级
      // 而不是"库里本来就没东西"
      final quote = Quote(
        id: 'note_degrade_1',
        content: '带有图片的笔记',
        deltaContent: '[{"insert":{"image":"media/images/degrade.jpg"}}]',
        date: DateTime.now().toIso8601String(),
      );
      await dbService.addQuote(quote);

      PathProviderPlatform.instance = _ThrowingPathProvider();

      final results = await MediaCleanupService.migrateExistingNotes();

      expect(results['migratedQuotes'], equals(0));
    });
  });

  group('MediaCleanupService.getMediaStats', () {
    test('媒体目录不存在时返回 0.0 MB 统计', () async {
      final stats = await MediaCleanupService.getMediaStats();

      expect(stats['totalSizeMB'], equals(0.0));
      expect(stats['imagesSizeMB'], equals(0.0));
      expect(stats['videosSizeMB'], equals(0.0));
      expect(stats['audiosSizeMB'], equals(0.0));
      expect(stats.containsKey('tempFiles'), isTrue);
    });

    test('媒体目录存在图片/视频/音频时正确统计各类文件大小与分块计算逻辑', () async {
      final appDocsDir = TestHarness.applicationDocumentsDirectory;
      final imagesDir =
          Directory(path.join(appDocsDir.path, 'media', 'images'));
      final videosDir =
          Directory(path.join(appDocsDir.path, 'media', 'videos'));
      final audiosDir =
          Directory(path.join(appDocsDir.path, 'media', 'audios'));

      await imagesDir.create(recursive: true);
      await videosDir.create(recursive: true);
      await audiosDir.create(recursive: true);

      // 写入图片、视频、音频文件
      final img = File(path.join(imagesDir.path, 'img1.png'));
      await img.writeAsBytes(List.filled(1024 * 1024, 65)); // 1MB

      final video = File(path.join(videosDir.path, 'vid1.mp4'));
      await video.writeAsBytes(List.filled(1024 * 1024 * 2, 66)); // 2MB

      final audio = File(path.join(audiosDir.path, 'aud1.mp3'));
      await audio.writeAsBytes(List.filled(1024 * 512, 67)); // 0.5MB

      // 为了测试分块 (chunk.length >= 50)，增加 55 个额外小文件
      for (var i = 0; i < 55; i++) {
        final f = File(path.join(imagesDir.path, 'chunk_file_$i.png'));
        await f.writeAsString('small');
      }

      final stats = await MediaCleanupService.getMediaStats();

      expect(stats['totalSizeMB'], greaterThan(3.4));
      expect(stats['imagesSizeMB'], greaterThan(0.9));
      expect(stats['videosSizeMB'], greaterThan(1.9));
      expect(stats['audiosSizeMB'], greaterThan(0.4));
    });
  });

  group('MediaCleanupService.verifyMediaIntegrity', () {
    test('引用文件全存在时返回 isHealthy: true 且 missingFiles 为 0', () async {
      final appDocsDir = TestHarness.applicationDocumentsDirectory;
      final imgFile =
          File(path.join(appDocsDir.path, 'media', 'images', 'valid_ref.jpg'));
      await imgFile.parent.create(recursive: true);
      await imgFile.writeAsString('img_data');

      final quote = Quote(
        id: 'note_verify_healthy',
        content: '健康笔记',
        deltaContent: '[{"insert":{"image":"media/images/valid_ref.jpg"}}]',
        date: DateTime.now().toIso8601String(),
      );
      await dbService.addQuote(quote);

      final results = await MediaCleanupService.verifyMediaIntegrity();

      expect(results['isHealthy'], isTrue);
      expect(results['missingFiles'], equals(0));
      expect(results['checkedReferences'], equals(1));
      expect((results['issues'] as List).isEmpty, isTrue);
    });

    test('笔记引用的媒体文件不存在时检测为 missingFiles 且 isHealthy: false', () async {
      final quote = Quote(
        id: 'note_verify_missing',
        content: '缺失媒体文件的笔记',
        deltaContent: '[{"insert":{"image":"media/images/missing_file.jpg"}}]',
        date: DateTime.now().toIso8601String(),
      );
      await dbService.addQuote(quote);

      final results = await MediaCleanupService.verifyMediaIntegrity();

      expect(results['isHealthy'], isFalse);
      expect(results['missingFiles'], equals(1));
      expect(results['checkedReferences'], equals(1));
      expect((results['issues'] as List).isNotEmpty, isTrue);
      expect(
          (results['issues'] as List).first, contains('note_verify_missing'));
    });

    test('验证媒体文件完整性异常时返回 error Map', () async {
      PathProviderPlatform.instance = _ThrowingPathProvider();

      final results = await MediaCleanupService.verifyMediaIntegrity();

      expect(results.containsKey('error'), isTrue);
      expect(results['error'], contains('Disk I/O failure'));
    });

    test('分块并发校验大量媒体文件完整性正确识别存在与缺失文件', () async {
      final appDocsDir = TestHarness.applicationDocumentsDirectory;
      final imagesDir =
          Directory(path.join(appDocsDir.path, 'media', 'images'));
      await imagesDir.create(recursive: true);

      // 创建 120 个引用的文件（超过单批次 50 个上限）
      // 其中前 80 个物理文件存在，后 40 个物理文件不存在
      const totalCount = 120;
      const existingCount = 80;

      final inserts = <Map<String, String>>[];
      for (var i = 0; i < totalCount; i++) {
        final relPath = 'media/images/bulk_check_$i.jpg';
        if (i < existingCount) {
          final file = File(path.join(imagesDir.path, 'bulk_check_$i.jpg'));
          await file.writeAsString('bytes_$i');
        }
        inserts.add({'image': relPath});
      }

      // 将 120 个引用分配到 3 条笔记中
      for (var n = 0; n < 3; n++) {
        final subList = inserts.sublist(n * 40, (n + 1) * 40);
        // 手动构造符合规范的 deltaContent JSON
        final jsonOps = subList
            .map((m) => '{"insert":{"image":"${m['image']}"}}')
            .join(',');
        final validDelta = '[$jsonOps]';
        final validQuote = Quote(
          id: 'note_bulk_$n',
          content: '批量笔记 $n',
          deltaContent: validDelta,
          date: DateTime.now().toIso8601String(),
        );
        await dbService.addQuote(validQuote);
      }

      final results = await MediaCleanupService.verifyMediaIntegrity();

      expect(results['checkedReferences'], equals(totalCount));
      expect(results['missingFiles'], equals(totalCount - existingCount));
      expect(results['checkFailedFiles'], equals(0));
      expect(results['isHealthy'], isFalse);
      expect((results['issues'] as List).length, equals(40));
    });

    test('存在性检查异常时拆分为独立错误桶 checkFailedFiles 且不影响其余正常文件', () async {
      final appDocsDir = TestHarness.applicationDocumentsDirectory;
      final imgFile = File(
          path.join(appDocsDir.path, 'media', 'images', 'valid_exist.jpg'));
      await imgFile.parent.create(recursive: true);
      await imgFile.writeAsString('valid_data');

      final quote = Quote(
        id: 'note_verify_err_bucket',
        content: '包含正常存在、缺失与检查异常文件的笔记',
        deltaContent: jsonEncode([
          {
            'insert': {'image': 'media/images/valid_exist.jpg'}
          },
          {
            'insert': {'image': 'media/images/missing_absent.jpg'}
          },
          {
            'insert': {'image': 'media/images/error_file.jpg'}
          },
        ]),
        date: DateTime.now().toIso8601String(),
      );
      await dbService.addQuote(quote);

      MediaCleanupService.fileExistsForTesting = (file) async {
        if (file.path.contains('error_file.jpg')) {
          throw const FileSystemException('Simulated I/O error');
        }
        return file.exists();
      };

      try {
        final results = await MediaCleanupService.verifyMediaIntegrity();

        expect(results['checkedReferences'], equals(3));
        expect(results['missingFiles'], equals(1));
        expect(results['checkFailedFiles'], equals(1));
        expect(results['isHealthy'], isFalse);
        final issues = results['issues'] as List;
        expect(issues.length, equals(2));
        expect(issues.any((i) => i.contains('不存在')), isTrue);
        expect(issues.any((i) => i.contains('存在性检查失败')), isTrue);
      } finally {
        MediaCleanupService.fileExistsForTesting = null;
      }
    });
  });

  group('MediaCleanupService.repairMediaReferences', () {
    test('完整触发修复流程（迁移笔记 + 验证完整性）', () async {
      final quote = Quote(
        id: 'note_repair_1',
        content: '待修复笔记',
        deltaContent: '[{"insert":{"image":"media/images/repair.jpg"}}]',
        date: DateTime.now().toIso8601String(),
      );
      await dbService.addQuote(quote);

      final appDocsDir = TestHarness.applicationDocumentsDirectory;
      final imgFile =
          File(path.join(appDocsDir.path, 'media', 'images', 'repair.jpg'));
      await imgFile.parent.create(recursive: true);
      await imgFile.writeAsString('repair_img');

      final results = await MediaCleanupService.repairMediaReferences();

      expect(results.containsKey('migration'), isTrue);
      expect(results.containsKey('verification'), isTrue);
      expect((results['verification'] as Map)['isHealthy'], isTrue);
    });

    test('当子流程异常时修复接口依然安全捕获并包含子任务状态', () async {
      PathProviderPlatform.instance = _ThrowingPathProvider();

      final results = await MediaCleanupService.repairMediaReferences();

      expect(results.containsKey('migration'), isTrue);
      expect(results.containsKey('verification'), isTrue);
      expect(
        (results['verification'] as Map).containsKey('error'),
        isTrue,
      );
    });
  });
}
