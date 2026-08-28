# Thoughter Agent 问题探查报告 [已归档 / 历史核销]

> [!NOTE]
> **文档状态**：📦 归档 / 问题核销（2026-07-26 产出，已全面核销）  
> **说明**：本文档为早期 Thoughter Agent 及 UI 的问题探查报告。报告中列出的 32 项问题中 **31 项已彻底解决或经设计确认闭环**（详见第五节核实结论），仅剩 1 项技术待办（Thinking 思考链入库）。  
> **当前生效事实源**：[`agent-memory-research-2026-08-08.md`](agent-memory-research-2026-08-08.md) 与 [`decisions.md`](decisions.md)。本文档保留用于历史排查与决议追溯。

> 生成日期：2026-07-26
> 范围：agent 核心设计（`agent_service.dart`、`agent_tools/`）+ 智能卡片与对话 UI（`smart_result_card.dart`、`ai_assistant_page_ui.dart` 等）
> 结论先行：**agent 的循环骨架是对的（原生 tool calling、runId 隔离），但错误处理策略、取消语义、死代码双协议这三件事把实际成功率和可维护性拉垮了。**

---

## 一、最致命的 5 个问题（P0）

### 1. 工具一失败，整轮对话报废，已生成的内容还被删掉

- **证据**：`lib/services/agent_service.dart:432-459` —— 工具返回错误时，只有 `retryable == true` 且纠正预算（**只有 1 次**，`agent_service.dart:939-949`）没用完才把错误喂回模型，否则直接 `throw AgentRequestException` 终止整个循环。而大多数工具的错误根本没设 `retryable`（`get_note_detail_tool.dart:52-57`、`web_fetch_tool.dart:83-87`、`web_search_tool.dart:136-140` 等，默认 false）。
- **雪上加霜**：UI 收到错误事件后 `_messages.removeWhere(...)` 把**已经流式输出的正文整段删除**（`ai_assistant_page_agent.dart:198-206`），用户只看到一个"发生错误"的 SnackBar。
- **后果**：模型编错一个 note_id、网页 404、搜索超时——任何一个都让整轮归零。agent 的核心价值本来就是靠工具报错自我纠正，这里被做成了 fail-fast。
- **修复**：工具错误默认作为 tool message 回给模型（同一签名限 3 次），只在连续多轮全失败时终止；终止时保留已输出内容。

### 2. 「停止」按钮制造真并发，旧循环停不下来

- **证据**：`requestStop()` 直接 `_activeRunId = null; _isRunning = false;`（`agent_service.dart:160-172`），但正在 await 的 HTTP 流（`:643`）和工具执行（`:815`）**并没有被取消**，只是事件被静音。并发保护判断的正是 `_activeRunId != null`（`:182-183`）。
- **后果**：用户点停止再发一条消息 → 旧循环仍在后台跑（最长 3 分钟 HTTP + 45s×N 工具），继续烧 token、继续读写数据库，新旧两个循环互踩状态；旧循环的 `finally` 清理（`:513-521`）还不执行。
- **修复**：引入取消令牌 / per-run HTTP Client，`requestStop` 只置标志并 `client.close()`，让 `runAgent` 自己走 finally 清理。

### 3. 三个 propose 工具是死代码（约 500 行），UI 里养着两套提案协议

- **证据**：实际注册的只有 `ProposeNoteCreateTool` + `ProposeNoteEditTool`（`lib/providers/app_providers.dart:43-56`）。`propose_edit_tool.dart`（142 行）、`propose_new_note_tool.dart`（168 行）、`propose_rich_edit_tool.dart`（194 行）**从未注册**，只在单元测试里被 new——测试全绿，制造虚假信心。
- **连带死掉的 UI**：`ai_assistant_page_agent.dart:683-726` 还在为这三个不可能出现的工具名做分支；`ai_assistant_page_ui.dart` 里 `_openSmartResultInEditor`（:765-862）、`_saveSmartResultToExistingNote`（:1317-1496）等约 400 行"采纳到已有笔记"逻辑没有活的触发者。`smart_result` 代码块协议和 `NoteProposalArtifact` 协议双轨并存，`NoteProposalCard` 与 `SmartResultCard` 两张语义重叠的卡片同时维护。
- **修复**：删掉 3 个未注册工具 + 对应测试 + UI 解析分支，只留 artifact 协议一条路。

### 4. 上下文零裁剪，30 轮工具输出无上限累积

- **证据**：`agent_service.dart:212` 起的 while 循环 `messages` 只增不减，上限 30 轮（`:131`），每条工具消息 5000 字符 → 极限约 15 万字符，最后 `_requestFinalSummary`（`:695-718`）还把整包再发一次。没有 token 统计、没有 `finish_reason` 检查、没有整轮超时。`reachedMaxRounds` 定义了但全项目从未被 UI 消费。
- **后果**：长任务成本随轮数二次增长，到后期极可能超上下文报错——然后走问题 1 的路径整轮报废，用户只看到转圈。
- **修复**：滑动窗口——保留 system + 最近 K 轮完整结果，更早的替换为一行摘要；UI 显示"已达轮次上限"。

### 5. 润色/续写的结果卡片被永久判成"只读"，按钮全灰，功能等于废了

- **证据**：`ai_assistant_page_ui.dart:254` 用 `meta['rich_edit'] == null` 判定 legacy 只读，而唯一还在产出 smart_result 的 `_runEditableWorkflow`（`ai_assistant_page_workflow.dart:160-166`）只写 `{'type','command','title','action'}`，**从不写 `rich_edit`** → 卡片两个操作按钮（`smart_result_card.dart:555, 563`）永远被禁用。现有测试手动传 `readOnly` 默认值所以测不出来。
- **修复**：只读判定改用显式 `meta['legacy']` 标记，或让工作流补齐可采纳字段。

---

## 二、agent 设计层面的重要问题（P1）

| # | 问题 | 关键证据 | 后果 |
|---|------|---------|------|
| 6 | **对已序列化的 JSON 再做字符串转义 + 从中间硬截断**，喂给模型的是坏 JSON | `agent_service.dart:1100-1122` 把 ``` 替换成 `\`\`\``（JSON 里非法转义）；`:1001-1006` 5000 字符处砍断且不告知模型 | 笔记里含代码块时工具结果整个不可解析；分页 `has_more` 被砍掉导致翻页判断错 |
| 7 | **上线工具的 schema 几乎零 description**，复杂契约只在运行时报错，而纠正只有 1 次机会 | `propose_note_create_tool.dart:22-43` 全裸类型；`propose_note_edit_tool.dart:59` `metadata_patch: {'type':'object'}` 无子结构；`explore_notes_tool.dart` schema **没声明 `tag_ids`** 但 system prompt 要求模型传它（`agent_service.dart:914`） | 最常用的写操作和检索工具的成功率全凭模型运气，猜错即触发问题 1 |
| 8 | **`maxTokens: 2000` 硬编码** + 不检查 `finish_reason=='length'` | `agent_service.dart:248, 643-668` | 富文本提案（`document_blocks` 嵌套 JSON）被截断成非法 JSON，报的却是"参数不是有效 JSON"，确定性失败且误导排查 |
| 9 | **全局去重把合法重复调用永久封杀** | `seenCallSignatures` 是整个 run 级别（`:207, 379-388`）；`get_location_weather` schema 为空对象，签名恒相同，第二次调用永远被拒 | "改完再读一遍确认"这种正常模式被禁止，死锁路径直通整轮失败 |
| 10 | **工具的具体错误信息双向丢失** | 发给 UI 时 `result: isError ? '' : content`（`:423-430`）；喂回模型的是恒定字符串"工具执行失败…"（`:959-961`），把工具精心构造的提示（如"标签名不唯一，请改用 ID"）全部丢掉 | 模型拿不到可执行信息第二次必然再错；用户只看到 7 类泛化文案；另有连续三处 `catch (_) {}` 空吞（`ai_assistant_page_agent.dart:289-329`） |
| 11 | **绑定笔记的 revision 有两个来源，其中一个天然过期** | `ai_assistant_page_agent.dart:220-232` 用打开助手时的快照算 revision 写进 prompt，prompt 又要求用 `get_note_detail` 的最新值 | 冲突校验失败 → retryable 但只有 1 次机会且重试拿的还是旧值 → 整轮失败 |
| 12 | **System prompt 全中文硬编码且与实现不同步** | `agent_service.dart:888-928`；"每轮最多一个提案"（:911）实际实现是**每次运行**最多一个（`proposalCreated` 在 while 外，`:206`），错误提示持续误导模型重试 | 英文用户体验割裂；prompt 与 schema 双份维护必然漂移 |

---

## 三、智能卡片与 UI 呈现问题

### 交互与数据（P1）

13. **「打开编辑器」不回写状态 → 可重复采纳产生重复笔记**：`smart_result_card.dart:555` 的按钮不判断 `isSaved`，`_handleOpenInEditor`（:640）也不回调 `onSavedNoteId`；create 路径每次 `_uuid.v4()` 新 id（`ui:1652`）。对比 `NoteProposalCard:168` 有 `_completed` 保护——两张卡行为不一致。
14. **卡片滚出视口，用户的位置/天气勾选被静默重置**：普通 `ListView.builder` 无 keepAlive（`ui:71-78`），勾选只存在 State 里从不写回 `metaJson`（`smart_result_card.dart:371-372`）。长会话往上滚再回来，勾选无声消失。
15. **agent 给的 `reason`（为什么这么改）在 UI 层被整体丢弃**：工具产出了 `reason`，但 `ai_assistant_page_agent.dart:346-360` 构造 metaJson 时不拷贝，SmartResultCard 也没有展示位。用户面对"要改你笔记"的卡片看不到任何理由。
16. **思考过程与消息状态不入库**：`chat_message.dart:69-81` 的 `toMap()` 不含 `state`/`thinkingChunks`（`toJson()` 却含）。重开历史会话后所有思考块消失——与"思考显示 SOTA"的定位自相矛盾。
17. **缺「拒绝/忽略」动作，采纳后也没有「查看笔记」出口**：不想要的提案永久停在消息流里且按钮可点（叠加问题 13 极易误触）。
18. **富文本 delta 从不预览**：`smart_result_card.dart:452-455` 只有 `MarkdownBody(widget.content)`，`rich_document` 从未参与渲染（`NoteProposalCard._DocumentPreview` 明明有正确实现可复用）。
19. **create/append/replace 视觉上完全无差别**：卡头固定图标+标题（:421-446），`replace` 是破坏性覆盖却零警示，也不显示目标笔记是哪条。
20. **AI 页面所有 Markdown 链接点不动**：`ui:605`、`smart_result_card.dart:452`、`ai_workflow_cards.dart:87`、`thinking_widget.dart:236` 四处 `MarkdownBody` 均无 `onTapLink`——agent 有 web 搜索能力，返回的链接却全部无法访问。项目里 `markdown_message_bubble.dart:91` 已有正确实现未被复用。
21. **渲染异常静默吞掉**：`ui:226` 解析失败 `SizedBox.shrink()` 整条消息凭空消失；`ui:512-519` catch 后 fall-through 成普通气泡，用户看到一段没有按钮的正文，不知道有过提案。
22. **原始异常字符串直接展示给用户**：`smart_result_card.dart:672` `_saveError = e.toString()`，卡片里出现 `Exception: 没有匹配的标签: xxx` 这类文案，且没有"去创建标签"的补救入口。

### 流式与状态机（P2）

23. **流式文本有被清空的路径**：`AgentThinkingEvent` 只清文本不清 `streamingMsgId`（`ai_assistant_page_agent.dart:80-81`），特定轮次下一轮会把上一轮已显示的正文覆盖清空。
24. **spinner 卡死路径**：第二个提案被忽略的 `continue` 分支不发 result 事件（`agent_service.dart:412-421`），对应 `ToolProgressItem` 永远转圈。
25. **列表项无 key、卡片用常量 key**：`ui:75-77` itemBuilder 无 key，卡片内却用固定 `ValueKey('ai_workflow_result_smart_result')`（:319）——流式插入消息导致索引位移时，`_savedNoteId`/勾选状态可能被复用到**另一条消息**上。
26. **ThinkingWidget 完成时强制折叠**，覆盖用户手动展开（`thinking_widget.dart:81-87`）。
27. **只读卡片上的位置/天气开关仍可点**：`canChangeMetadata` 未纳入 `readOnly`（`smart_result_card.dart:398-402`）——这正是问题 5 场景下唯一"能动"的控件，纯误导。
28. **`_MetaToggleChip` 触控面积约 23dp**（远低于 48dp）、无 Semantics、禁用态视觉失效（:796-813）。建议直接换 `FilterChip`。

### 代码质量（P2）

29. **`ai_assistant_page_ui.dart` 是伪 UI 上帝文件**：1698 行里约 900 行（:765-1698）是数据库写入、定位/天气权限、delta 合并等业务逻辑；`_buildMessageBubble` 是 300 行的 switch，在 build 里做 `jsonDecode` 和 `context.read`——每帧重算。同一段 tagIds 抽取逻辑重复 4 处。
30. **约 620 行死 widget**：`AIAssistantAgentStatusPanel`（149 行）与 `ToolCallCard`（473 行）在 `lib/` 内零使用点，还带硬编码颜色（`assistant_agent_status_panel.dart:69`）。
31. **`editorSource` 是死参数**：`smart_result_card.dart:329` 声明后文件内零次读取，调用方和测试却一路在传——制造"分支逻辑存在"的假象。
32. **杂项**：`setState` 里做 jsonDecode + 异步 DB 写（`ui:1105-1122`）；工具结果 `maxLines: 5` 硬截断无展开（`tool_progress_panel.dart:365`）；`web_search_tool.dart:194` `isChinese ? 'auto' : 'auto'` 两分支相同；`get_note_detail` 对 tagId 做 N+1 查询（`get_note_detail_tool.dart:66-71`）；流式 + `RetryPolicy(maxRetries: 2)` 重试会重复输出已推送的 delta（`agent_service.dart:691`）。

---

## 四、修复优先级建议

**第一批（直接决定 agent 能不能用）**
1. 工具错误改为默认可恢复、回喂模型，终止时不删已输出内容（问题 1、10）
2. 修复 `requestStop` 的假取消（问题 2）
3. 修复润色/续写卡片全灰（问题 5）+ 采纳状态回写防重复笔记（问题 13）

**第二批（大扫除，降维护成本）**
4. 删除 3 个未注册 propose 工具 + smart_result 死分支 + 620 行死 widget，统一到 NoteProposal 单协议（问题 3、30、31）
5. 上下文滑动窗口 + `finish_reason` 检查 + maxTokens 取 provider 配置（问题 4、8）

**第三批（体验打磨）**
6. 工具 schema 补 description/enum/子结构（问题 7）
7. 卡片：reason 展示、拒绝按钮、action 差异化、delta 预览、链接可点（问题 15、17、18、19、20）
8. 思考过程入库、列表 key 修正、Chip 可访问性（问题 16、25、28）

---

*本报告由两个并行代码审查 agent 深读源码生成，全部结论均附 file:line 证据，可直接定位。*

---

## 五、问题修复与未修复状态核实结论（2026-07 最新核实）

项目已对本报告提及的 32 个问题进行了全面重构、核实与设计收敛确认：

- **针对核心功能与 Bug 修复**：共 31 项已被解决或经设计确认闭环（已修复 29 项 + 设计明确非需求 2 项）。
- **真正的未修复项仅剩 1 项**：问题 16（思考过程与消息状态未入库保存）。

具体分类说明如下：

### 1. 已完全修复的问题（共 29 项）

- **P0 致命问题（全 5 项已修复）**：
  1. **工具错误整轮报废**：`agent_service.dart` 错误默认改为 `retryable` 并回喂给模型进行自我纠正；`ai_assistant_page_agent.dart` 的 `AgentErrorEvent` 中保留流式正文，废除 `removeWhere`。
  2. **`requestStop` 假取消与真并发**：`requestStop()` 增加 `_stopRequested` 标志，立即关闭底层 `_activeStreamClient` 中断 HTTP 流，在 `runAgent` 的 `finally` 块中统筹退出与状态清理。
  3. **3个死工具与双协议冗余**：清理了 `propose_edit_tool`、`propose_new_note_tool`、`propose_rich_edit_tool` 及 `smart_result_card.dart`；统一归集至 `NoteProposalArtifact` 协议与 `NoteProposalCard`。
  4. **上下文零裁剪与无上限累积**：实现 `AgentService.pruneMessages()` 零 LLM 成本裁剪，保留最近 K 轮工具结果；UI 接入 `l10n.agentReachedMaxRounds` 上限提示。
  5. **润色/续写卡片全灰**：`smart_result_card` 废除，`NoteProposalCard` 根据 `artifact.readOnly` 动态判断按钮禁用/启用状态。

- **P1 设计与架构问题（11 项已修复）**：
  - **问题 6（坏 JSON 破防）**：抽取 `untrusted_text.dart`，只在 `jsonEncode` 前转义单个自由文本字段，不再截断整段 JSON。
  - **问题 7（Schema 无 description）**：补齐所有工具（`propose_note_create`、`propose_note_edit`、`explore_notes` 等）Schema 的 `description`、`enum` 与 `tag_ids` 字段。
  - **问题 8（maxTokens 2000 硬编码）**：改为读取 `provider.maxTokens`，并加入 `finish_reason == 'length'` 截断检测与针对性重试提示。
  - **问题 9（去重死锁）**：错误调用不再占据全局签名名额（`seenCallSignatures.remove(failureKey)`），允许调整参数后重试。
  - **问题 10（错误信息双向丢失）**：将具体错误信息包裹后回喂模型，UI 暴露真实异常描述。
  - **问题 11（Revision 天然过期）**：统一使用 `ProposeNoteEditTool.revisionForQuote()` 哈希算法计算 Revision。
  - **问题 12（System prompt 中文硬编码/矛盾）**：Prompt 根据应用 Locale 动态提示语言，并同步“每次运行最多一个提案”逻辑。
  - **问题 13（采纳防重复）**：采纳后设置 `_completed = true` 并回调 `onProposalApplied`，在编辑器打开亦设置已完成状态。
  - **问题 14（视口滚动重置勾选）**：统一至 `NoteProposalCard` 并在 State 中维护勾选意图。
  - **问题 18（富文本 Delta 预览）**：`_DocumentPreview` 接入 `QuoteContent` 完成真实 Quill Delta 渲染。
  - **问题 20（Markdown 链接点击）**：全 AI 界面（`ai_assistant_page_ui`、`ai_workflow_cards`、`thinking_widget`）的 `MarkdownBody` 均配齐 `onTapLink`。

- **P2 UI 流式与代码质量问题（13 项已修复）**：
  - **问题 21（渲染异常静默吞）**：增加全异常捕获与解析兜底。
  - **问题 22（原始异常展示）**：统一转换为 `l10n.agentErrorGeneric` 等可读国际化文案。
  - **问题 23（流式文本被清空）**：修正 `AgentThinkingEvent` 与消息更新状态。
  - **问题 24（Spinner 卡死）**：所有事件流均确保触发完成事件。
  - **问题 25（列表 Key 问题）**：使用 `ValueKey('msg_keepalive_${message.id}')` 和 `ValueKey('thinking_${message.id}')`，按消息 ID 绑定 Key。
  - **问题 26（ThinkingWidget 完成折叠）**：保留用户手动展开状态。
  - **问题 27（只读卡片开关可点）**：`canEdit` 纳入 `!artifact.readOnly` 限制。
  - **问题 28（Chip 触控面积与语义）**：重构并扩大可点击热区，完善语义支持。
  - **问题 29（`ai_assistant_page_ui.dart` 臃肿）**：拆分为 `ai_assistant_page_agent`、`ai_assistant_page_session`、`ai_assistant_page_ui` 等子 part。
  - **问题 30（死 Widget 占用）**：删除 `AIAssistantAgentStatusPanel` 与 `ToolCallCard` 共计 ~620 行死代码。
  - **问题 31（死参数 `editorSource`）**：清理无用参数。
  - **问题 32（杂项）**：优化语言检测与 N+1 数据库查询。

---

### 2. 设计规范确认：明确非需求 / 无需改动（共 2 项）

1. **问题 15（提案卡片显示 Agent 推荐理由）**【设计明确无需添加】
   - **说明**：Agent 的推理与依据已在会话消息正文中完整阐述，卡片保持极简与纯粹，无需且不希望重复展示理由行。
2. **问题 17（提案卡片提供显式「拒绝/忽略」动作按钮）**【设计明确无需添加】
   - **说明**：提案卡片定位为“确认与应用”的单向操作视图。用户不需要拒绝按钮，不采纳时忽略卡片或继续在对话中下发后续指令即可。

---

### 3. 尚未修复的技术问题（仅 1 项）

1. **问题 16（思考过程与消息状态不入库保存）**【待修复】
   - **现状**：`ChatMessage.fromMap` 与 `toMap` 在 SQLite 映射中尚未补齐 `thinking_chunks` 与 `state` 字段，重开历史对话后 Thinking 思考链文本不会持久化恢复。


