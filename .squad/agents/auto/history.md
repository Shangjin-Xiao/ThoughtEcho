# AUTO 的项目记忆

## 核心背景

- 项目: ThoughtEcho (心迹)
- 负责人: 上晋
- 我的角色: 技术主管
- 技术栈: Flutter + Dart + SQLite + Provider

## 关键代码位置

- 入口: lib/main.dart
- 数据库: lib/services/database_service.dart
- AI 服务: lib/services/ai_service.dart
- 测试入口: test/all_tests.dart

## Learnings

<!-- 在此追加学到的项目知识 -->
- 2026-04-06: 设置页关于弹窗可通过与用户指南同款 `ElevatedButton.icon` 快速扩展外链操作，使用 `_launchUrl` 统一处理外部链接打开与失败提示。
- 2026-04-08: AIAssistantPage 会话绑定应使用可空且稳定的 `noteId`（`_boundNoteId`），未保存笔记不要生成临时 UUID，否则 `SessionHistorySheet` 无法回看历史；相关路径：`lib/pages/ai_assistant_page.dart`、`lib/pages/note_editor/editor_ai_features.dart`。
- 2026-04-08: Explore AI 引导文案采用“双轨策略”：优先 `AIService.streamGeneralConversation` 生成简短总结，失败或无 Key 自动回退本地统计拼接；实现位于 `lib/pages/explore_page.dart`。
- 2026-04-08: AIAssistantPage 工具进度面板完成后由 `_syncAgentProgressState` 触发 `_scheduleAgentStatusDismiss`，延迟约 1.2 秒自动清理并收起；路径 `lib/pages/ai_assistant_page.dart`。
- 2026-04-11: AIAssistantPage 稳定依赖三条 UI 合约：`ai_assistant_mode_toggle`、`ai_assistant_send_button`、以及 `_showAgentStatusPanel + _toolProgressItems` 驱动的 `ToolProgressPanel` 渲染；关键路径 `lib/pages/ai_assistant_page.dart`、`test/widget/pages/ai_assistant_page_test.dart`。
