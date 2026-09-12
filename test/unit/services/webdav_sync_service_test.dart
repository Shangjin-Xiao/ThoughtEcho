import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thoughtecho/services/mmkv_service.dart';
import 'package:thoughtecho/services/unified_log_service.dart';
import 'package:thoughtecho/services/webdav_sync_service.dart';
import 'package:thoughtecho/utils/app_logger.dart';
import 'package:thoughtecho/utils/mmkv_ffi_fix.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  final Map<String, String> secureStorage = {};
  late MMKVService mmkv;

  setUp(() async {
    // 清空 Mock 存储
    secureStorage.clear();

    // 初始化 SharedPreferences (为 FFI SafeMMKV 做 Mock 初始化准备)
    SharedPreferences.setMockInitialValues({});

    mmkv = MMKVService();
    await mmkv.init();

    // 清空 MMKV 中的同步配置
    final safeMMKV = SafeMMKV();
    await safeMMKV.initialize();
    await safeMMKV.clear();

    // Mock FlutterSecureStorage 方法通道
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      secureStorageChannel,
      (MethodCall methodCall) async {
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
      },
    );
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
          .setMockMethodCallHandler(
        secureStorageChannel,
        (MethodCall methodCall) async {
          if (methodCall.method == 'read') {
            throw PlatformException(
              code: 'READ_FAILED',
              message: 'Failed to read from secure storage',
            );
          }
          return null;
        },
      );

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

  test('WebDAVSyncService should initialize and save settings correctly',
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
  });

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
      throwsA(isA<Exception>().having(
        (e) => e.toString(),
        'message',
        contains('HTTPS is required to protect WebDAV credentials'),
      )),
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

  test('WebDAVSyncService should enforce HTTPS strictly on testConnection',
      () async {
    final service = WebDAVSyncService();

    // The testConnection method catches exceptions and returns false.
    // Instead of throwsA, we should test the boolean result.
    final result = await service.testConnection(
        'http://insecure.server.local/dav/', 'user', 'pass');
    expect(result, isFalse);
  });

  test('WebDAV media parser should extract existing remote files and sizes',
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
  });

  test('encodeMediaPath should encode special characters in path segments', () {
    expect(
      WebDAVSyncService.encodeMediaPathForTesting(
        'images/my photo #1?.jpg',
      ),
      'images/my%20photo%20%231%3F.jpg',
    );
    expect(
      WebDAVSyncService.encodeMediaPathForTesting(
        'audios/voice memo (1).mp3',
      ),
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
    records.add((level: level, message: message, source: source, error: error));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
