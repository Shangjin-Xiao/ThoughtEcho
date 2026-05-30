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

  test('WebDAVSyncService should enforce HTTPS strictly on saveSettings',
      () async {
    final service = WebDAVSyncService();

    expect(
      service.saveSettings(
        enabled: true,
        provider: 'custom',
        url: 'http://insecure.server.local/dav/',
        username: 'user',
        syncOnLaunch: false,
        syncOnChange: false,
      ),
      throwsA(isA<Exception>().having(
        (e) => e.toString(),
        'message',
        contains('HTTPS is required to protect WebDAV credentials'),
      )),
    );
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
}
