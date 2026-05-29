import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/pages/webdav_sync_page.dart';
import 'package:thoughtecho/services/mmkv_service.dart';
import 'package:thoughtecho/services/webdav_sync_service.dart';
import 'package:thoughtecho/utils/mmkv_ffi_fix.dart';

import '../../test_setup.dart';

void main() {
  const MethodChannel secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  final Map<String, String> secureStorage = {};
  late WebDAVSyncService syncService;

  setUpAll(() async {
    await TestSetup.setupWidgetTest();
  });

  setUp(() async {
    secureStorage.clear();

    // Mock SharedPreferences
    SharedPreferences.setMockInitialValues({});

    // 初始化 MMKV
    final mmkv = MMKVService();
    await mmkv.init();

    final safeMMKV = SafeMMKV();
    await safeMMKV.initialize();
    await safeMMKV.clear();

    // Mock FlutterSecureStorage
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

    syncService = WebDAVSyncService();
  });

  Widget buildTestApp() {
    return ChangeNotifierProvider<WebDAVSyncService>.value(
      value: syncService,
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh', ''),
        home: const WebDAVSyncPage(),
      ),
    );
  }

  testWidgets('WebDAVSyncPage renders correctly with standard fields',
      (WidgetTester tester) async {
    await tester.pumpWidget(buildTestApp());
    await tester.pumpAndSettle();

    // 验证页面标题是否正确渲染
    expect(find.text('WebDAV 云同步'), findsOneWidget);

    // 验证下拉选择框、各个文本输入框是否正确渲染
    expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    expect(find.text('用户名/账号'), findsOneWidget);
    expect(find.text('应用密码/Token'), findsOneWidget);
    expect(find.text('服务器地址'), findsOneWidget);

    // 验证测试连接和开启同步按钮是否正确渲染
    expect(find.text('测试连接'), findsOneWidget);
    // expect(find.text('启用云同步'), findsOneWidget);

    // 验证同步配置策略是否显示
    expect(find.text('应用启动时自动同步'), findsOneWidget);
    expect(find.text('修改笔记后自动后台同步'), findsOneWidget);
  });
}
