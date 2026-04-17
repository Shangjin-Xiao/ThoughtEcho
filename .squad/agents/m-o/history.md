# M-O 的项目记忆

## 核心背景

- 项目: ThoughtEcho (心迹)
- 负责人: 上晋
- 我的角色: 测试工程师
- 测试入口: test/all_tests.dart

## Learnings

<!-- 在此追加学到的项目知识 -->
- AI 助手模式切换改为 PopupMenuButton（输入区内显示当前模式文本，菜单项带 Icons.check_circle），相关 UI 在 lib/pages/ai_assistant_page.dart。
- 斜杠命令列表通过 ValueKey('slash_commands_visible'/'slash_commands_hidden') 控制显隐，ActionChip 文案仍为 /润色等。
- 工具调用进度使用 ToolProgressPanel（lib/widgets/ai/tool_progress_panel.dart），完成后会自动折叠展示“已执行 N 个操作”，AI 页面可能在 AnimatedSwitcher 过渡期出现多个面板。
- 实际 AI 助手模式切换入口目前是输入区内的 GestureDetector 切换按钮（`ai_assistant_mode_toggle`），不是 PopupMenuButton；关键文件：`lib/pages/ai_assistant_page.dart`。
- 发送按钮通过 `AnimatedIconButton` 暴露稳定测试键 `ai_assistant_send_button`，用于在生成态/停止态之间做回归验证。
- Explore 入口若传入 `exploreGuideSummary`，应优先显示为系统欢迎消息；仅当未提供 summary 时才触发动态 insight 生成逻辑。
- Agent 循环在 `lib/services/agent_service.dart` 具有 8 轮上限与重复调用防护，测试覆盖文件为 `test/unit/services/agent_service_loop_test.dart`。
- 首页“每日提示/今日思考”走 `AIService -> AIRequestHelper -> AINetworkManager(dio)`，默认直接请求 `currentProvider.apiUrl`；若填 `https://ollama.com/v1` 会命中 `/v1` 并返回 405。
- AI 助手在 Agent 模式走 `AgentService(openai_dart)`，会将 provider URL 归一化为 baseUrl 并补 `/chat/completions`，因此与首页链路的 URL 语义不一致。
- 关键排查路径：`lib/pages/home_page.dart`（每日提示触发）、`lib/services/ai_service.dart`（streamGenerateDailyPrompt）、`lib/services/agent_service.dart`（normalizeOpenAIBaseUrl）、`lib/utils/ai_network_manager.dart`（实际 POST）。
- 当前定向回归现状：`streaming_text_dialog_test.dart` 通过；`ai_assistant_page_test.dart` 多例 `Bad state: No element`；`agent_service_loop_test.dart` 有 1 例长 payload 保留断言失败。
- AgentService 仅接受 OpenAI Chat Completions 语义并显式拦截 Anthropic（`provider.id == 'anthropic'` 或 URL 含 `/v1/messages`），说明“OpenAI 兼容”并不能覆盖全部 Agent 能力场景。
