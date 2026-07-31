# Agent 真实 API 跑测台

无头驱动完整 `AgentService.runAgent` 循环，用真实 API，把每轮的**请求体、模型返回的
tool_calls、工具入参出参、事件流**全部落到 transcript 文件供人阅读。

**定位是探针，不是断言式测试。** 模型行为有随机性，写死断言只会得到无谓的红叉。
只有确定性不变量才断言：Delta 合法性、`content` 与 `deltaContent` 一致、媒体不丢失。

## 跑

```bash
timeout 900s flutter test --reporter compact --timeout none \
  test/live/agent_high_frequency_live_test.dart
```

transcript 落在 `build/agent-probe/<场景>-<模型>.md`（`build/` 已在 .gitignore 里）。

换模型对照：

```bash
TE_PROBE_MODEL=minimax-m3:cloud timeout 900s flutter test --timeout none \
  test/live/agent_high_frequency_live_test.dart
```

## 凭据

**绝不入库。** 只从环境变量或仓库外文件读：

| 来源 | 优先级 |
|---|---|
| `TE_TEST_API_KEY` / `TE_TEST_BASE_URL` / `TE_TEST_MODEL` 环境变量 | 高 |
| `AGENT_TEST_*` 环境变量 | 中 |
| `~/.thoughtecho-dev/agent-test.env`（`chmod 600`） | 低 |

未配置密钥时整组跳过，不会因为缺凭据而失败。

## 模型

| 模型 | 用途 |
|---|---|
| `gemma4:31b-cloud` | **默认**。普通用户能用到的较好档位，快、不显示思考过程 |
| `minimax-m3:cloud` | 更强，gemma4 表现不好时的对照 |
| `gpt-oss:20b-cloud` / `120b-cloud` | 不推荐做主力；容错路径压测、每日提示这类小任务可用 |

小模型填错参是常态，重点是**兜底是否到位**（错误信息能否让模型一次改对），
而不是针对某个模型调参。

## 结构

- `agent_probe.dart` — 跑测台本体
  - `AgentProbeConfig`：凭据与模型
  - `AgentProbe.start(...)`：装好 sqflite FFI、path_provider、安全存储
    MethodChannel 替身，起真实 `DatabaseService` 并按场景播种笔记与标签，
    挂上和 `app_providers.dart:_buildAgentTools` 一致的真实工具
    （只有定位与天气换成确定性替身）
  - `AgentProbe.ask(...)`：发一轮，历史按 `ai_assistant_page_agent.dart` 的形状
    构造（含 `tool_progress` 元数据），所以「记不记得住」的结论对生产有效
  - `ProposalCheck`：复刻 `ai_assistant_page_ui.dart:_validatedArtifactOps`
    的采纳前校验——采纳逻辑长在 UI 里无头跑不动，这里保住同一组不变量
- `agent_high_frequency_live_test.dart` — 用户高频场景

## 两个必踩的坑（已经踩过）

1. `flutter_test` 默认注入返回 HTTP 400 的 mock HttpClient，
   必须 `HttpOverrides.global = null` 才能走真实网络。
2. 推理模型的思考 token 计入 `max_tokens`，预算小会让 `content` 全空。

## 生产侧改动

只有一个：`AgentService` 新增可选的 `requestObserver`（`AgentRequestObserver`），
请求前只读回调，不参与任何生产逻辑。没有它就拿不到真实请求体。
