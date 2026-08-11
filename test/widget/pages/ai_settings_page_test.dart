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
  await tester.scrollUntilVisible(
    target,
    200,
    scrollable: find
        .descendant(
          of: find.byType(AISettingsPage),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
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
  });
}
