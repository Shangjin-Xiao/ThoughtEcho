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
