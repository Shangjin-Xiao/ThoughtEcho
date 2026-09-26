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
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
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

      memoryService = AgentMemoryService(
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

    testWidgets('渲染概览卡片、认知负荷与记忆列表', (tester) async {
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

      // 验证概览卡片呈现昵称与标题
      expect(find.text('Thoughter 记忆'), findsWidgets);
      expect(find.text('阿澈'), findsOneWidget);

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

      // 点击搜索按钮打开搜索输入框
      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();

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

    testWidgets('来源归因证据展示：点击追溯笔记', (tester) async {
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

      // 点击归因渊源按钮
      final evidenceBtn = find.text('见于 1 篇笔记');
      expect(evidenceBtn, findsOneWidget);
      await tester.tap(evidenceBtn);
      await _settleWithRealAsync(tester);

      // 底部抽屉展开并显示引用笔记内容和作者
      expect(find.text('树叶在林间细语，阳光穿过枝丫落在长椅上。'), findsOneWidget);
      expect(find.text('—— 史铁生'), findsOneWidget);
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
  });
}
