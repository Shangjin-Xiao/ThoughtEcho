# 统一 AI 容器与地图画廊 实施计划 (Implementation Plan)

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 根据最终产品设计，将当前零散的AI页面重构为大一统对话框 (`AIAssistantPage`)，引入原生的AI Skills系统驱动Agent Loop，并实现全屏相册式的地图画廊 (`MapMemoryPage`)。

**Architecture:** 
1. 先清理与保存当前的未提交基建代码。
2. 引入 `openai_dart` 包，搭建原生 AI Skills 实体和本地 `AgentService` 推理循环引擎（建议参考 opencode 或 Gemini CLI 等开源方案的简洁 `for/while` 循环）。
3. 构建唯一的 `AIAssistantPage`，实现单笔记与 Agent 模式的无缝切换与持久化（保留现有 `ChatSessionService`）。
4. 新建 `MapMemoryPage` 实现全聚合的相册式地图浏览，并用半屏面板复用卡片展示。
5. 最终在 `ExplorePage` 拼装所有入口。

**Tech Stack:** Flutter 3.x, Dart, `openai_dart` (for native JSON Tool Calling), `flutter_map`, `flutter_map_marker_cluster`, `sqflite`.

---

## Phase 0: 保存前序基建与引入新包

### Task 1: 提交当前的未追踪基建代码

**Files:**
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_zh.arb`
- Modify: `lib/pages/agent_chat_page.dart`, `lib/pages/home_page.dart`, `lib/pages/note_qa_chat_page.dart`
- Modify: `lib/services/agent_service.dart`, `lib/services/database_schema_manager.dart`, `lib/services/place_search_service.dart`
- Add: `test/unit/services/agent_service_test.dart`, `test/unit/services/database_schema_manager_poi_name_test.dart`, `test/unit/services/place_search_service_test.dart`

**Step 1: 运行现有测试**
Run: `flutter test test/unit/services/agent_service_test.dart test/unit/services/place_search_service_test.dart test/unit/services/database_schema_manager_poi_name_test.dart`
Expected: PASS

**Step 2: Commit**
```bash
git add .
git commit -m "feat(infra): finalize rate limits, agent duplication checks, and db schema tests"
```

### Task 2: 引入 `openai_dart` 包

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/services/agent_service.dart` (后续替换使用)

**Step 1: 添加依赖**
Run: `flutter pub add openai_dart`
Expected: Successfully adds the package to pubspec.yaml

**Step 2: Commit**
```bash
git add pubspec.yaml pubspec.lock
git commit -m "build: add openai_dart for native tool calling and skills system"
```

---

## Phase 1: AI Skills 核心引擎架构

*(注：工程师可在此阶段参考开源工具 opencode 或 Gemini CLI 的代码，了解如何实现极简的 Agent 工具注册与执行循环)*

### Task 3: 定义 AI Skill 数据模型

**Files:**
- Create: `lib/models/ai_skill.dart`
- Test: `test/unit/models/ai_skill_test.dart`

**Step 1: Write the failing test**
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/ai_skill.dart';
import 'package:openai_dart/openai_dart.dart';

void main() {
  test('AISkill generates correct OpenAI Tool schema', () {
    final skill = AISkill(
      id: 'polish',
      name: 'Polish Note',
      triggerWord: '/润色',
      description: '润色当前的笔记内容',
      systemPrompt: '请使用优美的语言...',
      requiresExternalTools: false,
    );
    final tool = skill.toOpenAITool();
    expect(tool.function.name, 'polish_note');
    expect(tool.function.strict, isTrue); // Ensure strict structured outputs
  });
}
```

**Step 2: Run test to verify it fails**
Run: `flutter test test/unit/models/ai_skill_test.dart`
Expected: FAIL (File not found / syntax error)

**Step 3: Write minimal implementation**
创建 `AISkill` 类，实现 `toOpenAITool()` 方法，映射为 `openai_dart` 的 `Tool` 对象，并确保 `strict: true` 且参数定义符合要求（`additionalProperties: false` 等）。

**Step 4: Run test to verify it passes**
Run: `flutter test test/unit/models/ai_skill_test.dart`
Expected: PASS

**Step 5: Commit**
```bash
git add lib/models/ai_skill.dart test/unit/models/ai_skill_test.dart
git commit -m "feat(ai): add AISkill model mapping to OpenAI strict tools schema"
```

### Task 4: 实现原生 Agent Loop 引擎

**Files:**
- Modify: `lib/services/agent_service.dart`
- Test: `test/unit/services/agent_service_loop_test.dart`

**Step 1: 改造 AgentService 的 runAgent 方法**
将原有拼 XML 的逻辑全部废弃。引入 `openai_dart` Client，使用一个 `while(true)` 循环发送请求。
- 提取所有的本地能力（查库、联网）和系统 Skills 转成 `tools` 列表。
- `if (response.toolCalls != null)` -> 在 Flutter 端执行对应逻辑 -> 追加 `tool` message -> 继续循环。
- `else` -> 跳出循环，返回最终文本。

**Step 2: 编写测试并验证**
*(这里可以使用 Mock Client 模拟大模型连续两次请求，第一次要求执行工具，第二次返回文本)*

**Step 3: Commit**
```bash
git add lib/services/agent_service.dart test/unit/services/agent_service_loop_test.dart
git commit -m "refactor(ai): implement native while-loop agent engine using openai_dart"
```

---

## Phase 2: 大一统 AI 容器 (`AIAssistantPage`)

### Task 5: 搭建统一直觉 UI

**Files:**
- Create: `lib/pages/ai_assistant_page.dart`
- Delete: `lib/pages/agent_chat_page.dart` (重命名为 ai_assistant_page.dart 并大改)
- Delete: `lib/pages/note_qa_chat_page.dart`

**Step 1: 实现统一布局与上下文指示器**
- 顶部导航栏提供“开启新对话(New Chat)”的 IconButton。
- 如果通过 `AIAssistantEntryContext.forNote(quote)` 传入，在输入框正上方浮动一张轻量的“当前绑定笔记”简影卡片（带 X 按钮，点击提示“切换到 Agent 模式”弹窗）。
- 如果是全局模式进入，显示 Explore 页传过来的动态欢迎语作为首条占位消息（不入持久化历史）。

**Step 2: Commit**
```bash
git rm lib/pages/agent_chat_page.dart lib/pages/note_qa_chat_page.dart
git add lib/pages/ai_assistant_page.dart
git commit -m "refactor(ui): merge chat pages into unified AIAssistantPage"
```

### Task 6: 实现智能结果应用闭环 (Slash Commands -> Editor)

**Files:**
- Create: `lib/widgets/ai/smart_result_card.dart`
- Modify: `lib/pages/ai_assistant_page.dart`

**Step 1: 实现特殊卡片渲染**
- 拦截模型输出。如果在单笔记模式且明确调用了某个 Skill（如润色），解析返回的文本渲染为 `SmartResultCard`。
- 卡片下方包含两个操作按钮 `[替换原笔记]` 和 `[追加到末尾]`。

**Step 2: 点击卡片返回编辑器**
- 点击按钮后，调用现有的 `Navigator.pop(context)` 将修改结果作为返回值丢回 `NoteFullEditorPage`，供用户手动审阅和保存。

**Step 3: Commit**
```bash
git add lib/widgets/ai/smart_result_card.dart lib/pages/ai_assistant_page.dart
git commit -m "feat(ai): add smart result cards with seamless editor integration"
```

---

## Phase 3: 地图回忆画廊 (`MapMemoryPage`)

### Task 7: 建立全屏相册式地图视图

**Files:**
- Create: `lib/pages/map_memory_page.dart`
- Test: `test/widget/pages/map_memory_page_test.dart`

**Step 1: Write the failing test**
编写测试确保页面渲染 `FlutterMap` 和 `MarkerClusterLayerWidget`。

**Step 2: 页面实现**
- 获取数据库中**所有** `latitude` 和 `longitude` 不为空的 `Quote` 数据。
- 初始 `center` 根据数据自动算边界（fitBounds），或者定位到当前物理位置。
- 不提供筛选器。使用 `flutter_map_marker_cluster`，缩小显示数字，放大会散开成一个个小图标。

**Step 3: 底部滑出面板**
- 为每个 Marker 绑定 `onTap` 事件。
- 触发 `showModalBottomSheet`，面板内使用现有的 `QuoteItemWidget(quote: quote)`。
- 点卡片直接 Push 到该笔记详情/编辑页。

**Step 4: 空状态**
- 如果数据为空，加载世界地图（定位到本地），悬浮气泡：“目前还没有带坐标的笔记”。

**Step 5: Commit**
```bash
git add lib/pages/map_memory_page.dart test/widget/pages/map_memory_page_test.dart
git commit -m "feat(map): implement full-screen map memory gallery with clustering and bottom sheet"
```

---

## Phase 4: 拼装中枢探索页 (`ExplorePage`)

### Task 8: 更新 Explore 页面终极布局

**Files:**
- Modify: `lib/pages/explore_page.dart`
- Modify: `lib/l10n/app_zh.arb`, `lib/l10n/app_en.arb`

**Step 1: 实现视觉层级**
- **顶部**：保留/优化现有的周期统计（字数、日历等）。根据这些数据组装一段动态字符串给 `AIAssistantPage` 传参。
- **中部**：两个大卡片并排，左边跳转 `AIAssistantPage` (无绑定笔记模式)，右边跳转 `MapMemoryPage`。
- **底部**：复用现成的最喜爱笔记/最近笔记列表组件。

**Step 2: 废除多余入口**
检查 `home_page.dart`、`app_drawer.dart`，移除通往老的“洞察”、“问笔记”的废旧路由。

**Step 3: 最终回归测试**
运行 `flutter analyze` 和 `flutter test`，确保整个项目 0 error。

**Step 4: Commit**
```bash
git add .
git commit -m "feat(explore): finalize layout hierarchy and wire up unified AI and map entry points"
```
