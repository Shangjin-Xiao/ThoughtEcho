# Dreaming 横向对比调研：OpenClaw 与 OpenAI Dreaming V3 (2026-09-26)

> **状态**：🔍 调研参考（不推翻任何唯一事实源）
> **责任人 / 产出角色**：AUTO
> **涉及模块**：`lib/services/dreaming_service.dart`、`lib/services/agent_memory_service.dart`、`lib/models/agent_memory.dart`、`lib/pages/ai_settings_page.dart`
> **关联历史**：
> - 🔒 [`agent-memory-research-2026-08-08.md`](agent-memory-research-2026-08-08.md)（一期定案，唯一事实源）
> - 🟢 [`dreaming-and-memory-plan-2026-08-28.md`](dreaming-and-memory-plan-2026-08-28.md)（二期设计依据与实现记录）

---

## 1. 背景与目标

此前对话里用户连续追问三件事：Dreaming 为什么只改 `taste` / `voice`（+ 近况切片 + 别名）、近况为什么不能多加、现在的记忆系统算不算完美。口头回答偏简化，这篇把两家外部实现的**原文与源码**真正读一遍，回答一个问题：

> OpenClaw 的三阶段 dreaming 与 OpenAI 的 Dreaming V3，各自解决了什么？ThoughtEcho 该学什么、不该学什么？

阅读范围（均为 2026-09-26 当天拉取的最新内容）：

**OpenClaw（文档 + 源码）**

- 概念文档：`docs/concepts/dreaming.md`、`docs/concepts/memory.md`、`docs/concepts/memory-search.md`、`docs/concepts/user-model.md`、`docs/concepts/active-memory.md`（索引页）、`docs/reference/memory-config.md`（全部配置键）、`docs/cli/memory.md`
- 源码（`openclaw/openclaw@main`，`extensions/memory-core/src/`）：
  - 调度与扫荡：`dreaming.ts`（`registerShortTermPromotionDreaming`，约 24KB）
  - 合并改写：`dreaming-consolidation.ts`（`consolidateMemory` / `applyMemoryConsolidationPlan` / `validateConsolidationPlan`，约 17KB）
  - 阶段执行：`dreaming-phases.ts`（约 52KB）、`dreaming-cron.ts`、`dreaming-narrative.ts`、`dreaming-dreams-file.ts`、`dreaming-markdown.ts`

**OpenAI**

- 官方公告 `openai.com/index/chatgpt-memory-dreaming/`（2026-06-04，`openai.com` 当天返回 403，内容以 Web 搜索抓取到的公告正文为准，下面凡引数字均注明出处形态）
- 帮助中心 `Memory in ChatGPT` / `Memory FAQ`（`help.openai.com`，同因 403 以搜索抓取为准）
- 第三方交叉验证：`thenextinput.com`、`digitalapplied.com`、`chatforest.com`、`ai2.work`、`aitoolbriefing.com` 的公告复述与解读，以及一条 Pro 用户在官方社区对 V3 的批评帖（诉求：pinned memories、opt-out、revision history）

结论先行：两家在“**改写而非追加、确定性门槛先行、可审查**”三件事上完全收敛，这正是 ThoughtEcho 当前最缺的三件。移动端调度与向量检索两件事则**明确不学**。

---

## 2. OpenClaw Dreaming：原文级精读

### 2.1 写什么、不写什么

`docs/concepts/dreaming.md` “What dreaming writes” 一节写死三类产物：

1. **机器状态**：进 SQLite-backed plugin state（recall store、phase signals、ingestion checkpoints、locks），用户不可见；
2. **改写前镜像（preimage）**：每次接受 `MEMORY.md` 改写前，旧文件先存进 SQLite，出事可回；
3. **人类可读输出**：`DREAMS.md`（或既有的 `dreams.md`）+ 可选的 `memory/dreaming/<phase>/YYYY-MM-DD.md` 阶段报告。

长期晋升**只写 `MEMORY.md`**，且新条目自带两样召回元数据：最多 3 个 concept tag（`<!-- trigger: … -->`）和 1–10 的 `<!-- importance: N -->`。合并时“已有的带注解条目逐字节保留，除非显式 merge / supersede”（源码 `applyMemoryConsolidationPlan` 逐行 splice 实现，见 2.4）。

### 2.2 三阶段：只有 deep 能写

| 阶段 | 做什么 | 写 durable 吗 |
|---|---|---|
| Light | 读短期 recall state + 每日文件 + 脱敏会话转录，去重、暂存候选，记 reinforcement signal | 否 |
| REM | 按近期痕迹做主题与反思摘要，记 REM reinforcement signal | 否 |
| Deep | 加权打分 + 三重阈值门，过了才交给 consolidation，写 `MEMORY.md` | **是，唯一写入口** |

源码对应：`dreaming.ts` 的 `runShortTermDreamingPromotion` 按 `light → REM → deep` 顺序调 `runDreamingSweepPhases`，然后 `rankShortTermPromotionCandidates`，再 `applyShortTermPromotions`；叙事（diary）只在 `applied.applied > 0` 时才生成，无推广则只记完成状态、不建文件（“An empty sweep records completion … without creating memory or dreaming files”）。

### 2.3 Deep 打分：六信号 + 三重硬门

`docs/concepts/dreaming.md` “Deep ranking signals” 表（与 `dreaming.ts` verbose 日志里打印的 `score/signals/recalls/queries/components={freq,rel,div,rec,cons,concept}` 一一对应）：

| 信号 | 权重 | 含义 |
|---|---|---|
| Relevance | 0.30 | 平均检索质量 |
| Frequency | 0.24 | 短期信号攒了多少条 |
| Query diversity | 0.15 | 多少种不同 query/day 上下文里冒出来过 |
| Recency | 0.15 | 时间衰减新鲜度 |
| Consolidation | 0.10 | 跨天复现强度 |
| Conceptual richness | 0.06 | concept-tag 密度 |

Light/REM 命中再给一个随时间衰减的小加成。三道硬门**必须全过**：`minScore`、`minRecallCount`、`minUniqueQueries`。默认值（`docs/cli/memory.md` 与 `docs/reference/memory-config.md`）：

- `frequency = 0 3 * * *`（凌晨 3 点，自动托管单个 cron，多 workspace 去重）
- deep 默认：`minScore = 0.75`（CLI 文档另有一处写 0.8，系版本差，当前 config 参考页以代码解析为准）、`minRecallCount = 3`、`minUniqueQueries = 3`、`recencyHalfLifeDays = 14`、`maxAgeDays = 30`、`maxPromotedSnippetTokens = 160`
- 安全线：`phases.deep.maxPriorEntryLossFraction = 0.25`（一次改写删掉超过 25% 老条目直接拒绝）

### 2.4 Consolidation：模型只做选择题，不写正文（源码级）

这是 OpenClaw 相对 ThoughtEcho 最大的实现差异，值得逐条抄：

- 系统提示（`CONSOLIDATION_SYSTEM_PROMPT`，`dreaming-consolidation.ts:16`）：模型返回且**只返回** `{"operations": [{candidateKey, action: added|merged|superseded, priorEntries}]}`，**不返回记忆正文**。新条目正文由 host 用候选的 `resultEntry`（`- snippet Source: path#Lx-Ly <!-- trigger… --> <!-- importance… -->`）拼出来。模型选“怎么并”，host 写“写什么”。
- 校验（`validateConsolidationPlan`）：操作数必须等于候选数、每个候选恰好一次；`priorEntries` 必须是原文**逐字匹配**的行（含续行、多重计数、跨 project-group 检查）；`merged` 要求归一化后与候选同一事实（`normalizeComparableMemoryFact` 去 tag/Source/大小写后比对），否则拒绝；`superseded` 必须有 lineage key 且 `priorEntries` 与该 lineage 下全部条目**集合相等**（防“换一半留一半”）；`added` 的 `priorEntries` 必须为空。
- 落盘（`applyMemoryConsolidationPlan`）：先算 `lossFraction`（删掉条数 / 原条数），超 `maxPriorEntryLossFraction` 拒；检查 `buildPromotionMarker(candidateKey)` 防重复应用；检查文件预算（`memoryFileMaxChars`，超了拒）；检查 `\0`；全过才 splice 并在文末追加 `## Consolidated Memory (<day>)` 段。任何一步失败 → 返回 null → 调用方走 **append-only fallback**（`consolidateMemory` 里 `rejected = true` 即回退，见 `dreaming-consolidation.ts:360` 起）。
- 可审查：改写前后 `DREAMS.md` 收到 added/merged/superseded 计数 + diff 风格 highlights（最多 8 行，`highlights` 字段），被拒的候选按 `rejectedCategory` 只记数、不贴原文（深报告“用计数说明为什么没晋升，不复制被拒片段”）。

### 2.5 污染门：结构性排除，不是扣分

合并 prompt 组装前，`provenance == untrusted | system` 的候选**直接移除**，不进 prompt（“structural taint gate, not a score penalty”）。会话转录入库同样：只有 interactive 会话有资格，cron/heartbeat/subagent/unknown 全排除；入库前脱敏；已作为 recall 上下文注入过的片段要剔除（防“回忆起来的东西又被学一遍”）。另有两套算子控制：`memoryPolicy.excludeSessions`（hook 来源 / channel / chatType）与 `memory forget`（按 session ID 永久拉黑，backfill 与转录索引同步生效）。

### 2.6 调度与可观测：移动端不照抄的部分

- 自动托管单个 cron（`dreaming-cron.ts` 的 `reconcileShortTermDreamingCronJob`，declaration key 为 `memory-core:memory-dreaming-promotion`），历史遗留 light/REM 独立 job 由 `openclaw doctor --fix` 收编；后台 completion 预算与 Skill Workshop 共享（最多 3 并发，`memory-core` 最多占 3）。
- CLI 可解释、可预演：`memory promote`（默认只预览，加 `--apply` 才写）、`memory promote-explain "<…>" [--json]`（解释某候选为什么晋升/没晋升）、`memory rem-harness [--grounded]`（不写任何东西的 REM 预演）、`rem-backfill [--stage-short-term]` + `--rollback`（历史笔记重放，可逆）。
- Dreams UI：开关状态、分阶段状态、下次运行时间、short-term / grounded / signal / promoted-today 四计数、grounded Scene 独立泳道、可展开的 Dream Diary 阅读器。

### 2.7 检索与 USER.md：ThoughtEcho 已部分对齐

- 检索（`docs/concepts/memory-search.md`）：向量相似 + BM25 并行再加权合并，之后 `hybrid relevance × recency decay × importance`，再 MMR（λ=0.7）去冗余。每日 dated 文件按 **30 天半衰期**衰减，`MEMORY.md` / `USER.md` 常青。确定性触发召回：命中已晋升可信条目时最多注入 3 条 compact 条目，且**只从 `MEMORY.md` / `USER.md` 来**，每日笔记与转录永不自动注入（与我们的“画像层注入 / 事实层 recall”分界同构）。
- 中文坑官方也承认：FTS-only 回退、`unicode61` vs `trigram` tokenizer 可配（`store.fts.tokenizer`），CJK 搜不到先 `memory index --force` 重建——与我们“`LIKE` + Dart 打分，不上 FTS5”的取舍是同一道题的不同答案（见 4.3）。
- `USER.md`（`docs/concepts/user-model.md`）：指令式条目（`Always / Never / Prefer` 开头）+ `<!-- observed: 日期 | status: active/superseded -->`，偏好变化**原位 supersede、不追加矛盾 active**，4000 字符 bootstrap 硬上限。这正是我们 `AgentMemoryKind` + `replacesId` + `profileInjectionMaxChars` 的镜像实现，可以互证。

---

## 3. OpenAI Dreaming V3：官方文稿精读（2026-06-04 公告 + 帮助中心）

> 出处说明：`openai.com` 与 `help.openai.com` 对本机抓取返回 403，以下转述以多路搜索抓取到的公告正文与帮助中心条文为准；数字类引用按第三方复述交叉核对过两家以上才采用，仍应视为**厂商自述、未独立验证**。

### 3.1 三代演进

1. **2024-04 Saved memories**：会话内显式“记住这个”才写，强信号触发。问题：记得像“记了几张纸条但没写下来的全忘”，且随时间变质。
2. **2025-04 Dreaming V0**：首次允许引用 saved 列表之外的聊天上下文，后台自动整理。但官方自己承认“never sufficient as a standalone memory system”，只能做补充。
3. **2026-06-04 Dreaming V3**：后台合成成为**独立主干**，不再依赖 saved 列表；从多轮对话合成连贯散文 profile（按工作 / 爱好 / 旅行等分类），Plus/Pro 先上，随后扩到 Free/Go；计算成本降约 **5x**，Plus/Pro 容量扩约 **2x**。

### 3.2 三个评估目标与厂商数字

官方把“好记忆”定义成三件事，并给出 2024 → 2025 → 2026 的内评曲线（`edtechinnovationhub` / `ai2.work` / `aitoolbriefing` 三家复述一致）：

| 目标 | 2024 saved | 2025 saved+V0 | 2026 V3 |
|---|---|---|---|
| 事实召回（carry forward） | 41.5% | 67.9% | **82.8%** |
| 偏好遵循（vegetarian 定制餐单类） | 31.4% | 55.3% | **71.3%** |
| 时间敏感（trip 已结束等） | 9.4% | 52.2% | **75.1%** |

时间敏感 9.4% → 75.1% 是官方自己承认旧架构“把过去当现在”（存时无强 recency 权重）的罪状，也是 V3 存在的核心理由。注意 `chatforest.com` 的反向提醒：公告只给了约 5x 计算量数字，**没有公开评测方法、数据集与复现步骤**，精度数字应看趋势、不锚定小数。

### 3.3 标志性行为：改写时态，而不只是过期扔掉

 canonical 例子（多家复述一字不差）：“You’re going to Singapore in July” → 行程结束后自动改成 “You went to Singapore in July 2026”，回家后再按 home location + timezone 给推荐。**这是 V3 与我们 TTL 过期策略的本质差**：我们是“到期不注入”，它是“到期改写事实”。 freshness 数字差（52.2% → 75.1%）主要从这里来。

### 3.4 用户侧擦子（我们缺的整套）

- **Memory summary page**：自动更新的记忆总览（“2 hours ago”），可直接改字、划词纠错、增删条目、指示“什么话题该提起、什么时候提起”；
- **Memory Sources**：回答下方书图标，点开看哪条记忆影响了这句回答，可逐条纠正（⋯ 菜单）。官方承认不会展示全部因子，但方向是“可解释的个性化”；
- **remembering / personalizing** 状态位：用到过去上下文时明确告诉你正在回忆/正在个性化；
- **两档开关**：`Reference saved memories`（显式要记住的，常驻）vs `Reference chat history`（过去聊天推导的，会随时间变）；另有 `Project-only memory`（限定在单个 project 内互见）与 Temporary Chat（不用也不写）；
- **自动容量管理**：Plus/Pro 按 recency + 提及频率自动分“常用在前 / 灰掉在后”，用户可手动置顶/降权，避免旧架构的 “memory full” 死局。

### 3.5 反面教材：Pro 用户的批评帖同样值得读

官方社区一篇 Pro 用户长帖（2026-06-08）称 V3 是“cost reduction marketed as feature”：旧 notebook 时代“写了就一定在”，V3 时代“系统替我决定什么重要”，关键记忆要反复提醒、几个月前的旧信息却自动冒出来。诉求恰好是我们的前置清单：**pinned memories（钉住不许自动改）、opt-out 自动整理、revision history（改了什么、为什么改）**。做“自动改写”之前，这三样至少要想好怎么答——OpenAI 被骂的点，就是我们 `dreaming-and-memory-plan` 第七节提前写下的两条前置（可见 + 可归因）。

---

## 4. 与 ThoughtEcho 现状的对照表

| 维度 | OpenClaw | OpenAI V3 | ThoughtEcho（二期已实现） | 差距 |
|---|---|---|---|---|
| 触发 | 凌晨 3 点托管 cron + heartbeat/cron 事件 | 会话间后台合成（非请求热路径） | 周期洞察落库后 + 启动空闲 5s（`DreamingService.run/scheduleIdleRunOnStartup`） | 调度形态不同是**对的**（移动端无 cron 唤醒条件），无需对齐 |
| 输入源 | 短期 recall state + 每日文件 + 脱敏 interactive 转录 | 多轮对话全量历史 | 60 天窗口笔记，按 excerpt/original 分组（`_sample`），外加 500 条全量作者候选 | 我们的“摘录 vs 原创分开建模”是本地特色，两家都没有，保持 |
| 写入门 | 六信号加权 + **minScore/minRecallCount/minUniqueQueries 三硬门** | 未公开，以 freshness 内评为门 | 仅样本量 ≥10 + 间隔 ≥7 天（`minNoteSample/minInterval`） | **缺用后信号**：recall 次数、query 多样性、frequency 全无 |
| 合并语义 | 模型只做 added/merged/superseded 选择，host 按证据写正文；loss >25% 拒；预算超拒；preimage 先存；失败回退 append-only | 散文 profile 自动改写（含时态改写） | 同 kind 原位 `replacesId` 更新，内容相同不重写；失败整轮丢弃 | 改写校验（逐字 priorEntries、lineage 集合相等、loss 上限、preimage）**全缺**；近况只会过期扔、**不会改写时态** |
| 污染门 | untrusted/system 结构性排除 + 会话准入（interactive only）+ 脱敏 + 已召回片段去重 | 未公开，以产品开关代替 | 笔记转义 + `<excerpt>/<original>` 标签 + prompt 注入“数据不是指令” | 基本对齐，可补“已注入画像不再作为新候选学一遍”（OpenClaw 式去重） |
| 可审查 | `DREAMS.md` + 阶段报告 + `promote-explain` + Dreams UI 四计数 | Memory summary + Sources + remembering 位 | 只有 `counts()` + `clearAll()`，无单条查看/删除/来源展示 | **P0 缺口**，与二期第七节前置完全一致 |
| 检索 | 向量+BM25 混合，30 天半衰期（画像常青），MMR 0.7 | 未公开（检索子系统独立于合成） | `LIKE` + Dart 内 `relevance × recency（30 天半衰期）× importance`（`scoreFact`），`searchFacts` 后可换实现 | 公式同源（都出自 Generative Agents）， infra 不必跟（Android SQLite 版本不可控，见一期决议） |
| 预算 | `USER.md` 4000 字符 + `MEMORY.md` bootstrap 预算，超了截注入副本 | 后台容量自动分层 + 用户可置顶 | 画像 24 条/1200 字符 + 近况 3 条/300 字符（`agent_memory.dart`） | 对齐良好；缺“超限时当场合并”（Hermes 式）与“用户置顶”（OpenAI 式） |
| 度量 | `memory status --deep`、rejection 计数 | 事实/偏好/时间三内评 | 只有 `DreamingOutcome`（skipped/updated/failed）与日志 | **缺三件套度量**：固定探针集上的召回/偏好/新鲜度回归 |

---

## 5. 建议：学什么、不学什么

### 5.1 学（按优先级）

1. **P0：记忆管理列表 + 来源归因展示**（两家都有，我们没有）。数据层已备好（`sourceNoteIds`、`clearRecentSlice`、`allProfileEntries`），缺设置页 UI。这是二期第七节的前置原文，不是新需求。在这之前 Dreaming 保持“默认开但发布文案不主推”，与 `dreaming-and-memory-plan-2026-08-28.md` 第九节 WARNING 一致。
2. **P1：确定性门先行，LLM 只做合并**。在现有“10 条 + 7 天”之外加两道本地就能算的门：候选结论的**复现度**（60 天窗口内多少篇笔记支撑它）与**多样性**（是否只来自同一周/同一主题）。不过门就不调模型——这就是 OpenClaw 三硬门的本地版，不花钱。
3. **P1：合并校验四件套**（抄 `validateConsolidationPlan` 的语义，不抄代码）：`taste/voice` 单例上限（已有 `compactAndPrune`，保留）、改写 loss 上限（如一次最多动 N 条画像，超了整轮放弃）、来源引用必填（无 `sourceNoteIds` 不写入）、改写前镜像（SQLite 里把被顶掉的 `superseded` 行至少保留 30 天可查，`compactAndPrune` 现删 30 天+ 旧 superseded 的逻辑要与此对齐）。
4. **P2：近况从“过期扔”升级到“改写时态”**（学 OpenAI 的 Singapore 例子）。`recent` 切片下轮运行时把上一条未过期切片也喂给模型，允许模型输出“之前在备考 → 已考完”式的修订，而不是等 14 天 TTL 一刀切。失败回退仍是“保留旧切片”。
5. **P2：度量三件套**。固定 20–30 条探针（事实/偏好/时间各 ~10 条， synthetic 用户画像 + 笔记夹具），每次改 prompt/阈值跑一遍，记录召回/遵循/新鲜度三数。OpenAI 的数字不可复现，但方法（分开测三件事）可以直接拿。

### 5.2 不学

- **凌晨 3 点 cron**：移动端后台唤醒 + 电量策略成本高于收益，周/月一次跟着洞察走的频率对文风足够（沿用二期 3.5 的产品判断）。
- **向量/embeddings 基建**：Android SQLite 版本跟随系统，trigram 中文分词不可控；几十到几百条量级 `LIKE` + Dart 打分够用，检索封在 `searchFacts` 后面（沿用一期决议）。
- **散文 profile 存法**：我们的画像是 200 字内指令句（PrefEval 依据：长对话里指令句遵循度显著高于观察句），不换成 OpenAI 式散文小传。

> [!IMPORTANT]
> 以上新增全部落在“信任与可逆”四条红线内：静默 ≠ 不透明（必可查）；改写必带来源；超预算/超 loss 整轮放弃；关闭记忆即整条链路停跑（含写入前二次检查，`dreaming_service.dart:208/223` 已有，不得删）。

---

## 6. 影响范围与迁移清单

- [ ] 模型/数据库：无 schema 变更。`source_note_ids`（v2）与近况表已够用；P1 的“改写前镜像”用现有 `superseded` 行 + 调整 `compactAndPrune` 保留策略实现，不新增表。
- [ ] UI：设置页记忆管理列表（查看/单条删除/来源笔记跳转/近况切片管理）——唯一必须的 UI 增量。
- [ ] 提示词：`DreamingService._systemPrompt` 加“复现度不足填 null”已部分有；P2 时态改写需新增上一轮切片输入段。
- [ ] 测试：`dreaming_service_test.dart` 加门槛三件套用例；`agent_memory_phase2_test.dart` 加 loss 上限/无来源不写入用例；新增探针回归集（`test/unit/services/dreaming_eval_*`，夹具合成数据，不得含真实用户笔记）。

## 7. 验证与后续交接

- 验证 1：管理列表上线前，Dreaming 不得作为卖点出现在更新说明；保持现状（静默增益）+ 日志可查。
- 验证 2：P1 门上线后看两个数：`skipped` 占比是否上升（门太严）与用户纠正率（`feedback` kind 增速）是否下降（记得更准）。
- 后续接手注意：
  - `docs/agent-memory-research-2026-08-08.md` 仍是记忆架构的唯一事实源，`docs/dreaming-and-memory-plan-2026-08-28.md` 仍是二期范围的依据；本文只回答“外部怎么做”，不新增契约。
  - OpenAI 侧数字全部是厂商内评（方法未公开），引用时必须带“自述、未独立验证”定语，不得写成第三方基准。
  - OpenClaw 侧 `minScore 0.75 vs 0.8` 的出入是文档版本差，实现以 `resolveMemoryDeepDreamingConfig` 解析结果为准；抄阈值时按本地探针集重标定，不直搬。
