import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:thoughtecho/services/data_directory_service.dart';

import '../../test_harness.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    await TestHarness.initialize();
  });

  setUp(() async {
    tempDir = await TestHarness.createTempDirectory('migration_test');
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

  Set<String> relativeFiles(MigrationFileScan scan) =>
      scan.files.map((e) => e.$2).toSet();

  group('DataDirectoryService.collectFilesForMigration', () {
    test('整目录收集应用数据，包括未来新增的数据源', () async {
      createFile('databases/thoughtecho.db');
      createFile('media/photo.jpg');
      createFile('ai_analyses.db');
      createFile('chat.db');
      createFile('backups/backup.zip');
      createFile('feature_cache/data.bin'); // 模拟未来新增数据源

      final scan = await DataDirectoryService.collectFilesForMigration(
        tempDir.path,
      );

      expect(scan.errors, isEmpty);
      final files = relativeFiles(scan);
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

      final scan = await DataDirectoryService.collectFilesForMigration(
        tempDir.path,
      );

      final files = relativeFiles(scan);
      expect(files, contains('databases/thoughtecho.db'));
      expect(files, contains('databases/thoughtecho.db-wal'));
      expect(files, isNot(contains('databases/thoughtecho.db-shm')));
      expect(files, isNot(contains('desktop.ini')));
      expect(files, isNot(contains('thumbs.db')));
      expect(files, isNot(contains('ntuser.dat')));
      expect(files, isNot(contains('.ds_store')));
    });

    test('相对路径以数据目录为基准，保持子目录结构', () async {
      final dataDir = Directory(abs('ThoughtEcho'))..createSync();
      createFile('ThoughtEcho/databases/thoughtecho.db');
      createFile('ThoughtEcho/media/sub/photo.jpg');

      final scan = await DataDirectoryService.collectFilesForMigration(
        dataDir.path,
      );

      expect(
        relativeFiles(scan),
        equals({'databases/thoughtecho.db', 'media/sub/photo.jpg'}),
      );
    });

    test('数据目录不存在时返回空列表和带原因的错误', () async {
      final missing = path.join(tempDir.path, 'does_not_exist');
      final scan = await DataDirectoryService.collectFilesForMigration(
        missing,
      );

      expect(scan.files, isEmpty);
      expect(scan.errors, hasLength(1));
      // 错误里要带上失败原因，否则用户只看到路径无法排障。
      expect(scan.errors.single, contains(missing));
      expect(scan.errors.single.length, greaterThan(missing.length + 8));
    });

    test('指向外部的目录链接被展开，文件落在链接名相对路径下', () async {
      // 外部目录必须是数据目录（tempDir）之外的兄弟目录，链接才属于"外部"。
      final external = await TestHarness.createTempDirectory('external_media');
      addTearDown(() => TestHarness.deleteTempDirectory(external));
      final externalFile = File(path.join(external.path, 'a.jpg'));
      externalFile.createSync();
      externalFile.writeAsStringSync('content');

      createFile('databases/thoughtecho.db');
      final link = Link(abs('media'));
      try {
        link.createSync(external.path);
      } on FileSystemException {
        markTestSkipped('当前环境无法创建符号链接');
        return;
      }

      final scan = await DataDirectoryService.collectFilesForMigration(
        tempDir.path,
      );

      final files = relativeFiles(scan);
      expect(files, contains('databases/thoughtecho.db'));
      expect(files, contains('media/a.jpg'));
      expect(scan.errors, isEmpty);
    });

    test('指向数据目录内部的链接被跳过，不产生重复或错误路径', () async {
      createFile('databases/thoughtecho.db');
      final link = Link(abs('dup'));
      try {
        link.createSync(abs('databases'));
      } on FileSystemException {
        markTestSkipped('当前环境无法创建符号链接');
        return;
      }

      final scan = await DataDirectoryService.collectFilesForMigration(
        tempDir.path,
      );

      final files = relativeFiles(scan);
      expect(files, contains('databases/thoughtecho.db'));
      expect(files, isNot(contains('dup/thoughtecho.db')));
    });

    test('指向外部的文件链接作为文件收集', () async {
      // 外部文件放在数据目录之外的兄弟目录，链接才属于"外部"。
      final externalDir =
          await TestHarness.createTempDirectory('external_files');
      addTearDown(() => TestHarness.deleteTempDirectory(externalDir));
      final externalFile = File(path.join(externalDir.path, 'external.dat'));
      externalFile.createSync();
      externalFile.writeAsStringSync('content');

      final link = Link(abs('linked.dat'));
      try {
        link.createSync(externalFile.path);
      } on FileSystemException {
        markTestSkipped('当前环境无法创建符号链接');
        return;
      }

      final scan = await DataDirectoryService.collectFilesForMigration(
        tempDir.path,
      );

      final files = relativeFiles(scan);
      expect(files, contains('linked.dat'));
      expect(scan.errors, isEmpty);
    });
  });

  group('DataDirectoryService.copyFilesForMigration', () {
    test('保持目录结构复制所有文件，并回报进度', () async {
      createFile('databases/thoughtecho.db');
      createFile('media/sub/photo.jpg');
      final target = await TestHarness.createTempDirectory('copy_target');
      addTearDown(() => TestHarness.deleteTempDirectory(target));

      final scan = await DataDirectoryService.collectFilesForMigration(
        tempDir.path,
      );
      final progressValues = <double>[];
      await DataDirectoryService.copyFilesForMigration(
        scan.files,
        target.path,
        onProgress: progressValues.add,
      );

      expect(
        File(path.join(target.path, 'databases', 'thoughtecho.db'))
            .existsSync(),
        isTrue,
      );
      expect(
        File(path.join(target.path, 'media', 'sub', 'photo.jpg')).existsSync(),
        isTrue,
      );
      expect(progressValues.last, closeTo(1.0, 0.001));
    });

    test('任一文件复制失败即抛出，不静默跳过', () async {
      // 收集之后源文件消失，模拟被占用/无权限等复制期失败。
      createFile('databases/thoughtecho.db');
      final target = await TestHarness.createTempDirectory('copy_fail_target');
      addTearDown(() => TestHarness.deleteTempDirectory(target));

      final scan = await DataDirectoryService.collectFilesForMigration(
        tempDir.path,
      );
      File(abs('databases/thoughtecho.db')).deleteSync();

      await expectLater(
        DataDirectoryService.copyFilesForMigration(scan.files, target.path),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('DataDirectoryService.validateDataDirectoryPath', () {
    test('相同目录返回错误', () {
      expect(
        DataDirectoryService.validateDataDirectoryPath(
          path.join(tempDir.path, 'a'),
          path.join(tempDir.path, 'a'),
        ),
        isNotNull,
      );
    });

    test('目标是当前目录的祖先时返回错误', () {
      expect(
        DataDirectoryService.validateDataDirectoryPath(
          path.join(tempDir.path, 'a', 'b'),
          tempDir.path,
        ),
        isNotNull,
      );
    });

    test('目标位于当前目录内部时返回错误', () {
      expect(
        DataDirectoryService.validateDataDirectoryPath(
          tempDir.path,
          path.join(tempDir.path, 'a', 'b'),
        ),
        isNotNull,
      );
    });

    test('无关目录返回 null', () {
      expect(
        DataDirectoryService.validateDataDirectoryPath(
          path.join(tempDir.path, 'a'),
          path.join(tempDir.path, 'other'),
        ),
        isNull,
      );
    });

    test('Windows 下大小写不同的同一目录被判为相同', () {
      // 用 Windows 风格路径直接验证，不依赖宿主平台。
      final windows = path.Context(style: path.Style.windows);
      expect(
        windows.equals(r'C:\Users\Me\Documents\ThoughtEcho',
            r'c:\users\me\documents\thoughtecho'),
        isTrue,
      );
    });

    test('不同盘符的目标不会被误判为祖先或嵌套', () {
      // package:path 的 Windows 风格把盘符作为第一段比较，跨盘迁移不应被拦。
      final windows = path.Context(style: path.Style.windows);
      const current = r'C:\Users\Me\Documents\ThoughtEcho';
      const target = r'D:\ThoughtEcho';
      expect(windows.isWithin(target, current), isFalse);
      expect(windows.isWithin(current, target), isFalse);
    });
  });

  group('DataDirectoryService.validateMigrationTarget', () {
    test('与当前目录相同返回错误', () async {
      final current = await DataDirectoryService.getCurrentDataDirectory();
      expect(
        await DataDirectoryService.validateMigrationTarget(current),
        isNotNull,
      );
    });

    test('目标是当前目录的祖先时返回错误', () async {
      final current = await DataDirectoryService.getCurrentDataDirectory();
      final ancestor = path.dirname(current);
      expect(
        await DataDirectoryService.validateMigrationTarget(ancestor),
        isNotNull,
      );
    });

    test('无关目录返回 null', () async {
      final unrelated = await TestHarness.createTempDirectory('target_test');
      addTearDown(() => TestHarness.deleteTempDirectory(unrelated));

      expect(
        await DataDirectoryService.validateMigrationTarget(unrelated.path),
        isNull,
      );
    });
  });

  group('DataDirectoryService.canonicalizePath', () {
    test('普通存在的目录原样返回', () {
      final real = Directory(abs('real'))..createSync();
      final resolved = DataDirectoryService.canonicalizePath(real.path);
      expect(path.equals(resolved, real.path), isTrue);
    });

    test('指向当前目录的符号链接被解析成同一真实路径', () {
      final real = Directory(abs('real'))..createSync();
      final link = Link(abs('link'));
      try {
        link.createSync(real.path);
      } on FileSystemException {
        markTestSkipped('当前环境无法创建符号链接');
        return;
      }

      final resolved = DataDirectoryService.canonicalizePath(link.path);
      expect(path.equals(resolved, real.path), isTrue);
    });

    test('不存在的目标目录解析为规范化路径（逐级向上解析存在的祖先）', () {
      final parent = Directory(abs('parent'))..createSync();
      final target = path.join(parent.path, 'sub', 'new');

      final resolved = DataDirectoryService.canonicalizePath(target);
      expect(path.equals(resolved, target), isTrue);
    });
  });
}
