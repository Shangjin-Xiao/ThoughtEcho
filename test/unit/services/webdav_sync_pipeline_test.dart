import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:thoughtecho/services/media_reference_service.dart';
import 'package:thoughtecho/services/webdav_sync_service.dart';
import 'package:thoughtecho/utils/mmkv_ffi_fix.dart';

class _MockPathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String testAppDir;
  _MockPathProvider(this.testAppDir);

  @override
  Future<String?> getApplicationDocumentsPath() async => testAppDir;
}

class _CountingDatabase implements Database {
  final Database _inner;
  int queryCount = 0;
  final List<String> queries = [];

  _CountingDatabase(this._inner);

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) {
    queryCount++;
    queries.add(sql);
    return _inner.rawQuery(sql, arguments);
  }

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) {
    queryCount++;
    queries.add('query: $table where $where');
    return _inner.query(
      table,
      distinct: distinct,
      columns: columns,
      where: where,
      whereArgs: whereArgs,
      groupBy: groupBy,
      having: having,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
  }

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) =>
      _inner.execute(sql, arguments);

  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) =>
      _inner.insert(
        table,
        values,
        nullColumnHack: nullColumnHack,
        conflictAlgorithm: conflictAlgorithm,
      );

  @override
  Future<void> close() => _inner.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestHttpClientAdapter implements HttpClientAdapter {
  final Future<ResponseBody> Function(RequestOptions options) fetchHandler;
  _TestHttpClientAdapter(this.fetchHandler);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return fetchHandler(options);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database rawDb;
  late _CountingDatabase countingDb;
  late Directory tempDir;
  late Directory mediaDir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final safeMMKV = SafeMMKV();
    await safeMMKV.initialize();
    await safeMMKV.clear();

    tempDir = await Directory.systemTemp.createTemp('webdav_pipeline_test');
    mediaDir = Directory(p.join(tempDir.path, 'media'));
    await mediaDir.create(recursive: true);

    PathProviderPlatform.instance = _MockPathProvider(tempDir.path);

    rawDb = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await rawDb.execute('''
      CREATE TABLE quotes(
        id TEXT PRIMARY KEY,
        content TEXT,
        delta_content TEXT,
        date TEXT
      )
    ''');
    await MediaReferenceService.initializeTable(rawDb);
    countingDb = _CountingDatabase(rawDb);
    MediaReferenceService.setDatabaseForTesting(countingDb);
  });

  tearDown(() async {
    MediaReferenceService.clearDatabaseForTesting();
    await rawDb.close();
    WebDAVSyncService.mediaDownloadConcurrencyForTesting = null;
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  String buildPropfindXml(List<String> relativePaths, {int fileSize = 10}) {
    final buffer = StringBuffer();
    buffer.writeln('<?xml version="1.0" encoding="utf-8"?>');
    buffer.writeln('<d:multistatus xmlns:d="DAV:">');
    for (final relPath in relativePaths) {
      buffer.writeln('  <d:response>');
      buffer.writeln('    <d:href>/dav/thoughtecho/media/$relPath</d:href>');
      buffer.writeln(
          '    <d:propstat><d:prop><d:getcontentlength>$fileSize</d:getcontentlength></d:prop></d:propstat>');
      buffer.writeln('  </d:response>');
    }
    buffer.writeln('</d:multistatus>');
    return buffer.toString();
  }

  group('WebDAV Media Sync Pipeline Tests', () {
    test('Criterion 1: 对本地数据库的媒体引用查询次数严格恒定为 1 次，不再随云端附件数量动态增长', () async {
      // 插入 20 条媒体引用记录到本地库
      await rawDb.insert('quotes', {
        'id': 'q1',
        'content': 'Test',
        'date': DateTime.now().toIso8601String(),
      });
      const fileCount = 20;
      for (var i = 0; i < fileCount; i++) {
        await rawDb.insert('media_references', {
          'id': 'ref_$i',
          'file_path': 'media/images/file_$i.jpg',
          'quote_id': 'q1',
          'created_at': DateTime.now().toIso8601String(),
        });
      }

      final files = List.generate(fileCount, (i) => 'images/file_$i.jpg');
      final xmlResponse = buildPropfindXml(files);

      final service = WebDAVSyncService();
      service.setUrlForTesting('https://dav.example.com/dav/');

      final dio = Dio();
      dio.httpClientAdapter = _TestHttpClientAdapter((options) async {
        if (options.method == 'PROPFIND') {
          if (options.path.contains('/images/')) {
            return ResponseBody.fromString(xmlResponse, 207);
          }
          return ResponseBody.fromString(buildPropfindXml([]), 207);
        } else if (options.method == 'GET') {
          // 返回 10 字节文件内容
          return ResponseBody.fromString(
            '0123456789',
            200,
            headers: {
              Headers.contentLengthHeader: ['10'],
            },
          );
        }
        return ResponseBody.fromString('', 404);
      });

      // 重置查询计数器
      countingDb.queryCount = 0;
      countingDb.queries.clear();

      final failureCount = await service.syncMediaFilesForTesting(dio);

      expect(failureCount, equals(0));
      // 严格断言：媒体同步全流程中对数据库的媒体引用查询严格恒定为 1 次
      expect(countingDb.queryCount, equals(1));
      expect(countingDb.queries.single,
          contains('SELECT DISTINCT file_path FROM media_references'));

      // 验证全部 20 个文件均落盘成功
      for (var i = 0; i < fileCount; i++) {
        final f = File(p.join(mediaDir.path, 'images', 'file_$i.jpg'));
        expect(await f.exists(), isTrue);
        expect(await f.readAsString(), equals('0123456789'));
      }
    });

    test('Criterion 2: 本地未引用的云端孤儿文件被跳过并不执行下载，不产生任何 SQLite substr 全表扫描',
        () async {
      await rawDb.insert('quotes', {
        'id': 'q1',
        'content': 'Test',
        'date': DateTime.now().toIso8601String(),
      });
      // 仅引用 file_0，其余 9 个均为云端孤儿文件
      await rawDb.insert('media_references', {
        'id': 'ref_0',
        'file_path': 'media/images/file_0.jpg',
        'quote_id': 'q1',
        'created_at': DateTime.now().toIso8601String(),
      });

      const totalRemote = 10;
      final files = List.generate(totalRemote, (i) => 'images/file_$i.jpg');
      final xmlResponse = buildPropfindXml(files);

      final service = WebDAVSyncService();
      service.setUrlForTesting('https://dav.example.com/dav/');

      final downloadedFiles = <String>[];
      final dio = Dio();
      dio.httpClientAdapter = _TestHttpClientAdapter((options) async {
        if (options.method == 'PROPFIND') {
          if (options.path.contains('/images/')) {
            return ResponseBody.fromString(xmlResponse, 207);
          }
          return ResponseBody.fromString(buildPropfindXml([]), 207);
        } else if (options.method == 'GET') {
          downloadedFiles.add(options.path);
          return ResponseBody.fromString(
            '0123456789',
            200,
            headers: {
              Headers.contentLengthHeader: ['10']
            },
          );
        }
        return ResponseBody.fromString('', 404);
      });

      countingDb.queryCount = 0;
      countingDb.queries.clear();

      final failureCount = await service.syncMediaFilesForTesting(dio);

      expect(failureCount, equals(0));
      // 仅有 1 次 DISTINCT 预加载查询
      expect(countingDb.queryCount, equals(1));
      // 没有任何包含 substr 的全表扫描或模糊匹配
      for (final q in countingDb.queries) {
        expect(q.contains('substr'), isFalse);
      }

      // 仅引用的 file_0 被下载，其余 9 个孤儿附件完全不下载
      expect(downloadedFiles.length, equals(1));
      expect(downloadedFiles.first, contains('file_0.jpg'));
      expect(
        await File(p.join(mediaDir.path, 'images', 'file_0.jpg')).exists(),
        isTrue,
      );
      for (var i = 1; i < totalRemote; i++) {
        expect(
          await File(p.join(mediaDir.path, 'images', 'file_$i.jpg')).exists(),
          isFalse,
        );
      }
    });

    test('Criterion 3: 20 个媒体文件下载时并发数严格限制在 4，所有文件下载并通过哈希校验后落地', () async {
      await rawDb.insert('quotes', {
        'id': 'q1',
        'content': 'Test',
        'date': DateTime.now().toIso8601String(),
      });
      const fileCount = 20;
      for (var i = 0; i < fileCount; i++) {
        await rawDb.insert('media_references', {
          'id': 'ref_$i',
          'file_path': 'media/images/file_$i.jpg',
          'quote_id': 'q1',
          'created_at': DateTime.now().toIso8601String(),
        });
      }

      final files = List.generate(fileCount, (i) => 'images/file_$i.jpg');
      final xmlResponse = buildPropfindXml(files);

      final service = WebDAVSyncService();
      service.setUrlForTesting('https://dav.example.com/dav/');

      var activeConnections = 0;
      var peakConnections = 0;

      final dio = Dio();
      dio.httpClientAdapter = _TestHttpClientAdapter((options) async {
        if (options.method == 'PROPFIND') {
          if (options.path.contains('/images/')) {
            return ResponseBody.fromString(xmlResponse, 207);
          }
          return ResponseBody.fromString(buildPropfindXml([]), 207);
        } else if (options.method == 'GET') {
          activeConnections++;
          if (activeConnections > peakConnections) {
            peakConnections = activeConnections;
          }
          // 模拟网络延迟
          await Future.delayed(const Duration(milliseconds: 15));
          activeConnections--;
          return ResponseBody.fromString(
            '0123456789',
            200,
            headers: {
              Headers.contentLengthHeader: ['10']
            },
          );
        }
        return ResponseBody.fromString('', 404);
      });

      final failureCount = await service.syncMediaFilesForTesting(dio);

      expect(failureCount, equals(0));
      // 峰值并发数严格为 4
      expect(peakConnections, equals(4));

      // 验证全部 20 个文件均落盘成功且临时文件已被清理
      for (var i = 0; i < fileCount; i++) {
        final targetPath = p.join(mediaDir.path, 'images', 'file_$i.jpg');
        expect(await File(targetPath).exists(), isTrue);
        expect(await File('$targetPath.tmp').exists(), isFalse);
      }
    });

    test('Criterion 4: 单张图片下载失败或哈希不一致时，其余 19 张图片正常落盘，且失败图片的 .tmp 被彻底清除',
        () async {
      await rawDb.insert('quotes', {
        'id': 'q1',
        'content': 'Test',
        'date': DateTime.now().toIso8601String(),
      });
      const fileCount = 20;
      for (var i = 0; i < fileCount; i++) {
        await rawDb.insert('media_references', {
          'id': 'ref_$i',
          'file_path': 'media/images/file_$i.jpg',
          'quote_id': 'q1',
          'created_at': DateTime.now().toIso8601String(),
        });
      }

      final files = List.generate(fileCount, (i) => 'images/file_$i.jpg');
      final xmlResponse = buildPropfindXml(files);

      final service = WebDAVSyncService();
      service.setUrlForTesting('https://dav.example.com/dav/');

      final dio = Dio();
      dio.httpClientAdapter = _TestHttpClientAdapter((options) async {
        if (options.method == 'PROPFIND') {
          if (options.path.contains('/images/')) {
            return ResponseBody.fromString(xmlResponse, 207);
          }
          return ResponseBody.fromString(buildPropfindXml([]), 207);
        } else if (options.method == 'GET') {
          // 让 file_7 发生下载损坏（返回长度不一致）
          if (options.path.contains('file_7.jpg')) {
            return ResponseBody.fromString(
              'short', // 期望 10 字节，实际仅 5 字节
              200,
              headers: {
                Headers.contentLengthHeader: ['5']
              },
            );
          }
          return ResponseBody.fromString(
            '0123456789',
            200,
            headers: {
              Headers.contentLengthHeader: ['10']
            },
          );
        }
        return ResponseBody.fromString('', 404);
      });

      final failureCount = await service.syncMediaFilesForTesting(dio);

      // 单个附件失败，failureCount 为 1
      expect(failureCount, equals(1));

      // 失败的 file_7 未落盘，且其对应的 .tmp 临时文件被彻底清除
      final failedTarget = p.join(mediaDir.path, 'images', 'file_7.jpg');
      expect(await File(failedTarget).exists(), isFalse);
      expect(await File('$failedTarget.tmp').exists(), isFalse);

      // 其余 19 张图片全部正常落盘且内容完整
      for (var i = 0; i < fileCount; i++) {
        if (i == 7) continue;
        final targetPath = p.join(mediaDir.path, 'images', 'file_$i.jpg');
        expect(await File(targetPath).exists(), isTrue);
        expect(await File('$targetPath.tmp').exists(), isFalse);
        expect(await File(targetPath).readAsString(), equals('0123456789'));
      }
    });
  });
}
