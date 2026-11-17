import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thoughtecho/services/app_preferences_service.dart';
import 'package:thoughtecho/services/media_fingerprint_cache.dart';
import 'package:thoughtecho/services/unified_log_service.dart';
import 'package:thoughtecho/services/webdav_sync_service.dart';
import 'package:thoughtecho/utils/app_logger.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel secureStorageChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  final Map<String, String> secureStorage = {};
  late AppPreferencesService appPrefs;

  setUp(() async {
    // 清空 Mock 存储
    secureStorage.clear();

    // 初始化 SharedPreferences (为 AppPreferencesService 做 Mock 初始化准备)
    SharedPreferences.setMockInitialValues({});

    appPrefs = AppPreferencesService();
    await appPrefs.init();
    await appPrefs.clear();

    // Mock FlutterSecureStorage 方法通道
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (
      MethodCall methodCall,
    ) async {
      if (methodCall.method == 'read') {
        return secureStorage[methodCall.arguments['key']];
      }
      if (methodCall.method == 'write') {
        secureStorage[methodCall.arguments['key']] =
            methodCall.arguments['value'];
        return null;
      }
      if (methodCall.method == 'delete') {
        secureStorage.remove(methodCall.arguments['key']);
        return null;
      }
      if (methodCall.method == 'readAll') {
        return secureStorage;
      }
      return null;
    });
  });

  test(
      'getPassword returns null without logging the raw exception on storage failure',
      () async {
    final logService = _RecordingLogService();
    AppLogger.serviceForTesting = logService;
    try {
      final service = WebDAVSyncService();

      // Mock secureStorage to throw an exception on read
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(secureStorageChannel, (
        MethodCall methodCall,
      ) async {
        if (methodCall.method == 'read') {
          throw PlatformException(
            code: 'READ_FAILED',
            message: 'Failed to read from secure storage',
          );
        }
        return null;
      });

      final password = await service.getPassword();
      expect(password, isNull);

      // 安全回归：读取失败只记来源，不把原始异常对象写入日志。
      // 若恢复 `error: e`，下面对 error 的断言会失败。
      final errorLogs = logService.records
          .where((r) => r.level == UnifiedLogLevel.error)
          .toList();
      expect(errorLogs, isNotEmpty);
      for (final record in errorLogs) {
        expect(record.message, contains('读取 WebDAV 密码失败'));
        expect(record.error, isNull);
      }
    } finally {
      AppLogger.initialize();
    }
  });

  test(
    'WebDAVSyncService should initialize and save settings correctly',
    () async {
      final service = WebDAVSyncService();

      // 测试默认配置
      expect(service.enabled, false);
      expect(service.provider, 'custom');
      expect(service.url, '');
      expect(service.username, '');
      expect(service.syncOnOpenOrForeground, true);
      expect(service.syncOnLaunch, true);
      expect(service.syncOnChange, true);

      // 保存新配置并包含密码
      await service.saveSettings(
        enabled: true,
        provider: 'nutstore',
        url: 'https://dav.jianguoyun.com/dav',
        username: 'user@example.com',
        password: 'my-app-token-123',
        syncOnLaunch: false,
        syncOnChange: true,
        syncOnCellular: false,
        syncNotesOnlyOnCellular: false,
      );

      // 检查缓存状态是否更新
      expect(service.enabled, true);
      expect(service.provider, 'nutstore');
      // 服务自动在 URL 后附加斜杠
      expect(service.url, 'https://dav.jianguoyun.com/dav/');
      expect(service.username, 'user@example.com');
      expect(service.syncOnOpenOrForeground, false);
      expect(service.syncOnLaunch, false);
      expect(service.syncOnChange, true);

      // 检查密码是否被加密安全存储
      final savedPassword = await service.getPassword();
      expect(savedPassword, 'my-app-token-123');
      expect(secureStorage['webdav_password'], 'my-app-token-123');
    },
  );

  test(
      'WebDAVSyncService should transition status correctly during sync initialization',
      () async {
    final service = WebDAVSyncService();

    // 初始状态应该为闲置
    expect(service.syncStatus, WebDAVSyncStatus.idle);
    expect(service.isSyncing, false);

    // 如果没有配置好连接，触发同步时应该快速跳过且状态维持原样
    await service.triggerSync();
    expect(service.syncStatus, WebDAVSyncStatus.idle);
    expect(service.isSyncing, false);
  });

  test(
      'WebDAVSyncService should enforce HTTPS strictly on saveSettings only when enabled',
      () async {
    final service = WebDAVSyncService();

    // 当 enabled = true 时，应该抛出异常
    expect(
      service.saveSettings(
        enabled: true,
        provider: 'custom',
        url: 'http://insecure.server.local/dav/',
        username: 'user',
        syncOnLaunch: false,
        syncOnChange: false,
        syncOnCellular: false,
        syncNotesOnlyOnCellular: false,
      ),
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('HTTPS is required to protect WebDAV credentials'),
        ),
      ),
    );

    // 当 enabled = false 时，应当允许用户暂存设置而不被阻止
    await service.saveSettings(
      enabled: false,
      provider: 'custom',
      url: 'http://insecure.server.local/dav/',
      username: 'user',
      syncOnLaunch: false,
      syncOnChange: false,
      syncOnCellular: false,
      syncNotesOnlyOnCellular: false,
    );
    expect(service.enabled, false);
    expect(service.url, 'http://insecure.server.local/dav/');
  });

  test(
    'WebDAVSyncService should enforce HTTPS strictly on testConnection',
    () async {
      final service = WebDAVSyncService();

      // The testConnection method catches exceptions and returns false.
      // Instead of throwsA, we should test the boolean result.
      final result = await service.testConnection(
        'http://insecure.server.local/dav/',
        'user',
        'pass',
      );
      expect(result, isFalse);
    },
  );

  test('buildBasicAuthHeader correctly encodes credentials', () {
    final header = WebDAVSyncService.buildBasicAuthHeader('user', 'pass');
    expect(header, 'Basic dXNlcjpwYXNz');
  });

  test(
    'WebDAV media parser should extract existing remote files and sizes',
    () {
      const xml = '''
<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/thoughtecho/media/images/</d:href>
    <d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop></d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/thoughtecho/media/images/1700000000000_%E5%9B%BE.png</d:href>
    <d:propstat><d:prop><d:getcontentlength>12345</d:getcontentlength></d:prop></d:propstat>
  </d:response>
  <d:response>
    <d:href>https://example.com/dav/thoughtecho/media/videos/movie.mp4</d:href>
    <d:propstat><d:prop><d:getcontentlength>99</d:getcontentlength></d:prop></d:propstat>
  </d:response>
</d:multistatus>
''';

      final files = WebDAVSyncService.extractRemoteMediaFilesForTesting(xml);

      expect(files, {
        'images/1700000000000_图.png': 12345,
        'videos/movie.mp4': 99,
      });
    },
  );

  test(
      'WebDAV media parser should tolerate whitespace in getcontentlength and trim etags',
      () {
    const xml = '''
<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/thoughtecho/media/images/photo.jpg</d:href>
    <d:propstat>
      <d:prop>
        <d:getcontentlength>
          45678
        </d:getcontentlength>
        <d:getetag>  "etag-with-spaces"  </d:getetag>
      </d:prop>
    </d:propstat>
  </d:response>
</d:multistatus>
''';

    final files = WebDAVSyncService.extractRemoteMediaFilesForTesting(xml);
    expect(files, {'images/photo.jpg': 45678});

    final etags = WebDAVSyncService.extractRemoteMediaEtagsForTesting(xml);
    expect(etags, {'images/photo.jpg': '"etag-with-spaces"'});
  });

  test('WebDAV media parser should reject traversal paths', () {
    const xml = '''
<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/thoughtecho/media/images/../../thoughtecho_sync.zip</d:href>
    <d:propstat><d:prop><d:getcontentlength>123</d:getcontentlength></d:prop></d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/thoughtecho/media/audios/valid.mp3</d:href>
    <d:propstat><d:prop><d:getcontentlength>456</d:getcontentlength></d:prop></d:propstat>
  </d:response>
</d:multistatus>
''';

    final files = WebDAVSyncService.extractRemoteMediaFilesForTesting(xml);

    expect(files, {'audios/valid.mp3': 456});
  });

  test(
    'mediaRelativePathFromHref should normalize paths and block path traversal',
    () {
      expect(
        WebDAVSyncService.mediaRelativePathFromHrefForTesting(
          '/dav/thoughtecho/media/images/photo.png',
        ),
        'images/photo.png',
      );
      expect(
        WebDAVSyncService.mediaRelativePathFromHrefForTesting(
          '/dav/thoughtecho/media/images/./photo.png',
        ),
        'images/photo.png',
      );
      expect(
        WebDAVSyncService.mediaRelativePathFromHrefForTesting(
          '/dav/thoughtecho/media/images/sub/../photo.png',
        ),
        'images/photo.png',
      );
      expect(
        WebDAVSyncService.mediaRelativePathFromHrefForTesting(
          '/dav/thoughtecho/media/images/../videos/photo.png',
        ),
        isNull,
      );
      expect(
        WebDAVSyncService.mediaRelativePathFromHrefForTesting(
          '/dav/thoughtecho/media/images/../../etc/passwd',
        ),
        isNull,
      );
      expect(
        WebDAVSyncService.mediaRelativePathFromHrefForTesting(
          '/dav/thoughtecho/media/images/photo.png\x00.zip',
        ),
        isNull,
      );
      expect(
        WebDAVSyncService.mediaRelativePathFromHrefForTesting(
          '/dav/thoughtecho/media/images/..\\..\\secret.txt',
        ),
        isNull,
      );
      expect(
        WebDAVSyncService.mediaRelativePathFromHrefForTesting(
          '/dav/thoughtecho/media/images/',
        ),
        isNull,
      );
      expect(
        WebDAVSyncService.mediaRelativePathFromHrefForTesting(
          '/dav/thoughtecho/media/images/photo.png?token=secret#section',
        ),
        'images/photo.png',
      );
      expect(
        WebDAVSyncService.mediaRelativePathFromHrefForTesting(
          'https://example.com/dav/thoughtecho/media/images/photo.png?token=secret#section',
        ),
        'images/photo.png',
      );
      expect(
        WebDAVSyncService.mediaRelativePathFromHrefForTesting(
          '/dav/thoughtecho/media/images/%252e%252e/secret.txt',
        ),
        isNull,
      );
      expect(
        WebDAVSyncService.mediaRelativePathFromHrefForTesting(
          '/dav/thoughtecho/media/images/%252fetc/passwd',
        ),
        isNull,
      );
      expect(
        WebDAVSyncService.mediaRelativePathFromHrefForTesting(
          '/dav/thoughtecho/media/images/%255csecret.txt',
        ),
        isNull,
      );
      // 双重编码的无害字符按单次解码还原，与 _encodeMediaPath 往返一致
      //（本地 images/%41.png 上传为 images/%2541.png，解回仍是 %41.png）。
      expect(
        WebDAVSyncService.mediaRelativePathFromHrefForTesting(
          '/dav/thoughtecho/media/images/%2541.png',
        ),
        'images/%41.png',
      );
    },
  );

  test('encodeMediaPath should encode special characters in path segments', () {
    expect(
      WebDAVSyncService.encodeMediaPathForTesting('images/my photo #1?.jpg'),
      'images/my%20photo%20%231%3F.jpg',
    );
    expect(
      WebDAVSyncService.encodeMediaPathForTesting('audios/voice memo (1).mp3'),
      'audios/voice%20memo%20(1).mp3',
    );
  });

  test('WebDAV media upload decision should skip files already on remote', () {
    final remoteMediaFiles = {
      'images/existing.png': 1024,
      'videos/no_size.mp4': null,
    };

    expect(
      WebDAVSyncService.shouldUploadMediaFileForTesting(
        'images/existing.png',
        1024,
        remoteMediaFiles,
      ),
      isFalse,
    );
    // 远端存在但没报出大小时无从比较，必须按「可能不一致」重传，
    // 否则服务端不返回 getcontentlength 的场景下媒体文件会永远漏同步。
    expect(
      WebDAVSyncService.shouldUploadMediaFileForTesting(
        'videos/no_size.mp4',
        2048,
        remoteMediaFiles,
      ),
      isTrue,
    );
    expect(
      WebDAVSyncService.shouldUploadMediaFileForTesting(
        'images/existing.png',
        512,
        remoteMediaFiles,
      ),
      isTrue,
    );
    expect(
      WebDAVSyncService.shouldUploadMediaFileForTesting(
        'audios/new.mp3',
        256,
        remoteMediaFiles,
      ),
      isTrue,
    );
  });

  test('WebDAV media folder helper should only classify synced folders', () {
    expect(
      WebDAVSyncService.mediaFolderFromRelativePathForTesting(
        'images/photo.png',
      ),
      'images',
    );
    expect(
      WebDAVSyncService.mediaFolderFromRelativePathForTesting(
        'videos/movie.mp4',
      ),
      'videos',
    );
    expect(
      WebDAVSyncService.mediaFolderFromRelativePathForTesting('html/card.html'),
      isNull,
    );
  });

  test('WebDAV sync file PROPFIND should ignore directory listings', () {
    const xml = '''
<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/thoughtecho/</d:href>
    <d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop></d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/thoughtecho/media/</d:href>
    <d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop></d:propstat>
  </d:response>
</d:multistatus>
''';

    expect(
      WebDAVSyncService.isTargetSyncFilePropfindResponseForTesting(
        xml,
        'https://example.com/dav/thoughtecho/thoughtecho_sync.zip',
      ),
      isFalse,
    );
  });

  test('WebDAV sync file PROPFIND should accept the target zip file', () {
    const xml = '''
<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/thoughtecho/thoughtecho_sync.zip</d:href>
    <d:propstat>
      <d:prop>
        <d:getetag>"abc"</d:getetag>
        <d:getcontentlength>321</d:getcontentlength>
      </d:prop>
    </d:propstat>
  </d:response>
</d:multistatus>
''';

    expect(
      WebDAVSyncService.isTargetSyncFilePropfindResponseForTesting(
        xml,
        'https://example.com/dav/thoughtecho/thoughtecho_sync.zip',
      ),
      isTrue,
    );
  });

  test('WebDAV sync file PROPFIND should ignore target 404 responses', () {
    const xml = '''
<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/thoughtecho/thoughtecho_sync.zip</d:href>
    <d:propstat>
      <d:prop/>
      <d:status>HTTP/1.1 404 Not Found</d:status>
    </d:propstat>
  </d:response>
</d:multistatus>
''';

    expect(
      WebDAVSyncService.isTargetSyncFilePropfindResponseForTesting(
        xml,
        'https://example.com/dav/thoughtecho/thoughtecho_sync.zip',
      ),
      isFalse,
    );
  });

  group('WebDAV listing validation', () {
    const target = '/dav/thoughtecho/thoughtecho_sync.zip';
    const media = '/dav/thoughtecho/media/images/photo.png';
    const validResponse = '<response><href>$target</href></response>'
        '<response><href>$media</href></response>';
    final invalidListings = <String, String>{
      'unclosed response tags after valid entries':
          '<multistatus>$validResponse${'<response>' * 2000}</multistatus>',
      'mismatched closing tags':
          '<multistatus>$validResponse<response></prop></multistatus>',
      'truncated property': '<multistatus>$validResponse<response><getetag>',
      'more than 8 MiB of response text':
          '<multistatus>$validResponse<!--${'x' * (8 * 1024 * 1024)}--></multistatus>',
      'more than 8 MiB of UTF-8 bytes':
          '<multistatus>$validResponse<!--${'图' * (3 * 1024 * 1024)}--></multistatus>',
      'more than 100000 elements':
          '<multistatus>$validResponse${'<prop/>' * 100000}</multistatus>',
      'more than 64 nested elements':
          '<multistatus>$validResponse${'<prop>' * 64}${'</prop>' * 64}</multistatus>',
      'a document type declaration':
          '<!DOCTYPE multistatus [<!ENTITY example "value">]>'
              '<multistatus>$validResponse</multistatus>',
    };

    for (final entry in invalidListings.entries) {
      test('rejects ${entry.key} without returning partial entries', () {
        expect(
          () =>
              WebDAVSyncService.extractRemoteMediaFilesForTesting(entry.value),
          throwsFormatException,
        );
        expect(
          () => WebDAVSyncService.isTargetSyncFilePropfindResponseForTesting(
            entry.value,
            'https://example.com$target',
          ),
          throwsFormatException,
        );
      });
    }

    for (final prefix in ['', 'd:', 'custom:']) {
      test('reads XML text and properties with prefix "$prefix"', () {
        final xml = '''
<${prefix}multistatus xmlns="DAV:" xmlns:d="DAV:" xmlns:custom="DAV:">
  <${prefix}response>
    <${prefix}href>/dav/thoughtecho/media/images/a&amp;b.png</${prefix}href>
    <${prefix}propstat><${prefix}prop>
      <${prefix}getcontentlength>42</${prefix}getcontentlength>
      <${prefix}getetag><![CDATA[ "media-etag" ]]></${prefix}getetag>
    </${prefix}prop></${prefix}propstat>
  </${prefix}response>
  <${prefix}response>
    <${prefix}href>$target</${prefix}href>
    <${prefix}status>HTTP/1.1 200 OK</${prefix}status>
  </${prefix}response>
</${prefix}multistatus>
''';
        expect(WebDAVSyncService.extractRemoteMediaFilesForTesting(xml), {
          'images/a&b.png': 42,
        });
        expect(WebDAVSyncService.extractRemoteMediaEtagsForTesting(xml), {
          'images/a&b.png': '"media-etag"',
        });
        expect(
          WebDAVSyncService.isTargetSyncFilePropfindResponseForTesting(
            xml,
            'https://example.com$target',
          ),
          isTrue,
        );
      });
    }
  });

  group('prependConflictPrefixToDelta', () {
    test('prepends conflict prefix to List-style Delta JSON', () {
      const delta = '[{"insert":"Hello\\n"}]';
      final result = WebDAVSyncService.prependConflictPrefixToDelta(delta);
      expect(result, '[{"insert":"[冲突备份] "},{"insert":"Hello\\n"}]');
    });

    test('prepends conflict prefix to Map-style Delta JSON with ops', () {
      const delta = '{"ops":[{"insert":"World\\n"}]}';
      final result = WebDAVSyncService.prependConflictPrefixToDelta(delta);
      expect(result, '{"ops":[{"insert":"[冲突备份] "},{"insert":"World\\n"}]}');
    });

    test('returns original string for null or empty input', () {
      expect(WebDAVSyncService.prependConflictPrefixToDelta(null), null);
      expect(WebDAVSyncService.prependConflictPrefixToDelta(''), '');
      expect(WebDAVSyncService.prependConflictPrefixToDelta('   '), '   ');
    });

    test('handles invalid JSON gracefully and logs error without crashing', () {
      final logService = _RecordingLogService();
      AppLogger.serviceForTesting = logService;
      try {
        const invalidJson = 'invalid json {';
        final result = WebDAVSyncService.prependConflictPrefixToDelta(
          invalidJson,
        );
        expect(result, invalidJson);

        final errorLogs = logService.records
            .where((r) => r.level == UnifiedLogLevel.error)
            .toList();
        expect(errorLogs, isNotEmpty);
        expect(errorLogs.first.message, contains('冲突笔记 Delta 内容加前缀失败'));
        expect(errorLogs.first.error, 'FormatException');
        expect(errorLogs.first.stackTrace, isNotNull);
      } finally {
        AppLogger.initialize();
      }
    });

    test('handles unsupported JSON structure gracefully and logs warning', () {
      final logService = _RecordingLogService();
      AppLogger.serviceForTesting = logService;
      try {
        const invalidStructure = '{"ops":"not-a-list"}';
        final result = WebDAVSyncService.prependConflictPrefixToDelta(
          invalidStructure,
        );
        expect(result, invalidStructure);

        const numberJson = '42';
        final numResult = WebDAVSyncService.prependConflictPrefixToDelta(
          numberJson,
        );
        expect(numResult, numberJson);

        final warningLogs = logService.records
            .where((r) => r.level == UnifiedLogLevel.warning)
            .toList();
        expect(warningLogs, hasLength(2));
        expect(warningLogs.first.message, contains('冲突笔记 Delta 结构不支持加前缀'));
      } finally {
        AppLogger.initialize();
      }
    });
  });

  group('Remote metadata extraction with getlastmodified', () {
    test(
        'parseRemoteHttpDateForTesting parses RFC 1123, RFC 850, asctime, and ISO-8601 in UTC',
        () {
      final rfc1123 = WebDAVSyncService.parseRemoteHttpDateForTesting(
        'Wed, 21 Oct 2015 07:28:00 GMT',
      );
      expect(rfc1123, DateTime.utc(2015, 10, 21, 7, 28, 0));
      expect(rfc1123?.isUtc, isTrue);

      final rfc850 = WebDAVSyncService.parseRemoteHttpDateForTesting(
        'Wednesday, 21-Oct-15 07:28:00 GMT',
      );
      expect(
        rfc850,
        HttpDate.parse('Wednesday, 21-Oct-15 07:28:00 GMT').toUtc(),
      );
      expect(rfc850?.isUtc, isTrue);

      final asctime = WebDAVSyncService.parseRemoteHttpDateForTesting(
        'Wed Oct 21 07:28:00 2015',
      );
      expect(asctime, DateTime.utc(2015, 10, 21, 7, 28, 0));
      expect(asctime?.isUtc, isTrue);

      final isoOffset = WebDAVSyncService.parseRemoteHttpDateForTesting(
        '2026-03-15T18:20:30+08:00',
      );
      expect(isoOffset, DateTime.utc(2026, 3, 15, 10, 20, 30));
      expect(isoOffset?.isUtc, isTrue);

      expect(WebDAVSyncService.parseRemoteHttpDateForTesting(null), isNull);
      expect(WebDAVSyncService.parseRemoteHttpDateForTesting('   '), isNull);
      expect(
        WebDAVSyncService.parseRemoteHttpDateForTesting('not-a-valid-date'),
        isNull,
      );
    });

    test(
        'extractRemoteMediaDetailsForTesting extracts length, etag, and lastModified',
        () {
      const xml = '''
<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/thoughtecho/media/images/rfc1123.png</d:href>
    <d:propstat>
      <d:prop>
        <d:getcontentlength>1024</d:getcontentlength>
        <d:getetag>"abc123"</d:getetag>
        <d:getlastmodified>Wed, 21 Oct 2015 07:28:00 GMT</d:getlastmodified>
      </d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/thoughtecho/media/videos/iso.mp4</d:href>
    <d:propstat>
      <d:prop><d:getlastmodified/></d:prop>
      <d:status>HTTP/1.1 404 Not Found</d:status>
    </d:propstat>
    <d:propstat>
      <d:prop>
        <d:getcontentlength>2048</d:getcontentlength>
        <d:getetag>W/"weak-v1"</d:getetag>
        <d:getlastmodified>2026-04-01T14:00:00+02:00</d:getlastmodified>
      </d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/dav/thoughtecho/media/audios/bad_date.mp3</d:href>
    <d:propstat>
      <d:prop>
        <d:getcontentlength>512</d:getcontentlength>
        <d:getlastmodified>invalid-timestamp</d:getlastmodified>
      </d:prop>
    </d:propstat>
  </d:response>
</d:multistatus>
''';

      final details = WebDAVSyncService.extractRemoteMediaDetailsForTesting(
        xml,
      );
      expect(
        details.keys,
        containsAll([
          'images/rfc1123.png',
          'videos/iso.mp4',
          'audios/bad_date.mp3',
        ]),
      );

      expect(details['images/rfc1123.png']!.length, 1024);
      expect(details['images/rfc1123.png']!.etag, '"abc123"');
      expect(
        details['images/rfc1123.png']!.lastModified,
        DateTime.utc(2015, 10, 21, 7, 28, 0),
      );

      expect(details['videos/iso.mp4']!.length, 2048);
      expect(details['videos/iso.mp4']!.etag, 'W/"weak-v1"');
      expect(
        details['videos/iso.mp4']!.lastModified,
        DateTime.utc(2026, 4, 1, 12, 0, 0),
      );

      expect(details['audios/bad_date.mp3']!.length, 512);
      expect(details['audios/bad_date.mp3']!.lastModified, isNull);
    });
  });

  group('Three-tier media upload decision', () {
    late Directory tempDir;
    late MediaFingerprintCache cache;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('webdav_three_tier_test');
      cache = MediaFingerprintCache(directory: tempDir);
      await cache.load();
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    Future<File> writeMediaFile(
      String relPath,
      String content, {
      DateTime? modified,
    }) async {
      final file = File(p.join(tempDir.path, 'media', relPath));
      await file.parent.create(recursive: true);
      await file.writeAsString(content, flush: true);
      if (modified != null) {
        await file.setLastModified(modified.toUtc());
      }
      return file;
    }

    test(
      'L1: missing remote, null length, or size mismatch uploads with 0 hashes',
      () async {
        final file = await writeMediaFile('images/l1.png', 'hello-world');
        final size = await file.length();

        expect(
          await WebDAVSyncService.shouldUploadMediaFileWithCacheForTesting(
            stdPath: 'images/l1.png',
            localFile: file,
            localSize: size,
            remoteMediaDetails: const {},
            fingerprintCache: cache,
          ),
          isTrue,
        );
        expect(
          await WebDAVSyncService.shouldUploadMediaFileWithCacheForTesting(
            stdPath: 'images/l1.png',
            localFile: file,
            localSize: size,
            remoteMediaDetails: const {
              'images/l1.png': RemoteMediaFileInfo(length: null),
            },
            fingerprintCache: cache,
          ),
          isTrue,
        );
        expect(
          await WebDAVSyncService.shouldUploadMediaFileWithCacheForTesting(
            stdPath: 'images/l1.png',
            localFile: file,
            localSize: size,
            remoteMediaDetails: {
              'images/l1.png': RemoteMediaFileInfo(length: size + 1),
            },
            fingerprintCache: cache,
          ),
          isTrue,
        );
        expect(cache.hashComputeCount, 0);
      },
    );

    test(
        'L2: empty cache enters L3 to build baseline, then matching stat skips with 0 hashes',
        () async {
      final remoteTime = DateTime.utc(2026, 5, 1, 12, 0, 0);
      final file = await writeMediaFile(
        'images/l2.png',
        'same-content',
        modified: remoteTime.add(const Duration(seconds: 2)),
      );
      final size = await file.length();

      // First encounter without cache must not silently skip at L2 without a baseline:
      // if remote carries a different SHA-256 ETag within the +2s skew window, it uploads.
      final diffRemoteSha = 'f' * 64;
      expect(
        await WebDAVSyncService.shouldUploadMediaFileWithCacheForTesting(
          stdPath: 'images/l2.png',
          localFile: file,
          localSize: size,
          remoteMediaDetails: {
            'images/l2.png': RemoteMediaFileInfo(
              length: size,
              etag: '"$diffRemoteSha"',
              lastModified: remoteTime,
            ),
          },
          fingerprintCache: cache,
        ),
        isTrue,
      );
      expect(cache.hashComputeCount, 1);

      // Simulate completed sync establishing the baseline
      await cache.markSynced(
        'images/l2.png',
        file,
        remoteEtag: '"opaque-l2-v1"',
        knownSize: size,
        knownLastModified: remoteTime.add(const Duration(seconds: 2)),
      );
      final hashesAfterBaseline = cache.hashComputeCount;

      // Subsequent run with synced baseline + mtime within +2s skips at L2 with 0 new hashes
      final shouldUpload =
          await WebDAVSyncService.shouldUploadMediaFileWithCacheForTesting(
        stdPath: 'images/l2.png',
        localFile: file,
        localSize: size,
        remoteMediaDetails: {
          'images/l2.png': RemoteMediaFileInfo(
            length: size,
            lastModified: remoteTime,
          ),
        },
        fingerprintCache: cache,
      );

      expect(shouldUpload, isFalse);
      expect(cache.hashComputeCount, hashesAfterBaseline);
    });

    test(
        'L2: does not blindly skip when cached stat differs or pending hash change exists',
        () async {
      final t1 = DateTime.utc(2026, 5, 1, 12, 0, 0);
      final t2 = DateTime.utc(2026, 5, 1, 12, 0, 1);
      final remoteTime = DateTime.utc(2026, 5, 1, 12, 0, 5);
      final file = await writeMediaFile(
        'images/in_place.png',
        'content-aaaa',
        modified: t1,
      );
      final size = await file.length();
      await cache.markSynced(
        'images/in_place.png',
        file,
        remoteEtag: '"opaque-1"',
        knownSize: size,
        knownLastModified: t1,
      );

      // Same-size in-place edit whose mtime is still older than remoteTime + 2s
      await writeMediaFile('images/in_place.png', 'content-bbbb', modified: t2);

      final shouldUploadAfterStatChange =
          await WebDAVSyncService.shouldUploadMediaFileWithCacheForTesting(
        stdPath: 'images/in_place.png',
        localFile: file,
        localSize: size,
        remoteMediaDetails: {
          'images/in_place.png': RemoteMediaFileInfo(
            length: size,
            lastModified: remoteTime,
          ),
        },
        fingerprintCache: cache,
      );
      expect(shouldUploadAfterStatChange, isTrue);
      expect(cache.hashComputeCount, 2);

      // Even if cached stat now matches t2, pending syncedSha256 != sha256 still prevents L2 skip
      final shouldUploadPendingChange =
          await WebDAVSyncService.shouldUploadMediaFileWithCacheForTesting(
        stdPath: 'images/in_place.png',
        localFile: file,
        localSize: size,
        remoteMediaDetails: {
          'images/in_place.png': RemoteMediaFileInfo(
            length: size,
            lastModified: remoteTime,
          ),
        },
        fingerprintCache: cache,
      );
      expect(shouldUploadPendingChange, isTrue);
      expect(cache.hashComputeCount, 2);
    });

    test(
      'L3: SHA-256 ETag detects same-size difference and hits cache on repeat',
      () async {
        final contentA = 'alpha-12345';
        final contentB = 'bravo-12345';
        expect(contentA.length, contentB.length);

        final shaA = crypto.sha256.convert(utf8.encode(contentA)).toString();
        final shaB = crypto.sha256.convert(utf8.encode(contentB)).toString();
        final t1 = DateTime.utc(2026, 5, 2, 8, 0, 0);
        final file = await writeMediaFile(
          'images/sha_etag.png',
          contentA,
          modified: t1,
        );
        final size = await file.length();

        // Match -> skip, computes SHA-256 once
        expect(
          await WebDAVSyncService.shouldUploadMediaFileWithCacheForTesting(
            stdPath: 'images/sha_etag.png',
            localFile: file,
            localSize: size,
            remoteMediaDetails: {
              'images/sha_etag.png': RemoteMediaFileInfo(
                length: size,
                etag: '"${shaA.toUpperCase()}"',
              ),
            },
            fingerprintCache: cache,
          ),
          isFalse,
        );
        expect(cache.sha256ComputeCount, 1);
        expect(cache.md5ComputeCount, 0);

        // Repeat -> cache hit, 0 new hashes
        expect(
          await WebDAVSyncService.shouldUploadMediaFileWithCacheForTesting(
            stdPath: 'images/sha_etag.png',
            localFile: file,
            localSize: size,
            remoteMediaDetails: {
              'images/sha_etag.png': RemoteMediaFileInfo(
                length: size,
                etag: '"$shaA"',
              ),
            },
            fingerprintCache: cache,
          ),
          isFalse,
        );
        expect(cache.hashComputeCount, 1);

        // Different remote SHA-256 with same size -> upload
        expect(
          await WebDAVSyncService.shouldUploadMediaFileWithCacheForTesting(
            stdPath: 'images/sha_etag.png',
            localFile: file,
            localSize: size,
            remoteMediaDetails: {
              'images/sha_etag.png': RemoteMediaFileInfo(
                length: size,
                etag: '"$shaB"',
              ),
            },
            fingerprintCache: cache,
          ),
          isTrue,
        );
        expect(cache.hashComputeCount, 1);
      },
    );

    test(
      'L3: MD5 ETag computes lazy MD5 and detects same-size difference',
      () async {
        final contentA = 'md5-alpha-01';
        final contentB = 'md5-bravo-02';
        expect(contentA.length, contentB.length);

        final md5A = crypto.md5.convert(utf8.encode(contentA)).toString();
        final md5B = crypto.md5.convert(utf8.encode(contentB)).toString();
        final file = await writeMediaFile('images/md5_etag.png', contentA);
        final size = await file.length();

        expect(
          await WebDAVSyncService.shouldUploadMediaFileWithCacheForTesting(
            stdPath: 'images/md5_etag.png',
            localFile: file,
            localSize: size,
            remoteMediaDetails: {
              'images/md5_etag.png': RemoteMediaFileInfo(
                length: size,
                etag: '"${md5A.toUpperCase()}"',
              ),
            },
            fingerprintCache: cache,
          ),
          isFalse,
        );
        expect(cache.sha256ComputeCount, 1);
        expect(cache.md5ComputeCount, 1);

        // Cache hit with MD5 ETag
        expect(
          await WebDAVSyncService.shouldUploadMediaFileWithCacheForTesting(
            stdPath: 'images/md5_etag.png',
            localFile: file,
            localSize: size,
            remoteMediaDetails: {
              'images/md5_etag.png': RemoteMediaFileInfo(
                length: size,
                etag: '"$md5A"',
              ),
            },
            fingerprintCache: cache,
          ),
          isFalse,
        );
        expect(cache.hashComputeCount, 2);

        // Different MD5 ETag -> upload
        expect(
          await WebDAVSyncService.shouldUploadMediaFileWithCacheForTesting(
            stdPath: 'images/md5_etag.png',
            localFile: file,
            localSize: size,
            remoteMediaDetails: {
              'images/md5_etag.png': RemoteMediaFileInfo(
                length: size,
                etag: '"$md5B"',
              ),
            },
            fingerprintCache: cache,
          ),
          isTrue,
        );
      },
    );

    test(
      'L3: opaque strong ETag requires recorded ETag and unchanged SHA-256',
      () async {
        final t1 = DateTime.utc(2026, 5, 3, 10, 0, 0);
        final file = await writeMediaFile(
          'images/opaque.png',
          'opaque-payload-1',
          modified: t1,
        );
        final size = await file.length();

        // Unsynced opaque ETag -> upload
        expect(
          await WebDAVSyncService.shouldUploadMediaFileWithCacheForTesting(
            stdPath: 'images/opaque.png',
            localFile: file,
            localSize: size,
            remoteMediaDetails: {
              'images/opaque.png': RemoteMediaFileInfo(
                length: size,
                etag: '"inode-100"',
              ),
            },
            fingerprintCache: cache,
          ),
          isTrue,
        );

        await cache.markSynced(
          'images/opaque.png',
          file,
          remoteEtag: '"inode-100"',
          knownSize: size,
          knownLastModified: t1,
        );
        final countAfterSync = cache.hashComputeCount;

        // Same opaque ETag and unchanged local file -> skip via cache hit
        expect(
          await WebDAVSyncService.shouldUploadMediaFileWithCacheForTesting(
            stdPath: 'images/opaque.png',
            localFile: file,
            localSize: size,
            remoteMediaDetails: {
              'images/opaque.png': RemoteMediaFileInfo(
                length: size,
                etag: '"inode-100"',
              ),
            },
            fingerprintCache: cache,
          ),
          isFalse,
        );
        expect(cache.hashComputeCount, countAfterSync);

        // Remote opaque ETag changed -> upload
        expect(
          await WebDAVSyncService.shouldUploadMediaFileWithCacheForTesting(
            stdPath: 'images/opaque.png',
            localFile: file,
            localSize: size,
            remoteMediaDetails: {
              'images/opaque.png': RemoteMediaFileInfo(
                length: size,
                etag: '"inode-200"',
              ),
            },
            fingerprintCache: cache,
          ),
          isTrue,
        );

        // Local same-size overwrite -> upload even if remote ETag stayed "inode-100"
        await writeMediaFile(
          'images/opaque.png',
          'opaque-payload-2',
          modified: t1.add(const Duration(seconds: 5)),
        );
        expect(
          await WebDAVSyncService.shouldUploadMediaFileWithCacheForTesting(
            stdPath: 'images/opaque.png',
            localFile: file,
            localSize: size,
            remoteMediaDetails: {
              'images/opaque.png': RemoteMediaFileInfo(
                length: size,
                etag: '"inode-100"',
              ),
            },
            fingerprintCache: cache,
          ),
          isTrue,
        );
      },
    );

    test(
        'L3 safe degradation: weak or missing ETag records baseline and detects same-size local edits',
        () async {
      final t1 = DateTime.utc(2026, 5, 4, 9, 0, 0);
      final file = await writeMediaFile(
        'images/weak_or_none.png',
        'weak-payload-111',
        modified: t1,
      );
      final size = await file.length();

      // Even if a weak ETag contains 32-hex chars, it must degrade safely rather than act as MD5
      final fakeWeakHex =
          'W/"${crypto.md5.convert(utf8.encode('other-content-xx'))}"';

      // First run on size/weak-only server: records baseline and skips
      expect(
        await WebDAVSyncService.shouldUploadMediaFileWithCacheForTesting(
          stdPath: 'images/weak_or_none.png',
          localFile: file,
          localSize: size,
          remoteMediaDetails: {
            'images/weak_or_none.png': RemoteMediaFileInfo(
              length: size,
              etag: fakeWeakHex,
            ),
          },
          fingerprintCache: cache,
        ),
        isFalse,
      );
      expect(cache.hashComputeCount, 1);
      expect(cache.peek('images/weak_or_none.png')?.syncedSha256, isNotNull);

      // Second run unmodified: cache hit
      expect(
        await WebDAVSyncService.shouldUploadMediaFileWithCacheForTesting(
          stdPath: 'images/weak_or_none.png',
          localFile: file,
          localSize: size,
          remoteMediaDetails: {
            'images/weak_or_none.png': RemoteMediaFileInfo(
              length: size,
              etag: null,
            ),
          },
          fingerprintCache: cache,
        ),
        isFalse,
      );
      expect(cache.hashComputeCount, 1);

      // Same-size in-place edit: recomputes and detects syncedSha256 mismatch
      await writeMediaFile(
        'images/weak_or_none.png',
        'weak-payload-222',
        modified: t1.add(const Duration(seconds: 10)),
      );
      expect(
        await WebDAVSyncService.shouldUploadMediaFileWithCacheForTesting(
          stdPath: 'images/weak_or_none.png',
          localFile: file,
          localSize: size,
          remoteMediaDetails: {
            'images/weak_or_none.png': RemoteMediaFileInfo(
              length: size,
              etag: null,
            ),
          },
          fingerprintCache: cache,
        ),
        isTrue,
      );
      expect(cache.hashComputeCount, 2);
    });

    test(
        'L3 safe degradation: first encounter with weak/no ETag and newer local mtime uploads',
        () async {
      final remoteTime = DateTime.utc(2026, 5, 4, 9, 0, 0);
      final file = await writeMediaFile(
        'images/newer_local.png',
        'newer-local-payload',
        modified: remoteTime.add(const Duration(seconds: 10)),
      );
      final size = await file.length();

      expect(
        await WebDAVSyncService.shouldUploadMediaFileWithCacheForTesting(
          stdPath: 'images/newer_local.png',
          localFile: file,
          localSize: size,
          remoteMediaDetails: {
            'images/newer_local.png': RemoteMediaFileInfo(
              length: size,
              etag: 'W/"weak-etag"',
              lastModified: remoteTime,
            ),
          },
          fingerprintCache: cache,
        ),
        isTrue,
      );
    });

    test(
        'L3: opaque 32-hex and 64-hex ETags converge via syncedRemoteEtag without re-uploading unchanged files',
        () async {
      final t1 = DateTime.utc(2026, 5, 5, 10, 0, 0);
      final file = await writeMediaFile(
        'images/opaque_hex.png',
        'opaque-hex-payload-v1',
        modified: t1,
      );
      final size = await file.length();
      const opaqueHex32 = '"0123456789abcdef0123456789abcdef"';
      const opaqueHex64 =
          '"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"';

      for (final opaqueEtag in const [opaqueHex32, opaqueHex64]) {
        final scopedDir = await Directory.systemTemp.createTemp(
          'webdav_opaque_hex_',
        );
        try {
          final scopedCache = MediaFingerprintCache(directory: scopedDir);
          await scopedCache.load();

          // First encounter with opaque hex ETag != file digest -> upload once
          expect(
            await WebDAVSyncService.shouldUploadMediaFileWithCacheForTesting(
              stdPath: 'images/opaque_hex.png',
              localFile: file,
              localSize: size,
              remoteMediaDetails: {
                'images/opaque_hex.png': RemoteMediaFileInfo(
                  length: size,
                  etag: opaqueEtag,
                ),
              },
              fingerprintCache: scopedCache,
            ),
            isTrue,
          );

          await scopedCache.markSynced(
            'images/opaque_hex.png',
            file,
            remoteEtag: opaqueEtag,
            knownSize: size,
            knownLastModified: t1,
          );
          final hashesAfterSync = scopedCache.hashComputeCount;

          // Subsequent run with same opaque hex ETag -> must skip with 0 new hashes
          expect(
            await WebDAVSyncService.shouldUploadMediaFileWithCacheForTesting(
              stdPath: 'images/opaque_hex.png',
              localFile: file,
              localSize: size,
              remoteMediaDetails: {
                'images/opaque_hex.png': RemoteMediaFileInfo(
                  length: size,
                  etag: opaqueEtag,
                ),
              },
              fingerprintCache: scopedCache,
            ),
            isFalse,
          );
          expect(scopedCache.hashComputeCount, hashesAfterSync);

          // Same-size local edit -> must upload even though ETag stayed the same
          await writeMediaFile(
            'images/opaque_hex.png',
            'opaque-hex-payload-v2',
            modified: t1.add(const Duration(seconds: 5)),
          );
          expect(
            await WebDAVSyncService.shouldUploadMediaFileWithCacheForTesting(
              stdPath: 'images/opaque_hex.png',
              localFile: file,
              localSize: size,
              remoteMediaDetails: {
                'images/opaque_hex.png': RemoteMediaFileInfo(
                  length: size,
                  etag: opaqueEtag,
                ),
              },
              fingerprintCache: scopedCache,
            ),
            isTrue,
          );
        } finally {
          await writeMediaFile(
            'images/opaque_hex.png',
            'opaque-hex-payload-v1',
            modified: t1,
          );
          await scopedDir.delete(recursive: true);
        }
      }
    });

    test(
        'L3: failed upload followed by mtime-only touch still retries upload on weak-ETag server',
        () async {
      final remoteTime = DateTime.utc(2026, 5, 6, 8, 0, 0);
      final t1 = remoteTime.add(const Duration(seconds: 10));
      final t2 = t1.add(const Duration(seconds: 10));
      final file = await writeMediaFile(
        'images/failed_retry.png',
        'unsynced-local-bytes',
        modified: t1,
      );
      final size = await file.length();

      // Run 1: triggers upload and caches sha256 with syncedSha256 == null
      expect(
        await WebDAVSyncService.shouldUploadMediaFileWithCacheForTesting(
          stdPath: 'images/failed_retry.png',
          localFile: file,
          localSize: size,
          remoteMediaDetails: {
            'images/failed_retry.png': RemoteMediaFileInfo(
              length: size,
              etag: 'W/"weak-1"',
              lastModified: remoteTime,
            ),
          },
          fingerprintCache: cache,
        ),
        isTrue,
      );
      expect(cache.peek('images/failed_retry.png')?.syncedSha256, isNull);

      // Simulate failed PUT followed by touching mtime without changing bytes
      await file.setLastModified(t2);
      expect(
        await WebDAVSyncService.shouldUploadMediaFileWithCacheForTesting(
          stdPath: 'images/failed_retry.png',
          localFile: file,
          localSize: size,
          remoteMediaDetails: {
            'images/failed_retry.png': RemoteMediaFileInfo(
              length: size,
              etag: 'W/"weak-1"',
              lastModified: remoteTime,
            ),
          },
          fingerprintCache: cache,
        ),
        isTrue,
      );
      expect(cache.peek('images/failed_retry.png')?.syncedSha256, isNull);
    });
  });

  group('Hardened _verifyDownloadedFileHash', () {
    late Directory tempDir;
    late File sampleFile;
    late String sampleSha256Hex;
    late String sampleSha256Base64;
    late String sampleMd5Hex;
    late String sampleMd5Base64;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('webdav_verify_hash');
      sampleFile = File(p.join(tempDir.path, 'sample.bin'));
      const content = 'thoughtecho-synthetic-media-payload';
      await sampleFile.writeAsString(content, flush: true);

      final bytes = utf8.encode(content);
      final shaDigest = crypto.sha256.convert(bytes);
      sampleSha256Hex = shaDigest.toString().toLowerCase();
      sampleSha256Base64 = base64Encode(shaDigest.bytes);

      final md5Digest = crypto.md5.convert(bytes);
      sampleMd5Hex = md5Digest.toString().toLowerCase();
      sampleMd5Base64 = base64Encode(md5Digest.bytes);
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'validates x-checksum-sha256 and x-amz-meta-sha256 in hex and Base64',
      () async {
        await WebDAVSyncService.verifyDownloadedFileHashForTesting(
          sampleFile,
          responseHeaders: {
            'X-Checksum-Sha256': ['"sha256=${sampleSha256Hex.toUpperCase()}"'],
          },
        );
        await WebDAVSyncService.verifyDownloadedFileHashForTesting(
          sampleFile,
          responseHeaders: {
            'x-amz-meta-sha256': [sampleSha256Base64],
          },
        );
        await WebDAVSyncService.verifyDownloadedFileHashForTesting(
          sampleFile,
          responseHeaders: {
            'x-checksum-sha256': ['sha256="$sampleSha256Base64"'],
          },
        );
      },
    );

    test(
      'throws on SHA-256 mismatch or malformed SHA-256 checksum header',
      () async {
        await expectLater(
          WebDAVSyncService.verifyDownloadedFileHashForTesting(
            sampleFile,
            responseHeaders: {
              'x-checksum-sha256': ['0' * 64],
            },
          ),
          throwsException,
        );
        await expectLater(
          WebDAVSyncService.verifyDownloadedFileHashForTesting(
            sampleFile,
            responseHeaders: {
              'x-amz-meta-sha256': [base64Encode(List<int>.filled(32, 7))],
            },
          ),
          throwsException,
        );
        await expectLater(
          WebDAVSyncService.verifyDownloadedFileHashForTesting(
            sampleFile,
            responseHeaders: {
              'x-checksum-sha256': ['not-valid-sha256'],
            },
          ),
          throwsFormatException,
        );
        await expectLater(
          WebDAVSyncService.verifyDownloadedFileHashForTesting(
            sampleFile,
            responseHeaders: {
              'x-amz-meta-sha256': [
                base64Encode([1, 2, 3]),
              ],
            },
          ),
          throwsFormatException,
        );
      },
    );

    test(
        'validates content-md5 in 32-hex and 16-byte Base64 and rejects malformed/mismatch',
        () async {
      await WebDAVSyncService.verifyDownloadedFileHashForTesting(
        sampleFile,
        responseHeaders: {
          'Content-MD5': ['"${sampleMd5Hex.toUpperCase()}"'],
        },
      );
      await WebDAVSyncService.verifyDownloadedFileHashForTesting(
        sampleFile,
        responseHeaders: {
          'content-md5': [sampleMd5Base64],
        },
      );

      await expectLater(
        WebDAVSyncService.verifyDownloadedFileHashForTesting(
          sampleFile,
          responseHeaders: {
            'content-md5': ['f' * 32],
          },
        ),
        throwsException,
      );
      await expectLater(
        WebDAVSyncService.verifyDownloadedFileHashForTesting(
          sampleFile,
          responseHeaders: {
            'content-md5': ['invalid-md5-value'],
          },
        ),
        throwsFormatException,
      );
    });

    test(
        'allows valid explicit checksum download even when strong ETag is opaque 32/64-hex, while still enforcing ETag consistency',
        () async {
      const opaque32Hex = '"0123456789abcdef0123456789abcdef"';
      const opaque64Hex =
          '"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"';

      await WebDAVSyncService.verifyDownloadedFileHashForTesting(
        sampleFile,
        remoteEtag: opaque32Hex,
        responseHeaders: {
          'x-checksum-sha256': [sampleSha256Hex],
          'etag': [opaque32Hex],
        },
      );

      await WebDAVSyncService.verifyDownloadedFileHashForTesting(
        sampleFile,
        remoteEtag: opaque64Hex,
        responseHeaders: {
          'content-md5': [sampleMd5Base64],
          'etag': [opaque64Hex],
        },
      );

      // ETag consistency between PROPFIND and GET header must still fail when mismatched
      await expectLater(
        WebDAVSyncService.verifyDownloadedFileHashForTesting(
          sampleFile,
          remoteEtag: opaque32Hex,
          responseHeaders: {
            'x-checksum-sha256': [sampleSha256Hex],
            'etag': ['"fedcba9876543210fedcba9876543210"'],
          },
        ),
        throwsException,
      );
    });

    test(
      'verifies strong 64-hex and 32-hex ETags and throws on mismatch',
      () async {
        await WebDAVSyncService.verifyDownloadedFileHashForTesting(
          sampleFile,
          remoteEtag: '"$sampleSha256Hex"',
          responseHeaders: {
            'x-checksum-sha256': [sampleSha256Hex],
            'etag': ['"${sampleSha256Hex.toUpperCase()}"'],
          },
        );
        await WebDAVSyncService.verifyDownloadedFileHashForTesting(
          sampleFile,
          remoteEtag: '"$sampleMd5Hex"',
        );

        await expectLater(
          WebDAVSyncService.verifyDownloadedFileHashForTesting(
            sampleFile,
            remoteEtag: '"${'a' * 64}"',
          ),
          throwsException,
        );
        await expectLater(
          WebDAVSyncService.verifyDownloadedFileHashForTesting(
            sampleFile,
            responseHeaders: {
              'etag': ['"${'b' * 32}"'],
            },
          ),
          throwsException,
        );
      },
    );

    test(
        'throws when strong header ETag conflicts with strong PROPFIND remoteEtag',
        () async {
      await expectLater(
        WebDAVSyncService.verifyDownloadedFileHashForTesting(
          sampleFile,
          remoteEtag: '"opaque-etag-v1"',
          responseHeaders: {
            'etag': ['"opaque-etag-v2"'],
          },
        ),
        throwsException,
      );
    });

    test(
        'does not treat non-hex 32/64-char strong ETag or weak ETag as crypto hash and logs debug diagnostic',
        () async {
      final logService = _RecordingLogService();
      AppLogger.serviceForTesting = logService;
      try {
        const nonHex32 = '"nonhex-32char-etag-placeholder!!"';
        expect(nonHex32.length, 34); // 32 chars inside quotes
        await WebDAVSyncService.verifyDownloadedFileHashForTesting(
          sampleFile,
          remoteEtag: nonHex32,
          responseHeaders: {
            'etag': [nonHex32],
          },
        );

        final nonHex64 = '"${'z' * 64}"';
        await WebDAVSyncService.verifyDownloadedFileHashForTesting(
          sampleFile,
          remoteEtag: nonHex64,
        );

        // Weak ETag even wrapping 32/64 hex chars must not be treated as crypto hash
        await WebDAVSyncService.verifyDownloadedFileHashForTesting(
          sampleFile,
          remoteEtag: 'W/"${'0' * 32}"',
          responseHeaders: {
            'etag': ['w/"${'1' * 64}"'],
          },
        );

        // Missing headers/ETag
        await WebDAVSyncService.verifyDownloadedFileHashForTesting(sampleFile);

        final debugLogs = logService.records
            .where((r) => r.level == UnifiedLogLevel.debug)
            .toList();
        expect(debugLogs.length, 4);
      } finally {
        AppLogger.initialize();
      }
    });
  });

  group('WebDAV media sync integration with fingerprint cache', () {
    late Directory tempDir;
    late PathProviderPlatform previousPathProvider;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('webdav_cache_int_test');
      previousPathProvider = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _TestPathProvider(tempDir.path);
    });

    tearDown(() async {
      PathProviderPlatform.instance = previousPathProvider;
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
        'syncMediaFiles uploads new file, saves cache, skips on next sync, and re-uploads on same-size edit',
        () async {
      final mediaImage = File(
        p.join(tempDir.path, 'media', 'images', 'note_pic.png'),
      );
      await mediaImage.parent.create(recursive: true);
      const v1 = 'payload-v1-000';
      const v2 = 'payload-v2-999';
      expect(v1.length, v2.length);
      final t1 = DateTime.utc(2026, 6, 1, 10, 0, 0);
      await mediaImage.writeAsString(v1, flush: true);
      await mediaImage.setLastModified(t1);

      var remoteExists = false;
      var remoteEtag = '"opaque-v1"';
      var remoteLastModified = 'Mon, 01 Jun 2026 10:00:00 GMT';
      var remoteLength = v1.length;
      final uploadedPaths = <String>[];

      final dio = Dio();
      dio.httpClientAdapter = _FakeHttpClientAdapter((options) async {
        if (options.method == 'PROPFIND') {
          if (options.path.contains('/images/') && remoteExists) {
            return ResponseBody.fromString('''
<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/thoughtecho/media/images/note_pic.png</d:href>
    <d:propstat>
      <d:prop>
        <d:getcontentlength>$remoteLength</d:getcontentlength>
        <d:getetag>$remoteEtag</d:getetag>
        <d:getlastmodified>$remoteLastModified</d:getlastmodified>
      </d:prop>
    </d:propstat>
  </d:response>
</d:multistatus>
''', 207);
          }
          return ResponseBody.fromString(
            '<?xml version="1.0"?><d:multistatus xmlns:d="DAV:"/>',
            207,
          );
        }
        if (options.method == 'PUT') {
          uploadedPaths.add(options.path);
          remoteExists = true;
          return ResponseBody.fromString(
            '',
            201,
            headers: {
              'etag': [remoteEtag],
            },
          );
        }
        return ResponseBody.fromString('', 404);
      });

      final service = WebDAVSyncService();
      service.setUrlForTesting('https://dav.example.com/dav/');

      // Run 1: uploads new file and persists cache
      expect(await service.syncMediaFilesForTesting(dio), 0);
      expect(uploadedPaths, hasLength(1));

      final cacheFile = File(
        p.join(tempDir.path, MediaFingerprintCache.defaultCacheFileName),
      );
      expect(await cacheFile.exists(), isTrue);
      final cacheAfterRun1 = MediaFingerprintCache(directory: tempDir);
      await cacheAfterRun1.load();
      expect(
        cacheAfterRun1.peek('images/note_pic.png')?.syncedRemoteEtag,
        'opaque-v1',
      );

      // Run 2: skips without uploading
      expect(await service.syncMediaFilesForTesting(dio), 0);
      expect(uploadedPaths, hasLength(1));

      // Run 3: same-size local edit triggers re-upload even when remote ETag stayed opaque-v1
      await mediaImage.writeAsString(v2, flush: true);
      await mediaImage.setLastModified(t1.add(const Duration(seconds: 10)));

      expect(await service.syncMediaFilesForTesting(dio), 0);
      expect(uploadedPaths, hasLength(2));

      final cacheAfterRun3 = MediaFingerprintCache(directory: tempDir);
      await cacheAfterRun3.load();
      expect(
        cacheAfterRun3.peek('images/note_pic.png')?.syncedRemoteEtag,
        'opaque-v1',
      );
    });

    test(
        'download preserves existing target file and cleans .tmp when hash verification fails',
        () async {
      final targetFile = File(
        p.join(tempDir.path, 'media', 'images', 'guarded.png'),
      );
      await targetFile.parent.create(recursive: true);
      await targetFile.writeAsString('intact-original-bytes', flush: true);
      final tmpFile = File('${targetFile.path}.tmp');

      final dio = Dio();
      dio.httpClientAdapter = _FakeHttpClientAdapter((options) async {
        if (options.method == 'GET') {
          return ResponseBody.fromString(
            'corrupted-remote-bytes',
            200,
            headers: {
              Headers.contentLengthHeader: ['22'],
              'x-checksum-sha256': ['0' * 64],
            },
          );
        }
        return ResponseBody.fromString('', 404);
      });

      final service = WebDAVSyncService();
      service.setUrlForTesting('https://dav.example.com/dav/');

      final ok = await service.downloadMediaFileForTesting(
        dio,
        stdPath: 'images/guarded.png',
        appDir: tempDir,
        remoteInfo: const RemoteMediaFileInfo(length: 22),
      );

      expect(ok, isFalse);
      expect(await targetFile.exists(), isTrue);
      expect(await targetFile.readAsString(), 'intact-original-bytes');
      expect(await tmpFile.exists(), isFalse);
    });

    test(
        'syncMediaFiles prunes deleted local files, updates skipped-upload baseline, and marks downloaded files synced',
        () async {
      final localFile = File(
        p.join(tempDir.path, 'media', 'images', 'baseline_fill.png'),
      );
      await localFile.parent.create(recursive: true);
      const localBytes = 'baseline-fill-content';
      final t1 = DateTime.utc(2026, 6, 2, 10, 0, 0);
      await localFile.writeAsString(localBytes, flush: true);
      await localFile.setLastModified(t1);
      final localSha =
          crypto.sha256.convert(utf8.encode(localBytes)).toString();

      // Seed cache with a stale deleted path AND an entry missing syncedSha256
      final seedCache = MediaFingerprintCache(directory: tempDir);
      await seedCache.load();
      seedCache.putEntry(
        'images/deleted_local.png',
        MediaFingerprintEntry(
          fileSize: 10,
          lastModifiedEpochMs: t1.millisecondsSinceEpoch,
          sha256: 'a' * 64,
          syncedSha256: 'a' * 64,
        ),
      );
      seedCache.putEntry(
        'images/baseline_fill.png',
        MediaFingerprintEntry(
          fileSize: localBytes.length,
          lastModifiedEpochMs: t1.millisecondsSinceEpoch,
          sha256: localSha,
          syncedSha256: null,
        ),
      );
      await seedCache.save();

      final dio = Dio();
      dio.httpClientAdapter = _FakeHttpClientAdapter((options) async {
        if (options.method == 'PROPFIND') {
          if (options.path.contains('/images/')) {
            return ResponseBody.fromString('''
<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/thoughtecho/media/images/baseline_fill.png</d:href>
    <d:propstat>
      <d:prop>
        <d:getcontentlength>${localBytes.length}</d:getcontentlength>
        <d:getlastmodified>Tue, 02 Jun 2026 10:00:00 GMT</d:getlastmodified>
      </d:prop>
    </d:propstat>
  </d:response>
</d:multistatus>
''', 207);
          }
          return ResponseBody.fromString(
            '<?xml version="1.0"?><d:multistatus xmlns:d="DAV:"/>',
            207,
          );
        }
        if (options.method == 'GET') {
          return ResponseBody.fromString(
            'downloaded-media-ok',
            200,
            headers: {
              Headers.contentLengthHeader: ['19'],
            },
          );
        }
        return ResponseBody.fromString('', 500);
      });

      final service = WebDAVSyncService();
      service.setUrlForTesting('https://dav.example.com/dav/');

      expect(await service.syncMediaFilesForTesting(dio), 0);

      // Verify download also marks fingerprint cache synced with PROPFIND fallback ETag
      final dlCache = MediaFingerprintCache(directory: tempDir);
      await dlCache.load();
      expect(dlCache.peek('images/deleted_local.png'), isNull);
      expect(dlCache.peek('images/baseline_fill.png')?.syncedSha256, localSha);

      final downloadedOk = await service.downloadMediaFileForTesting(
        dio,
        stdPath: 'images/from_remote.png',
        appDir: tempDir,
        remoteInfo: const RemoteMediaFileInfo(
          length: 19,
          etag: '"propfind-dl-etag"',
        ),
        fingerprintCache: dlCache,
      );
      expect(downloadedOk, isTrue);
      expect(
        dlCache.peek('images/from_remote.png')?.syncedRemoteEtag,
        'propfind-dl-etag',
      );
      expect(
        dlCache.peek('images/from_remote.png')?.syncedSha256,
        crypto.sha256.convert(utf8.encode('downloaded-media-ok')).toString(),
      );
    });

    test(
        'switching WebDAV server or account via saveSettings isolates sync baselines',
        () async {
      final mediaFile = File(
        p.join(tempDir.path, 'media', 'images', 'server_switch.png'),
      );
      await mediaFile.parent.create(recursive: true);
      const payload = 'server-switch-media-bytes';
      final t1 = DateTime.utc(2026, 6, 3, 10, 0, 0);
      await mediaFile.writeAsString(payload, flush: true);
      await mediaFile.setLastModified(t1);

      final uploadedToServerA = <String>[];
      final uploadedToServerB = <String>[];
      var remoteHasOnA = false;
      var remoteHasOnB = true;

      final dio = Dio();
      dio.httpClientAdapter = _FakeHttpClientAdapter((options) async {
        final host = options.uri.host;
        if (options.method == 'PROPFIND') {
          if (options.path.contains('/images/')) {
            final exists =
                host == 'dav-a.example.com' ? remoteHasOnA : remoteHasOnB;
            if (!exists) {
              return ResponseBody.fromString(
                '<?xml version="1.0"?><d:multistatus xmlns:d="DAV:"/>',
                207,
              );
            }
            return ResponseBody.fromString('''
<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/thoughtecho/media/images/server_switch.png</d:href>
    <d:propstat>
      <d:prop>
        <d:getcontentlength>${payload.length}</d:getcontentlength>
        <d:getetag>"$host-etag-v1"</d:getetag>
        <d:getlastmodified>Thu, 04 Jun 2026 10:00:00 GMT</d:getlastmodified>
      </d:prop>
    </d:propstat>
  </d:response>
</d:multistatus>
''', 207);
          }
          return ResponseBody.fromString(
            '<?xml version="1.0"?><d:multistatus xmlns:d="DAV:"/>',
            207,
          );
        }
        if (options.method == 'PUT') {
          if (host == 'dav-a.example.com') {
            uploadedToServerA.add(options.path);
            remoteHasOnA = true;
          } else {
            uploadedToServerB.add(options.path);
            remoteHasOnB = true;
          }
          return ResponseBody.fromString(
            '',
            201,
            headers: {
              'etag': ['"$host-etag-v1"'],
            },
          );
        }
        return ResponseBody.fromString('', 404);
      });

      final service = WebDAVSyncService();
      await service.saveSettings(
        enabled: true,
        provider: 'custom',
        url: 'https://dav-a.example.com/dav/',
        username: 'alice',
        syncOnLaunch: true,
        syncOnChange: true,
        syncOnCellular: false,
        syncNotesOnlyOnCellular: false,
      );

      expect(await service.syncMediaFilesForTesting(dio), 0);
      expect(uploadedToServerA, hasLength(1));

      // Switch to server B which already has a same-size, newer-mtime file with a different ETag
      await service.saveSettings(
        enabled: true,
        provider: 'custom',
        url: 'https://dav-b.example.com/dav/',
        username: 'alice',
        syncOnLaunch: true,
        syncOnChange: true,
        syncOnCellular: false,
        syncNotesOnlyOnCellular: false,
      );

      expect(await service.syncMediaFilesForTesting(dio), 0);
      expect(uploadedToServerB, hasLength(1));
    });

    test(
        'PUT omitting ETag queries post-upload ETag without falling back to pre-upload ETag and converges',
        () async {
      final mediaFile = File(
        p.join(tempDir.path, 'media', 'images', 'no_put_etag.png'),
      );
      await mediaFile.parent.create(recursive: true);
      const v1 = 'no-put-etag-v1';
      const v2 = 'no-put-etag-v2';
      final t1 = DateTime.utc(2026, 6, 5, 10, 0, 0);
      await mediaFile.writeAsString(v1, flush: true);
      await mediaFile.setLastModified(t1);

      var remoteEtag = '"opaque-1"';
      var putCount = 0;

      final dio = Dio();
      dio.httpClientAdapter = _FakeHttpClientAdapter((options) async {
        if (options.method == 'PROPFIND') {
          if (options.path.endsWith('/images/no_put_etag.png')) {
            final xml = '''
<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/thoughtecho/media/images/no_put_etag.png</d:href>
    <d:propstat>
      <d:prop>
        <d:getcontentlength>${v1.length}</d:getcontentlength>
        <d:getetag>$remoteEtag</d:getetag>
      </d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>
</d:multistatus>
''';
            return ResponseBody.fromString(
              xml,
              207,
              headers: {
                Headers.contentLengthHeader: [xml.length.toString()],
              },
            );
          }
          if (options.path.contains('/images/')) {
            return ResponseBody.fromString('''
<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/thoughtecho/media/images/no_put_etag.png</d:href>
    <d:propstat>
      <d:prop>
        <d:getcontentlength>${v1.length}</d:getcontentlength>
        <d:getetag>$remoteEtag</d:getetag>
      </d:prop>
    </d:propstat>
  </d:response>
</d:multistatus>
''', 207);
          }
          return ResponseBody.fromString(
            '<?xml version="1.0"?><d:multistatus xmlns:d="DAV:"/>',
            207,
          );
        }
        if (options.method == 'PUT') {
          putCount++;
          // Server advances opaque ETag on each PUT and omits ETag header in PUT response
          remoteEtag = '"opaque-${putCount + 1}"';
          return ResponseBody.fromString('', 204);
        }
        return ResponseBody.fromString('', 404);
      });

      final service = WebDAVSyncService();
      service.setUrlForTesting('https://dav.example.com/dav/');

      // Run 1: uploads v1 -> server advances ETag to opaque-2; post-PUT PROPFIND records opaque-2
      expect(await service.syncMediaFilesForTesting(dio), 0);
      expect(putCount, 1);

      final cache1 = MediaFingerprintCache(directory: tempDir);
      await cache1.load();
      expect(
        cache1.peek('images/no_put_etag.png')?.syncedRemoteEtag,
        'opaque-2',
      );

      // Run 2: converges with 0 re-uploads (no Last-Modified on server)
      expect(await service.syncMediaFilesForTesting(dio), 0);
      expect(putCount, 1);

      // Local edit -> uploads v2, server becomes opaque-3, post-PUT records opaque-3
      await mediaFile.writeAsString(v2, flush: true);
      await mediaFile.setLastModified(t1.add(const Duration(seconds: 5)));
      expect(await service.syncMediaFilesForTesting(dio), 0);
      expect(putCount, 2);
      final cache2 = MediaFingerprintCache(directory: tempDir);
      await cache2.load();
      expect(
        cache2.peek('images/no_put_etag.png')?.syncedRemoteEtag,
        'opaque-3',
      );
    });

    test(
        'PUT omitting ETag when post-upload lookup is unavailable clears syncedRemoteEtag instead of saving stale ETag',
        () async {
      final mediaFile = File(
        p.join(tempDir.path, 'media', 'images', 'no_etag_lookup.png'),
      );
      await mediaFile.parent.create(recursive: true);
      const payload = 'no-etag-lookup-bytes';
      await mediaFile.writeAsString(payload, flush: true);

      final dio = Dio();
      dio.httpClientAdapter = _FakeHttpClientAdapter((options) async {
        if (options.method == 'PROPFIND') {
          if (options.path.endsWith('/images/no_etag_lookup.png')) {
            return ResponseBody.fromString('', 404);
          }
          if (options.path.contains('/images/')) {
            return ResponseBody.fromString('''
<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/thoughtecho/media/images/no_etag_lookup.png</d:href>
    <d:propstat>
      <d:prop>
        <d:getcontentlength>${payload.length}</d:getcontentlength>
        <d:getetag>"stale-pre-put-etag"</d:getetag>
      </d:prop>
    </d:propstat>
  </d:response>
</d:multistatus>
''', 207);
          }
          return ResponseBody.fromString(
            '<?xml version="1.0"?><d:multistatus xmlns:d="DAV:"/>',
            207,
          );
        }
        if (options.method == 'PUT') {
          return ResponseBody.fromString('', 204);
        }
        return ResponseBody.fromString('', 404);
      });

      final service = WebDAVSyncService();
      service.setUrlForTesting('https://dav.example.com/dav/');
      expect(await service.syncMediaFilesForTesting(dio), 0);

      final cache = MediaFingerprintCache(directory: tempDir);
      await cache.load();
      final entry = cache.peek('images/no_etag_lookup.png');
      expect(entry, isNotNull);
      expect(entry!.syncedSha256, isNotNull);
      expect(entry.syncedRemoteEtag, isNull);
    });

    test(
        'concurrent local overwrite during PUT leaves attachment unsynced so next sync uploads new bytes',
        () async {
      final mediaFile = File(
        p.join(tempDir.path, 'media', 'images', 'race.png'),
      );
      await mediaFile.parent.create(recursive: true);
      const v1 = 'race-bytes-v1';
      const v2 = 'race-bytes-v2';
      final t1 = DateTime.utc(2026, 6, 6, 10, 0, 0);
      final t2 = t1.add(const Duration(seconds: 5));
      await mediaFile.writeAsString(v1, flush: true);
      await mediaFile.setLastModified(t1);

      var putCount = 0;
      var remoteExists = false;

      final dio = Dio();
      dio.httpClientAdapter = _FakeHttpClientAdapter((options) async {
        if (options.method == 'PROPFIND') {
          if (options.path.contains('/images/') && remoteExists) {
            return ResponseBody.fromString('''
<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/thoughtecho/media/images/race.png</d:href>
    <d:propstat>
      <d:prop>
        <d:getcontentlength>${v1.length}</d:getcontentlength>
        <d:getetag>"race-etag-$putCount"</d:getetag>
      </d:prop>
    </d:propstat>
  </d:response>
</d:multistatus>
''', 207);
          }
          return ResponseBody.fromString(
            '<?xml version="1.0"?><d:multistatus xmlns:d="DAV:"/>',
            207,
          );
        }
        if (options.method == 'PUT') {
          putCount++;
          remoteExists = true;
          if (putCount == 1) {
            // Simulate same-size local overwrite while PUT is in flight
            await mediaFile.writeAsString(v2, flush: true);
            await mediaFile.setLastModified(t2);
          }
          return ResponseBody.fromString(
            '',
            201,
            headers: {
              'etag': ['"race-etag-$putCount"'],
            },
          );
        }
        return ResponseBody.fromString('', 404);
      });

      final service = WebDAVSyncService();
      service.setUrlForTesting('https://dav.example.com/dav/');

      expect(await service.syncMediaFilesForTesting(dio), 0);
      expect(putCount, 1);

      final cacheAfterRace = MediaFingerprintCache(directory: tempDir);
      await cacheAfterRace.load();
      expect(cacheAfterRace.peek('images/race.png')?.syncedSha256, isNull);

      // Next sync must re-upload v2 and mark v2 synced
      expect(await service.syncMediaFilesForTesting(dio), 0);
      expect(putCount, 2);

      final cacheAfterRetry = MediaFingerprintCache(directory: tempDir);
      await cacheAfterRetry.load();
      expect(
        cacheAfterRetry.peek('images/race.png')?.syncedSha256,
        crypto.sha256.convert(utf8.encode(v2)).toString(),
      );
    });

    test(
        'unreadable attachment during L3 hash read is counted as per-file failure without aborting remaining uploads',
        () async {
      final badFile = File(
        p.join(tempDir.path, 'media', 'images', 'a_unreadable.png'),
      );
      final goodFile = File(
        p.join(tempDir.path, 'media', 'images', 'b_readable.png'),
      );
      await badFile.parent.create(recursive: true);
      const badContent = 'bad-attachment-payload';
      const goodContent = 'good-attachment-payload';
      await badFile.writeAsString(badContent, flush: true);
      await goodFile.writeAsString(goodContent, flush: true);

      final uploadedPaths = <String>[];
      MediaFingerprintCache.readGuardForTesting = (file) async {
        if (p.basename(file.path) == 'a_unreadable.png') {
          throw FileSystemException('Permission denied', file.path);
        }
      };
      addTearDown(() => MediaFingerprintCache.readGuardForTesting = null);

      final dio = Dio();
      dio.httpClientAdapter = _FakeHttpClientAdapter((options) async {
        if (options.method == 'PROPFIND') {
          if (options.path.contains('/images/')) {
            return ResponseBody.fromString('''
<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/thoughtecho/media/images/a_unreadable.png</d:href>
    <d:propstat>
      <d:prop>
        <d:getcontentlength>${badContent.length}</d:getcontentlength>
      </d:prop>
    </d:propstat>
  </d:response>
</d:multistatus>
''', 207);
          }
          return ResponseBody.fromString(
            '<?xml version="1.0"?><d:multistatus xmlns:d="DAV:"/>',
            207,
          );
        }
        if (options.method == 'PUT') {
          uploadedPaths.add(options.path);
          return ResponseBody.fromString(
            '',
            201,
            headers: {
              'etag': ['"good-etag"'],
            },
          );
        }
        return ResponseBody.fromString('', 404);
      });

      final service = WebDAVSyncService();
      service.setUrlForTesting('https://dav.example.com/dav/');

      final failureCount = await service.syncMediaFilesForTesting(dio);
      expect(failureCount, 1);
      expect(uploadedPaths, hasLength(1));
      expect(uploadedPaths.single, endsWith('/images/b_readable.png'));
    });
  });
}

class _TestPathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String _appDir;
  _TestPathProvider(this._appDir);

  @override
  Future<String?> getApplicationDocumentsPath() async => _appDir;
}

class _FakeHttpClientAdapter implements HttpClientAdapter {
  final Future<ResponseBody> Function(RequestOptions options) _handler;
  _FakeHttpClientAdapter(this._handler);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) =>
      _handler(options);

  @override
  void close({bool force = false}) {}
}

/// 记录型日志服务：只捕获日志调用，不落库、不上报。
/// 未实现的 [UnifiedLogService] 成员走 [noSuchMethod]，与
/// `excerpt_intent_service_test.dart` 中的记录器模式一致。
class _RecordingLogService implements UnifiedLogService {
  final List<
      ({
        UnifiedLogLevel level,
        String message,
        String? source,
        Object? error,
        StackTrace? stackTrace,
      })> records = [];

  @override
  void verbose(
    String message, {
    String? source,
    Object? error,
    StackTrace? stackTrace,
  }) {
    log(
      UnifiedLogLevel.verbose,
      message,
      source: source,
      error: error,
      stackTrace: stackTrace,
    );
  }

  @override
  void debug(
    String message, {
    String? source,
    Object? error,
    StackTrace? stackTrace,
  }) {
    log(
      UnifiedLogLevel.debug,
      message,
      source: source,
      error: error,
      stackTrace: stackTrace,
    );
  }

  @override
  void info(
    String message, {
    String? source,
    Object? error,
    StackTrace? stackTrace,
  }) {
    log(
      UnifiedLogLevel.info,
      message,
      source: source,
      error: error,
      stackTrace: stackTrace,
    );
  }

  @override
  void warning(
    String message, {
    String? source,
    Object? error,
    StackTrace? stackTrace,
  }) {
    log(
      UnifiedLogLevel.warning,
      message,
      source: source,
      error: error,
      stackTrace: stackTrace,
    );
  }

  @override
  void error(
    String message, {
    String? source,
    Object? error,
    StackTrace? stackTrace,
  }) {
    log(
      UnifiedLogLevel.error,
      message,
      source: source,
      error: error,
      stackTrace: stackTrace,
    );
  }

  @override
  void log(
    UnifiedLogLevel level,
    String message, {
    String? source,
    Object? error,
    StackTrace? stackTrace,
  }) {
    records.add((
      level: level,
      message: message,
      source: source,
      error: error,
      stackTrace: stackTrace,
    ));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
