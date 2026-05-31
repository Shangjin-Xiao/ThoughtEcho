import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thoughtecho/services/mmkv_service.dart';
import 'package:thoughtecho/services/webdav_sync_service.dart';
import 'package:thoughtecho/services/connectivity_service.dart';
import 'package:thoughtecho/utils/mmkv_ffi_fix.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  const MethodChannel connectivityChannel =
      MethodChannel('dev.fluttercommunity.plus/connectivity');

  final Map<String, String> secureStorage = {};
  late MMKVService mmkv;
  List<String> mockConnectivityResults = ['wifi'];

  setUp(() async {
    secureStorage.clear();
    mockConnectivityResults = ['wifi'];

    // Initialize SharedPreferences
    SharedPreferences.setMockInitialValues({});

    mmkv = MMKVService();
    await mmkv.init();

    // Clear MMKV config
    final safeMMKV = SafeMMKV();
    await safeMMKV.initialize();
    await safeMMKV.clear();

    // Mock FlutterSecureStorage channel
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

    // Mock connectivity_plus channel
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      connectivityChannel,
      (MethodCall methodCall) async {
        if (methodCall.method == 'check') {
          return mockConnectivityResults;
        }
        return null;
      },
    );
  });

  group('WebDAV Cellular Sync Tests', () {
    test('Should initialize and save cellular sync settings correctly',
        () async {
      final service = WebDAVSyncService();

      // Default values should be false
      expect(service.syncOnCellular, false);
      expect(service.syncNotesOnlyOnCellular, false);

      // Save settings with cellular options enabled
      await service.saveSettings(
        enabled: true,
        provider: 'custom',
        url: 'https://example.com/dav',
        username: 'test_user',
        password: 'test_password',
        syncOnLaunch: true,
        syncOnChange: true,
        syncOnCellular: true,
        syncNotesOnlyOnCellular: true,
      );

      expect(service.syncOnCellular, true);
      expect(service.syncNotesOnlyOnCellular, true);

      // Reload settings in a new instance to verify MMKV persistence
      final newService = WebDAVSyncService();
      expect(newService.syncOnCellular, true);
      expect(newService.syncNotesOnlyOnCellular, true);
    });

    test('ConnectivityService should correctly identify cellular network type',
        () async {
      final connectivityService = ConnectivityService();

      // WiFi Connection
      mockConnectivityResults = ['wifi'];
      bool isCellular = await connectivityService.isCellularConnection();
      expect(isCellular, isFalse);

      // Cellular Connection
      mockConnectivityResults = ['mobile'];
      isCellular = await connectivityService.isCellularConnection();
      expect(isCellular, isTrue);
    });
  });
}
