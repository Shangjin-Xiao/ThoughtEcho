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
4. 增加 API 地址语义一致性检查：  
   - 首页链路（`AIService`）默认把 `apiUrl` 当成完整 endpoint；  
   - Agent 链路（`AgentService`）把 `apiUrl` 当成 baseUrl 并补 `/chat/completions`；  
   - 回归时必须验证两条链路对同一配置不会出现“助手可用但首页 405”分裂行为。
5. 流式/思考能力验证要求：  
   - 至少一个测试模拟多 chunk 按时间到达并断言 UI 分步更新；  
   - 至少一个测试覆盖 `reasoning_content/thinking_delta -> ThinkingWidget` 端到端显示。
6. 在联调环境做一次 endpoint 冒烟：  
   - 用同一 provider 配置同时触发“AI 助手首轮对话”和“首页今日思考”；  
   - 任一链路出现 405 时，优先排查是否把 base URL 误当完整 endpoint。
7. 做一次 Provider 契约冒烟（尤其是“OpenAI 兼容”场景）：  
   - 校验 endpoint 语义（baseUrl vs 完整 endpoint）在首页链路与 Agent 链路一致；  
   - 校验 headers/payload 是否符合 provider 要求（如 Anthropic `x-api-key` + `/v1/messages`）；  
   - 对“再加 SDK”类改动，先跑契约测试再跑 UI 回归，避免兼容假象。

## 验收标准
- 定向回归集全部通过
- Agent loop 新增失败分支测试通过
- AI 助手关键交互（模式切换、发送按钮、工具进度、smart_result）均有稳定断言
- 同一 provider 配置下，首页与助手请求路径语义一致（或被明确校验并给出阻断提示）
