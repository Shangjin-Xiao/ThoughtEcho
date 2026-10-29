import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:thoughtecho/services/database_schema_manager.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/mmkv_service.dart';
import 'package:thoughtecho/services/webdav_sync_service.dart';
import 'package:thoughtecho/utils/mmkv_ffi_fix.dart';

import '../../test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('sync backs up each local revision once despite duplicate remote IDs',
      () async {
    await TestHarness.initialize();
    await MMKVService().init();
    await SafeMMKV().clear();
    await MMKVService().setString(
      'webdav_last_sync_time',
      '2026-01-01T00:00:00Z',
    );

    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await DatabaseSchemaManager().createTables(db);
    DatabaseService.setTestDatabase(db);
    await DatabaseService().init();
    addTearDown(() async {
      DatabaseService.clearTestDatabase();
      await db.close();
    });

    const connectivityChannel =
        MethodChannel('dev.fluttercommunity.plus/connectivity');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(connectivityChannel, (_) async => ['mobile']);
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(connectivityChannel, null);
    });

    final localContent = List.filled(1024, 'Local note text. ').join();
    final localDelta = jsonEncode([
      {'insert': '$localContent\n'},
    ]);
    for (final id in ['q1', 'q2', 'unchanged']) {
      await db.insert('quotes', {
        'id': id,
        'content': localContent,
        'delta_content': localDelta,
        'date': '2026-01-01T00:00:00Z',
        'last_modified': '2026-01-02T00:00:00Z',
        'is_deleted': 0,
      });
    }
    for (final tagId in ['tag1', 'tag2']) {
      await db.insert('categories', {'id': tagId, 'name': tagId});
      await db.insert('quote_tags', {'quote_id': 'q1', 'tag_id': tagId});
    }

    final remoteData = {
      'categories': <Object>[],
      'quotes': [
        // Non-conflicts must not prevent a later record from backing up q1.
        {
          'id': 'q1',
          'content': 'Stale remote text',
          'last_modified': '2025-12-31T00:00:00Z',
        },
        {
          'id': 'q1',
          'content': localContent,
          'last_modified': '2026-01-02T00:00:00Z',
        },
        // Cross the tag prefetch chunk boundary; repeats include both identical
        // records and different remote revisions of the same local snapshot.
        for (var i = 0; i < 901; i++)
          {
            'id': 'q1',
            'content': 'Remote q1',
            'last_modified':
                i.isEven ? '2026-01-03T00:00:00Z' : '2026-01-04T00:00:00Z',
          },
        {
          'id': 'q2',
          'content': 'Remote q2',
          'lastModified': '2026-01-03T00:00:00Z',
        },
        {
          'id': 'unchanged',
          'content': localContent,
          'last_modified': '2026-01-02T00:00:00Z',
        },
      ],
    };
    final jsonBytes = utf8.encode(jsonEncode(remoteData));
    final remoteZip = ZipEncoder().encode(
      Archive()
        ..addFile(ArchiveFile('backup_data.json', jsonBytes.length, jsonBytes)),
    );
    List<int>? uploadedZip;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      final body = await request.fold<List<int>>([], (a, b) => a..addAll(b));
      final response = request.response;
      if (request.uri.path.endsWith('thoughtecho_sync.zip')) {
        switch (request.method) {
          case 'PROPFIND':
            response.statusCode = 207;
            response.write('''
<d:multistatus xmlns:d="DAV:"><d:response>
<d:href>/dav/thoughtecho/thoughtecho_sync.zip</d:href>
<d:propstat><d:prop><d:getetag>"revision-1"</d:getetag>
<d:getcontentlength>${remoteZip.length}</d:getcontentlength>
</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>
</d:response></d:multistatus>''');
          case 'GET':
            response.add(remoteZip);
          case 'PUT':
            uploadedZip = body;
            response.statusCode = 204;
          default:
            response.statusCode = 405;
        }
      } else {
        // All requests here are directory existence checks. Media is skipped.
        response.statusCode = 207;
      }
      await response.close();
    });

    final service = WebDAVSyncService.forTesting();
    addTearDown(service.dispose);
    await service.saveSettings(
      enabled: true,
      provider: 'custom',
      url: 'https://webdav.example.invalid/dav/',
      username: 'test-user',
      password: 'synthetic-password',
      syncOnLaunch: false,
      syncOnChange: false,
      syncOnCellular: false,
      syncNotesOnlyOnCellular: true,
    );
    await HttpOverrides.runWithHttpOverrides(
      () => service.triggerSync(),
      _LoopbackHttpOverrides(server.port),
    );

    expect(service.syncStatus, WebDAVSyncStatus.success,
        reason: service.lastSyncError);
    final backups = await db.query('quotes',
        where: 'category_id = ?',
        whereArgs: [WebDAVSyncService.conflictCategoryId]);
    expect(backups.length, 2);
    expect(service.lastConflictCount, 2);
    for (final backup in backups) {
      expect(backup['content'], '[冲突备份] $localContent');
      expect(jsonDecode(backup['delta_content']! as String), [
        {'insert': '[冲突备份] '},
        {'insert': '$localContent\n'},
      ]);
    }
    final backupTags =
        await db.query('quote_tags', where: 'quote_id != ?', whereArgs: ['q1']);
    expect(backupTags, hasLength(2));
    expect(backupTags.map((tag) => tag['tag_id']),
        unorderedEquals(['tag1', 'tag2']));
    expect(backupTags.map((tag) => tag['quote_id']).toSet(), hasLength(1));
    final originals = await db
        .query('quotes', where: 'id IN (?, ?)', whereArgs: ['q1', 'q2']);
    expect(originals.map((q) => q['content']),
        unorderedEquals(['Remote q1', 'Remote q2']));
    // Confirm the persisted result also reaches the outgoing sync package.
    expect(uploadedZip, isNotNull);
    final uploadedData =
        WebDAVSyncService.decodeAndValidateRemoteSyncZipForTesting(
            uploadedZip!);
    expect(uploadedData['quotes'] as List, hasLength(5));
  });
}

// Route the production HTTPS client to an isolated local server without adding
// a testing hook to WebDAVSyncService or contacting a real provider.
class _LoopbackHttpOverrides extends HttpOverrides {
  _LoopbackHttpOverrides(this.port);
  final int port;

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _LoopbackHttpClient(super.createHttpClient(context), port);
}

class _LoopbackHttpClient implements HttpClient {
  _LoopbackHttpClient(this.delegate, this.port);
  final HttpClient delegate;
  final int port;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) {
    if (url.host != 'webdav.example.invalid' || url.scheme != 'https') {
      throw StateError('Unexpected test URL');
    }
    return delegate.openUrl(
        method, url.replace(scheme: 'http', host: '127.0.0.1', port: port));
  }

  @override
  Duration? get connectionTimeout => delegate.connectionTimeout;
  @override
  set connectionTimeout(Duration? value) => delegate.connectionTimeout = value;
  @override
  set idleTimeout(Duration value) => delegate.idleTimeout = value;
  @override
  void close({bool force = false}) => delegate.close(force: force);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
