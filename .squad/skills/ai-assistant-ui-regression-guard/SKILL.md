# Skill: ai-assistant-ui-regression-guard

## 目的
在 AI 助手页重构时，防止“状态有更新但界面不可见/不可操作”的隐性回归。

## 适用场景
- 修改 `lib/pages/ai_assistant_page.dart` 的输入区、模式切换、Agent 状态展示；
- 调整工具调用事件流或消息渲染逻辑；
- 优化 AI 助手 UI 布局但需保持流程可测。

## 必查清单
1. 模式切换入口存在稳定 key：`ai_assistant_mode_toggle`；
2. 发送入口存在稳定 key：`ai_assistant_send_button`；
3. Agent 状态满足 `_showAgentStatusPanel && _toolProgressItems.isNotEmpty` 时，必须可见 `ToolProgressPanel`；
4. Explore 传入 `exploreGuideSummary` 时，首屏出现对应 system message；
5. 运行 `test/widget/pages/ai_assistant_page_test.dart` 验证流程链路。

## 最小修复策略
- 优先补“UI 绑定缺口”（key、条件渲染、首屏消息注入）；
- 避免改动请求链路和工具执行核心逻辑，除非有直接证据表明根因在服务层。

## 验证命令
```bash
flutter test test/widget/pages/ai_assistant_page_test.dart -r compact
flutter test test/unit/services/agent_service_loop_test.dart -r compact
```
