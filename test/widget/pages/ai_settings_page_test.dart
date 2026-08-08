import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/models/agent_memory.dart';
import 'package:thoughtecho/models/ai_provider_settings.dart';
import 'package:thoughtecho/models/multi_ai_settings.dart';
import 'package:thoughtecho/pages/ai_settings_page.dart';
import 'package:thoughtecho/services/agent_memory_service.dart';
import 'package:thoughtecho/services/settings_service.dart';

import '../../test_harness.dart';

/// DeepSeek 排在模板列表靠前的位置，不用滚动就能点到，并且自带默认模型，
/// 选完即可保存。
const _presetName = 'DeepSeek';

const _secureStorageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

/// flutter_secure_storage 在测试里没有原生实现，用内存 Map 顶上，
/// 否则任何读写都会抛 MissingPluginException。
void _installSecureStorageFake() {
  final store = <String, String>{};
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_secureStorageChannel, (call) async {
    final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? {};
    switch (call.method) {
      case 'read':
        return store[args['key'] as String];
      case 'readAll':
        return Map<String, String>.from(store);
      case 'write':
        store[args['key'] as String] = args['value'] as String;
        return null;
      case 'delete':
        store.remove(args['key'] as String);
        return null;
      case 'deleteAll':
        store.clear();
        return null;
      case 'containsKey':
        return store.containsKey(args['key'] as String);
      default:
        return null;
    }
  });
}

Widget _wrap(
  SettingsService settingsService,
  AgentMemoryService memoryService,
) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<SettingsService>.value(value: settingsService),
      ChangeNotifierProvider<AgentMemoryService>.value(value: memoryService),
    ],
    child: MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const AISettingsPage(),
    ),
  );
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(AISettingsPage)));

void main() {
  group('AISettingsPage', () {
    late SettingsService settingsService;
    late AgentMemoryService memoryService;

    setUp(() async {
      await TestHarness.initialize();
      _installSecureStorageFake();
      settingsService = await SettingsService.create();

      // 记忆卡片会去查条目数，给它一个真实的内存库，别让页面测试依赖异常路径。
      memoryService = AgentMemoryService(
        settingsService: settingsService,
        databasePath: inMemoryDatabasePath,
      );
    });

    tearDown(() async {
      memoryService.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_secureStorageChannel, null);
      await TestHarness.tearDown();
    });

    testWidgets('shows the empty state and the recommended Ollama Cloud entry',
        (tester) async {
      await tester.pumpWidget(_wrap(settingsService, memoryService));
      await tester.pumpAndSettle();

      final l10n = _l10n(tester);
      expect(find.text(l10n.aiServiceEmptyTitle), findsOneWidget);
      expect(find.text(l10n.ollamaCloudTipTitle), findsOneWidget);
      expect(find.text(l10n.ollamaCloudTipAction), findsOneWidget);
    });

    testWidgets(
        'adding a service creates a new entry instead of overwriting '
        'the current one', (tester) async {
      await settingsService.saveMultiAISettings(
        const MultiAISettings(
          providers: [
            AIProviderSettings(
              id: 'existing',
              name: '已有配置',
              apiUrl: 'https://api.deepseek.com/v1/chat/completions',
              model: 'deepseek-chat',
            ),
          ],
          currentProviderId: 'existing',
        ),
      );

      await tester.pumpWidget(_wrap(settingsService, memoryService));
      await tester.pumpAndSettle();

      final l10n = _l10n(tester);
      expect(settingsService.multiAISettings.providers, hasLength(1));

      // 打开新建页
      await tester.tap(find.text(l10n.addAiService));
      await tester.pumpAndSettle();
      expect(find.text(l10n.newAiServiceTitle), findsOneWidget);

      // 选一个模板，名称、地址和默认模型会自动填好
      await tester.tap(find.text(l10n.selectProviderTemplate).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text(_presetName).last);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, l10n.apiKeyField),
        'sk-test-key-1234',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.save));
      await tester.pumpAndSettle();

      final providers = settingsService.multiAISettings.providers;
      expect(providers, hasLength(2));
      expect(providers.first.id, 'existing');
      expect(providers.first.name, '已有配置');
      expect(providers.last.name, _presetName);
      expect(providers.last.model, 'deepseek-chat');
      expect(providers.last.isEnabled, isTrue);
      expect(
        settingsService.multiAISettings.currentProviderId,
        providers.last.id,
      );
    });

    testWidgets('editing the current service updates it in place',
        (tester) async {
      await settingsService.saveMultiAISettings(
        const MultiAISettings(
          providers: [
            AIProviderSettings(
              id: 'local',
              name: '本机模型',
              apiUrl: 'http://localhost:1234/v1/chat/completions',
              model: 'old-model',
            ),
          ],
          currentProviderId: 'local',
        ),
      );

      await tester.pumpWidget(_wrap(settingsService, memoryService));
      await tester.pumpAndSettle();

      final l10n = _l10n(tester);

      // 点击当前配置直接进编辑页
      await tester.tap(find.text('本机模型'));
      await tester.pumpAndSettle();
      expect(find.text(l10n.editAiServiceTitle), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextFormField, l10n.modelNameField),
        'new-model',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.save));
      await tester.pumpAndSettle();

      final providers = settingsService.multiAISettings.providers;
      expect(providers, hasLength(1));
      expect(providers.single.id, 'local');
      expect(providers.single.model, 'new-model');
    });

    testWidgets('memory switch defaults on and does not clear entries',
        (tester) async {
      await memoryService.rememberProfile(
        kind: AgentMemoryKind.style,
        directive: '回复保持碎句',
      );

      await tester.pumpWidget(_wrap(settingsService, memoryService));
      await tester.pumpAndSettle();

      final l10n = _l10n(tester);
      final switchTile = find.widgetWithText(
        SwitchListTile,
        l10n.agentMemoryEnableTitle,
      );
      await tester.scrollUntilVisible(switchTile, 200);
      await tester.pumpAndSettle();

      expect(tester.widget<SwitchListTile>(switchTile).value, isTrue);

      await tester.tap(switchTile);
      await tester.pumpAndSettle();

      // 关开关只停读写：条目还在，注入才停。
      expect(settingsService.agentMemoryEnabled, isFalse);
      expect((await memoryService.counts()).profileCount, 1);
      expect(await memoryService.buildProfileBlock(), isNull);
    });
  });
}
