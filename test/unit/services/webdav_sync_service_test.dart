import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thoughtecho/services/mmkv_service.dart';
import 'package:thoughtecho/services/webdav_sync_service.dart';
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

  test('WebDAVSyncService should initialize and save settings correctly',
      () async {
    final service = WebDAVSyncService();

    // 测试默认配置
    expect(service.enabled, false);
    expect(service.provider, 'custom');
    expect(service.url, '');
    expect(service.username, '');
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
    expect(
      WebDAVSyncService.shouldUploadMediaFileForTesting(
        'videos/no_size.mp4',
        2048,
        remoteMediaFiles,
      ),
      isFalse,
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
}
