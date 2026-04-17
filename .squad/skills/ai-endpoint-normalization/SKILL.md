---
name: ai-endpoint-normalization
description: 统一 AI Provider 的 base URL / endpoint 语义，避免链路间 405 分裂
---

# AI Endpoint Normalization

## 适用场景
- 同一 provider 在不同请求链路表现不一致（一个成功、一个 405）
- 用户可能填入 base URL（如 `/v1`）或完整 endpoint（如 `/v1/chat/completions`）
- 混合支持 OpenAI 兼容接口与 Anthropic messages 接口

## 核心模式
1. 在 `AIProviderSettings` 增加统一 URL 解析方法（如 `resolveRequestUrl`）。
2. 解析逻辑必须遵循：
   - OpenAI 兼容：`/v1` 自动补全 `/chat/completions`，完整 endpoint 保持不变；
   - Anthropic：`/v1/messages` 保持原样，禁止补全 OpenAI 后缀。
3. 在网络层唯一入口（`AINetworkManager.makeRequest/makeStreamRequest`）调用解析方法，禁止 UI 或业务层各自拼接。
4. provider 能力判定（如 Agent 是否支持 Chat Completions）复用同一语义字段，避免重复 if-else。

## 验证清单
- 单测覆盖 4 类 URL：
  - OpenAI `/v1` → 自动补全
  - 已是 `/chat/completions` → 不变
  - Anthropic `/v1/messages` → 不变
  - custom 非兼容地址 → 不变
- 冒烟验证：
  - AI 助手请求
  - 首页每日提示请求
  - 两条链路同一配置均可用
