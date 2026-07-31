# Thoughter Agent 工作交接（2026-07-31）

> 给接手的下一位：先读 `AGENTS.md`，再读本文。本文只讲 agent 这条线。

## 0. 凭据（不要写进仓库）

用户提供的真实 API 凭据已存在**仓库外**：

```bash
~/.thoughtecho-dev/agent-test.env   # chmod 600
# AGENT_TEST_BASE_URL=https://ollama.com/v1
# AGENT_TEST_MODEL=gpt-oss:20b-cloud
# AGENT_TEST_API_KEY=...
```

用户明确授权用它跑真实 API 测试。可用模型：

| 模型 | 特点 |
|---|---|
| `gpt-oss:20b-cloud` | 推理模型，思考约 90 token；**测 tool calling 用这个** |
| `minimax-m3:cloud` | 推理模型 |
| `gemma4:31b-cloud` | 不推理，最快最省，跑冒烟用这个 |

**红线**：密钥不得进入源码、测试夹具、日志、截图或提交。测试只从环境变量读。
仓库测试统一用 `TE_TEST_API_KEY` / `TE_TEST_BASE_URL` / `TE_TEST_MODEL`，未设置则整组跳过。

## 1. 已完成（已推送到 main）

### `578ce45c` 修好每日提示与会话标题

两个根因，都已验证修复：

1. `_isValidApiKeyFormat` 是前缀白名单（只认 `sk-`/`sk_`/`or_`/`Bearer `），把
   Ollama Cloud、Gemini、智谱、API Ninjas 的密钥全判成非法 →
   `hasValidApiKeyAsync()` 返回 false → 每日提示退默认模板、标题退本地截断。
   agent 不受影响是因为它取密钥只要求非空。已改为基本体检（长度 + 无空白/控制字符）。
2. 推理模型的思考 token 计入 `max_tokens`。标题写死 30、每日提示写死 100，
   `content` 还没开始输出就被 `finish_reason: length` 截断。已提到 512 / 800。

### `75f7d9d4` 会话历史带上工具轨迹

`_askAgent` 原来用 `m.metaJson == null` 把所有带元数据的消息整条排除，
而工具轨迹恰恰存在 `tool_progress` 消息的 metaJson 里（早就落库了）。
新增 `lib/utils/agent_history_builder.dart` 把它压成摘要喂回模型。
历史预算 4000 → 12000 字符。

**⚠️ 这一条只有单元测试，没有任何真实 API 或真机验证。**「记得住」和
「表现得更主动」之间还隔着模型自己的行为，需要下面的跑测台来确认。

### `2031880f` 跑测台建成，第一轮就修掉「改已有笔记撞死」

跑测台在 `test/live/`，用法见 `test/live/README.md`。**探针为主、断言极少**：
真实 API 驱动完整 loop，请求体/tool_calls/工具入参出参/事件流落到
`build/agent-probe/<场景>-<模型>.md`；只对 Delta 合法性、
`content`/`deltaContent` 一致这类确定性不变量断言。
生产侧只加了一个只读的 `AgentRequestObserver` 钩子。

第一轮（三个高频场景）结果：

| 场景 | gpt-oss:20b | gemma4:31b |
|---|---|---|
| 生成笔记 | ✅ create/plain | ✅ create/**rich** |
| 改已有笔记 | ❌ 整轮失败 | ❌ 整轮失败 → **已修复** ✅ |
| 编辑器润色 | 未跑 | ✅ edit/plain |

「改已有笔记」的根因**与模型强弱无关**：`operations` 漏了 `type` 字段，
而 `tool_argument_validator` 只校验顶层、不下钻数组元素，items 里的
`required: ['type']` 形同虚设；错参一路放行到深处，以
`不支持的富文本操作: null` 的形式漏给模型，模型无从纠正，
原样重试撞满 `_maxToolFailuresPerSignature`，整轮 `toolExecutionFailed`，
用户拿到 0 字回复。编辑器入口下模型更容易带上 `type`，所以那条路径看着是好的。

已修：校验器递归下钻，错误带路径（`operations[0].type`），嵌套层就地列出可接受
字段。修复后同一场景模型一次改对。

**这条的教训值得记住**：schema 里声明了约束不等于约束生效；
喂回模型的错误信息质量直接决定它能不能自我纠正。

## 2. 跑测台（✅ 已建成，见上；以下为当初的设计约束，仍然有效）

目标：无头驱动完整 agent loop，用真实 API，把每轮的请求体、模型返回的
tool_calls、工具入参出参、事件流全部落到 transcript 文件，供人读。

现成的地基（别重造）：

- `test/test_harness.dart`：sqflite FFI + path_provider 假实现，已可用
- `test/integration/ai_service_live_features_test.dart`：真实 API 测试的写法样板，
  含安全存储 MethodChannel mock
- `AgentService` 构造支持注入 `apiKeyResolver` 和 `completionRequester`
  （见 `test/unit/services/agent_service_loop_test.dart` 的 `_FakeSettingsService`）
- 工具列表构造见 `lib/providers/app_providers.dart:_buildAgentTools`

**两个必踩的坑**（已经踩过，别再踩）：

1. `flutter_test` 默认注入返回 HTTP 400 的 mock HttpClient。测试里必须
   `HttpOverrides.global = null;` 才能走真实网络。
   （`test/integration/ai_service_integration_test.dart` 此前就是因为这个从来跑不通。）
2. 推理模型的思考 token 计入 `max_tokens`，小预算会让 `content` 全空。

## 3. 测试内容清单（用户点名要盯的）

### A. agent 运行时行为是否符合预期

- **跨轮记忆**（验证 `75f7d9d4`）：第一轮让它查某个主题的笔记，第二轮问
  「你刚才查到的那几条里，哪条最长？」——看它是直接回答，还是又调一次
  `explore_notes`。后者说明轨迹没喂进去或者模型没在用。
- **跨会话记忆**：存库后重开会话，问同样的追问。
- **工具选择**：模糊请求（「随便写点」「帮我记一下」）应该先调
  `get_location_weather` / `explore_notes` / `get_tags` 建立上下文再动笔，
  这是 system prompt 明写的期望（`agent_service.dart:_buildSystemPrompt`）。
  实际是不是这样，跑了才知道。
- **自我纠正**：故意让它拿到不存在的 note_id、不唯一的标签名、404 的网页。
  期望是把错误回喂模型让它改，而不是整轮失败。相关预算：
  `_maxToolFailuresPerSignature = 3`、`_maxConsecutiveFailedToolRounds = 3`。
- **停止**：跑到一半 `requestStop()`，确认底层 HTTP 流真的断了、旧 run 走完
  finally 清理、新 run 能正常启动（`_stopHandoverTimeout = 10s`）。
- **轮次上限**：构造需要很多轮的任务，看 `maxToolRounds = 30` 命中时的表现。
  注意 `reachedMaxRounds` 定义了但 UI 是否消费过要重新确认。
- **上下文裁剪**：让工具返回大量内容，确认 `pruneMessages` 触发且
  `assistant(tool_calls)` 与其后的 tool 消息组没被拆散（拆散会直接 400）。

### B. 富文本是否正常（用户特别点名）

- `propose_note_create` 走 `rich` + `document_blocks` 时，生成的 Quill Delta
  是否合法、能否被编辑器打开。
- `propose_note_edit` 的三种模式：`replaceDocument` 整篇重写、`insert_text`
  普通替换、`insert_blocks` 带格式替换；文本锚点必须唯一匹配。
- **`content` 与 `deltaContent` 必须一致**（AGENTS.md 硬性要求）。采纳提案后
  落库的笔记两个字段是否同步，是最容易出问题的地方。
- 含媒体的笔记：只允许不跨越媒体的局部文本修改，验证它不会把媒体搞丢。
- 相关代码：`lib/utils/agent_note_document_codec.dart`、
  `lib/utils/quill_delta_builder.dart`、`lib/utils/quill_structured_edit.dart`。

### C. 提案卡片

- 采纳后是否回写状态、能否重复采纳产生重复笔记。
- `_buildProposalAdoptionNotice` 是否真的让模型知道用户已采纳。

## 4. 已确认仍然存在的问题（可以直接开工）

- **预设 provider 加 Ollama**：用户要求把 `gemma4:31b-cloud` /
  `minimax-m3:cloud` 这档普通用户能用到的模型加进预设
  （`lib/constants/ai_provider_presets.dart`）。用户说已经加了一部分，
  接手前先看现状。注意这和本节末尾「先不用管」那条是用户后来改的口径，
  以这条为准。

### 已查证结案的（别再当待办）

- **跨轮记忆是好的**（`75f7d9d4` 生效）。曾一度误判为失效，原因是跑测台没走
  UI 层：`AgentHistoryBuilder.build` 在 `ai_assistant_page_agent.dart:_askAgent`
  里调用，**不在 `AgentService` 内部**。探针直接喂原始消息给 `runAgent`，
  轨迹从没被构造出来。补上后第二轮追问 1 个模型轮次、0 次工具调用，直接依据
  `[已执行的工具轨迹]` 作答。见 `b944f005`。
- **思考过程混进洞察正文**（`23030f41` 已修）。根因在
  `processStreamToText`：没有 `onThinking` 时把 reasoning 当正文的兜底，
  `chunks.isEmpty` 判的是单个 event 而不是整条流，而推理模型的 reasoning
  总是先于 content 到达。已改成攒到流末再判。真实 API A/B 验证过。
- **gemma4 不显示思考过程不是 bug**：它三个场景 0 次 reasoning delta，
  gpt-oss:20b 有 765 次——gemma4 根本不吐 reasoning 字段。

- **每次运行最多一个提案，但提示词说的是「每轮」**。`proposalCreated` 声明在
  `agent_service.dart:283`，`while` 在 `:291` —— 作用域是整次运行。而喂给模型的
  错误信息（`:509`）和 system prompt（`:1079`）都写「每轮最多一个」，模型会以为
  下一轮还能提，反复撞墙。**「帮我把这几条整理一下」这类多步任务做不了。**
  修法二选一：改成真正的每轮一个，或者把文案改成「本次对话最多一个」。
- **agent 不支持 Anthropic**：`_supportsChatCompletions` 就一行
  `!provider.isAnthropicMessagesApi`，命中直接抛 `unsupportedProvider`。
- **预设 provider 只有 5 个**（openai/anthropic/openrouter/deepseek/custom），
  没有 ollama、硅基流动、智谱等，用户得手填 URL。
  **用户明确说这条先不用管，之后慢慢来。**

## 5. 别踩的坑

- **仓库根的 `THOUGHTER_ISSUES_REPORT.md`（7-26 那份）已经部分过期**，不要当待办
  清单。里面 P0 的 fail-fast、假取消、上下文不裁剪三条，看现在的
  `agent_service.dart` 都已经修了（`_maxToolFailuresPerSignature`、
  `_stopHandoverTimeout`、`_pruneThresholdRatio`）。动手前先核对源码。
- **这个仓库有并发会话在改**。工作期间多次出现别的进程修改甚至 stage 文件。
  提交前务必 `git diff --cached --name-only` 核对，只 `git add <明确文件>`，
  必要时用 `git commit -- <pathspec>` 绕开被别人污染的 index。
- **commit message 不要加 `Co-Authored-By`**（用户明确要求）。
- 上下文压缩（compaction）用户说**先不做**。
- pi / opencode / gemini-cli 这些参考实现全是 Node/TS，**不能桥接进 Flutter**
  （需要在 App 里塞 JS 运行时，iOS 禁 JIT 直接不可行）。只借鉴设计。
  chatbox 是 **GPLv3**，ThoughtEcho 是 MIT，**不能抄它的代码**。
  本地参考源码在 `~/ai-reference/`（含 pi、opencode、gemini-cli）。

## 6. 用户偏好

- 交流用中文。
- 只跑相关测试，不跑全量，不编译 APK，输出精简。
- 派子代理时显式指定模型（sonnet/opus），不要继承主模型。
- 测试命令加 `timeout`。
