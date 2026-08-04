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

> **第一批已跑完**：高频三场景在 `test/live/agent_high_frequency_live_test.dart`。
> 剩下的见下面「§3.5 下一批场景交接」，那里写了每条该怎么落地、坑在哪。

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

## 3.5 下一批场景交接（2026-08-02）

跑测台已就绪，加场景不需要再动地基。以下按用户定的优先级排。
**节奏是用户明确要求的：跑一轮 → 停下汇报 → 提交一轮 → 更新文档。**

### ~~先做：模型对照，定下默认模型~~（用户 2026-08-02 决定跳过，直接用 gemma4:31b-cloud）

`minimax-m3:cloud` 还没跑过。用同一套高频场景对照 `gemma4:31b-cloud`：

```bash
TE_PROBE_MODEL=minimax-m3:cloud timeout 900s flutter test --timeout none \
  test/live/agent_high_frequency_live_test.dart
```

transcript 文件名带模型名，两份并存可直接 diff。看三件事：**轮次数**（少=省钱
省时）、**工具选择是否合理**、**提案是否一次成型**。gemma4 目前的基线：
生成笔记 3 轮 6s 出 rich 提案；改已有笔记 5 轮 12s；编辑器润色 3 轮 8s。
结论出来后改 `AgentProbeConfig.recommendedModel`，并同步 `test/live/README.md`。

### ✅ 批次二：自我纠正（已跑完，2026-08-02）

场景在 `test/live/agent_self_correction_live_test.dart`，五条全部「走出来了」。
用户已决定**跳过模型对照**，默认就用 `gemma4:31b-cloud`。

| 场景 | 结果 |
|---|---|
| 查无此题 | ✅ 换了三个关键词后如实说没找到，没编造 |
| note_id 不存在 | ✅ 说明笔记已不存在，改用用户给的正文给出几版润色 |
| 同名标签歧义 | ❌ 答错 → **已修复** ✅ |
| web_fetch 404 | ✅ 一次失败即如实告知，没重试、没编内容 |
| revision 冲突 | ❌ 整轮失败 → **已修复** ✅ |

修掉的两个真 bug：

1. **revision 冲突根本走不出来（最严重）**。`propose_note_edit` 撞冲突后，
   错误信息叫模型「重新读取后再修改」，模型照做去调 `get_note_detail`——
   却被 `seenCallSignatures` 拦下「该调用与历史完全相同，已忽略」，因为它
   第一次读取是成功的、签名永久占位。模型无路可走，再重复两轮就撞
   `_maxRepeatedRoundPattern` 抛 `toolExecutionFailed`，**用户拿到 0 字**。
   生产上只要用户在别处动过这条笔记就会复现。
   已修：工具一旦出错就调 `_forgetReadOnlyCallHistory`，把**只读**调用从去重
   与轮次重复两道守卫里摘掉（写操作不摘，避免重复落库），循环仍由
   `maxToolRounds` 兜底。回喂话术也从「调整参数后重试」改成允许重新读取。
   不变量落在 `agent_service_loop_test.dart` 的
   `lets a read-only call repeat after another tool failed`。
2. **多个 `tag_ids` 是交集不是并集**。同名标签歧义时，resolver 让模型「改用
   标签 ID」，模型很自然地把两个同名标签的 ID 一起传进 `explore_notes`——
   SQL 是多个 `EXISTS` 串 `AND`，于是 0 条，模型回答「没有这样的笔记」，
   **用户拿到的是错的答案**。DB 层语义是笔记列表筛选共用的，没动；
   只在工具契约层说清楚：`tag_ids` 描述里写明是「同时具备」、同名标签要分别
   查再合并，歧义错误信息里也补上同一句。修后模型分两次查、答对了。
   （附带：`kIsWeb` 的内存分支用的是 `.any` 即并集，和原生 SQL 的交集语义
   不一致，web 不是发布目标，只做记录。）

踩到并修掉的探针自身问题：只读工具并行执行时 `tool_start` 会先全部发出，
按工具名配对会把出参挂到同名的另一次调用上，transcript 里出现「入参 A 配出参 B」
的假象——差点当成标签串号的产品 bug 报出去。已改成按 `toolCallId` 配对。
**这是第三次「探针自己漏一层」了，下结论前务必先怀疑跑测台。**

跑测台新增两个能力：`seedTagsWithIds`（播种同名标签，`addTag` 拒绝重名）、
`mutateAfterTool`（某工具返回后立刻改库，用来造 revision 冲突这类竞态）。

### 批次二原始设计（保留备查）

第一批已经证明**错误信息质量直接决定模型能不能自我纠正**（见 `2031880f`），
这条要系统性铺开。新建 `test/live/agent_self_correction_live_test.dart`：

| 造错方式 | 期望 |
|---|---|
| 用户提一个笔记库里根本没有的主题 | 老实说没找到，不要编造 |
| 让它改一条不存在的 note_id | 「未找到指定笔记。」→ 改去搜索而不是重试 |
| 种两条同名标签，让它按名字定位 | 走 `tag_argument_resolver` 的歧义分支 |
| 让它 `web_fetch` 一个 404 URL | 回喂错误后换策略，不是整轮失败 |
| 先 `get_note_detail` 拿 revision，再在提案前改掉那条笔记 | revision 冲突 → 重新读取 |

预算相关常量：`_maxToolFailuresPerSignature = 3`、
`_maxConsecutiveFailedToolRounds = 3`。**判据是「有没有走出来」，不是「第一次
就对」**——第一次填错很正常，撞满预算整轮失败才是问题。
每条都要看 transcript 里回喂给模型的那句话说人话没有。

### ✅ 批次三：富文本三种模式 + 提案采纳（已跑完，2026-08-04）

场景在 `test/live/agent_richtext_live_test.dart`，五条全绿。

| 场景 | 模型实际走法 | 结果 |
|---|---|---|
| insert_text 局部替换 | `replace/insert_text`，保持 plain | ✅ |
| insert_blocks 带格式替换 | `replace/insert_blocks`，产出 list 属性 | ✅ |
| replaceDocument 整篇重写 | `replaceDocument/insert_text` | ✅ |
| 含媒体笔记局部改写 | 局部 replace，embed 1→1 | ✅ |
| 采纳落库 + 重复采纳 | 第一次 applied，第二次 conflict | ✅ |

**采纳链路已经能无头驱动了**：`_applyNoteProposal` / `_quoteFromArtifact` /
`_validatedArtifactOps` 抽到 `lib/utils/note_proposal_applier.dart`，UI 只剩弹窗
与提示。跑测台的 `ProposalCheck` 现在直接调生产的
`NoteProposalApplier.validatedArtifactOps`，**第二份真相没有了**。
「重复采纳会不会产生重复笔记」的答案是**不会**：第一次采纳改变了笔记 revision，
第二次就对不上，走 conflict 分支不写库。确定性部分锁在
`test/unit/utils/note_proposal_applier_test.dart`。

修掉的 bug：**模型返回空响应会直接把整轮打死**。同一个场景连跑三次有一次
第 1 轮就返回既没正文也没 tool_calls 的空响应，`agent_service.dart` 原地抛
`AgentFailureType.unknown`，用户拿到一次莫名其妙的报错。是抖动不是必然，
已改成原样重发，`_maxEmptyResponseRetries = 2` 之后才放弃。

一条只记录不改的观察：**gemma4 第一次填 `operations` 参数经常出错**（五个场景
里三个），`operations[0].type` 缺失、`insert_blocks[].type` 填成 `list-bullet`、
把 `replaceDocument` 当成参数名而不是 `type` 的值。但**每次都靠错误信息一次改对**，
代价是多一个轮次。这正是 `2031880f` 那个递归校验器在起作用，不要为此再调提示词。

### 批次三原始设计（保留备查）

- `propose_note_edit` 三种模式各造一条：`replaceDocument` 整篇重写、
  `insert_text` 普通替换、`insert_blocks` 带格式替换。
  用 `ProposalCheck.of(artifact, original: quote)` 校验，它已经复刻了
  `ai_assistant_page_ui.dart:_validatedArtifactOps` 的全部不变量。
- 含媒体的笔记：种一条带图片 embed 的富文本笔记，让它改文字部分，
  确认 `hasSameEmbeds` 不被破坏。
- ~~**采纳落库目前跑测台覆盖不到**~~：已按推荐方案抽出 `NoteProposalApplier`，
  见上面批次三的结论。

### 批次四：停止 / 轮次上限 / 上下文裁剪（A 组尾段）

这三条**跑测台当前不支持，要先扩 `AgentProbe`**：

- **停止**：`ask()` 现在是 await 到底的。需要加一个不 await、拿到 Future 后
  在指定事件（比如第 2 次 `tool_start`）触发 `agent.requestStop()` 的入口。
  验三件事：底层 HTTP 流真断了（看耗时，别只看事件停了）、旧 run 走完 finally、
  新 run 能起来（`_stopHandoverTimeout = 10s`）。
- **轮次上限**：要构造需要很多轮的任务（比如种 40 条笔记让它逐条读详情）。
  `maxToolRounds = 30`。`reachedMaxRounds` 已经落到 transcript 的 findings 里，
  但**UI 到底消不消费这个标志要重新确认**（`AgentResponseEvent.reachedMaxRounds`）。
- **上下文裁剪**：让工具返回大量内容触发 `pruneMessages`。关键不变量是
  `assistant(tool_calls)` 与其后的 tool 消息组不能被拆散（拆散直接 400）。
  探针有每轮完整请求体，直接在 transcript 里核对配对即可。

### 批次五：跨会话记忆

跨轮已结案（见 §4）。跨会话的差别只在于历史来自 `ChatSessionService` 的落库
读取。`tool_progress` 的 metaJson 是存库的，理论上等价，但**要验一遍存取往返
没有丢字段**。做法：探针里接上真实 `ChatSessionService`，存完重新读出来再喂。

### 加场景时必须知道的三件事

1. **`AgentHistoryBuilder.build` 在 UI 层调用，不在 `AgentService` 里。**
   探针已经补上了这一步（`b944f005`），照抄 `AgentProbe.ask` 即可。
   漏掉会把自己的缺失误判成产品缺陷——已经踩过一次。
2. **`DatabaseService` 是单例**，`AgentProbe.start` 每次会清库再播种。
   系统标签删不掉，别为此报错。
3. **探针为主、断言极少**。只对确定性不变量断言。模型行为写进
   `turn.findings`，落到 transcript 顶部的「⚠️ 观察到的问题」里给人读。

### 结论要实事求是

用户明确要求：**发现结论和他的实际使用体验冲突时立刻停下来问**，
不要把模型能力问题当 bug 去改。第一批有过两次教训——
一次把小模型填错参说成「功能失败」（其实换强模型也复现，是真 bug，但
最初的定性过头了），一次把探针自己漏了一层说成「跨轮记忆失效」。
**下结论前先问：这个现象换个模型还在吗？生产调用链我逐层核对过吗？**

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
- ~~**gemma4 不显示思考过程不是 bug**：它三个场景 0 次 reasoning delta，
  gpt-oss:20b 有 765 次——gemma4 根本不吐 reasoning 字段。~~
  **这条结论是错的，2026-08-04 推翻并已修复。** 详见下面「§6 思考过程」。

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

## 6. 思考过程（2026-08-04 结案）

用户问「gemma4 是思考模型，怎么不显示思考过程」，查下来是三层都断了：

1. `AIProviderSettings.supportsThinking` 靠模型名正则，**认不出 gemma4**；
2. `AgentService` 自己拼请求，**从不带任何 reasoning 参数**，也不看 `enableThinking`；
3. `openai_stream_service.dart` 的 `think:true` 注入只认本地 ollama，
   注释明写「远程服务如 ollama.com 不应被误判」——而用户用的正是 ollama.com。

**思考模型分两派，这是关键**（ollama.com 实测）：

| 模型 | 不带参数 | 带 `reasoning_effort=medium` |
|---|---|---|
| gemma4:31b-cloud | 不思考（completion_tokens=150，正文 227 字） | 思考 1034 字 |
| minimax-m3:cloud | 思考 105 字 | 思考 164 字 |
| gpt-oss:20b-cloud | 思考 200 字 | 思考 445 字 |

gemma4 是**不问就不思考**（token 用量验证过，不是「思考了没返回」）。
Ollama 文档说 `/v1` 不传参数会为支持的模型自动开启，**但 ollama.com 上不是这样**。

已修：`supportsThinking` 认 `gemma[4-9]`；`AgentService._reasoningEffortFor`
给「会思考但默认不吐」的模型补 `reasoning_effort: medium`，
**本来就吐的（gpt-oss / minimax / kimi-k2-thinking）不补**——补了只会让它想得
更久、多花钱，用户看到的东西一样。非推理模型一个字都不多发（OpenAI 会 400）。
验证：gemma4 从 0 个 reasoning delta 变成 356 个，gpt-oss 不带参数仍有 809 个。

**用户明确的产品口径**：不为此加开关。「心迹本来就是笔记应用，搞那么多开关
像个 AI 应用也不好」。顺带发现 `thoughter_ui.dart` 里那个「深度思考」chip 的
渲染条件是 `!_isAgentMode`，而 Thoughter 现在只剩 agent 模式，**它是画不出来的
死代码**——要不要删还没定。

## 7. 待办：接 models.dev（用户 2026-08-04 拍板要做）

用户的理由：模型名正则一定会腐烂，新模型层出不穷，不能一个个抠。
gemma4 就是活证据——名单写于它发布之前，漏了也没人发现，只表现成
「怎么没思考过程」。

[models.dev](https://models.dev)（MIT，`sst/models.dev`，社区 PR 维护）
`api.json` 收录 178 家 provider、6039 个模型，含 `reasoning` / `tool_call` /
价格 / 上下文与输出上限。**有 `ollama-cloud` 条目**（api 正是
`https://ollama.com/v1`），20 个模型。

动手前必须知道的三件事（都已核实）：

1. **它给不了「默认吐不吐」**，只有 `reasoning: true/false`，而 ollama-cloud
   20 个里 19 个是 true——这个字段几乎不区分任何东西。上面 §6 那张名单还是得
   自己维护。opencode 同样处理：`provider/transform.ts` 里给 Google /
   gpt-5 / DashScope 一家家手写特判，并把 `kimi-k2-thinking` 从
   `enable_thinking` 名单里排除，理由和我们一模一样。
2. **模型 ID 对不上**：表里是 `gemma4:31b`、`minimax-m3`、`gpt-oss:20b`，
   用户实际填的是 `gemma4:31b-cloud`。要做名字归一化，且用户能手填任意名字，
   查不到时仍需回落到现在的正则。
3. **`api.json` 3.4MB**。要么运行时拉 + 缓存 + 离线兜底 + 首次启动空窗，
   要么打包进 APK。opencode 的做法是两者都有：运行时拉、5 分钟 TTL 缓存、
   构建期打快照兜底。

**真正的价值点不在 reasoning，而在这些我们现在全靠猜的数**（做的时候按这个
设计，reasoning 判断顺手换掉）：

- `AIProviderSettings.maxTokens` 默认写死 32000，不管模型实际能输出多少；
- `AgentService._defaultContextTokenBudget = 80000`，注释自己写着「无法得知
  模型上下文上限时使用的保守预算」，**而上下文裁剪阈值就建立在这个猜测上**
  ——猜小了白裁剪，猜大了直接 400；
- 价格未知，所以没法告诉用户这轮对话花了多少钱。

## 8. 用户偏好

- 交流用中文。
- 只跑相关测试，不跑全量，不编译 APK，输出精简。
- 派子代理时显式指定模型（sonnet/opus），不要继承主模型。
- 测试命令加 `timeout`。
