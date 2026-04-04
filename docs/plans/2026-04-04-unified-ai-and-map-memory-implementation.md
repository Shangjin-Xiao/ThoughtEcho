# 统一 AI 容器与地图画廊 实施计划 (Implementation Plan)

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.
> **SPECIAL INSTRUCTION FOR THE EXECUTING AGENT:** 
> 1. You MUST operate strictly in **YOLO mode** (Autonomous execution, do NOT stop to ask the user for permission between tasks).
> 2. You are ONLY a **Dispatcher (调度员)**. Do NOT write all code yourself. 
> 3. For **Frontend/UI/UX tasks**, dispatch them to Gemini CLI's built-in subagents (e.g., `generalist`, `codebase_investigator`).
> 4. For **Backend/Logic tasks**, dispatch them using Copilot with `GPT-5.3-codex` (must use `exhigh`), `Claude 4.5 Sonnet`, or `Claude 4.5 Opus`.
>    - **CRITICAL LIMIT:** `Claude 4.5 Opus` MUST NOT be called more than 10 times in total. Reserve it ONLY for extremely complex logic tasks.
> 5. **Copilot Delegation & Batching Instructions:** When you dispatch tasks to Copilot, you MUST explicitly instruct Copilot to:
>    - Complete **larger batches of tasks** at once (do not just modify one code block per call; complete entire functional units).
>    - Spawn its own subagents if necessary (Copilot is allowed to use subagents too).
>    - Perform a **Code Review using a subagent** immediately after finishing its own implementation tasks.
> 6. **Context Limit Warning:** Do NOT send all user notes to the LLM context. Always use Agent tools to search/query notes incrementally.
> 7. After completing the overall implementation, perform a **Final Code Review** using the Gemini CLI built-in subagent first, followed by Codex 5.3.

**Goal:** 根据最终产品设计，将当前零散的AI页面重构为大一统对话框 (`AIAssistantPage`)，引入原生的AI Skills系统驱动Agent Loop，并实现全屏相册式的地图画廊 (`MapMemoryPage`)。

**Architecture:** 
1. 先清理与保存当前的未提交基建代码。
2. 研究开源代码：Clone 并研究 `opencode`, `Gemini CLI`, `OpenClaw` 等工具中 Agent Loop 的实现。
3. 引入 `openai_dart` 包，搭建原生 AI Skills 实体和本地 `AgentService` 推理循环引擎。
4. 构建唯一的 `AIAssistantPage`，实现单笔记与 Agent 模式的无缝切换与持久化（保留现有 `ChatSessionService`）。
5. 新建 `MapMemoryPage` 实现全聚合的相册式地图浏览，并用半屏面板复用卡片展示。
6. 最终在 `ExplorePage` 拼装所有入口。

**Tech Stack:** Flutter 3.x, Dart, `openai_dart`, `flutter_map`, `flutter_map_marker_cluster`, `sqflite`.

---

## Phase 0: 准备工作与开源代码研究

### Task 1: 提交当前的未追踪基建代码
**Dispatcher Action:** Use `generalist` subagent to:
1. Run existing tests for agent service, schema manager, place search service.
2. Commit the unstaged changes with a conventional commit message.

### Task 2: 引入 `openai_dart` 包
**Dispatcher Action:** Run `flutter pub add openai_dart` and commit the `pubspec.yaml` update.

### Task 3: 研究开源 Agent 工具代码
**Dispatcher Action:** Use `run_shell_command` to clone repositories like `opencode` or browse local Gemini CLI source code to study how they implement the `Agent Loop` (while/for loops for tool execution). 
- Note: Apply the learned best practices to the Dart implementation in Phase 1.

---

## Phase 1: AI Skills 核心引擎架构 (Backend)

### Task 4: 定义 AI Skill 数据模型
**Dispatcher Action:** Dispatch to Backend Copilot (`GPT-5.3-codex exhigh` or `Claude 4.5 Sonnet`) to:
1. Create `lib/models/ai_skill.dart`.
2. Define the `AISkill` class with properties: `id`, `name`, `triggerWord`, `systemPrompt`, etc.
3. Implement `toOpenAITool()` that strictly maps to the OpenAI JSON Schema (`strict: true`).
4. Write tests in `test/unit/models/ai_skill_test.dart`.
5. Review own code via subagent, then commit.

### Task 5: 实现原生 Agent Loop 引擎
**Dispatcher Action:** Dispatch to Backend Copilot (`Claude 4.5 Opus` for high complexity - note the <10 calls limit!) to:
1. Refactor `lib/services/agent_service.dart`.
2. Remove XML parsing. Implement a `while(true)` loop using `openai_dart` to handle native tool calling.
3. Ensure the context does **NOT** load all notes at once; rely on specific search tools (e.g. `SearchNotesTool`) to query selectively.
4. Add robust error handling and duplicate tool call prevention.
5. Review own code via subagent, then commit.

---

## Phase 2: 大一统 AI 容器 (`AIAssistantPage`) (Frontend)

### Task 6: 搭建统一直觉 UI
**Dispatcher Action:** Dispatch to Gemini CLI `generalist` subagent to:
1. Create `lib/pages/ai_assistant_page.dart` to replace both `agent_chat_page.dart` and `note_qa_chat_page.dart`.
2. Implement the floating context chip when entering from a specific note.
3. Implement the dynamic greeting when entering from the Explore page.
4. Add the "New Chat" button in the AppBar.
5. Commit the code and remove old pages.

### Task 7: 实现智能结果卡片与编辑器闭环
**Dispatcher Action:** Dispatch to Gemini CLI `generalist` subagent to:
1. Create `lib/widgets/ai/smart_result_card.dart`.
2. Render cards for `/润色`, `/续写` commands with `[替换原笔记]` and `[追加到末尾]` buttons.
3. Handle popping context back to `NoteFullEditorPage`.
4. Commit the code.

---

## Phase 3: 地图回忆画廊 (`MapMemoryPage`) (Frontend)

### Task 8: 建立全屏相册式地图视图
**Dispatcher Action:** Dispatch to Gemini CLI `generalist` subagent to:
1. Create `lib/pages/map_memory_page.dart`.
2. Fetch `latitude` and `longitude` for all quotes.
3. Use `flutter_map_marker_cluster` to group markers.
4. Implement a Bottom Sheet that shows `QuoteItemWidget` on marker tap.
5. Implement empty state (show map with floating bubble "目前还没有带坐标的笔记").
6. Commit the code.

---

## Phase 4: 拼装中枢探索页 (`ExplorePage`) (Frontend)

### Task 9: 更新 Explore 页面终极布局
**Dispatcher Action:** Dispatch to Gemini CLI `generalist` subagent to:
1. Refactor `lib/pages/explore_page.dart`.
2. Keep the top data dashboard (generating the greeting string).
3. Place `AI 助手` and `地图回忆` cards in the middle.
4. Remove legacy routing to old insight pages in `home_page.dart` or drawer.
5. Ensure 0 analysis errors and all tests pass.
6. Commit the code.

---

## Phase 5: Code Review

### Task 10: 最终代码审查
**Dispatcher Action:** 
1. Dispatch to Gemini CLI built-in subagent (`code-reviewer` skill or `generalist`) to review the overall architecture and changes.
2. Dispatch to Copilot (`GPT-5.3-codex exhigh`) for a deep logic review of the Agent Loop and UI components.
3. Apply any recommended fixes, format code, and finalize the feature branch.