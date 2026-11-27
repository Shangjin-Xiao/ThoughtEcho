import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/models/agent_memory.dart';
import 'package:thoughtecho/models/ai_model_metadata.dart';
import 'package:thoughtecho/models/ai_provider_settings.dart';
import 'package:thoughtecho/models/ai_task.dart';
import 'package:thoughtecho/models/multi_ai_settings.dart';
import 'package:thoughtecho/pages/ai_service_config_page.dart';
import 'package:thoughtecho/pages/ai_settings_page.dart';
import 'package:thoughtecho/pages/user_guide_page.dart';
import 'package:thoughtecho/services/agent_memory_service.dart';
import 'package:thoughtecho/services/api_key_manager.dart';
import 'package:thoughtecho/services/openai_stream_service.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/utils/ai_connection_tester.dart';
import 'package:thoughtecho/utils/aptabase_helper.dart';

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
  AgentMemoryService memoryService, {
  Locale locale = const Locale('zh'),
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<SettingsService>.value(value: settingsService),
      ChangeNotifierProvider<AgentMemoryService>.value(value: memoryService),
    ],
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const AISettingsPage(),
    ),
  );
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(Scaffold).last));

/// 滚到目标为止，滚的是页面本身那个列表。
///
/// 不能用 `tester.scrollUntilVisible` 的默认 scrollable：页面上的 `TextField`
/// 自带一个 `EditableText` 滚动视图，默认查找会同时匹配到两个 `Scrollable`
/// 而抛「Too many elements」。
/// 在真实时间里等 [condition] 成立，带上界。
///
/// 用于等真实异步 I/O：`pumpAndSettle` 推的是 fake-async 的时钟，推不动它，
/// 而固定延时在慢机器上只是把偶发失败的概率调小。超时即断言失败。
Future<void> _waitFor(
  WidgetTester tester,
  bool Function() condition, {
  required String describe,
  Duration timeout = const Duration(seconds: 5),
}) async {
  var satisfied = false;
  await tester.runAsync(() async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (condition()) {
        satisfied = true;
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    satisfied = condition();
  });
  expect(satisfied, isTrue, reason: '等待「$describe」超时（${timeout.inSeconds}s）');
}

Future<void> _scrollTo(WidgetTester tester, Finder target) async {
  final configFinder = find.byType(AIServiceConfigPage);
  final pageFinder = configFinder.evaluate().isNotEmpty
      ? configFinder
      : find.byType(AISettingsPage);
  await tester.scrollUntilVisible(
    target,
    200,
    scrollable: find
        .descendant(
          of: pageFinder,
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
}

Future<void> _openServiceConfig(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('ai_service_entry_card')));
  await tester.pumpAndSettle();
}

class _FailingSaveSettingsService extends SettingsService {
  _FailingSaveSettingsService(super.prefs);

  Object? saveMultiError;

  @override
  Future<void> saveMultiAISettings(MultiAISettings settings) async {
    if (saveMultiError != null) {
      throw saveMultiError!;
    }
    return super.saveMultiAISettings(settings);
  }
}

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
      // 先在 fake-async 之外把库打开：否则首次打开会发生在 widget build 里，
      // 那条 Future 在 testWidgets 的时钟下永远不完成。
      await memoryService.counts();
    });

    tearDown(() async {
      memoryService.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_secureStorageChannel, null);
      await TestHarness.tearDown();
    });

    testWidgets('shows the empty state when no providers are configured',
        (tester) async {
      await tester.pumpWidget(_wrap(settingsService, memoryService));
      await tester.pumpAndSettle();

      final l10n = _l10n(tester);
      expect(find.text(l10n.aiServiceEmptyTitle), findsOneWidget);
      expect(find.text(l10n.aiConfigHelpLink), findsOneWidget);
      expect(find.byKey(const ValueKey('ai_task_routing_card')), findsNothing);
      expect(find.text(l10n.ollamaCloudTipTitle), findsNothing);
      expect(find.text(l10n.ollamaCloudTipAction), findsNothing);
    });

    testWidgets(
        'saved connection test uses its stored key and saved destination',
        (tester) async {
      const provider = AIProviderSettings(
        id: 'saved-provider',
        name: 'Saved provider',
        apiUrl: 'https://original.example/v1',
        model: 'test-model',
      );
      await APIKeyManager()
          .saveProviderApiKey(provider.id, 'synthetic-stored-key');
      await settingsService.saveMultiAISettings(
        const MultiAISettings(providers: [provider]),
      );
      final testedProviders = <AIProviderSettings>[];
      AIConnectionTester.testOverrideForTesting = ({
        required AIProviderSettings provider,
        required String systemPrompt,
        required String userMessage,
        Duration timeout = const Duration(seconds: 30),
      }) async {
        testedProviders.add(provider);
        return 'pong';
      };
      addTearDown(() => AIConnectionTester.testOverrideForTesting = null);

      await tester.pumpWidget(_wrap(settingsService, memoryService));
      await tester.pumpAndSettle();
      await _openServiceConfig(tester);
      final l10n = _l10n(tester);
      await tester.tap(find.byTooltip(l10n.moreOptions));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.testConnectionButton));
      await tester.pumpAndSettle();

      expect(testedProviders, hasLength(1));
      expect(testedProviders.single.apiUrl, provider.apiUrl);
      expect(testedProviders.single.apiKey, 'synthetic-stored-key');
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
      await _openServiceConfig(tester);

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
      expect(providers.last.providerSlug, 'deepseek');
      expect(providers.last.protocol, AIProtocolType.openAICompatible);
      expect(providers.last.isEnabled, isTrue);
      expect(
        settingsService.multiAISettings.currentProviderId,
        providers.last.id,
      );
    });

    testWidgets(
        'editing the current service clears stale modelMetadata on model or endpoint change, and preserves it on rename only',
        (tester) async {
      await settingsService.saveMultiAISettings(
        const MultiAISettings(
          providers: [
            AIProviderSettings(
              id: 'local',
              name: '本机模型',
              apiUrl: 'http://localhost:1234/v1/chat/completions',
              model: 'old-model',
              modelMetadata: AIModelMetadata(
                contextWindow: 65536,
                reasoning: true,
              ),
            ),
          ],
          currentProviderId: 'local',
        ),
      );

      final testedDrafts = <AIProviderSettings>[];
      AIConnectionTester.testOverrideForTesting = ({
        required AIProviderSettings provider,
        required String systemPrompt,
        required String userMessage,
        Duration timeout = const Duration(seconds: 30),
      }) async {
        testedDrafts.add(provider);
        return 'pong';
      };
      addTearDown(() => AIConnectionTester.testOverrideForTesting = null);

      await tester.pumpWidget(_wrap(settingsService, memoryService));
      await tester.pumpAndSettle();
      await _openServiceConfig(tester);

      final l10n = _l10n(tester);

      // 1. 仅重命名配置（模型名与端点均未变化）-> 草稿测试连接与保存均保留 modelMetadata
      await tester.tap(find.text('本机模型'));
      await tester.pumpAndSettle();
      expect(find.text(l10n.editAiServiceTitle), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextFormField, l10n.configNameField),
        '本机主力模型',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.testConnectionButton));
      await tester.pumpAndSettle();
      expect(testedDrafts.last.modelMetadata?.contextWindow, 65536);
      expect(testedDrafts.last.modelMetadata?.reasoning, isTrue);

      await tester.tap(find.text(l10n.save));
      await tester.pumpAndSettle();

      var providers = settingsService.multiAISettings.providers;
      expect(providers, hasLength(1));
      expect(providers.single.id, 'local');
      expect(providers.single.name, '本机主力模型');
      expect(providers.single.model, 'old-model');
      expect(providers.single.modelMetadata?.contextWindow, 65536);
      expect(providers.single.modelMetadata?.reasoning, isTrue);

      // 1b. 等价端点改写（/v1/chat/completions -> /v1）-> 草稿与保存均保留 modelMetadata
      await tester.tap(find.text('本机主力模型'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, l10n.apiUrlField),
        'http://localhost:1234/v1',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.testConnectionButton));
      await tester.pumpAndSettle();
      expect(testedDrafts.last.apiUrl, 'http://localhost:1234/v1');
      expect(testedDrafts.last.modelMetadata?.contextWindow, 65536);
      expect(testedDrafts.last.modelMetadata?.reasoning, isTrue);

      await tester.tap(find.text(l10n.save));
      await tester.pumpAndSettle();

      providers = settingsService.multiAISettings.providers;
      expect(providers.single.apiUrl, 'http://localhost:1234/v1');
      expect(providers.single.modelMetadata?.contextWindow, 65536);
      expect(providers.single.modelMetadata?.reasoning, isTrue);

      // 2. 更换模型名 -> 草稿测试连接与保存均清空旧 modelMetadata
      await tester.tap(find.text('本机主力模型'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, l10n.modelNameField),
        'new-model',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.testConnectionButton));
      await tester.pumpAndSettle();
      expect(testedDrafts.last.model, 'new-model');
      expect(testedDrafts.last.modelMetadata, isNull);

      await tester.tap(find.text(l10n.save));
      await tester.pumpAndSettle();

      providers = settingsService.multiAISettings.providers;
      expect(providers, hasLength(1));
      expect(providers.single.id, 'local');
      expect(providers.single.model, 'new-model');
      expect(providers.single.modelMetadata, isNull);
    });

    testWidgets(
        'editing a service clears stale modelMetadata when switching to a different endpoint',
        (tester) async {
      await settingsService.saveMultiAISettings(
        const MultiAISettings(
          providers: [
            AIProviderSettings(
              id: 'local',
              name: '本机主力模型',
              apiUrl: 'http://localhost:1234/v1',
              model: 'local-model',
              modelMetadata: AIModelMetadata(
                contextWindow: 131072,
                reasoning: true,
              ),
            ),
          ],
          currentProviderId: 'local',
        ),
      );

      final testedDrafts = <AIProviderSettings>[];
      AIConnectionTester.testOverrideForTesting = ({
        required AIProviderSettings provider,
        required String systemPrompt,
        required String userMessage,
        Duration timeout = const Duration(seconds: 30),
      }) async {
        testedDrafts.add(provider);
        return 'pong';
      };
      addTearDown(() => AIConnectionTester.testOverrideForTesting = null);

      await tester.pumpWidget(_wrap(settingsService, memoryService));
      await tester.pumpAndSettle();
      await _openServiceConfig(tester);

      final l10n = _l10n(tester);
      await tester.tap(find.text('本机主力模型'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, l10n.apiUrlField),
        'http://localhost:11434/v1',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.testConnectionButton));
      await tester.pumpAndSettle();
      expect(testedDrafts.last.modelMetadata, isNull);

      await tester.tap(find.text(l10n.save));
      await tester.pumpAndSettle();

      expect(
        settingsService.multiAISettings.providers.single.modelMetadata,
        isNull,
      );
    });

    testWidgets(
        'editing a service stored under a preset alias preserves modelMetadata while canonicalizing providerSlug',
        (tester) async {
      await APIKeyManager()
          .saveProviderApiKey('p_gemini_alias', 'sk-test-gemini-1234');
      await settingsService.saveMultiAISettings(
        const MultiAISettings(
          providers: [
            AIProviderSettings(
              id: 'p_gemini_alias',
              name: 'Gemini 服务',
              apiUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
              model: 'gemini-2.5-flash',
              providerSlug: 'gemini',
              modelMetadata: AIModelMetadata(
                contextWindow: 1048576,
                reasoning: true,
              ),
            ),
          ],
          currentProviderId: 'p_gemini_alias',
        ),
      );

      final testedDrafts = <AIProviderSettings>[];
      AIConnectionTester.testOverrideForTesting = ({
        required AIProviderSettings provider,
        required String systemPrompt,
        required String userMessage,
        Duration timeout = const Duration(seconds: 30),
      }) async {
        testedDrafts.add(provider);
        return 'pong';
      };
      addTearDown(() => AIConnectionTester.testOverrideForTesting = null);

      await tester.pumpWidget(_wrap(settingsService, memoryService));
      await tester.pumpAndSettle();
      await _openServiceConfig(tester);

      final l10n = _l10n(tester);
      await tester.tap(find.text('Gemini 服务'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, l10n.configNameField),
        '主力 Gemini',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.testConnectionButton));
      await tester.pumpAndSettle();
      expect(testedDrafts.last.providerSlug, 'google');
      expect(testedDrafts.last.modelMetadata?.contextWindow, 1048576);
      expect(testedDrafts.last.modelMetadata?.reasoning, isTrue);

      await tester.tap(find.text(l10n.save));
      await tester.pumpAndSettle();

      final providers = settingsService.multiAISettings.providers;
      expect(providers.single.name, '主力 Gemini');
      expect(providers.single.providerSlug, 'google');
      expect(providers.single.modelMetadata?.contextWindow, 1048576);
      expect(providers.single.modelMetadata?.reasoning, isTrue);
    });

    testWidgets('memory switch defaults on and toggles off', (tester) async {
      // sqflite 是真实的异步 I/O，在 testWidgets 的 fake-async 区里 await 它
      // 永远不会返回；碰数据库的部分一律走 runAsync。
      await tester.runAsync(() async {
        await memoryService.rememberProfile(
          kind: AgentMemoryKind.style,
          directive: '回复保持碎句',
        );
      });

      await tester.pumpWidget(_wrap(settingsService, memoryService));
      await tester.pumpAndSettle();

      final l10n = _l10n(tester);
      final switchTile = find.widgetWithText(
        SwitchListTile,
        l10n.agentMemoryEnableTitle,
      );
      await _scrollTo(tester, switchTile);

      expect(tester.widget<SwitchListTile>(switchTile).value, isTrue);

      await tester.tap(switchTile);
      await tester.pumpAndSettle();
      expect(settingsService.agentMemoryEnabled, isFalse);

      // 关开关只停读写，条目不删——数据侧的不变量在单元测试里断言，
      // 这里只确认 UI 和设置对得上。
      await tester.runAsync(() async {
        expect((await memoryService.counts()).profileCount, 1);
        expect(await memoryService.buildProfileBlock(), isNull);
      });
    });

    testWidgets('nickname field loads the stored value and saves edits',
        (tester) async {
      // 本地存储在同一个文件的用例之间是共享的，上一个用例把记忆关掉了就会
      // 让这里的输入框处于禁用状态。显式置位，别依赖用例顺序。
      await settingsService.setAgentMemoryEnabled(true);
      await settingsService.setUserNickname('阿澈');

      await tester.pumpWidget(_wrap(settingsService, memoryService));
      await tester.pumpAndSettle();

      final l10n = _l10n(tester);
      final field = find.widgetWithText(TextField, '阿澈');
      await _scrollTo(tester, field);
      expect(
        tester.widget<TextField>(field).decoration?.labelText,
        l10n.agentMemoryNicknameTitle,
      );

      await tester.enterText(field, '小澈  ');
      await tester.pumpAndSettle();
      // 落盘是真实异步 I/O，fake-async 的时钟推不动它，得回到真实时间里等。
      // 等的是「值真的变了」这个信号本身，不是一个拍脑袋的固定延时——
      // 固定延时在慢机器上必然偶发失败，而这里超时了就是真的没写进去。
      await _waitFor(
        tester,
        () => settingsService.userNickname == '小澈',
        describe: '称呼落盘',
      );

      // 服务侧会 trim。
      expect(settingsService.userNickname, '小澈');
    });

    testWidgets('nickname field is disabled while memory is off',
        (tester) async {
      await settingsService.setAgentMemoryEnabled(false);

      await tester.pumpWidget(_wrap(settingsService, memoryService));
      await tester.pumpAndSettle();

      final l10n = _l10n(tester);
      final field = find.widgetWithText(
        TextField,
        l10n.agentMemoryNicknameDisabled,
      );
      await _scrollTo(tester, field);

      // 关掉记忆后画像块整块不注入，称呼也就不会生效——输入框必须跟着禁用，
      // 否则用户填了却没反应。
      expect(tester.widget<TextField>(field).enabled, isFalse);
    });

    testWidgets('tracks telemetry for connection test and provider save',
        (tester) async {
      await settingsService.saveMultiAISettings(
        MultiAISettings.defaultSettings(),
      );
      final events = <Map<String, dynamic>>[];
      AptabaseHelper.onTrackEventForTesting = (event, props) {
        events.add({'event': event, 'props': props});
      };
      AIConnectionTester.testOverrideForTesting = ({
        required AIProviderSettings provider,
        required String systemPrompt,
        required String userMessage,
        Duration timeout = const Duration(seconds: 30),
      }) async =>
          'pong';

      try {
        await tester.pumpWidget(_wrap(settingsService, memoryService));
        await tester.pumpAndSettle();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pumpAndSettle();

        // 1. Verify page view is tracked
        expect(
          events.any((e) =>
              e['event'] == 'page_view' &&
              e['props']?['page'] == 'ai_settings'),
          isTrue,
        );

        final l10n = _l10n(tester);

        // 2. Open Add AI Service
        await tester.tap(find.text(l10n.addAiService));
        await tester.pumpAndSettle();

        // Select DeepSeek preset
        await tester.tap(find.text(l10n.selectProviderTemplate).last);
        await tester.pumpAndSettle();
        await tester.tap(find.text(_presetName).last);
        await tester.pumpAndSettle();

        await tester.enterText(
          find.widgetWithText(TextFormField, l10n.apiKeyField),
          'sk-test-key-1234',
        );
        await tester.pumpAndSettle();

        // Tap Test Connection in edit page
        await tester.tap(find.text(l10n.testConnectionButton));
        await tester.pumpAndSettle();

        expect(
          events.any((e) =>
              e['event'] == 'feature_used' &&
              e['props']?['action'] == 'ai_test_connection' &&
              e['props']?['provider_preset'] == 'deepseek'),
          isTrue,
        );

        // Tap Save (new provider)
        await tester.tap(find.text(l10n.save));
        await tester.pumpAndSettle();

        expect(
          events.any((e) =>
              e['event'] == 'feature_used' &&
              e['props']?['action'] == 'ai_provider_save' &&
              e['props']?['is_new'] == true &&
              e['props']?['provider_preset'] == 'deepseek'),
          isTrue,
        );

        // 3. Open service config page and edit existing provider
        await _openServiceConfig(tester);
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        expect(
          events.any((e) =>
              e['event'] == 'page_view' &&
              e['props']?['page'] == 'ai_service_config'),
          isTrue,
        );
        await tester.tap(find.text(_presetName));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.widgetWithText(TextFormField, l10n.modelNameField),
          'deepseek-reasoner',
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text(l10n.save));
        await tester.pumpAndSettle();

        expect(
          events.any((e) =>
              e['event'] == 'feature_used' &&
              e['props']?['action'] == 'ai_provider_save' &&
              e['props']?['is_new'] == false &&
              e['props']?['provider_preset'] == 'deepseek'),
          isTrue,
        );

        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
      } finally {
        AptabaseHelper.onTrackEventForTesting = null;
        AIConnectionTester.testOverrideForTesting = null;
      }
    });

    testWidgets(
        'assigns task provider via bottom sheet, shows task badge on provider tile, and cleans up on delete',
        (tester) async {
      final events = <Map<String, dynamic>>[];
      AptabaseHelper.onTrackEventForTesting = (event, props) {
        events.add({'event': event, 'props': props});
      };
      addTearDown(() => AptabaseHelper.onTrackEventForTesting = null);

      await APIKeyManager()
          .saveProviderApiKey('p_default', 'sk-default-123456');
      await APIKeyManager().saveProviderApiKey('p_dream', 'sk-dreaming-123456');
      await settingsService.saveMultiAISettings(
        const MultiAISettings(
          providers: [
            AIProviderSettings(
              id: 'p_default',
              name: '默认轻量服务',
              apiUrl: 'https://open.bigmodel.cn/api/paas/v4',
              model: 'glm-4-flash',
              providerSlug: 'zhipuai',
            ),
            AIProviderSettings(
              id: 'p_dream',
              name: '推理专线服务',
              apiUrl: 'https://api.deepseek.com/v1',
              model: 'deepseek-reasoner',
              providerSlug: 'deepseek',
            ),
          ],
          currentProviderId: 'p_default',
        ),
      );

      await tester.pumpWidget(_wrap(settingsService, memoryService));
      await tester.pumpAndSettle();
      await _openServiceConfig(tester);

      final l10n = _l10n(tester);
      await _scrollTo(tester, find.text(l10n.aiRoutingModeCustom));
      await tester.tap(find.text(l10n.aiRoutingModeCustom));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('ai_task_routing_card')),
        findsOneWidget,
      );
      expect(
        find.text(l10n.aiTaskFollowingDefault('默认轻量服务')),
        findsNWidgets(6),
      );

      // Assign Dreaming to p_dream via ModalBottomSheet
      final dreamingTile = find.byKey(const ValueKey('ai_task_tile_dreaming'));
      await _scrollTo(tester, dreamingTile);
      await tester.tap(dreamingTile);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('ai_task_option_p_dream')));
      await tester.pumpAndSettle();

      expect(settingsService.multiAISettings.currentProviderId, 'p_default');
      expect(
        settingsService.multiAISettings.taskProviderIds[AITask.dreaming],
        'p_dream',
      );
      expect(
        events.any(
          (e) =>
              e['event'] == 'feature_used' &&
              e['props']?['action'] == 'ai_task_provider_select' &&
              e['props']?['task'] == 'dreaming' &&
              e['props']?['uses_default'] == false,
        ),
        isTrue,
      );

      // Scroll back up to verify provider tile badge for p_dream
      final dreamProviderTile = find.text('推理专线服务');
      await tester.scrollUntilVisible(
        dreamProviderTile,
        -200,
        scrollable: find
            .descendant(
              of: find.byType(AIServiceConfigPage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('provider_task_badge_p_dream_dreaming')),
        findsOneWidget,
      );

      // Delete p_dream -> taskProviderIds[dreaming] is cleaned and falls back to default
      await tester.tap(find.byTooltip(l10n.moreOptions).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.delete));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, l10n.delete));
      await tester.pumpAndSettle();

      expect(
        settingsService.multiAISettings.taskProviderIds
            .containsKey(AITask.dreaming),
        isFalse,
      );
      expect(settingsService.multiAISettings.currentProviderId, 'p_default');
    });

    testWidgets(
        'selecting follow default clears persisted taskProviderIds when bound provider is disabled',
        (tester) async {
      await APIKeyManager()
          .saveProviderApiKey('p_default', 'sk-default-123456');
      await settingsService.saveMultiAISettings(
        const MultiAISettings(
          providers: [
            AIProviderSettings(
              id: 'p_default',
              name: '默认服务',
              apiUrl: 'https://open.bigmodel.cn/api/paas/v4',
              model: 'glm-4-flash',
              isEnabled: true,
            ),
            AIProviderSettings(
              id: 'p_disabled',
              name: '已停用服务',
              apiUrl: 'https://api.deepseek.com/v1',
              model: 'deepseek-chat',
              isEnabled: false,
            ),
          ],
          currentProviderId: 'p_default',
          taskProviderIds: {AITask.dailyInsight: 'p_disabled'},
        ),
      );

      await tester.pumpWidget(_wrap(settingsService, memoryService));
      await tester.pumpAndSettle();
      await _openServiceConfig(tester);

      final dailyTile = find.byKey(const ValueKey('ai_task_tile_dailyInsight'));
      await _scrollTo(tester, dailyTile);
      await tester.tap(dailyTile);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('ai_task_option_default')));
      await tester.pumpAndSettle();

      expect(
        settingsService.multiAISettings.taskProviderIds
            .containsKey(AITask.dailyInsight),
        isFalse,
      );
    });

    testWidgets(
        'shows error SnackBar and skips telemetry when saving task provider fails',
        (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final failingSettings = _FailingSaveSettingsService(prefs);
      addTearDown(failingSettings.dispose);

      await APIKeyManager()
          .saveProviderApiKey('p_default', 'sk-default-123456');
      await APIKeyManager().saveProviderApiKey('p_alt', 'sk-alt-key-123456');
      await failingSettings.saveMultiAISettings(
        const MultiAISettings(
          providers: [
            AIProviderSettings(
              id: 'p_default',
              name: '默认服务',
              apiUrl: 'https://open.bigmodel.cn/api/paas/v4',
              model: 'glm-4-flash',
            ),
            AIProviderSettings(
              id: 'p_alt',
              name: '备选服务',
              apiUrl: 'https://api.deepseek.com/v1',
              model: 'deepseek-chat',
            ),
          ],
          currentProviderId: 'p_default',
          routingMode: AIRoutingMode.custom,
        ),
      );

      final events = <Map<String, dynamic>>[];
      AptabaseHelper.onTrackEventForTesting = (event, props) {
        events.add({'event': event, 'props': props});
      };
      addTearDown(() => AptabaseHelper.onTrackEventForTesting = null);

      await tester.pumpWidget(_wrap(failingSettings, memoryService));
      await tester.pumpAndSettle();
      await _openServiceConfig(tester);
      final l10n = _l10n(tester);

      failingSettings.saveMultiError = StateError('模拟存储写入失败');

      final dailyTile = find.byKey(const ValueKey('ai_task_tile_dailyInsight'));
      await _scrollTo(tester, dailyTile);
      await tester.tap(dailyTile);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('ai_task_option_p_alt')));
      await tester.pumpAndSettle();

      expect(
        find.textContaining(
          l10n.saveSettingsError('Bad state: 模拟存储写入失败'),
        ),
        findsOneWidget,
      );
      expect(
        failingSettings.multiAISettings.taskProviderIds
            .containsKey(AITask.dailyInsight),
        isFalse,
      );
      expect(
        events.any(
          (e) =>
              e['event'] == 'feature_used' &&
              e['props']?['action'] == 'ai_task_provider_select',
        ),
        isFalse,
      );
    });

    testWidgets(
        'editing custom gateway from /gateway to /gateway/v1 clears stale modelMetadata because AgentService base URL changes',
        (tester) async {
      await APIKeyManager().saveProviderApiKey('p_gw', 'sk-gw-test-1234');
      await settingsService.saveMultiAISettings(
        const MultiAISettings(
          providers: [
            AIProviderSettings(
              id: 'p_gw',
              name: '内部网关',
              apiUrl: 'https://corp.example/gateway',
              model: 'gateway-model',
              modelMetadata: AIModelMetadata(
                contextWindow: 131072,
                reasoning: true,
              ),
            ),
          ],
          currentProviderId: 'p_gw',
        ),
      );

      final testedDrafts = <AIProviderSettings>[];
      AIConnectionTester.testOverrideForTesting = ({
        required AIProviderSettings provider,
        required String systemPrompt,
        required String userMessage,
        Duration timeout = const Duration(seconds: 30),
      }) async {
        testedDrafts.add(provider);
        return 'pong';
      };
      addTearDown(() => AIConnectionTester.testOverrideForTesting = null);

      await tester.pumpWidget(_wrap(settingsService, memoryService));
      await tester.pumpAndSettle();
      await _openServiceConfig(tester);

      final l10n = _l10n(tester);
      await tester.tap(find.text('内部网关'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, l10n.apiUrlField),
        'https://corp.example/gateway/v1',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.testConnectionButton));
      await tester.pumpAndSettle();
      expect(testedDrafts.last.modelMetadata, isNull);

      await tester.tap(find.text(l10n.save));
      await tester.pumpAndSettle();

      expect(
        settingsService.multiAISettings.providers.single.modelMetadata,
        isNull,
      );
    });

    testWidgets(
        'renaming a slugless Anthropic gateway preserves modelMetadata and null providerSlug',
        (tester) async {
      await APIKeyManager()
          .saveProviderApiKey('p_ant_gw', 'sk-ant-gw-test-1234');
      await settingsService.saveMultiAISettings(
        const MultiAISettings(
          providers: [
            AIProviderSettings(
              id: 'p_ant_gw',
              name: 'Claude 网关',
              apiUrl: 'https://gateway.example/v1',
              model: 'claude-sonnet-4-5',
              protocol: AIProtocolType.anthropicMessages,
              modelMetadata: AIModelMetadata(
                contextWindow: 200000,
                reasoning: true,
              ),
            ),
          ],
          currentProviderId: 'p_ant_gw',
        ),
      );

      await tester.pumpWidget(_wrap(settingsService, memoryService));
      await tester.pumpAndSettle();
      await _openServiceConfig(tester);

      final l10n = _l10n(tester);
      await tester.tap(find.text('Claude 网关'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, l10n.configNameField),
        '主力 Claude 网关',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.save));
      await tester.pumpAndSettle();

      final saved = settingsService.multiAISettings.providers.single;
      expect(saved.name, '主力 Claude 网关');
      expect(saved.providerSlug, isNull);
      expect(saved.protocol, AIProtocolType.anthropicMessages);
      expect(saved.modelMetadata?.contextWindow, 200000);
      expect(saved.modelMetadata?.reasoning, isTrue);
    });

    testWidgets(
        'editor treats shared https://api.anthropic.com/v1 as OpenAI-compatible and migrates host-inferred records',
        (tester) async {
      await APIKeyManager()
          .saveProviderApiKey('p_ant_shared', 'sk-ant-shared-1234');
      await settingsService.saveMultiAISettings(
        const MultiAISettings(
          providers: [
            AIProviderSettings(
              id: 'p_ant_shared',
              name: 'Anthropic 兼容配置',
              apiUrl: 'https://api.anthropic.com/v1',
              model: 'claude-sonnet-4-5',
              providerSlug: 'anthropic',
              protocol: AIProtocolType.anthropicMessages,
              modelMetadata: AIModelMetadata(
                contextWindow: 200000,
                reasoning: true,
              ),
            ),
          ],
          currentProviderId: 'p_ant_shared',
        ),
      );

      final testedDrafts = <AIProviderSettings>[];
      AIConnectionTester.testOverrideForTesting = ({
        required AIProviderSettings provider,
        required String systemPrompt,
        required String userMessage,
        Duration timeout = const Duration(seconds: 30),
      }) async {
        // Also verify real runtime config construction succeeds without throwing
        final config = OpenAIStreamService.buildOpenAIConfig(provider);
        expect(config.baseUrl, 'https://api.anthropic.com/v1');
        testedDrafts.add(provider);
        return 'pong';
      };
      addTearDown(() => AIConnectionTester.testOverrideForTesting = null);

      await tester.pumpWidget(_wrap(settingsService, memoryService));
      await tester.pumpAndSettle();
      await _openServiceConfig(tester);

      final l10n = _l10n(tester);
      await tester.tap(find.text('Anthropic 兼容配置'));
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.testConnectionButton));
      await tester.pumpAndSettle();
      expect(testedDrafts, hasLength(1));
      expect(testedDrafts.single.providerSlug, 'anthropic');
      expect(testedDrafts.single.protocol, AIProtocolType.openAICompatible);
      expect(testedDrafts.single.isAnthropicMessagesApi, isFalse);
      expect(find.text(l10n.connectionTestSuccess), findsOneWidget);

      await tester.tap(find.text(l10n.save));
      await tester.pumpAndSettle();

      final saved = settingsService.multiAISettings.providers.single;
      expect(saved.providerSlug, 'anthropic');
      expect(saved.protocol, AIProtocolType.openAICompatible);
      expect(saved.isAnthropicMessagesApi, isFalse);
      expect(saved.modelMetadata?.contextWindow, 200000);
    });

    testWidgets(
        'testing literal /v1/messages endpoint shows localized English guidance without Chinese text',
        (tester) async {
      AIConnectionTester.testOverrideForTesting = null;
      await APIKeyManager()
          .saveProviderApiKey('p_ant_native', 'sk-ant-native-1234');
      await settingsService.saveMultiAISettings(
        const MultiAISettings(
          providers: [
            AIProviderSettings(
              id: 'p_ant_native',
              name: 'Anthropic Native Messages',
              apiUrl: 'https://api.anthropic.com/v1/messages',
              model: 'claude-sonnet-4-5',
            ),
          ],
          currentProviderId: 'p_ant_native',
        ),
      );

      await tester.pumpWidget(
        _wrap(
          settingsService,
          memoryService,
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();
      await _openServiceConfig(tester);

      final l10n = _l10n(tester);
      await tester.tap(find.text('Anthropic Native Messages'));
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.testConnectionButton));
      await tester.pumpAndSettle();

      final expectedMessage = l10n.connectionTestFailed(
        l10n.aiUnsupportedAnthropicMessagesProtocol,
      );
      expect(find.text(expectedMessage), findsOneWidget);
      expect(expectedMessage, contains('Native Anthropic Messages'));
      expect(RegExp(r'[\u4e00-\u9fff]').hasMatch(expectedMessage), isFalse);
    });

    testWidgets(
        'editor preserves OpenAI-compatible protocol on custom gateway base ending in /messages and restored Anthropic slug gateway',
        (tester) async {
      await APIKeyManager()
          .saveProviderApiKey('p_inbox_gw', 'sk-inbox-gw-1234');
      await APIKeyManager()
          .saveProviderApiKey('p_restored_ant', 'sk-restored-ant-1234');
      await settingsService.saveMultiAISettings(
        const MultiAISettings(
          providers: [
            AIProviderSettings(
              id: 'p_inbox_gw',
              name: '消息路由网关',
              apiUrl: 'https://gateway.example/v1/inbox/messages',
              model: 'gpt-4o-mini',
              protocol: AIProtocolType.openAICompatible,
            ),
            AIProviderSettings(
              id: 'p_restored_ant',
              name: '恢复的 Claude 网关',
              apiUrl: 'https://gateway.example/v1',
              model: 'claude-sonnet-4-5',
              providerSlug: 'anthropic',
              modelMetadata: AIModelMetadata(
                contextWindow: 200000,
                reasoning: true,
              ),
            ),
          ],
          currentProviderId: 'p_inbox_gw',
        ),
      );

      final testedDrafts = <AIProviderSettings>[];
      AIConnectionTester.testOverrideForTesting = ({
        required AIProviderSettings provider,
        required String systemPrompt,
        required String userMessage,
        Duration timeout = const Duration(seconds: 30),
      }) async {
        final config = OpenAIStreamService.buildOpenAIConfig(provider);
        expect(config.baseUrl, 'https://gateway.example/v1/inbox/messages');
        testedDrafts.add(provider);
        return 'pong';
      };
      addTearDown(() => AIConnectionTester.testOverrideForTesting = null);

      await tester.pumpWidget(_wrap(settingsService, memoryService));
      await tester.pumpAndSettle();
      await _openServiceConfig(tester);

      final l10n = _l10n(tester);

      // 1. Test connection & save on custom OpenAI-compatible gateway ending in /messages
      await tester.tap(find.text('消息路由网关'));
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.testConnectionButton));
      await tester.pumpAndSettle();
      expect(testedDrafts, hasLength(1));
      expect(testedDrafts.single.protocol, AIProtocolType.openAICompatible);
      expect(testedDrafts.single.isAnthropicMessagesApi, isFalse);
      expect(find.text(l10n.connectionTestSuccess), findsOneWidget);

      await tester.tap(find.text(l10n.save));
      await tester.pumpAndSettle();

      final savedInbox = settingsService.multiAISettings.providers
          .firstWhere((p) => p.id == 'p_inbox_gw');
      expect(savedInbox.protocol, AIProtocolType.openAICompatible);
      expect(savedInbox.isAnthropicMessagesApi, isFalse);

      // 2. Edit restored Anthropic slug gateway (protocol: null) via moreOptions -> preserves slug, native protocol, and metadata
      await tester.tap(find.byTooltip(l10n.moreOptions).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.edit));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, l10n.configNameField),
        '恢复的 Claude 网关（已重命名）',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.save));
      await tester.pumpAndSettle();

      final savedRestored = settingsService.multiAISettings.providers
          .firstWhere((p) => p.id == 'p_restored_ant');
      expect(savedRestored.name, '恢复的 Claude 网关（已重命名）');
      expect(savedRestored.providerSlug, 'anthropic');
      expect(savedRestored.protocol, AIProtocolType.anthropicMessages);
      expect(savedRestored.isAnthropicMessagesApi, isTrue);
      expect(savedRestored.modelMetadata?.contextWindow, 200000);
    });

    testWidgets(
        'editor preserves native /v1/messages protocol and metadata on preset-host rename, and detects changed /v1/messages URLs on preset hosts',
        (tester) async {
      AIConnectionTester.testOverrideForTesting = null;
      await APIKeyManager()
          .saveProviderApiKey('p_or_native', 'sk-or-native-1234');
      await APIKeyManager()
          .saveProviderApiKey('p_or_openai', 'sk-or-openai-1234');
      await settingsService.saveMultiAISettings(
        const MultiAISettings(
          providers: [
            AIProviderSettings(
              id: 'p_or_native',
              name: 'OpenRouter 原生 Messages',
              apiUrl: 'https://openrouter.ai/api/v1/messages',
              model: 'anthropic/claude-sonnet-4.5',
              providerSlug: 'openrouter',
              protocol: AIProtocolType.anthropicMessages,
              modelMetadata: AIModelMetadata(
                contextWindow: 200000,
                reasoning: true,
              ),
            ),
            AIProviderSettings(
              id: 'p_or_openai',
              name: 'OpenRouter 标准配置',
              apiUrl: 'https://openrouter.ai/api/v1',
              model: 'anthropic/claude-sonnet-4.5',
              providerSlug: 'openrouter',
              protocol: AIProtocolType.openAICompatible,
              modelMetadata: AIModelMetadata(
                contextWindow: 128000,
                reasoning: false,
              ),
            ),
          ],
          currentProviderId: 'p_or_native',
        ),
      );

      addTearDown(() => AIConnectionTester.testOverrideForTesting = null);

      await tester.pumpWidget(_wrap(settingsService, memoryService));
      await tester.pumpAndSettle();
      await _openServiceConfig(tester);

      final l10n = _l10n(tester);
      final expectedUnsupportedMsg = l10n.connectionTestFailed(
        l10n.aiUnsupportedAnthropicMessagesProtocol,
      );

      // 1. Rename restored OpenRouter /v1/messages provider -> Test Connection shows guidance, Save preserves protocol & metadata
      await tester.tap(find.text('OpenRouter 原生 Messages'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, l10n.configNameField),
        'OpenRouter 原生 Messages（已重命名）',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.testConnectionButton));
      await tester.pumpAndSettle();
      expect(find.text(expectedUnsupportedMsg), findsOneWidget);

      await tester.tap(find.text(l10n.save));
      await tester.pumpAndSettle();

      final renamedNative = settingsService.multiAISettings.providers
          .firstWhere((p) => p.id == 'p_or_native');
      expect(renamedNative.name, 'OpenRouter 原生 Messages（已重命名）');
      expect(renamedNative.providerSlug, 'openrouter');
      expect(renamedNative.protocol, AIProtocolType.anthropicMessages);
      expect(renamedNative.isAnthropicMessagesApi, isTrue);
      expect(renamedNative.modelMetadata?.contextWindow, 200000);
      expect(renamedNative.modelMetadata?.reasoning, isTrue);

      // 2. Change OpenRouter OpenAI provider URL to /v1/messages -> classified as native Messages, clears stale metadata
      ScaffoldMessenger.of(
        tester.element(find.byType(AIServiceConfigPage)),
      ).clearSnackBars();
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip(l10n.moreOptions).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.edit));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, l10n.apiUrlField),
        'https://openrouter.ai/api/v1/messages',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.testConnectionButton));
      await tester.pumpAndSettle();
      expect(find.text(expectedUnsupportedMsg), findsOneWidget);

      await tester.tap(find.text(l10n.save));
      await tester.pumpAndSettle();

      final switchedToNative = settingsService.multiAISettings.providers
          .firstWhere((p) => p.id == 'p_or_openai');
      expect(switchedToNative.providerSlug, 'openrouter');
      expect(switchedToNative.protocol, AIProtocolType.anthropicMessages);
      expect(switchedToNative.isAnthropicMessagesApi, isTrue);
      expect(switchedToNative.modelMetadata, isNull);
      expect(
        settingsService.multiAISettings.currentProviderId,
        'p_or_native',
      );

      // 3. Follow guidance and switch /v1/messages back to /api/v1 -> transitions cleanly to OpenAI-compatible
      final testedDrafts = <AIProviderSettings>[];
      AIConnectionTester.testOverrideForTesting = ({
        required AIProviderSettings provider,
        required String systemPrompt,
        required String userMessage,
        Duration timeout = const Duration(seconds: 30),
      }) async {
        final config = OpenAIStreamService.buildOpenAIConfig(provider);
        expect(config.baseUrl, 'https://openrouter.ai/api/v1');
        testedDrafts.add(provider);
        return 'pong';
      };

      ScaffoldMessenger.of(
        tester.element(find.byType(AIServiceConfigPage)),
      ).clearSnackBars();
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip(l10n.moreOptions).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.edit));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, l10n.apiUrlField),
        'https://openrouter.ai/api/v1',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.testConnectionButton));
      await tester.pumpAndSettle();
      expect(testedDrafts, hasLength(1));
      expect(testedDrafts.single.protocol, AIProtocolType.openAICompatible);
      expect(testedDrafts.single.providerSlug, 'openrouter');
      expect(find.text(l10n.connectionTestSuccess), findsOneWidget);

      await tester.tap(find.text(l10n.save));
      await tester.pumpAndSettle();

      final switchedBackToOpenAI = settingsService.multiAISettings.providers
          .firstWhere((p) => p.id == 'p_or_openai');
      expect(switchedBackToOpenAI.protocol, AIProtocolType.openAICompatible);
      expect(switchedBackToOpenAI.providerSlug, 'openrouter');
      expect(switchedBackToOpenAI.isAnthropicMessagesApi, isFalse);
      expect(
        settingsService.multiAISettings.currentProviderId,
        'p_or_native',
      );
    });

    testWidgets(
        'editing the light provider preserves both currentProviderId and lightProviderId',
        (tester) async {
      await APIKeyManager().saveProviderApiKey('p_primary', 'sk-primary-1234');
      await APIKeyManager().saveProviderApiKey('p_light', 'sk-light-123456');
      await settingsService.saveMultiAISettings(
        const MultiAISettings(
          providers: [
            AIProviderSettings(
              id: 'p_primary',
              name: '主力旗舰服务',
              apiUrl: 'https://api.deepseek.com/v1',
              model: 'deepseek-reasoner',
            ),
            AIProviderSettings(
              id: 'p_light',
              name: '轻量快速服务',
              apiUrl: 'https://open.bigmodel.cn/api/paas/v4',
              model: 'glm-4-flash',
            ),
          ],
          currentProviderId: 'p_primary',
          routingMode: AIRoutingMode.tiered,
          lightProviderId: 'p_light',
        ),
      );

      await tester.pumpWidget(_wrap(settingsService, memoryService));
      await tester.pumpAndSettle();
      await _openServiceConfig(tester);

      final l10n = _l10n(tester);
      await tester.tap(find.byTooltip(l10n.moreOptions).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.edit));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, l10n.modelNameField),
        'glm-4.5-flash',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.save));
      await tester.pumpAndSettle();

      expect(settingsService.multiAISettings.currentProviderId, 'p_primary');
      expect(settingsService.multiAISettings.lightProviderId, 'p_light');
      expect(
        settingsService.multiAISettings.lightProvider?.model,
        'glm-4.5-flash',
      );
    });

    testWidgets(
        'AISettingsPage orders feature switches and memory options per hierarchy spec',
        (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await settingsService.setAgentMemoryEnabled(true);
      await settingsService.setDreamingEnabled(true);

      await tester.pumpWidget(_wrap(settingsService, memoryService));
      await tester.pumpAndSettle();

      final l10n = _l10n(tester);

      final entrySectionY =
          tester.getTopLeft(find.text(l10n.aiServiceEntrySectionTitle)).dy;
      final featuresSectionY =
          tester.getTopLeft(find.text(l10n.aiFeaturesSectionTitle)).dy;
      final memorySectionY =
          tester.getTopLeft(find.text(l10n.agentMemorySectionTitle)).dy;
      expect(entrySectionY, lessThan(featuresSectionY));
      expect(featuresSectionY, lessThan(memorySectionY));

      // AI feature switches: 今日思考使用 AI -> 周期报告洞察使用 AI -> AI 卡片生成
      final dailySwitchY =
          tester.getTopLeft(find.text(l10n.todayThoughtsUseAi)).dy;
      final reportSwitchY =
          tester.getTopLeft(find.text(l10n.reportInsightsUseAi)).dy;
      final cardSwitchY =
          tester.getTopLeft(find.text(l10n.aiCardGeneration)).dy;
      expect(dailySwitchY, lessThan(reportSwitchY));
      expect(reportSwitchY, lessThan(cardSwitchY));

      // Thoughter memory options: 长期记忆 -> 称呼 -> 查看与管理记忆 -> 自动整理记忆 (+子开关) -> 清空记忆
      final memEnableY =
          tester.getTopLeft(find.text(l10n.agentMemoryEnableTitle)).dy;
      final nicknameY =
          tester.getTopLeft(find.text(l10n.agentMemoryNicknameTitle)).dy;
      final manageY =
          tester.getTopLeft(find.text(l10n.agentMemoryManageTitle)).dy;
      final dreamEnableY =
          tester.getTopLeft(find.text(l10n.dreamingEnableTitle)).dy;
      final dreamIdleY =
          tester.getTopLeft(find.text(l10n.dreamingOnIdleTitle)).dy;
      final dreamAfterInsightY =
          tester.getTopLeft(find.text(l10n.dreamingAfterInsightTitle)).dy;
      final clearY =
          tester.getTopLeft(find.text(l10n.agentMemoryClearTitle)).dy;

      expect(memEnableY, lessThan(nicknameY));
      expect(nicknameY, lessThan(manageY));
      expect(manageY, lessThan(dreamEnableY));
      expect(dreamEnableY, lessThan(dreamIdleY));
      expect(dreamIdleY, lessThan(dreamAfterInsightY));
      expect(dreamAfterInsightY, lessThan(clearY));
    });

    testWidgets(
        'AISettingsPage entry card reflects default, tiered light, and custom routing summaries',
        (tester) async {
      await settingsService.saveMultiAISettings(
        const MultiAISettings(
          providers: [
            AIProviderSettings(
              id: 'p_main',
              name: '主力服务',
              apiUrl: 'https://api.openai.com/v1',
              model: 'gpt-4o',
            ),
            AIProviderSettings(
              id: 'p_light',
              name: '轻量服务',
              apiUrl: 'https://open.bigmodel.cn/api/paas/v4',
              model: 'glm-4-flash',
            ),
          ],
          currentProviderId: 'p_main',
          routingMode: AIRoutingMode.tiered,
        ),
      );

      await tester.pumpWidget(_wrap(settingsService, memoryService));
      await tester.pumpAndSettle();
      final l10n = _l10n(tester);

      expect(find.text('主力服务 · gpt-4o'), findsOneWidget);
      expect(find.text(l10n.aiServiceEntrySummaryDefault), findsOneWidget);

      await settingsService.saveMultiAISettings(
        settingsService.multiAISettings.copyWith(lightProviderId: 'p_light'),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(l10n.aiServiceEntrySummaryTieredLight('轻量服务')),
        findsOneWidget,
      );

      await settingsService.saveMultiAISettings(
        settingsService.multiAISettings.copyWith(
          routingMode: AIRoutingMode.custom,
          taskProviderIds: const {
            AITask.dailyInsight: 'p_light',
            AITask.sessionTitle: 'p_light',
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(l10n.aiServiceEntrySummaryCustom(2)),
        findsOneWidget,
      );
    });

    testWidgets(
        'AIServiceConfigPage tiered mode binds light model, shows single light badge, pre-fills custom mode on first switch, and cleans up on delete',
        (tester) async {
      await APIKeyManager().saveProviderApiKey('p_main', 'sk-main-123456');
      await APIKeyManager().saveProviderApiKey('p_light', 'sk-light-123456');
      await settingsService.saveMultiAISettings(
        const MultiAISettings(
          providers: [
            AIProviderSettings(
              id: 'p_main',
              name: '主力服务',
              apiUrl: 'https://api.openai.com/v1',
              model: 'gpt-4o',
            ),
            AIProviderSettings(
              id: 'p_light',
              name: '轻量服务',
              apiUrl: 'https://open.bigmodel.cn/api/paas/v4',
              model: 'glm-4-flash',
            ),
          ],
          currentProviderId: 'p_main',
          routingMode: AIRoutingMode.tiered,
        ),
      );

      await tester.pumpWidget(_wrap(settingsService, memoryService));
      await tester.pumpAndSettle();
      await _openServiceConfig(tester);
      final l10n = _l10n(tester);

      expect(
        find.byKey(const ValueKey('ai_tiered_routing_card')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('ai_task_routing_card')),
        findsNothing,
      );

      // Select p_light for the light tier
      final lightTile = find.byKey(const ValueKey('ai_tier_light_tile'));
      await _scrollTo(tester, lightTile);
      await tester.tap(lightTile);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('ai_light_option_p_light')));
      await tester.pumpAndSettle();

      expect(settingsService.multiAISettings.lightProviderId, 'p_light');

      // Scroll up to check single light badge on p_light without 6 task badges
      await tester.scrollUntilVisible(
        find.text('轻量服务'),
        -200,
        scrollable: find
            .descendant(
              of: find.byType(AIServiceConfigPage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('provider_light_badge_p_light')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('provider_task_badge_p_light_dailyInsight')),
        findsNothing,
      );

      // Switch to custom mode -> pre-fills the 3 light tasks
      await _scrollTo(tester, find.text(l10n.aiRoutingModeCustom));
      await tester.tap(find.text(l10n.aiRoutingModeCustom));
      await tester.pumpAndSettle();

      final customSettings = settingsService.multiAISettings;
      expect(customSettings.routingMode, AIRoutingMode.custom);
      expect(customSettings.taskProviderIds[AITask.dailyInsight], 'p_light');
      expect(customSettings.taskProviderIds[AITask.periodicInsight], 'p_light');
      expect(customSettings.taskProviderIds[AITask.sessionTitle], 'p_light');
      expect(customSettings.taskProviderIds.containsKey(AITask.agent), isFalse);
      expect(
        customSettings.taskProviderIds.containsKey(AITask.dreaming),
        isFalse,
      );
      expect(
        customSettings.taskProviderIds.containsKey(AITask.cardGeneration),
        isFalse,
      );

      // Switch back to tiered mode and delete p_light -> cleans up lightProviderId & taskProviderIds
      await _scrollTo(tester, find.text(l10n.aiRoutingModeTiered));
      await tester.tap(find.text(l10n.aiRoutingModeTiered));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('轻量服务'),
        -200,
        scrollable: find
            .descendant(
              of: find.byType(AIServiceConfigPage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip(l10n.moreOptions).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.delete));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, l10n.delete));
      await tester.pumpAndSettle();

      expect(settingsService.multiAISettings.lightProviderId, isNull);
      expect(settingsService.multiAISettings.taskProviderIds, isEmpty);
    });

    testWidgets(
        'AIServiceConfigPage switches primary service on provider tile tap and via primary model picker, and opens UserGuidePage',
        (tester) async {
      await APIKeyManager().saveProviderApiKey('p_main', 'sk-main-123456');
      await APIKeyManager().saveProviderApiKey('p_second', 'sk-second-123456');
      await settingsService.saveMultiAISettings(
        const MultiAISettings(
          providers: [
            AIProviderSettings(
              id: 'p_main',
              name: '服务甲',
              apiUrl: 'https://api.openai.com/v1',
              model: 'gpt-4o',
            ),
            AIProviderSettings(
              id: 'p_second',
              name: '服务乙',
              apiUrl: 'https://api.deepseek.com/v1',
              model: 'deepseek-chat',
            ),
          ],
          currentProviderId: 'p_main',
          routingMode: AIRoutingMode.tiered,
        ),
      );

      await tester.pumpWidget(_wrap(settingsService, memoryService));
      await tester.pumpAndSettle();
      await _openServiceConfig(tester);
      final l10n = _l10n(tester);

      // 1. Tap non-current provider tile -> directly switches primary service
      await tester.tap(find.byKey(const ValueKey('ai_provider_tile_p_second')));
      await tester.pumpAndSettle();

      expect(settingsService.multiAISettings.currentProviderId, 'p_second');
      expect(find.text(l10n.switchedTo('服务乙')), findsOneWidget);

      ScaffoldMessenger.of(
        tester.element(find.byType(AIServiceConfigPage)),
      ).clearSnackBars();
      await tester.pumpAndSettle();

      // 2. Tap primary model tile in Model Assignment -> switches back to p_main
      final primaryTile = find.byKey(const ValueKey('ai_tier_primary_tile'));
      await _scrollTo(tester, primaryTile);
      await tester.tap(primaryTile);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('ai_primary_option_p_main')));
      await tester.pumpAndSettle();

      expect(settingsService.multiAISettings.currentProviderId, 'p_main');
      expect(find.text(l10n.switchedTo('服务甲')), findsOneWidget);

      ScaffoldMessenger.of(
        tester.element(find.byType(AIServiceConfigPage)),
      ).clearSnackBars();
      await tester.pumpAndSettle();

      // 3. Tap setup guide link -> navigates to UserGuidePage
      final helpBtn = find.text(l10n.aiConfigHelpLink);
      await _scrollTo(tester, helpBtn);
      await tester.tap(helpBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(UserGuidePage), findsOneWidget);
    });
  });
}
