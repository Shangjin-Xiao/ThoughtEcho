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
- 2026-04-16: AI 请求链路存在 endpoint 语义分裂：`AIService.streamGenerateDailyPrompt` 直接使用 `provider.apiUrl` 作为完整 endpoint，而 `AgentService` 会把 OpenAI 兼容地址归一化为 baseUrl（去掉 `/chat/completions`）；同一配置可出现“助手可用、首页 405”。关键路径：`lib/services/ai_service.dart`、`lib/utils/ai_request_helper.dart`、`lib/utils/ai_network_manager.dart`、`lib/services/agent_service.dart`、`lib/pages/home_page.dart`。
- 2026-04-16: AI 助手页当前输入区未提供测试约定 key（`ai_assistant_mode_toggle` / `ai_assistant_send_button`），导致 `test/widget/pages/ai_assistant_page_test.dart` 多例 `Bad state: No element`；回归时需先保证这两个稳定选择器存在。路径：`lib/pages/ai_assistant/ai_assistant_page_ui.dart`。
- 2026-04-16: 思考过程显示链路已接通（`onThinking -> thinkingChunks -> ThinkingWidget`），但 `_enableThinking` 目前只切换 UI 状态未透传请求层，属于“可见但不可控”风险。路径：`lib/pages/ai_assistant/ai_assistant_page_workflow.dart`、`lib/pages/ai_assistant/ai_assistant_page_ui.dart`。
- 2026-04-16: AI endpoint 语义统一采用 `AIProviderSettings.resolveRequestUrl`：OpenAI 兼容 provider 若仅配置 `/v1` 会自动补全 `/chat/completions`，Anthropic `/v1/messages` 保持原样，实际请求由 `AINetworkManager` 统一解析；路径：`lib/models/ai_provider_settings.dart`、`lib/utils/ai_network_manager.dart`。
