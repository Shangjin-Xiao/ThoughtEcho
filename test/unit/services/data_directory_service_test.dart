import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:thoughtecho/services/data_directory_service.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('thoughtecho_migration_test');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  String abs(String rel) => path.join(tempDir.path, rel);

  void createFile(String rel) {
    final file = File(abs(rel));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('content');
  }

  Set<String> relativeFiles(Map<String, dynamic> result) {
    return (result['files'] as List<String>)
        .map((f) => path.relative(f, from: tempDir.path))
        .toSet();
  }

  group('DataDirectoryService.collectFilesForMigration', () {
    test('整目录收集应用数据，包括未来新增的数据源', () async {
      createFile('databases/thoughtecho.db');
      createFile('media/photo.jpg');
      createFile('ai_analyses.db');
      createFile('chat.db');
      createFile('backups/backup.zip');
      createFile('feature_cache/data.bin'); // 模拟未来新增数据源

      final result = await DataDirectoryService.collectFilesForMigration(
        tempDir.path,
      );

      expect(result['errors'], isEmpty);
      final files = relativeFiles(result);
      expect(
        files,
        containsAll([
          'databases/thoughtecho.db',
          'media/photo.jpg',
          'ai_analyses.db',
          'chat.db',
          'backups/backup.zip',
          'feature_cache/data.bin',
        ]),
      );
    });

    test('跳过系统文件和 SQLite -shm 临时文件，保留 -wal', () async {
      createFile('databases/thoughtecho.db');
      createFile('databases/thoughtecho.db-wal');
      createFile('databases/thoughtecho.db-shm');
      createFile('desktop.ini');
      createFile('thumbs.db');
      createFile('ntuser.dat');
      createFile('.ds_store');

      final result = await DataDirectoryService.collectFilesForMigration(
        tempDir.path,
      );

      final files = relativeFiles(result);
      expect(files, contains('databases/thoughtecho.db'));
      expect(files, contains('databases/thoughtecho.db-wal'));
      expect(files, isNot(contains('databases/thoughtecho.db-shm')));
      expect(files, isNot(contains('desktop.ini')));
      expect(files, isNot(contains('thumbs.db')));
      expect(files, isNot(contains('ntuser.dat')));
      expect(files, isNot(contains('.ds_store')));
    });

    test('excludePath 位于数据目录内时，其中的文件不参与收集', () async {
      createFile('databases/thoughtecho.db');
      createFile('nested_target/data.bin');
      createFile('nested_target/deep/inner.bin');

      final result = await DataDirectoryService.collectFilesForMigration(
        tempDir.path,
        excludePath: abs('nested_target'),
      );

      final files = relativeFiles(result);
      expect(files, contains('databases/thoughtecho.db'));
      expect(files, isNot(contains('nested_target/data.bin')));
      expect(files, isNot(contains('nested_target/deep/inner.bin')));
    });

    test('数据目录不存在时返回空列表和错误', () async {
      final missing = path.join(tempDir.path, 'does_not_exist');
      final result = await DataDirectoryService.collectFilesForMigration(
        missing,
      );

      expect(result['files'], isEmpty);
      expect(result['errors'], isNotEmpty);
    });
  });
}
