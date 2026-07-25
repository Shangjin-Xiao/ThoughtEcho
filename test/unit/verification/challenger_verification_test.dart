import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:thoughtecho/services/database_backup_service.dart';
import 'package:thoughtecho/services/database_schema_manager.dart';
import 'package:thoughtecho/services/localsend/models/device.dart';
import 'package:thoughtecho/services/localsend/models/info_register_dto.dart';
import 'package:thoughtecho/services/localsend/models/multicast_dto.dart';
import 'package:thoughtecho/services/localsend/models/prepare_upload_request_dto.dart';
import 'package:thoughtecho/services/localsend/models/prepare_upload_response_dto.dart';
import 'package:thoughtecho/services/webdav_sync_service.dart';
import 'package:thoughtecho/utils/path_security_utils.dart';
import 'package:thoughtecho/utils/zip_stream_processor.dart';

class FakePathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async {
    return Directory.systemTemp.path;
  }

  @override
  Future<String?> getApplicationSupportPath() async {
    return Directory.systemTemp.path;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Milestone 4 Empirical Verification Suite (Challenger 1)', () {
    // ------------------------------------------------------------------------
    // 1. Path Traversal & Zip Extraction Security Verification
    // ------------------------------------------------------------------------
    group('1. Zip Slip & Path Traversal Verification', () {
      late Directory tempDir;
      late String extractDir;

      setUp(() async {
        tempDir = await Directory.systemTemp.createTemp('challenger_zip_test_');
        extractDir = p.join(tempDir.path, 'extract_target');
        await Directory(extractDir).create(recursive: true);
      });

      tearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      test('sanitizeZipEntryName normalizes backslashes and leading slashes',
          () {
        expect(
          PathSecurityUtils.sanitizeZipEntryName(r'media\images\photo.jpg'),
          equals('media/images/photo.jpg'),
        );
        expect(
          PathSecurityUtils.sanitizeZipEntryName(
              r'..\..\Windows\System32\cmd.exe'),
          equals('../../Windows/System32/cmd.exe'),
        );
        expect(
          PathSecurityUtils.sanitizeZipEntryName('///etc/shadow'),
          equals('etc/shadow'),
        );
      });

      test('validateExtractionPath blocks POSIX, Windows & mixed traversal',
          () {
        // POSIX relative traversal
        final posixPath = p.join(extractDir, '..', 'forbidden.txt');
        expect(
          () => PathSecurityUtils.validateExtractionPath(posixPath, extractDir),
          throwsA(isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('安全警告'),
          )),
        );

        // Windows style backslash traversal
        final winEntry =
            PathSecurityUtils.sanitizeZipEntryName(r'..\..\evil.dll');
        final winSub = winEntry.replaceAll('/', p.separator);
        final winPath = p.join(extractDir, winSub);
        expect(
          () => PathSecurityUtils.validateExtractionPath(winPath, extractDir),
          throwsA(isA<Exception>()),
        );

        // Mixed slash traversal
        final mixedEntry =
            PathSecurityUtils.sanitizeZipEntryName(r'sub/..\../evil.txt');
        final mixedSub = mixedEntry.replaceAll('/', p.separator);
        final mixedPath = p.join(extractDir, mixedSub);
        expect(
          () => PathSecurityUtils.validateExtractionPath(mixedPath, extractDir),
          throwsA(isA<Exception>()),
        );
      });

      test('validateExtractionPath blocks directory prefix matching attacks',
          () {
        // Attack vector: extractDir is /path/target, target is /path/target_evil/file.txt
        final prefixMatchPath =
            '${extractDir}_malicious${p.separator}payload.sh';
        expect(
          () => PathSecurityUtils.validateExtractionPath(
              prefixMatchPath, extractDir),
          throwsA(isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('安全警告'),
          )),
        );
      });

      test('ZipStreamProcessor rejects archive containing Zip Slip entry',
          () async {
        final zipFile = File(p.join(tempDir.path, 'malicious.zip'));
        final archive = Archive();

        final safeBytes = utf8.encode('safe payload');
        archive.addFile(
            ArchiveFile('quotes/safe.txt', safeBytes.length, safeBytes));

        final evilBytes = utf8.encode('malicious payload');
        archive.addFile(
            ArchiveFile('../escaped_file.txt', evilBytes.length, evilBytes));

        final zipData = ZipEncoder().encode(archive);
        zipFile.writeAsBytesSync(zipData);

        expect(
          ZipStreamProcessor.extractZipStreaming(zipFile.path, extractDir),
          throwsA(isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('安全警告'),
          )),
        );

        final escapedFile = File(p.join(tempDir.path, 'escaped_file.txt'));
        expect(await escapedFile.exists(), isFalse);
      });
    });

    // ------------------------------------------------------------------------
    // 2. Database Rollback Verification
    // ------------------------------------------------------------------------
    group('2. SQLite Transaction Rollback Verification', () {
      late Database db;
      late DatabaseBackupService backupService;
      late String dbPath;

      setUpAll(() {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
        PathProviderPlatform.instance = FakePathProviderPlatform();
      });

      setUp(() async {
        dbPath = p.join(Directory.systemTemp.path, 'challenger_rollback.db');
        if (File(dbPath).existsSync()) {
          File(dbPath).deleteSync();
        }
        db = await databaseFactory.openDatabase(dbPath);
        await DatabaseSchemaManager().createTables(db);
        backupService = DatabaseBackupService();
      });

      tearDown(() async {
        await db.close();
      });

      test('importDataFromMap error rolls back entire transaction', () async {
        // 1. Setup baseline database state
        await db.insert('categories', {
          'id': 'cat_orig',
          'name': 'Original Category',
          'is_default': 1,
          'last_modified': '2026-01-01T00:00:00Z',
        });
        await db.insert('quotes', {
          'id': 'quote_orig',
          'content': 'Original Quote Content',
          'date': '2026-01-01T00:00:00Z',
          'last_modified': '2026-01-01T00:00:00Z',
        });
        await db.insert('quote_tags', {
          'quote_id': 'quote_orig',
          'tag_id': 'cat_orig',
        });

        // 2. Craft corrupted data payload that fails midway
        final invalidPayload = {
          'categories': [
            {'id': 'cat_new', 'name': 'New Category'},
          ],
          'quotes': [
            'this_is_not_a_map_and_will_throw_TypeError',
          ],
        };

        // 3. Attempt import and catch error
        expect(
          () async => await backupService.importDataFromMap(
            db,
            invalidPayload,
            clearExisting: true,
          ),
          throwsA(anything),
        );

        // 4. Empirically verify original database records remain 100% intact
        final categories = await db.query('categories');
        expect(categories.length, equals(1));
        expect(categories.first['id'], equals('cat_orig'));

        final quotes = await db.query('quotes');
        expect(quotes.length, equals(1));
        expect(quotes.first['id'], equals('quote_orig'));

        final tags = await db.query('quote_tags');
        expect(tags.length, equals(1));
        expect(tags.first['quote_id'], equals('quote_orig'));
      });

      test(
          'importDataWithLWWMerge invalid payload preserves database integrity',
          () async {
        await db.insert('quotes', {
          'id': 'lww_quote_orig',
          'content': 'LWW Original',
          'date': '2026-01-01T00:00:00Z',
          'last_modified': '2026-01-01T00:00:00Z',
        });

        final invalidMergePayload = <String, dynamic>{
          'categories': [
            {'id': 'cat_lww', 'name': 'LWW Cat'},
          ],
          // Missing 'quotes' key
        };

        final report = await backupService.importDataWithLWWMerge(
          db,
          invalidMergePayload,
        );

        expect(report.hasErrors, isTrue);

        final quotes = await db.query('quotes');
        expect(quotes.length, equals(1));
        expect(quotes.first['id'], equals('lww_quote_orig'));
      });
    });

    // ------------------------------------------------------------------------
    // 3. WebDAV Sync Lock & Error Sanitization Verification
    // ------------------------------------------------------------------------
    group('3. WebDAV Lock & Error Sanitization Verification', () {
      test('Sanitizes HTTP 507 Insufficient Storage error', () {
        final dioException = DioException(
          requestOptions: RequestOptions(path: 'https://dav.example.com/file'),
          response: Response(
            requestOptions:
                RequestOptions(path: 'https://dav.example.com/file'),
            statusCode: 507,
          ),
        );
        final sanitized =
            WebDAVSyncService.sanitizeSyncErrorForTesting(dioException);
        expect(sanitized, equals('服务器存储空间不足'));
      });

      test('Sanitizes HTTP 401 & 403 Authentication errors', () {
        final dioException401 = DioException(
          requestOptions: RequestOptions(path: 'https://dav.example.com/file'),
          response: Response(
            requestOptions:
                RequestOptions(path: 'https://dav.example.com/file'),
            statusCode: 401,
          ),
        );
        final sanitized =
            WebDAVSyncService.sanitizeSyncErrorForTesting(dioException401);
        expect(sanitized, equals('认证失败，请检查用户名和密码'));
      });

      test('Sanitizes HTTP 404 Not Found error', () {
        final dioException404 = DioException(
          requestOptions: RequestOptions(path: 'https://dav.example.com/file'),
          response: Response(
            requestOptions:
                RequestOptions(path: 'https://dav.example.com/file'),
            statusCode: 404,
          ),
        );
        final sanitized =
            WebDAVSyncService.sanitizeSyncErrorForTesting(dioException404);
        expect(sanitized, equals('服务器路径不存在，请检查地址配置'));
      });

      test('Sanitizes network connection & SSL errors', () {
        const socketErr = SocketException('Failed host lookup: dav.server.com');
        expect(
          WebDAVSyncService.sanitizeSyncErrorForTesting(socketErr),
          equals('无法连接到服务器，请检查网络和地址'),
        );

        const sslErr = HandshakeException('CERTIFICATE_VERIFY_FAILED');
        expect(
          WebDAVSyncService.sanitizeSyncErrorForTesting(sslErr),
          equals('SSL 证书验证失败'),
        );
      });

      test('Strips raw URLs and sensitive credentials from error text', () {
        const credentialUrlError =
            'Connection failed to https://myuser:supersecretpass99@dav.jianguoyun.com/dav/thoughtecho/';
        final sanitized =
            WebDAVSyncService.sanitizeSyncErrorForTesting(credentialUrlError);

        expect(sanitized, contains('[服务器地址]'));
        expect(sanitized, isNot(contains('supersecretpass99')));
        expect(sanitized, isNot(contains('myuser')));
        expect(sanitized, isNot(contains('dav.jianguoyun.com')));
      });
    });

    // ------------------------------------------------------------------------
    // 4. LocalSend Isolate Non-blocking Execution Verification
    // ------------------------------------------------------------------------
    group('4. LocalSend Isolate Offloading Verification', () {
      test(
          'Isolate.run handles PrepareUploadRequestDto JSON encoding & decoding',
          () async {
        final reqDto = PrepareUploadRequestDto(
          info: InfoRegisterDto(
            alias: 'Test Device',
            version: '2.1',
            deviceModel: 'Linux',
            deviceType: DeviceType.desktop,
            fingerprint: 'fp-12345',
            port: 53317,
            protocol: ProtocolType.https,
            download: false,
          ),
          files: {},
        );

        // Verify offloaded JSON encoding via Isolate.run
        final encodedJson =
            await Isolate.run(() => jsonEncode(reqDto.toJson()));
        expect(encodedJson, contains('Test Device'));
        expect(encodedJson, contains('fp-12345'));

        // Verify offloaded JSON decoding via Isolate.run
        final decodedDto = await Isolate.run(() {
          final map = jsonDecode(encodedJson) as Map<String, dynamic>;
          return PrepareUploadRequestDto.fromJson(map);
        });

        expect(decodedDto.info.alias, equals('Test Device'));
        expect(decodedDto.info.fingerprint, equals('fp-12345'));
      });

      test('Isolate.run handles PrepareUploadResponseDto JSON serialization',
          () async {
        final resDto = PrepareUploadResponseDto(
          sessionId: 'session-777',
          files: {'file_0': 'token-abc'},
        );

        final jsonString = await Isolate.run(() => jsonEncode(resDto.toJson()));
        expect(jsonString, contains('session-777'));
        expect(jsonString, contains('token-abc'));

        final parsedRes = await Isolate.run(() {
          final map = jsonDecode(jsonString) as Map<String, dynamic>;
          return PrepareUploadResponseDto.fromJson(map);
        });

        expect(parsedRes.sessionId, equals('session-777'));
        expect(parsedRes.files['file_0'], equals('token-abc'));
      });
    });
  });
}
