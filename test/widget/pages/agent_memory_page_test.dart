import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/models/agent_memory.dart';
import 'package:thoughtecho/models/note_tag.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/pages/agent_memory/agent_memory_page.dart';
import 'package:thoughtecho/pages/ai_settings_page.dart';
import 'package:thoughtecho/services/agent_memory_service.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/theme/app_semantic_colors.dart';
import 'package:thoughtecho/theme/theme_style.dart';
import 'package:thoughtecho/utils/aptabase_helper.dart';
import 'package:thoughtecho/widgets/app_loading_view.dart';

import '../../test_harness.dart';

class _FakeDatabaseService extends ChangeNotifier
    with Fake
    implements DatabaseService {
  final Map<String, Quote> quotes = {};

  @override
  Future<Quote?> getQuoteById(String id, {bool includeDeleted = false}) async {
    return quotes[id];
  }

  @override
  Future<List<NoteTag>> getTags() async => const [];
}

class _TrackingAgentMemoryService extends AgentMemoryService {
  _TrackingAgentMemoryService({
    required super.settingsService,
    super.databasePath,
  });

  int allProfileEntriesCalls = 0;
  int activeRecentSlicesCalls = 0;
  int allFactsCalls = 0;
  Completer<void>? onAllProfileEntriesCompleter;

  @override
  Future<List<AgentMemoryProfileEntry>> allProfileEntries() async {
    allProfileEntriesCalls++;
    if (onAllProfileEntriesCompleter != null) {
      await onAllProfileEntriesCompleter!.future;
    }
    return super.allProfileEntries();
  }

  @override
  Future<List<AgentMemoryRecentSlice>> activeRecentSlices({
    DateTime? now,
    int limit = AgentMemoryRecentSlice.maxRecentSlices,
  }) {
    activeRecentSlicesCalls++;
    return super.activeRecentSlices(now: now, limit: limit);
  }

  @override
  Future<List<AgentMemoryFact>> allFacts({
    int limit = AgentMemoryService.factsCapacity,
    String? query,
  }) {
    allFactsCalls++;
    return super.allFacts(limit: limit, query: query);
  }
}

Widget _buildWrapper({
  required Widget child,
  required SettingsService settingsService,
  required AgentMemoryService memoryService,
  DatabaseService? databaseService,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<SettingsService>.value(value: settingsService),
      ChangeNotifierProvider<AgentMemoryService>.value(value: memoryService),
      if (databaseService != null)
        ChangeNotifierProvider<DatabaseService>.value(value: databaseService),
    ],
    child: MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(
        useMaterial3: true,
        extensions: [
          AppShapeTokens.fromForm(ThemeStyleForm.material, Brightness.light),
          AppSemanticColors.light,
        ],
      ),
      home: child,
    ),
  );
}

const _secureStorageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

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

/// 辅助等待异步数据库 I/O 并在 FakeAsync 时钟中完成渲染沉降。
Future<void> _settleWithRealAsync(
  WidgetTester tester, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pump();
    if (find.byType(AppLoadingView).evaluate().isEmpty &&
        find.byType(CircularProgressIndicator).evaluate().isEmpty) {
      break;
    }
  }
  await tester.pumpAndSettle();
}

/// 辅助等待特定组件渲染出现。
Future<void> _waitForWidget(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
}

/// 辅助等待特定组件从渲染树中消失。
Future<void> _waitForWidgetGone(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isEmpty) {
      return;
    }
  }
}

void _setLargeSurfaceSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('AgentMemoryPage 长期记忆管理页面测试', () {
    late SettingsService settingsService;
    late AgentMemoryService memoryService;
    late _FakeDatabaseService fakeDb;

    setUp(() async {
      await TestHarness.initialize();
      _installSecureStorageFake();
      settingsService = await SettingsService.create();
      await settingsService.setAgentMemoryEnabled(true);
      await settingsService.setUserNickname('阿澈');

      memoryService = _TrackingAgentMemoryService(
        settingsService: settingsService,
        databasePath: inMemoryDatabasePath,
      );
      // 先在 fake-async 之外把库打开
      await memoryService.counts();
      fakeDb = _FakeDatabaseService();
    });

    tearDown(() async {
      await memoryService.clearAll();
      memoryService.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_secureStorageChannel, null);
      await TestHarness.tearDown();
    });

    testWidgets('渲染概览卡片与记忆列表', (tester) async {
      _setLargeSurfaceSize(tester);
      await tester.runAsync(() async {
        await memoryService.rememberProfile(
          kind: AgentMemoryKind.voice,
          directive: '回复保持碎句与哲思留白',
          source: 'dreaming',
        );
        await memoryService.saveRecentSlice(
          content: '最近在准备系统架构师考试',
          ttl: const Duration(days: 10),
        );
        await memoryService.addFact(
          content: '偏好阅读博尔赫斯',
          importance: 8,
          category: '文学',
        );
      });

      await tester.pumpWidget(
        _buildWrapper(
          child: const AgentMemoryPage(),
          settingsService: settingsService,
          memoryService: memoryService,
          databaseService: fakeDb,
        ),
      );
      await _settleWithRealAsync(tester);

      // 验证概览卡片呈现昵称、标题与统计摘要
      expect(find.text('Thoughter 记忆'), findsWidgets);
      expect(find.text('阿澈'), findsOneWidget);
      expect(find.text('共 1 条画像 · 1 条近况 · 1 条细节'), findsOneWidget);

      // 验证不含容量进度条与无病呻吟的修饰文案
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.text('容量充足，对话与灵感畅通'), findsNothing);

      // 验证不含手动添加浮动按钮
      expect(find.byType(FloatingActionButton), findsNothing);

      // 验证条目内容展示
      expect(find.text('回复保持碎句与哲思留白'), findsOneWidget);
      expect(find.text('最近在准备系统架构师考试'), findsOneWidget);
      expect(find.text('偏好阅读博尔赫斯'), findsOneWidget);

      // 验证分类胶囊
      expect(find.text('写作声音'), findsOneWidget);
      expect(find.text('近期状态'), findsWidgets);
      expect(find.text('文学'), findsOneWidget);
    });

    testWidgets('分类过滤 Chips 正确切换条目展示', (tester) async {
      _setLargeSurfaceSize(tester);
      await tester.runAsync(() async {
        await memoryService.rememberProfile(
          kind: AgentMemoryKind.style,
          directive: '喜欢幽默轻快的对话语气',
        );
        await memoryService.saveRecentSlice(
          content: '正在规划去云南旅行',
        );
        await memoryService.addFact(
          content: '常听巴赫的管风琴曲',
        );
      });

      await tester.pumpWidget(
        _buildWrapper(
          child: const AgentMemoryPage(),
          settingsService: settingsService,
          memoryService: memoryService,
          databaseService: fakeDb,
        ),
      );
      await _settleWithRealAsync(tester);

      // 切换到「画像特质」
      await tester.tap(find.text('画像特质 (1)'));
      await _settleWithRealAsync(tester);

      expect(find.text('喜欢幽默轻快的对话语气'), findsOneWidget);
      expect(find.text('正在规划去云南旅行'), findsNothing);
      expect(find.text('常听巴赫的管风琴曲'), findsNothing);

      // 切换到「近期状态」
      await tester.tap(find.text('近期状态 (1)'));
      await _settleWithRealAsync(tester);

      expect(find.text('喜欢幽默轻快的对话语气'), findsNothing);
      expect(find.text('正在规划去云南旅行'), findsOneWidget);
      expect(find.text('常听巴赫的管风琴曲'), findsNothing);

      // 切换到「记忆细节」
      await tester.tap(find.text('记忆细节 (1)'));
      await _settleWithRealAsync(tester);

      expect(find.text('常听巴赫的管风琴曲'), findsOneWidget);
      expect(find.text('喜欢幽默轻快的对话语气'), findsNothing);
    });

    testWidgets('搜索框实时过滤特质与事实', (tester) async {
      _setLargeSurfaceSize(tester);
      await tester.runAsync(() async {
        await memoryService.rememberProfile(
          kind: AgentMemoryKind.identity,
          directive: '是一名资深软件工程师',
        );
        await memoryService.rememberProfile(
          kind: AgentMemoryKind.preference,
          directive: '早晨只喝黑咖啡',
        );
      });

      await tester.pumpWidget(
        _buildWrapper(
          child: const AgentMemoryPage(),
          settingsService: settingsService,
          memoryService: memoryService,
          databaseService: fakeDb,
        ),
      );
      await _settleWithRealAsync(tester);

      expect(find.text('是一名资深软件工程师'), findsOneWidget);
      expect(find.text('早晨只喝黑咖啡'), findsOneWidget);

      // 验证搜索与更多选项按钮的 tooltip
      expect(find.byTooltip('搜索'), findsOneWidget);
      expect(find.byTooltip('更多选项'), findsOneWidget);

      // 点击搜索按钮打开搜索输入框
      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();

      // 验证激活搜索后按钮变为取消提示
      expect(find.byTooltip('取消'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '咖啡');
      await _waitForWidgetGone(tester, find.text('是一名资深软件工程师'));

      expect(find.text('早晨只喝黑咖啡'), findsOneWidget);
      expect(find.text('是一名资深软件工程师'), findsNothing);
    });

    testWidgets('原位编辑画像指令并持久化', (tester) async {
      _setLargeSurfaceSize(tester);
      late final AgentMemoryProfileEntry entry;
      await tester.runAsync(() async {
        entry = await memoryService.rememberProfile(
          kind: AgentMemoryKind.voice,
          directive: '回复保持碎句',
        );
      });

      await tester.pumpWidget(
        _buildWrapper(
          child: const AgentMemoryPage(),
          settingsService: settingsService,
          memoryService: memoryService,
          databaseService: fakeDb,
        ),
      );
      await _settleWithRealAsync(tester);

      // 点击编辑按钮
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();

      // 修改指令文本
      await tester.enterText(
        find.byType(TextField),
        '回复保持自然舒展，无需刻意断句',
      );
      await tester.tap(find.text('保存修正'));
      await _waitForWidgetGone(tester, find.byType(EditableText));
      await _waitForWidget(tester, find.text('回复保持自然舒展，无需刻意断句'));

      // 验证界面与数据库均已更新
      expect(find.text('回复保持自然舒展，无需刻意断句'), findsOneWidget);
      await tester.runAsync(() async {
        final active = await memoryService.activeProfile();
        expect(active.first.id, entry.id);
        expect(active.first.directive, '回复保持自然舒展，无需刻意断句');
      });
    });

    testWidgets('确认遗忘单条画像条目', (tester) async {
      _setLargeSurfaceSize(tester);
      await tester.runAsync(() async {
        await memoryService.rememberProfile(
          kind: AgentMemoryKind.preference,
          directive: '不想被提起高数相关的话题',
        );
      });

      await tester.pumpWidget(
        _buildWrapper(
          child: const AgentMemoryPage(),
          settingsService: settingsService,
          memoryService: memoryService,
          databaseService: fakeDb,
        ),
      );
      await _settleWithRealAsync(tester);

      expect(find.text('不想被提起高数相关的话题'), findsOneWidget);

      // 点击遗忘按钮
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      // 弹窗确认
      expect(find.text('让 Thoughter 忘掉这条？'), findsOneWidget);
      await tester.tap(find.text('忘掉'));
      await _waitForWidgetGone(tester, find.byType(AlertDialog));
      await _waitForWidgetGone(tester, find.text('不想被提起高数相关的话题'));

      // 验证已从活跃列表移除
      expect(find.text('不想被提起高数相关的话题'), findsNothing);
      await tester.runAsync(() async {
        final active = await memoryService.activeProfile();
        expect(active, isEmpty);
      });
    });

    testWidgets('来源归因展示：卡片底部呈现关联笔记数量且无需预览抽屉', (tester) async {
      _setLargeSurfaceSize(tester);
      fakeDb.quotes['quote-1'] = Quote(
        id: 'quote-1',
        content: '树叶在林间细语，阳光穿过枝丫落在长椅上。',
        date: '2026-08-15',
        sourceAuthor: '史铁生',
      );

      await tester.runAsync(() async {
        await memoryService.rememberProfile(
          kind: AgentMemoryKind.taste,
          directive: '钟爱自然与光影意象的散文摘录',
          sourceNoteIds: const ['quote-1'],
          source: 'dreaming',
        );
      });

      await tester.pumpWidget(
        _buildWrapper(
          child: const AgentMemoryPage(),
          settingsService: settingsService,
          memoryService: memoryService,
          databaseService: fakeDb,
        ),
      );
      await _settleWithRealAsync(tester);

      // 验证底部元信息包含关联笔记数量，且不弹出抽屉
      expect(find.text('·  关联 1 篇笔记'), findsOneWidget);
      expect(find.text('树叶在林间细语，阳光穿过枝丫落在长椅上。'), findsNothing);
    });

    testWidgets('更多菜单支持触发整理记忆', (tester) async {
      _setLargeSurfaceSize(tester);
      await tester.runAsync(() async {
        await memoryService.saveRecentSlice(
          content: '过期的临时切片',
          ttl: const Duration(days: -1),
        );
      });

      await tester.pumpWidget(
        _buildWrapper(
          child: const AgentMemoryPage(),
          settingsService: settingsService,
          memoryService: memoryService,
          databaseService: fakeDb,
        ),
      );
      await _settleWithRealAsync(tester);

      // 点击右上角更多菜单
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      // 点击整理记忆
      await tester.tap(find.text('整理记忆'));
      await tester.pumpAndSettle();

      // 弹窗确认
      expect(find.text('将自动清理已过期的近期状态、过时的历史画像与低权重细节。是否继续？'), findsOneWidget);
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();

      // 验证清理完成并刷新
      expect(find.text('过期的临时切片'), findsNothing);
    });

    testWidgets('AISettingsPage 包含「管理记忆」入口并可点击跳转', (tester) async {
      _setLargeSurfaceSize(tester);
      await tester.runAsync(() async {
        await memoryService.rememberProfile(
          kind: AgentMemoryKind.identity,
          directive: '测试画像',
        );
      });

      await tester.pumpWidget(
        _buildWrapper(
          child: const AISettingsPage(),
          settingsService: settingsService,
          memoryService: memoryService,
          databaseService: fakeDb,
        ),
      );
      await _settleWithRealAsync(tester);

      final manageTile = find.text('管理记忆');
      expect(manageTile, findsOneWidget);
      expect(find.text('查看、纠偏与管理 Thoughter 记下的特质与依据'), findsOneWidget);

      await tester.tap(manageTile);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await _settleWithRealAsync(tester);

      // 跳转到了 AgentMemoryPage
      expect(find.byType(AgentMemoryPage), findsOneWidget);
    });

    testWidgets('搜索框输入触发 agent_memory_search 匿名遥测并支持 300ms 防抖', (tester) async {
      final trackedEvents = <Map<String, dynamic>>[];
      AptabaseHelper.onTrackEventForTesting = (eventName, props) {
        trackedEvents.add({
          'eventName': eventName,
          'props': props,
        });
      };
      addTearDown(() => AptabaseHelper.onTrackEventForTesting = null);

      _setLargeSurfaceSize(tester);
      await tester.pumpWidget(
        _buildWrapper(
          child: const AgentMemoryPage(),
          settingsService: settingsService,
          memoryService: memoryService,
          databaseService: fakeDb,
        ),
      );
      await _settleWithRealAsync(tester);

      // 点击搜索按钮打开搜索框
      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();

      // 输入第一个字：防抖时间内不应立即触发遥测
      await tester.enterText(find.byType(TextField), '架');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(
        trackedEvents.where((e) => e['eventName'] == 'agent_memory_search'),
        isEmpty,
      );

      // 继续输入第二个字：重置防抖计时器
      await tester.enterText(find.byType(TextField), '架构');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(
        trackedEvents.where((e) => e['eventName'] == 'agent_memory_search'),
        isEmpty,
      );

      // 防抖时间到期后触发一次遥测
      await tester.pump(const Duration(milliseconds: 200));
      final searchEvents = trackedEvents
          .where((e) => e['eventName'] == 'agent_memory_search')
          .toList();
      expect(searchEvents, hasLength(1));
      // 绝不上报搜索内容
      expect(searchEvents.first['props'], isNull);

      // 再次输入发起新的搜索（启动防抖计时器）
      await tester.enterText(find.byType(TextField), '架构师');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 在防抖计时器未到期时清空输入为 ""，此时应立即取消 pending 的计时器
      await tester.enterText(find.byType(TextField), '');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(
        trackedEvents.where((e) => e['eventName'] == 'agent_memory_search'),
        hasLength(1),
      );

      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 30));
        });
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
    });

    testWidgets('搜索框输入未过防抖时间即关闭搜索时不触发 agent_memory_search 遥测', (tester) async {
      final trackedEvents = <Map<String, dynamic>>[];
      AptabaseHelper.onTrackEventForTesting = (eventName, props) {
        trackedEvents.add({
          'eventName': eventName,
          'props': props,
        });
      };
      addTearDown(() => AptabaseHelper.onTrackEventForTesting = null);

      _setLargeSurfaceSize(tester);
      await tester.pumpWidget(
        _buildWrapper(
          child: const AgentMemoryPage(),
          settingsService: settingsService,
          memoryService: memoryService,
          databaseService: fakeDb,
        ),
      );
      await _settleWithRealAsync(tester);

      // 打开搜索并输入
      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '临时输入');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 在防抖未触发时点击取消关闭搜索框
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 30));
        });
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();

      expect(
        trackedEvents.where((e) => e['eventName'] == 'agent_memory_search'),
        isEmpty,
      );
    });

    testWidgets('高频快速输入时防抖抑制中间异步查询与埋点，仅最后一次生效', (tester) async {
      final trackedEvents = <Map<String, dynamic>>[];
      AptabaseHelper.onTrackEventForTesting = (eventName, props) {
        trackedEvents.add({
          'eventName': eventName,
          'props': props,
        });
      };
      addTearDown(() => AptabaseHelper.onTrackEventForTesting = null);

      _setLargeSurfaceSize(tester);
      await tester.runAsync(() async {
        await memoryService.rememberProfile(
          kind: AgentMemoryKind.identity,
          directive: '精通跨平台架构设计',
        );
        await memoryService.rememberProfile(
          kind: AgentMemoryKind.preference,
          directive: '喜好浅色主题与极简排版',
        );
        await memoryService.addFact(
          content: '常读操作系统底层原理',
        );
      });

      await tester.pumpWidget(
        _buildWrapper(
          child: const AgentMemoryPage(),
          settingsService: settingsService,
          memoryService: memoryService,
          databaseService: fakeDb,
        ),
      );
      await _settleWithRealAsync(tester);

      expect(find.text('精通跨平台架构设计'), findsOneWidget);
      expect(find.text('喜好浅色主题与极简排版'), findsOneWidget);
      expect(find.text('常读操作系统底层原理'), findsOneWidget);

      final trackingService = memoryService as _TrackingAgentMemoryService;
      final initialFactCalls = trackingService.allFactsCalls;

      // 打开搜索框
      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();

      // 高频连续输入：第 1 次输入 '架'
      await tester.enterText(find.byType(TextField), '架');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 高频连续输入：第 2 次输入 '架构'
      await tester.enterText(find.byType(TextField), '架构');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 高频连续输入：第 3 次输入 '极简'
      await tester.enterText(find.byType(TextField), '极简');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 在 300ms 防抖未到期前：未发起新的数据库查询，旧条目依然全部展示，无遥测
      expect(trackingService.allFactsCalls, equals(initialFactCalls));
      expect(find.text('精通跨平台架构设计'), findsOneWidget);
      expect(find.text('喜好浅色主题与极简排版'), findsOneWidget);
      expect(find.text('常读操作系统底层原理'), findsOneWidget);
      expect(
        trackedEvents.where((e) => e['eventName'] == 'agent_memory_search'),
        isEmpty,
      );

      // 防抖到期后（300ms）：仅最后一次输入触发异步查询与埋点
      await tester.pump(const Duration(milliseconds: 250));
      await _waitForWidgetGone(tester, find.text('精通跨平台架构设计'));
      await _waitForWidgetGone(tester, find.text('常读操作系统底层原理'));

      // 验证仅触发了一次遥测
      final searchEvents = trackedEvents
          .where((e) => e['eventName'] == 'agent_memory_search')
          .toList();
      expect(searchEvents, hasLength(1));
      expect(searchEvents.first['props'], isNull);

      // 验证仅最后一次生效，页面展示仅匹配 '极简' 的条目
      expect(find.text('喜好浅色主题与极简排版'), findsOneWidget);
      expect(find.text('精通跨平台架构设计'), findsNothing);
      expect(find.text('常读操作系统底层原理'), findsNothing);
    });

    testWidgets('防抖期内快速清空输入框立即取消待执行任务并即时刷新全部条目', (tester) async {
      final trackedEvents = <Map<String, dynamic>>[];
      AptabaseHelper.onTrackEventForTesting = (eventName, props) {
        trackedEvents.add({
          'eventName': eventName,
          'props': props,
        });
      };
      addTearDown(() => AptabaseHelper.onTrackEventForTesting = null);

      _setLargeSurfaceSize(tester);
      await tester.runAsync(() async {
        await memoryService.rememberProfile(
          kind: AgentMemoryKind.identity,
          directive: '资深全栈工程师',
        );
        await memoryService.rememberProfile(
          kind: AgentMemoryKind.preference,
          directive: '只喝意式浓缩咖啡',
        );
      });

      await tester.pumpWidget(
        _buildWrapper(
          child: const AgentMemoryPage(),
          settingsService: settingsService,
          memoryService: memoryService,
          databaseService: fakeDb,
        ),
      );
      await _settleWithRealAsync(tester);

      // 打开搜索框
      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();

      // 先输入并让防抖生效过滤到只剩咖啡
      await tester.enterText(find.byType(TextField), '咖啡');
      await tester.pump(const Duration(milliseconds: 350));
      await _waitForWidgetGone(tester, find.text('资深全栈工程师'));
      expect(find.text('只喝意式浓缩咖啡'), findsOneWidget);
      expect(find.text('资深全栈工程师'), findsNothing);
      expect(
        trackedEvents.where((e) => e['eventName'] == 'agent_memory_search'),
        hasLength(1),
      );

      // 输入新的内容 '资深'，防抖期内（100ms）未到期
      await tester.enterText(find.byType(TextField), '资深');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 立即清空输入框为 ''
      await tester.enterText(find.byType(TextField), '');
      await _waitForWidget(tester, find.text('资深全栈工程师'));

      // 验证无需等待 300ms 防抖，即时恢复全部条目
      expect(find.text('资深全栈工程师'), findsOneWidget);
      expect(find.text('只喝意式浓缩咖啡'), findsOneWidget);

      // 即使度过后续 350ms，pending 的任务已被取消，不会有新的遥测产生
      await tester.pump(const Duration(milliseconds: 350));
      expect(
        trackedEvents.where((e) => e['eventName'] == 'agent_memory_search'),
        hasLength(1),
      );
    });

    testWidgets('防抖期内关闭搜索或页面销毁时取消定时器并作废旧请求', (tester) async {
      final trackedEvents = <Map<String, dynamic>>[];
      AptabaseHelper.onTrackEventForTesting = (eventName, props) {
        trackedEvents.add({
          'eventName': eventName,
          'props': props,
        });
      };
      addTearDown(() => AptabaseHelper.onTrackEventForTesting = null);

      _setLargeSurfaceSize(tester);
      await tester.runAsync(() async {
        await memoryService.rememberProfile(
          kind: AgentMemoryKind.identity,
          directive: '全栈开发者',
        );
      });

      await tester.pumpWidget(
        _buildWrapper(
          child: const AgentMemoryPage(),
          settingsService: settingsService,
          memoryService: memoryService,
          databaseService: fakeDb,
        ),
      );
      await _settleWithRealAsync(tester);

      // 1. 测试在防抖期间点击取消/关闭搜索
      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '待作废输入');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 点击关闭图标取消搜索
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      await _settleWithRealAsync(tester);

      // 验证未触发遥测且输入框已关闭
      expect(find.byType(TextField), findsNothing);
      expect(
        trackedEvents.where((e) => e['eventName'] == 'agent_memory_search'),
        isEmpty,
      );

      // 2. 测试在防抖期间销毁页面（dispose）
      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '销毁前输入');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 卸载页面，触发 dispose
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 350));

      // 验证未发生未捕获异常且无多余遥测
      expect(
        trackedEvents.where((e) => e['eventName'] == 'agent_memory_search'),
        isEmpty,
      );
    });

    testWidgets('过时的异步查询请求在返回后命中版本号不匹配并早退中断后续查询', (tester) async {
      _setLargeSurfaceSize(tester);
      await tester.runAsync(() async {
        await memoryService.rememberProfile(
          kind: AgentMemoryKind.identity,
          directive: '资深全栈工程师',
        );
        await memoryService.addFact(content: '熟练掌握并发编程');
      });

      await tester.pumpWidget(
        _buildWrapper(
          child: const AgentMemoryPage(),
          settingsService: settingsService,
          memoryService: memoryService,
          databaseService: fakeDb,
        ),
      );
      await _settleWithRealAsync(tester);

      final trackingService = memoryService as _TrackingAgentMemoryService;
      trackingService.allProfileEntriesCalls = 0;
      trackingService.activeRecentSlicesCalls = 0;
      trackingService.allFactsCalls = 0;

      // 打开搜索框
      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();

      // 设置第一个请求在 allProfileEntries 处被暂停
      final profileCompleter = Completer<void>();
      trackingService.onAllProfileEntriesCompleter = profileCompleter;

      // 触发第 1 个搜索输入并等待防抖触发
      await tester.enterText(find.byType(TextField), '并发');
      await tester.pump(const Duration(milliseconds: 350));
      // 此时第 1 个请求正在 await profileCompleter.future
      expect(trackingService.allProfileEntriesCalls, equals(1));
      expect(trackingService.activeRecentSlicesCalls, equals(0));

      // 快速清空搜索触发第 2 个即时请求，此时 _bundleRequestId 被递增，作废第 1 个请求
      // 清除暂停拦截器让第 2 个请求及后续调用正常通过
      trackingService.onAllProfileEntriesCompleter = null;
      await tester.enterText(find.byType(TextField), '');
      await tester.pump();

      // 现在释放第 1 个请求
      profileCompleter.complete();

      // 等待第 2 个有效请求在 real async 下完成各步骤数据库查询
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 30));
        });
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();

      // 验证第 1 个请求因为版本号不匹配而早退，其后续的 activeRecentSlices 与 allFacts 并未被多余执行
      // 总共只有第 2 个有效请求完整执行了 activeRecentSlices 与 allFacts 各 1 次
      expect(trackingService.activeRecentSlicesCalls, equals(1));
      expect(trackingService.allFactsCalls, equals(1));
    });

    testWidgets('编辑画像指令成功时触发 agent_memory_edit 匿名遥测', (tester) async {
      final trackedEvents = <Map<String, dynamic>>[];
      AptabaseHelper.onTrackEventForTesting = (eventName, props) {
        trackedEvents.add({
          'eventName': eventName,
          'props': props,
        });
      };
      addTearDown(() => AptabaseHelper.onTrackEventForTesting = null);

      _setLargeSurfaceSize(tester);
      await tester.runAsync(() async {
        await memoryService.rememberProfile(
          kind: AgentMemoryKind.style,
          directive: '原始风格指令',
        );
      });

      await tester.pumpWidget(
        _buildWrapper(
          child: const AgentMemoryPage(),
          settingsService: settingsService,
          memoryService: memoryService,
          databaseService: fakeDb,
        ),
      );
      await _settleWithRealAsync(tester);

      // 点击编辑按钮
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();

      // 在对话框中修改指令并保存
      await tester.enterText(find.byType(TextField), '修改后的风格指令');
      await tester.tap(find.text('保存修正'));
      await _waitForWidgetGone(tester, find.byType(EditableText));
      await _settleWithRealAsync(tester);

      final editEvents = trackedEvents
          .where((e) => e['eventName'] == 'agent_memory_edit')
          .toList();
      expect(editEvents, isNotEmpty);
      expect(editEvents.first['props'], equals({'kind': 'style'}));
    });

    testWidgets('确认遗忘画像触发 agent_memory_delete 匿名遥测', (tester) async {
      final trackedEvents = <Map<String, dynamic>>[];
      AptabaseHelper.onTrackEventForTesting = (eventName, props) {
        trackedEvents.add({
          'eventName': eventName,
          'props': props,
        });
      };
      addTearDown(() => AptabaseHelper.onTrackEventForTesting = null);

      _setLargeSurfaceSize(tester);
      await tester.runAsync(() async {
        await memoryService.rememberProfile(
          kind: AgentMemoryKind.taste,
          directive: '偏好冷色调设计',
        );
      });

      await tester.pumpWidget(
        _buildWrapper(
          child: const AgentMemoryPage(),
          settingsService: settingsService,
          memoryService: memoryService,
          databaseService: fakeDb,
        ),
      );
      await _settleWithRealAsync(tester);

      // 点击删除/遗忘按钮
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      // 弹窗确认
      await tester.tap(find.text('忘掉'));
      await _waitForWidgetGone(tester, find.byType(AlertDialog));
      await _settleWithRealAsync(tester);

      final deleteEvents = trackedEvents
          .where((e) => e['eventName'] == 'agent_memory_delete')
          .toList();
      expect(deleteEvents, isNotEmpty);
      expect(
          deleteEvents.first['props'],
          equals({
            'type': 'profile',
            'kind': 'taste',
          }));
    });
  });
}
