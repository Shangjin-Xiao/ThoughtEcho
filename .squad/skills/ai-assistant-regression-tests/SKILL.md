---
name: ai-assistant-regression-tests
description: 针对 AI 助手页、工具调用进度与流式错误处理的回归测试模板
---

# AI 助手回归测试技能

## 适用场景
- AI 助手页改动后需要快速确认核心流程可用
- Agent 工具调用循环、异常分支或最大轮次逻辑有调整
- 流式响应 UI（如对话框/消息气泡）出现展示或交互异常

## 执行步骤
1. 先跑定向回归集：  
   `flutter test test/widget/pages/ai_assistant_page_test.dart test/unit/widgets/streaming_text_dialog_test.dart test/unit/services/agent_service_loop_test.dart test/unit/utils/ai_prompt_manager_test.dart`
2. 若失败先看三类高频根因：  
   - 缺少稳定测试 key（如模式切换、发送按钮）  
   - Explore welcome summary 未注入  
   - Agent 状态面板断言过于依赖时序（需放宽 pump 节奏）
3. 覆盖失败/退化分支：  
   - Agent API 抛错 -> 必须触发 `AgentErrorEvent`  
   - 工具循环不收敛 -> 必须触发最大轮次摘要  
   - Streaming onError -> UI 显示错误且禁止 apply

## 验收标准
- 定向回归集全部通过
- Agent loop 新增失败分支测试通过
- AI 助手关键交互（模式切换、发送按钮、工具进度、smart_result）均有稳定断言
