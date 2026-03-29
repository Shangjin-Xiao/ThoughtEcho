# Explore 页与统一 AI 重构 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 将当前底部导航中的“洞察”重构为轻量 `Explore` 中枢页，并引入统一的全局 AI 助手页面与地图回忆入口，同时让“问笔记”复用同一 AI 容器。

**Architecture:** 本次重构采用“先基建、再入口、后工作流”的分层方式。`Explore` 本身只承载数据概览和两个入口卡片，不直接承载完整聊天或完整地图；统一 AI 页面负责全局对话、笔记上下文对话与 `/` 命令工作流；地图回忆页面第一版只做浏览跳转，不承担编辑职责。旧 `AIFeaturesPage` 和 `NoteQAChatPage` 不直接删除，先改造成兼容 wrapper，待新入口稳定后再清理。

**Tech Stack:** Flutter 3.x, Dart, Provider, SQLite (`sqflite` / `sqflite_common_ffi`), `flutter_chat_ui`, OpenAI-compatible streaming API, `flutter_map`, Nominatim, Flutter l10n

---

## 决策冻结

以下产品决策在本计划中视为已确认，不再反复讨论：

1. 底部导航“洞察”改为“探索”。
2. `Explore` 是轻量中枢页，首屏结构为：数据概览 + AI 助手入口 + 地图回忆入口。
3. `AI 助手` 是独立页面，从 `Explore` 进入时默认为全局模式。
4. “问笔记”不再长期维护独立页面，而是复用同一个 `AI 助手` 页面，只是自动携带当前笔记上下文。
5. `地图回忆` 第一版是纯浏览页，只负责看分布、点 marker、跳笔记详情。
6. `/智能洞察`、`/润色`、`/续写`、`/深度分析` 在统一 AI 页面第一版就进入范围。

## 涉及文档

- 参考总纲：`docs/plans/2026-03-28-master-refactoring-explore-page-and-ai-ide.md`
- 参考 AI 产品方案：`docs/plans/2026-03-28-global-ai-ide-and-agent-design.md`
- 参考 AI 基建方案：`docs/plans/2026-03-26-ai-chat-history-and-agent-design.md`
- 参考地图方案：`docs/plans/2026-03-26-map-location-picker-and-note-map.md`

## Phase 0: 代码现状确认与迁移顺序冻结

### Task 1: 锁定本次重构的旧入口与替换目标

**Files:**
- Inspect: `lib/pages/home_page.dart`
- Inspect: `lib/pages/ai_features_page.dart`
- Inspect: `lib/pages/ai_periodic_report_page.dart`
- Inspect: `lib/pages/insights_page.dart`
- Inspect: `lib/pages/note_qa_chat_page.dart`
- Inspect: `lib/widgets/ask_note_widgets.dart`
- Inspect: `lib/l10n/app_zh.arb`
- Inspect: `lib/l10n/app_en.arb`

**Step 1: 记录当前入口映射**

- 底部导航第 3 个 tab 当前指向 `AIFeaturesPage`
- `AIFeaturesPage` 当前包含 `AIPeriodicReportPage` + `InsightsPage`
- 首页和笔记列表中的“问笔记”仍然直达 `NoteQAChatPage`

**Step 2: 在计划备注中冻结迁移顺序**

- 先保留旧页面类型名，新增新页面与新服务
- 再把旧入口改成跳转 wrapper
- 最后才考虑删除旧结构

**Step 3: 验证**

Run: `flutter analyze --no-fatal-infos`
Expected: 基线通过，便于后续每个阶段做回归对比

---

## Phase 1: Explore 中枢页替换旧洞察页

### Task 2: 新增 Explore 页面骨架并替换底部导航文案

**Files:**
- Create: `lib/pages/explore_page.dart`
- Modify: `lib/pages/home_page.dart`
- Modify: `lib/l10n/app_zh.arb`
- Modify: `lib/l10n/app_en.arb`
- Test: `test/widget/pages/explore_page_test.dart`

**Step 1: 写失败的 widget test，固定首屏结构**

```dart
testWidgets('ExplorePage renders overview and two entry cards', (tester) async {
  await tester.pumpWidget(const MaterialApp(home: ExplorePage()));

  expect(find.text('AI 助手'), findsOneWidget);
  expect(find.text('地图回忆'), findsOneWidget);
});
```

**Step 2: 运行测试确认失败**

Run: `flutter test test/widget/pages/explore_page_test.dart`
Expected: FAIL with `ExplorePage` not found

**Step 3: 添加最小页面骨架**

```dart
class ExplorePage extends StatelessWidget {
  const ExplorePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        children: const [
          SizedBox(height: 12),
          Placeholder(),
        ],
      ),
    );
  }
}
```

**Step 4: 更新底部导航文案**

- 新增 `navExplore`
- 将 `home_page.dart` 第 3 个 `NavigationDestination` 的 label 从 `navInsights` 切到 `navExplore`
- 图标可暂时沿用 `Icons.explore_outlined` / `Icons.explore`

**Step 5: 运行测试和分析**

Run: `flutter test test/widget/pages/explore_page_test.dart`
Expected: PASS

Run: `flutter analyze --no-fatal-infos`
Expected: 无新增 error

**Step 6: Commit**

```bash
git add lib/pages/explore_page.dart lib/pages/home_page.dart lib/l10n/app_zh.arb lib/l10n/app_en.arb test/widget/pages/explore_page_test.dart
git commit -m "feat: add Explore page shell and replace insights nav label"
```

### Task 3: 抽出数据概览区块供 Explore 复用

**Files:**
- Create: `lib/widgets/explore/explore_overview_section.dart`
- Modify: `lib/pages/explore_page.dart`
- Modify: `lib/pages/ai_periodic_report_page.dart`
- Modify: `lib/pages/ai_report/report_overview.dart`
- Test: `test/widget/pages/explore_page_test.dart`

**Step 1: 写失败测试，固定 Explore 顶部显示概览区**

```dart
expect(find.byType(ExploreOverviewSection), findsOneWidget);
```

**Step 2: 抽离最小可复用组件**

- 从 `AIPeriodicReportPage` 当前顶部概览逻辑中提炼一个只负责展示的 section
- 不把“周期选择器”“精选卡片”“洞察结果”搬进 Explore
- Explore 首屏只复用概览，不复用整个旧报告页

**Step 3: 验证**

Run: `flutter test test/widget/pages/explore_page_test.dart`
Expected: PASS

Run: `flutter analyze --no-fatal-infos`
Expected: 无新增 error

**Step 4: Commit**

```bash
git add lib/widgets/explore/explore_overview_section.dart lib/pages/explore_page.dart lib/pages/ai_periodic_report_page.dart lib/pages/ai_report/report_overview.dart test/widget/pages/explore_page_test.dart
git commit -m "refactor: extract overview section for Explore page"
```

### Task 4: 添加 AI 助手与地图回忆入口卡片

**Files:**
- Create: `lib/widgets/explore/explore_entry_card.dart`
- Modify: `lib/pages/explore_page.dart`
- Modify: `lib/l10n/app_zh.arb`
- Modify: `lib/l10n/app_en.arb`
- Test: `test/widget/pages/explore_page_test.dart`

**Step 1: 写失败测试，固定两个入口卡片文案和点击行为**

```dart
expect(find.text('AI 助手'), findsOneWidget);
expect(find.text('地图回忆'), findsOneWidget);
```

**Step 2: 实现入口卡片**

- `AI 助手` 卡片跳转统一 AI 页面
- `地图回忆` 卡片跳转地图回忆页面
- 首屏不直接嵌入聊天流和地图控件

**Step 3: 验证**

Run: `flutter test test/widget/pages/explore_page_test.dart`
Expected: PASS

Run: `flutter analyze --no-fatal-infos`
Expected: 无新增 error

**Step 4: Commit**

```bash
git add lib/widgets/explore/explore_entry_card.dart lib/pages/explore_page.dart lib/l10n/app_zh.arb lib/l10n/app_en.arb test/widget/pages/explore_page_test.dart
git commit -m "feat: add Explore entry cards for AI assistant and map memory"
```

---

## Phase 2: 统一 AI 页面与会话上下文模型

### Task 5: 定义统一 AI 页面使用的上下文模型

**Files:**
- Create: `lib/models/ai_assistant_entry_context.dart`
- Test: `test/unit/models/ai_assistant_entry_context_test.dart`

**Step 1: 写失败测试，固定两种入口上下文**

```dart
test('builds global context', () {
  final context = AIAssistantEntryContext.global();
  expect(context.noteId, isNull);
  expect(context.entryType, AIAssistantEntryType.global);
});

test('builds note context', () {
  final quote = Quote.validated(content: 'hello', date: '2026-03-29');
  final context = AIAssistantEntryContext.forNote(quote);
  expect(context.entryType, AIAssistantEntryType.note);
});
```

**Step 2: 实现最小模型**

```dart
enum AIAssistantEntryType { global, note }

class AIAssistantEntryContext {
  final AIAssistantEntryType entryType;
  final Quote? quote;
  final String? initialCommand;
}
```

**Step 3: 验证**

Run: `flutter test test/unit/models/ai_assistant_entry_context_test.dart`
Expected: PASS

**Step 4: Commit**

```bash
git add lib/models/ai_assistant_entry_context.dart test/unit/models/ai_assistant_entry_context_test.dart
git commit -m "feat: add AI assistant entry context model"
```

### Task 6: 创建统一 AI 页面壳层

**Files:**
- Create: `lib/pages/ai_assistant_page.dart`
- Create: `lib/widgets/ai/ai_assistant_header.dart`
- Modify: `lib/pages/explore_page.dart`
- Test: `test/widget/pages/ai_assistant_page_test.dart`

**Step 1: 写失败测试，固定页面能接收全局与笔记上下文**

```dart
testWidgets('AI assistant page renders note context banner', (tester) async {
  final quote = Quote.validated(content: 'note body', date: '2026-03-29');

  await tester.pumpWidget(
    MaterialApp(
      home: AIAssistantPage(
        entryContext: AIAssistantEntryContext.forNote(quote),
      ),
    ),
  );

  expect(find.textContaining('note body'), findsOneWidget);
});
```

**Step 2: 实现最小页面壳层**

- AppBar 标题使用新的 `aiAssistantTitle`
- 全局模式显示“未绑定笔记”状态
- 笔记模式显示上下文 banner
- 聊天主体暂时先用占位容器，后续接入持久化会话

**Step 3: 从 Explore 接上入口**

- `AI 助手` 卡片统一跳 `AIAssistantPage(entryContext: global())`

**Step 4: 验证**

Run: `flutter test test/widget/pages/ai_assistant_page_test.dart`
Expected: PASS

Run: `flutter analyze --no-fatal-infos`
Expected: 无新增 error

**Step 5: Commit**

```bash
git add lib/pages/ai_assistant_page.dart lib/widgets/ai/ai_assistant_header.dart lib/pages/explore_page.dart test/widget/pages/ai_assistant_page_test.dart
git commit -m "feat: add unified AI assistant page shell"
```

---

## Phase 3: AI 聊天持久化与 Agent 基建

### Task 7: 消除 ChatMessage 双定义并补齐数据库映射

**Files:**
- Modify: `lib/models/chat_message.dart`
- Modify: `lib/models/chat_session.dart`
- Test: `test/unit/models/chat_message_test.dart`
- Test: `test/unit/models/chat_session_test.dart`

**Step 1: 写失败测试，固定 `role`、`includedInContext`、`toMap` / `fromMap`**

```dart
test('chat message serializes to database map', () {
  final message = ChatMessage(
    id: 'm1',
    content: 'hello',
    isUser: true,
    role: 'user',
    timestamp: DateTime.parse('2026-03-29T00:00:00Z'),
  );

  expect(message.toMap('s1')['session_id'], 's1');
});
```

**Step 2: 把 `ChatMessage` 收敛到 `lib/models/chat_message.dart`**

- 删除 `chat_session.dart` 中内联 `ChatMessage`
- `chat_session.dart` 改为 import 单一模型
- 为两个模型补齐 `toMap` / `fromMap`

**Step 3: 验证**

Run: `flutter test test/unit/models/chat_message_test.dart test/unit/models/chat_session_test.dart`
Expected: PASS

**Step 4: Commit**

```bash
git add lib/models/chat_message.dart lib/models/chat_session.dart test/unit/models/chat_message_test.dart test/unit/models/chat_session_test.dart
git commit -m "refactor: unify chat models and add database mapping"
```

### Task 8: 在主数据库增加聊天表迁移

**Files:**
- Modify: `lib/services/database_schema_manager.dart`
- Test: `test/unit/services/chat_schema_migration_test.dart`

**Step 1: 写失败测试，固定聊天表存在与字段存在**

```dart
test('migration creates chat_sessions and chat_messages tables', () async {
  // open upgraded test database
  // verify table names and role/session_type columns exist
});
```

**Step 2: 实现迁移**

- 使用目标分支上的下一个可用 schema 版本号，不写死 `v20`
- 新增 `chat_sessions`
- 新增 `chat_messages`
- `note_id` 可空，`session_type` 区分 `note` / `agent`
- `role` 支持 `user` / `assistant` / `system` / `tool`

**Step 3: 验证**

Run: `flutter test test/unit/services/chat_schema_migration_test.dart`
Expected: PASS

Run: `flutter analyze --no-fatal-infos`
Expected: 无新增 error

**Step 4: Commit**

```bash
git add lib/services/database_schema_manager.dart test/unit/services/chat_schema_migration_test.dart
git commit -m "feat: add chat session schema to main database"
```

### Task 9: 新增聊天会话服务并接入统一 AI 页面

**Files:**
- Create: `lib/services/chat_session_service.dart`
- Modify: `lib/main.dart`
- Modify: `lib/pages/ai_assistant_page.dart`
- Test: `test/unit/services/chat_session_service_test.dart`
- Test: `test/widget/pages/ai_assistant_page_test.dart`

**Step 1: 写失败测试，固定创建会话、加载历史、追加消息**

```dart
test('creates note session for saved quote id', () async {
  final session = await service.getOrCreateNoteSession(
    noteId: 'q1',
    noteTitle: 'Title',
  );

  expect(session.sessionType, 'note');
});
```

**Step 2: 实现最小服务**

- `getOrCreateGlobalSession()`
- `getOrCreateNoteSession()`
- `loadMessages(sessionId)`
- `appendMessage(sessionId, message)`
- 未保存笔记不持久化，只走内存 fallback

**Step 3: 在 `main.dart` 注入 Provider**

- 使用 `ChangeNotifierProvider` 或合适 Provider 方式注入

**Step 4: 统一 AI 页面改用持久化会话源**

- 不再只依赖 `InMemoryChatController`
- 页面刷新后能恢复历史

**Step 5: 验证**

Run: `flutter test test/unit/services/chat_session_service_test.dart test/widget/pages/ai_assistant_page_test.dart`
Expected: PASS

**Step 6: Commit**

```bash
git add lib/services/chat_session_service.dart lib/main.dart lib/pages/ai_assistant_page.dart test/unit/services/chat_session_service_test.dart test/widget/pages/ai_assistant_page_test.dart
git commit -m "feat: persist AI assistant chat sessions"
```

### Task 10: 增加 Agent runtime 与工具调用护栏

**Files:**
- Create: `lib/services/agent_service.dart`
- Create: `lib/services/agent_tools/search_notes_tool.dart`
- Modify: `lib/pages/ai_assistant_page.dart`
- Modify: `lib/services/ai_service.dart`
- Modify: `lib/utils/ai_request_helper.dart`
- Test: `test/unit/services/agent_service_test.dart`

**Step 1: 写失败测试，固定工具循环终止条件**

```dart
test('stops repeated tool invocation with same arguments', () async {
  // same tool call twice should terminate loop
});
```

**Step 2: 实现最小 Agent 服务**

- Chat 模式继续走普通对话
- Agent 模式走非流式工具循环
- 至少提供 `SearchNotesTool`
- 解析失败时允许一次 repair retry
- 重复工具调用自动终止

**Step 3: 验证**

Run: `flutter test test/unit/services/agent_service_test.dart`
Expected: PASS

Run: `flutter analyze --no-fatal-infos`
Expected: 无新增 error

**Step 4: Commit**

```bash
git add lib/services/agent_service.dart lib/services/agent_tools/search_notes_tool.dart lib/pages/ai_assistant_page.dart lib/services/ai_service.dart lib/utils/ai_request_helper.dart test/unit/services/agent_service_test.dart
git commit -m "feat: add agent runtime for unified AI assistant"
```

---

## Phase 4: 问笔记复用统一 AI 页面

### Task 11: 把 NoteQAChatPage 改造成兼容 wrapper

**Files:**
- Modify: `lib/pages/note_qa_chat_page.dart`
- Modify: `lib/widgets/ask_note_widgets.dart`
- Modify: `lib/pages/home_page.dart`
- Test: `test/widget/pages/note_qa_chat_page_test.dart`

**Step 1: 写失败测试，固定 wrapper 行为**

```dart
testWidgets('NoteQAChatPage forwards note context to AIAssistantPage', (tester) async {
  // build page and verify AIAssistantPage is shown
});
```

**Step 2: 改造页面**

- `NoteQAChatPage` 先保留类名，内部直接转发到 `AIAssistantPage(entryContext: forNote(...))`
- `initialQuestion` 改造成初始输入或初始命令

**Step 3: 替换显式直跳逻辑**

- `home_page.dart::_showAIQuestionDialog`
- `ask_note_widgets.dart` 三个入口

**Step 4: 验证**

Run: `flutter test test/widget/pages/note_qa_chat_page_test.dart`
Expected: PASS

Run: `flutter analyze --no-fatal-infos`
Expected: 无新增 error

**Step 5: Commit**

```bash
git add lib/pages/note_qa_chat_page.dart lib/widgets/ask_note_widgets.dart lib/pages/home_page.dart test/widget/pages/note_qa_chat_page_test.dart
git commit -m "refactor: route ask note flows through unified AI assistant"
```

---

## Phase 5: `/` 命令工作流与结果应用

### Task 12: 增加 slash command 输入能力

**Files:**
- Create: `lib/widgets/ai/ai_command_input.dart`
- Create: `lib/models/ai_slash_command.dart`
- Modify: `lib/pages/ai_assistant_page.dart`
- Modify: `lib/l10n/app_zh.arb`
- Modify: `lib/l10n/app_en.arb`
- Test: `test/widget/pages/ai_assistant_page_test.dart`

**Step 1: 写失败测试，固定输入 `/` 后出现命令菜单**

```dart
expect(find.text('/智能洞察'), findsOneWidget);
expect(find.text('/润色'), findsOneWidget);
```

**Step 2: 实现命令菜单**

- 首批命令：`/智能洞察`、`/周期报告`、`/深度分析`、`/润色`、`/续写`
- 命令触发的是会话内工作流，不是新页面跳转

**Step 3: 验证**

Run: `flutter test test/widget/pages/ai_assistant_page_test.dart`
Expected: PASS

**Step 4: Commit**

```bash
git add lib/widgets/ai/ai_command_input.dart lib/models/ai_slash_command.dart lib/pages/ai_assistant_page.dart lib/l10n/app_zh.arb lib/l10n/app_en.arb test/widget/pages/ai_assistant_page_test.dart
git commit -m "feat: add slash command input for AI assistant"
```

### Task 13: 实现 `/智能洞察` 与 `/周期报告` 的会话工作流卡片

**Files:**
- Create: `lib/widgets/ai/insight_workflow_card.dart`
- Create: `lib/widgets/ai/report_workflow_card.dart`
- Modify: `lib/pages/ai_assistant_page.dart`
- Modify: `lib/pages/insights_page.dart`
- Modify: `lib/pages/ai_periodic_report_page.dart`
- Test: `test/widget/pages/ai_assistant_page_test.dart`

**Step 1: 写失败测试，固定命令后出现配置卡片**

```dart
expect(find.byType(InsightWorkflowCard), findsOneWidget);
```

**Step 2: 实现工作流**

- 将原有分析参数选择改造成会话中的卡片
- 生成结果后可继续追问
- 保存历史仍复用现有 `AIAnalysisDatabaseService`

**Step 3: 验证**

Run: `flutter test test/widget/pages/ai_assistant_page_test.dart`
Expected: PASS

**Step 4: Commit**

```bash
git add lib/widgets/ai/insight_workflow_card.dart lib/widgets/ai/report_workflow_card.dart lib/pages/ai_assistant_page.dart lib/pages/insights_page.dart lib/pages/ai_periodic_report_page.dart test/widget/pages/ai_assistant_page_test.dart
git commit -m "feat: add insight and report workflows to AI assistant"
```

### Task 14: 实现 `/润色`、`/续写`、`/深度分析` 的 artifact 结果块与一键应用

**Files:**
- Create: `lib/widgets/ai/ai_artifact_block.dart`
- Create: `lib/utils/ai_artifact_apply_helper.dart`
- Modify: `lib/pages/ai_assistant_page.dart`
- Modify: `lib/pages/note_full_editor_page.dart`
- Modify: `lib/pages/note_editor/editor_ai_features.dart`
- Test: `test/unit/utils/ai_artifact_apply_helper_test.dart`
- Test: `test/widget/pages/ai_assistant_page_test.dart`

**Step 1: 写失败测试，固定 artifact block 显示与 apply action**

```dart
expect(find.byType(AIArtifactBlock), findsOneWidget);
```

**Step 2: 实现最小应用流程**

- 对有笔记上下文的会话，支持将生成文本传给编辑器
- 第一版只支持“整段替换”或“追加到末尾”两种稳定模式
- 不做复杂选区编辑

**Step 3: 验证**

Run: `flutter test test/unit/utils/ai_artifact_apply_helper_test.dart test/widget/pages/ai_assistant_page_test.dart`
Expected: PASS

**Step 4: Commit**

```bash
git add lib/widgets/ai/ai_artifact_block.dart lib/utils/ai_artifact_apply_helper.dart lib/pages/ai_assistant_page.dart lib/pages/note_full_editor_page.dart lib/pages/note_editor/editor_ai_features.dart test/unit/utils/ai_artifact_apply_helper_test.dart test/widget/pages/ai_assistant_page_test.dart
git commit -m "feat: add artifact output and apply-to-editor flow"
```

---

## Phase 6: 地图选点与地图回忆

### Task 15: 给 Quote 增加 `poiName` 并完成 schema 协调

**Files:**
- Modify: `lib/models/quote_model.dart`
- Modify: `lib/services/database_schema_manager.dart`
- Test: `test/unit/models/quote_model_test.dart`

**Step 1: 写失败测试，固定 `poiName` 序列化与展示语义**

```dart
test('quote serializes poiName', () {
  final quote = Quote.validated(
    content: 'hello',
    date: '2026-03-29',
    poiName: '故宫博物院',
  );

  expect(quote.toJson()['poi_name'], '故宫博物院');
});
```

**Step 2: 实现模型与迁移**

- `Quote` 增加 `poiName`
- 增加 `hasDisplayLocation`
- 数据库迁移使用与聊天表协调后的最终版本号
- `_removeTagIdsColumnSafely` 的重建 SQL 同步带上 `poi_name`

**Step 3: 验证**

Run: `flutter test test/unit/models/quote_model_test.dart`
Expected: PASS

Run: `flutter analyze --no-fatal-infos`
Expected: 无新增 error

**Step 4: Commit**

```bash
git add lib/models/quote_model.dart lib/services/database_schema_manager.dart test/unit/models/quote_model_test.dart
git commit -m "feat: add poiName field for map memory data model"
```

### Task 16: 增加 PlaceSearchService 与地图选点页

**Files:**
- Create: `lib/services/place_search_service.dart`
- Create: `lib/pages/map_location_picker_page.dart`
- Modify: `lib/pages/note_editor/editor_metadata_location_section.dart`
- Modify: `lib/pages/note_editor/editor_location_dialogs.dart`
- Modify: `lib/pages/note_editor/editor_save_and_draft.dart`
- Test: `test/unit/services/place_search_service_test.dart`
- Test: `test/widget/pages/map_location_picker_page_test.dart`

**Step 1: 写失败测试，固定反向选点与手动搜索行为**

```dart
test('reverseSelectedPoint returns poi candidate', () async {
  // fake http client returns a poi candidate
});
```

**Step 2: 实现服务和页面**

- `PlaceSearchService` 从 `LocationService` 中解耦
- 地图拖动稳定后只 reverse 一次
- 搜索只在用户主动提交时请求
- 选中地点后回填 `location`、`latitude`、`longitude`、`poiName`

**Step 3: 验证**

Run: `flutter test test/unit/services/place_search_service_test.dart test/widget/pages/map_location_picker_page_test.dart`
Expected: PASS

Run: `flutter analyze --no-fatal-infos`
Expected: 无新增 error

**Step 4: Commit**

```bash
git add lib/services/place_search_service.dart lib/pages/map_location_picker_page.dart lib/pages/note_editor/editor_metadata_location_section.dart lib/pages/note_editor/editor_location_dialogs.dart lib/pages/note_editor/editor_save_and_draft.dart test/unit/services/place_search_service_test.dart test/widget/pages/map_location_picker_page_test.dart
git commit -m "feat: add map location picker and place search service"
```

### Task 17: 新增地图回忆浏览页并接上 Explore 入口

**Files:**
- Create: `lib/pages/map_memory_page.dart`
- Create: `lib/models/map_note_preview.dart`
- Modify: `lib/pages/explore_page.dart`
- Modify: `lib/services/database_service.dart`
- Test: `test/widget/pages/map_memory_page_test.dart`

**Step 1: 写失败测试，固定浏览页行为**

```dart
testWidgets('MapMemoryPage opens note detail when marker tapped', (tester) async {
  // render page with one preview and tap marker
});
```

**Step 2: 实现浏览页**

- 只加载有坐标的笔记预览 DTO
- 默认开启聚合
- 点 cluster 放大
- 点单个 marker 进入笔记详情或编辑页
- 第一版不在地图页直接编辑位置

**Step 3: 验证**

Run: `flutter test test/widget/pages/map_memory_page_test.dart`
Expected: PASS

Run: `flutter analyze --no-fatal-infos`
Expected: 无新增 error

**Step 4: Commit**

```bash
git add lib/pages/map_memory_page.dart lib/models/map_note_preview.dart lib/pages/explore_page.dart lib/services/database_service.dart test/widget/pages/map_memory_page_test.dart
git commit -m "feat: add browse-only map memory page"
```

---

## Phase 7: 过渡清理与回归验证

### Task 18: 将 AIFeaturesPage 改造成过渡 wrapper

**Files:**
- Modify: `lib/pages/ai_features_page.dart`
- Test: `test/widget/pages/ai_features_page_test.dart`

**Step 1: 写失败测试，固定过渡行为**

```dart
testWidgets('AIFeaturesPage redirects to Explore-compatible experience', (tester) async {
  // ensure old route still works
});
```

**Step 2: 实现 wrapper**

- 不再维护 tab 结构
- 直接跳转到 `ExplorePage` 或显示兼容占位并引导用户进入新入口

**Step 3: 验证**

Run: `flutter test test/widget/pages/ai_features_page_test.dart`
Expected: PASS

**Step 4: Commit**

```bash
git add lib/pages/ai_features_page.dart test/widget/pages/ai_features_page_test.dart
git commit -m "refactor: convert legacy AI features page into transition wrapper"
```

### Task 19: 做一轮聚焦回归测试

**Files:**
- Test: `test/widget/pages/home_page_test.dart`
- Test: `test/widget/pages/explore_page_test.dart`
- Test: `test/widget/pages/ai_assistant_page_test.dart`
- Test: `test/widget/pages/map_memory_page_test.dart`
- Test: `test/unit/models/quote_model_test.dart`
- Test: `test/unit/services/location_service_test.dart`

**Step 1: 运行核心测试集**

Run: `flutter test test/widget/pages/home_page_test.dart`
Expected: PASS

Run: `flutter test test/widget/pages/explore_page_test.dart test/widget/pages/ai_assistant_page_test.dart test/widget/pages/map_memory_page_test.dart`
Expected: PASS

Run: `flutter test test/unit/models/quote_model_test.dart test/unit/services/location_service_test.dart`
Expected: PASS

**Step 2: 运行分析**

Run: `flutter analyze --no-fatal-infos`
Expected: 无新增 error

**Step 3: Commit**

```bash
git add .
git commit -m "test: verify Explore, AI assistant, and map memory refactor"
```

## 风险与护栏

1. **Schema 冲突风险**
   - 聊天表和 `poi_name` 都依赖数据库迁移，实施前必须先确认目标分支最新 schema 版本。

2. **页面过渡期回归**
   - `AIFeaturesPage` 和 `NoteQAChatPage` 不直接删除，只做 wrapper，避免旧入口崩掉。

3. **统一 AI 首版过重**
   - 即便 `/` 命令首版进入范围，也要先保证聊天容器稳定，再逐个把工作流命令挂上。

4. **地图页职责膨胀**
   - 第一版地图回忆只浏览，不接受“顺手在地图里编辑笔记”的扩张。

5. **首屏复杂度失控**
   - `Explore` 首屏只允许数据概览 + 两张入口卡片，不在首屏内直接嵌入完整地图和完整聊天。

## 完成定义

- 底部导航进入的是 `Explore`，不是旧洞察页。
- Explore 首屏能清晰看到数据概览、AI 助手入口、地图回忆入口。
- 从 Explore 进入 AI 助手是全局模式；从笔记进入是同一页面的笔记上下文模式。
- “问笔记”不再维护独立长期交互逻辑。
- `/智能洞察`、`/润色`、`/续写`、`/深度分析` 能在统一 AI 页面内完成。
- 地图回忆页第一版可浏览并跳转笔记，地图选点可为笔记补充 `poiName`。
