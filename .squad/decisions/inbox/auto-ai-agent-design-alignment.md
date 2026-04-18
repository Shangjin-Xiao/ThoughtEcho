### 2026-04-18T13:46Z: AI Agent 设计规范对齐修复

**By:** 上晋 (via AUTO)
**类型:** 架构决策 + 代码规范

**背景**: 对照 `docs/plans/2026-04-18-ai-agent-design.md` 设计规范文档，发现 5 处实现与设计不符的问题，已全部修复。

**核心决策:**

1. **SmartResultCard 元数据交互按钮** — 新增 📍 添加位置 / 🌤️ 添加天气 FilterChip 切换按钮，用户可在保存前决定是否附加环境信息，符合设计规范第9节
2. **打开编辑器时元数据传递** — `_openSmartResultAsNewNote` 现传递 `tagIds`/`includeLocation`/`includeWeather` 到 `NoteFullEditorPage` 的 `initialQuote`，修复元数据丢失问题，符合设计规范第2节
3. **草稿保存防线** — `_openAiAssistant()` 现在进入前检查 `_hasUnsavedChanges()`，未保存时弹确认对话框强制先保存，符合设计规范第10节
4. **短文本快捷记录弹窗** — AI 新建笔记内容<200字符且≤2行时自动走 `AddNoteDialog`，长内容走 `NoteFullEditorPage`，符合设计规范第4节
5. **Agent 流式响应** — `AgentService.runAgent()` 从非流式改为流式 Completions API，新增 `AgentTextDeltaEvent` 逐 token 推送，smart_result 卡片实现打字机效果，符合设计规范第11节

**修改文件清单:**
- `lib/widgets/ai/smart_result_card.dart` — Stateful 化 + 元数据按钮
- `lib/pages/ai_assistant/ai_assistant_page_ui.dart` — 短文本路由 + 编辑器元数据传递 + AddNoteDialog 集成
- `lib/pages/ai_assistant_page.dart` — AgentTextDeltaEvent import + AddNoteDialog import
- `lib/pages/ai_assistant/ai_assistant_page_agent.dart` — 流式文本增量渲染逻辑
- `lib/pages/note_editor/editor_ai_features.dart` — 草稿保存防线
- `lib/services/agent_service.dart` — 流式 API + AgentTextDeltaEvent + ChatStreamAccumulator
- `lib/widgets/add_note_dialog.dart` — 新增 prefilled 参数
- `lib/l10n/app_zh.arb` / `lib/l10n/app_en.arb` — 新增 l10n 键
- `test/widgets/smart_result_card_test.dart` — 回调签名修复