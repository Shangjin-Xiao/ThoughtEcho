# Thoughter 记忆系统调研报告（2026-08-08）

> 状态：**首版已实现**（见文末「落地状态」）。本文是外部调研结果与出处记录，配合
> `docs/memory-system-plan-2026-07-31.md`（内部构想与现状核查）使用：
> 前者回答"业界怎么做、我们的设想对不对"，后者回答"我们现状是什么、从哪开始"。
> 本文第五节以后描述的能力有一部分仍未实现，写用户文档前先对照文末的状态清单。

## 调研目标

为 Thoughter（ThoughtEcho 的 AI Agent）设计记忆系统，满足：

- 记住用户偏好、身份，给出更好的回答；
- 每日提示与洞察也受益于同一份记忆；
- 核心设想：基本信息（身份、文字偏好）每次对话注入；详细信息（习惯、爱好、
  常去的地方等）按需读写；记忆定期整理。

## 一、调研来源清单

| # | 来源 | 类型 | 出处 |
|---|---|---|---|
| 1 | Gemini CLI | 实现源码 | `https://github.com/google-gemini/gemini-cli`。关键文件：`docs/tools/memory.md`、`docs/cli/auto-memory.md`、`docs/cli/tutorials/memory-management.md`、`evals/hierarchical_memory.eval.ts`、`packages/core/src/services/memoryService.ts` |
| 2 | Claude Code（fork 源码参考） | 实现源码 | `https://github.com/jarmuine/claude-code`。关键文件：`src/memdir/memoryTypes.ts`（记忆类型与写读准则）、`src/memdir/memoryAge.ts`（时效标注）、`src/memdir/memoryScan.ts` |
| 3 | OpenClaw | 实现源码 | `https://github.com/openclaw/openclaw`。关键文件：`docs/concepts/memory.md`、`docs/concepts/dreaming.md`、`docs/concepts/memory-search.md`、`docs/concepts/user-model.md`、`docs/concepts/active-memory.md`、`docs/cli/memory.md`、`extensions/memory-core/` |
| 4 | Hermes Agent（Nous Research） | 实现源码 | `https://github.com/NousResearch/hermes-agent`。关键文件：`website/docs/user-guide/features/memory.md`、`tools/memory_tool.py`、`agent/memory_manager.py` |
| 5 | Honcho（Plastic Labs） | 实现源码 | `https://github.com/plastic-labs/honcho` |
| 6 | Mem0 | 论文 | arXiv:2504.19413《Mem0: Building Production-Ready AI Agents with Scalable Long-Term Memory》 |
| 7 | Generative Agents | 论文 | arXiv:2304.03442《Generative Agents: Interactive Simulacra of Human Behavior》 |
| 8 | Sleep-time Compute | 论文 | arXiv:2504.13171《Sleep-time Compute: Beyond Inference Scaling at Test-time》 |
| 9 | PrefEval | 论文 | arXiv:2502.09597《Do LLMs Recognize Your Preferences? Evaluating Personalized Preference Following in LLMs》 |
| 10 | MemGPT | 论文 | arXiv:2310.08560《MemGPT: Towards LLMs as Operating Systems》 |
| 11 | ZifaMem | 论文 | arXiv:2607.17564《ZifaMem: Structured Memory for Persona, Preference, and Emotional Continuity in AI Companions》 |

## 二、各系统记忆设计要点

### Gemini CLI（#1）

- **分层上下文**：`GEMINI.md` 分 global（`~/.gemini/GEMINI.md`）、project（`./GEMINI.md`）、
  subdirectory 三级，按层级覆盖，冲突时子级优先（`hierarchical_memory.eval.ts` 有专门的
  层级冲突 eval 用例）。
- **写入口**：`save_memory` 工具，单参数 `fact`（一句自包含的自然语言事实），追加到全局
  `GEMINI.md` 的「Gemini Added Memories」段落，自动进入后续所有会话。
- **Auto Memory（实验性）**：后台扫描历史会话转录，把跨会话反复出现的流程提炼成
  SKILL.md 草稿放进收件箱，人工审查后提升为技能。只处理空闲 3 小时以上、≥10 条
  用户消息的会话；子代理默认产出零技能除非证据充分；密钥敏感内容脱敏。

### Claude Code fork（#2）

- **记忆类型学**（`memoryTypes.ts`）：记忆分四类——
  - `user`：用户角色、目标、职责、知识（怎么写更对用户有用）；
  - `feedback`：用户对做法的纠正**和**确认（只记纠正会越做越保守；要记"为什么"）；
  - `project`：进行中的工作、动因、截止（相对日期存成绝对日期；快衰减）；
  - `reference`：外部系统的位置指针。
- **明确"什么不记"**：代码模式、架构、git 历史、已文档化内容、临时任务细节——
  这些都是可从当前状态推导的。用户明确要求保存 PR 列表这类活动日志时也要追问
  其中"令人意外、非显然"的部分才值得存。
- **时效标注**（`memoryAge.ts`）：按 mtime 输出"47 days ago"这类人类可读年龄，
  并附"记忆是某时点的观察，不是活状态，引用前要验证"的提醒。模型对日期算术
  不敏感，原始时间戳不能触发时效推理。
- **条目结构**：frontmatter（name/description/type）+ 正文；feedback/project 类
  正文用"规则/事实 → **Why:** → **How to apply:**"结构，方便未来判断边界。

### OpenClaw（#3）

四层记忆 + 混合检索 + 后台整理，是本次调研中最完整的方案：

- **`USER.md`**：用户模型层。稳定偏好、沟通风格、关系、活动项目上下文，写成
  **指令式**条目：`<!-- observed: 日期 | status: active/superseded -->` + 以
  `Always / Never / Prefer` 开头的单条行为指令。偏好改变时原位 supersede，禁止
  追加矛盾 active 条目。每次会话开头加载，独立小预算。原则：只存能改善助力的
  信息，不建档案卷宗。
- **`MEMORY.md`**：长期记忆。非画像的持久事实与决策，会话开头加载，超出注入
  预算时保留文件本体、只截断注入副本。
- **`memory/YYYY-MM-DD.md`** 每日笔记：工作层，今日/昨日自动加载，更早的不注入，
  只被检索。会话前的"自动记忆 flush"（compaction 前的静默回合）提醒 agent 把
  重要上下文落盘。
- **检索**（`memory_search`）：hybrid 检索 = 向量相似度 + BM25 关键词并行 + 加权
  合并；确定性排序 = **relevance × recency 衰减（30 天半衰期，仅对日期文件）
  × importance 乘数（1-10，写入时打标）**，公式源自 Generative Agents（#7）
  且不做查询时模型调用。可选 MMR 去重（λ=0.7）。**只有 MEMORY.md/USER.md 的
  已晋级条目会触发自动注入**，每日笔记永不自动注入。
- **Dreaming（定期整理）**：三阶段后台整理——
  1. light：读短期信号/每日笔记/脱敏转录，去重暂存候选；
  2. REM：主题与反思摘要；
  3. deep：加权打分（relevance 0.30 / frequency 0.24 / query diversity 0.15 /
     recency 0.15 / consolidation 0.10 / concept richness 0.06）过三重阈值
     （minScore / minRecallCount / minUniqueQueries），再交给 LLM 子代理合并重写
     `MEMORY.md`。
  重写必须保留原条目 ≥75%、包含候选来源引用、不超过注入预算，否则回退为
  追加式。有人类可读的 `DREAMS.md` 日记供审查。默认 cron 凌晨 3 点。
- **隐私**：不可信来源（工具输出、网页、非本人发言）的候选被结构性排除在
  晋级路径外。

### Hermes Agent（#4）——与本次设想最接近

- **双文件**：`MEMORY.md`（agent 个人笔记，2200 字符上限）与 `USER.md`（用户画像，
  1375 字符上限），存 `~/.hermes/memories/`，会话开始时**冻结快照**注入系统提示
  （会话中不再变更，保住前缀缓存；写入立即可落盘但下个会话才生效）。
- **`memory` 工具**：add / replace / remove 三动作，replace/remove 用唯一短子串
  匹配，无 read（内容本就在系统提示里）。
- **容量管理**：超限时工具返回错误并附当前条目清单与用量，agent **当场自行
  合并/删除腾空间后重试**——不静默丢弃、不自动压缩，超 80% 就应主动合并。
- **内容准则**：主动保存偏好、环境事实、纠正、约定、完成的工作；跳过琐碎、
  可再发现、原始数据倾泻、会话性临时信息、已在上下文文件中的内容。
- **防重复**：精确重复自动拒绝；**安全扫描**：注入系统提示的内容先过注入/泄露
  模式扫描（隐身 Unicode、凭证外泄、SSH 后门等）。
- **会话搜索**：全部会话存 SQLite + FTS5，`session_search` 工具按需检索（~20ms），
  与持久记忆互补：记忆管"总该在上下文里的"，会话搜索管"上周聊过什么"。
- **后台自省**：每轮对话后后台 review 提炼记忆/技能，可配更便宜的模型
  （`auxiliary.background_review`），有 write_approval 门控与 `/memory pending`
  审查流。
- **外部提供商**：Honcho、Mem0 等 8 个插件，与内置记忆并行，不替代。

### Honcho（#5）

服务端记忆基础设施（FastAPI + 数据库），"reasoning-first"：从对话/事件中提取结论
而非匹配片段；peer-centric 模型（user/agent/group/project/idea 随时间变化）。
**需要后端与数据库，与 ThoughtEcho 本地优先 + 隐私约束冲突，仅作概念参考。**

### 论文要点

- **Mem0（#6）**：从对话动态提取、合并、检索关键信息；快速提取 + 慢速合并整理的
  双层节奏；图式记忆增强可捕捉实体关系。LoCoMo 基准验证。
- **Generative Agents（#7）**：记忆流按 relevance × recency × importance 打分，
  周期性 reflection 把观察归纳成更高级的信念；OpenClaw 检索排序与 dreaming 的
  直接理论来源。
- **Sleep-time Compute（#8）**：把思考从"查询时"挪到"离线时"——预先想好用户
  可能问什么、预计算有用量。OpenClaw dreaming 与 Hermes 后台 review 的依据。
- **PrefEval（#9）**：长对话中偏好遵循度急剧下降；**稳定偏好应以指令形式在
  使用点明确复述**（OpenClaw USER.md 写指令而非观察的依据）。
- **MemGPT（#10）**：分层记忆 + 数据在主存/外存间搬运，模型自己管理"换页"——
  注入层 ↔ 检索层的分界理论。
- **ZifaMem（#11）**：AI 陪伴场景，会话摘要 + 情景记忆 + 合并的用户模型三层结构，
persona grounding 在四个骨干模型上均提升（+42% 相对），是最贴近本应用场景的
  论文佐证。

## 三、行业共识总结

1. **双层文件是事实标准**：`USER.md`（画像，每次注入）+ `MEMORY.md`（长期事实，
   每次注入）+ 每日笔记/会话档案（不注入，按需检索）。三家独立实现收敛到同一
   形态，可视为经过实践验证。
2. **注入层必须有硬性预算**：Hermes 用字符上限，超限工具报错、agent 当场合并；
   OpenClaw 超预算只截断注入副本、文件本体保留。
3. **写入口是"模型自己维护"的工具**：add/replace/remove + 短子串匹配；
   模型在对话中自然学习什么值得记（纠正与确认都要记）。
4. **内容像指令不像日记**：`Always/Never/Prefer` 开头 + observed 日期 +
   active/superseded 状态；偏好改变原位 supersede，不追加矛盾历史（#9）。
5. **检索层与注入层严格分离**：只有 USER.md/MEMORY.md 的晋级条目可自动注入；
   其余一律走显式检索，永不自动进上下文。
6. **定期整理是后台任务，不占对话时间**：启发式门槛（评分/频次/多样性）是硬
   门禁，LLM 只做合并重写且必须通过保留率校验，失败回退追加式（#7、#8）。
7. **记忆是"快照"不是"事实"**：标时效 + 验证提示（#2），回复前核对当前状态。
8. **对话之外同样受益**：compaction 前强制 flush（#3）、后台 review 提炼（#4）、
   每日提示/洞察消费画像。

## 四、对核心设想的评估

> 基本信息（身份、文字偏好）每次注入 + 详细信息（习惯、爱好、常去的地方）按需
> 读写 + 定期整理

**方向与行业共识一致，可直接采纳**。三个需要细化的点：

1. **"按需读写"需要检索工具支撑**：模型无法凭空知道"需"。OpenClaw 用
   `memory_search` 工具由模型主动触发；ThoughtEcho 无 embedding 基础设施，
   SQLite FTS5 关键词检索是务实起点（中文需注意分词，trigram 或专门策略——
   OpenClaw 文档明确提及 CJK 需重建索引）。
2. **注入层要有硬上限 + 淘汰机制**：推荐 Hermes 的"溢出即当场整理"（零常驻
   成本）+ OpenClaw 的"定期 deep phase"（信息量大后启用）两级策略。
3. **整理的目标是"晋级"不是"压缩"**：等级制度 会话记录 → 每日笔记 → 长期记忆
   → 用户画像，向上晋级、向下归档；整理任务从次要层筛选晋级到注入层。

**ThoughtEcho 特有判据**：用户的笔记本身是巨大的知识库。记忆只存"笔记中不可
推导的内容"（身份、表达偏好、沟通风格、用户对 thoughter 的纠正反馈），与
现有 `explore_notes` 检索职责分离，避免两套检索打架（#2 的"什么不记"判据）。

## 五、ThoughtEcho 落地建议（**历史方案，已被第七节取代**）

> ⚠️ 本节是实现之前写的草案，**不是当前契约**。实际落地在几个关键处偏离了它：
> 表名是 `agent_memory_profile` / `agent_memory_facts`，预算是 24 条 / 1200 字符而不是
> 500-800 token，画像走**独立 user 数据消息**而不是系统提示，检索工具叫 `recall`
> 而不是 `memory_search`，实现是 `LIKE` + Dart 打分而不是 FTS5。
> 要改代码请以第七节和 `AGENTS.md` 为准，本节只用来回溯当初为什么这么设计。

### 数据模型（本地 SQLite，新增表）

```text
user_profile_entries  注入层（USER.md 等价物）
  id, kind (identity/preference/style/feedback), directive,
  observed_at, status (active/superseded), source
  每次会话拼入系统提示，硬预算 500-800 token；偏好变化原位 supersede

memory_entries        长期事实层（MEMORY.md 等价物）
  id, category, content, importance (1-10), trigger_phrases,
  created_at, last_recalled_at, recall_count, source_ref
  预算余量内注入前 N 条，其余靠检索

daily_sessions        次要层（会话自动沉淀）
  session_id, date, summary, extracted_facts, last_promoted_at
  不注入；由 memory_search 工具按需检索

consolidation_runs    整理日志
  run_at, phase, promoted/deduped/superseded 计数
```

### Agent 侧改动（最小面）

1. 新工具（沿用 `lib/services/agent_tool.dart` 现有抽象）：
   - `remember(user_profile|fact, content)`：写入注入层；超预算时返回当前条目
     清单让模型当场合并（#4 模式）；
   - `memory_search(query)`：FTS5 检索次要层，结果附时效标注（#2 的"X 天前"模式）。
2. 系统提示注入：`agent_service.dart` 的 `_buildSystemPrompt` 增加 `<user_profile>`
   块；首版每轮注入，后续优化为会话开始冻结快照（#4 前缀缓存模式）。
3. 整理任务：复用 smart_push 调度设施，每周一次；LLM 合并可配便宜模型
   （#4 `auxiliary.background_review` 模式）；保留率校验失败回退追加式（#3）。

### 每日提示与洞察接入

- `streamGenerateDailyPrompt`（`ai_service.dart`）增加用户画像上下文参数，沿用
  现有"历史洞察仅供参考、可完全不引用"的软性措辞（`ai_prompt_manager.dart`）。
- 智能推送内容选择（`smart_push_content.dart`）二期再消费记忆，本期不扩大范围。

### 明确不做的

- 外部记忆服务（Honcho/Mem0 类）：本地优先 + 隐私约束，记忆必须留在设备上。
- 首版不做 embedding 向量检索：FTS5 + 触发短语足够，检索接口抽象好便于以后替换。
- 记忆不接管笔记检索：职责归 `explore_notes`，系统提示中明确边界。

### 测试与回归点

- 偏好变更后 supersede，不存在两个 active 矛盾条目；
- 超预算报错路径 + 模型当场合并；
- 记忆内容按不可信数据处理（沿用 `untrusted_text.dart` 安全路径；系统提示注入
  内容过注入/泄露扫描，#4）；
- 整理任务：去重、过期淘汰、保留率校验、失败回退。

### 与现有计划文档的关系

- `docs/memory-system-plan-2026-07-31.md` 中的 L1 事件层（`user_signals` 记录
  提案采纳/忽略、字段手动修改）可作为本报告的"信号采集"前置层——先记可观测
  行为，再经整理晋级为偏好档案（#7 reflection 的本地化版本）；
- 该文档"已知的坑"（隐私本地化、只记可观测写作习惯不猜性格、AI 失败降级）与
  本报告共识一致，实施时同时遵守。

## 六、结论

三层设想（身份注入 / 细节按需 / 定期整理）即为 OpenClaw + Hermes 生产系统的
实际设计。需补充的工程细节：**注入层硬预算 + 溢出当场整理**、**FTS5 检索工具
让"按需"可执行**、**整理任务启发式门槛把关、LLM 只做可回退的合并重写**。
首版建议只做注入层 + `remember` + `memory_search` 两个工具；整理任务等数据
积累后再上（第一阶段收集信号，第二阶段整理才有意义）。

## 七、落地状态（2026-08-08 首版）

### 已实现

| 能力 | 位置 |
|---|---|
| 独立数据库 `agent_memory.db`（画像层 + 事实层两张表） | `lib/services/agent_memory_service.dart` |
| 领域模型 | `lib/models/agent_memory.dart` |
| 读写、检索、预算渲染、容量淘汰 | `lib/services/agent_memory_service.dart` |
| `remember`（add/update/delete × profile/fact） | `lib/services/agent_tools/remember_tool.dart` |
| `recall`（关键词检索 + 回带画像 id） | `lib/services/agent_tools/recall_tool.dart` |
| 画像作为独立 user 数据消息注入 Agent | `lib/services/agent_service.dart` |
| 每日提示与周期洞察消费画像层 | `lib/services/ai_service.dart`、`lib/utils/ai_prompt_manager.dart` |
| 开关（默认开）+ 清空 | `lib/services/settings_service.dart`、`lib/pages/ai_settings_page.dart` |
| 进入 Thoughter 的一次性告知 | `lib/widgets/ai/agent_memory_notice.dart` |

几处和调研建议不同的选择，都有理由：

- **不用 FTS5**：默认 unicode61 分词器对中文等于不分词，要中文可用得靠 `trigram`
  （SQLite 3.34+），而 Android 的 sqflite 跟随系统 SQLite 版本，不可控。条目量级是
  几十到几百条，`LIKE` 取候选 + Dart 内打分完全够。检索封在
  `AgentMemoryService.searchFacts` 后面，换实现不动调用方。
- **不建 `daily_sessions` / `consolidation_runs`**：按报告自己的结论，没数据积累时
  整理任务无意义。整理日志先走 `UnifiedLogService`。
- **容量溢出不报错给模型**，直接按得分淘汰。让模型在对话里处理容量只会浪费一轮，
  用户也看不懂。
- **`agent_memory_facts.embedding` 列现在恒为 NULL**，为二期向量检索预留，
  免得那时再写一次迁移。
- **不进备份、不进设备同步**：记忆是设备级的行为画像，跨设备合并会产生互相矛盾的
  条目，收益小风险大。换机即失忆是这一版接受的代价。
- **独立数据库文件而不是主库新增两张表**：仓库里聊天记录、日志、AI 分析都各自
  开库，记忆属于同一类附属数据。物理隔离还让上一条从"备份代码恰好没导出这两张表"
  的隐式约定变成文件层面的事实，主库的 schema 版本也不用为记忆往上走。

### 待办（按优先级）

1. **Dreaming / 定期整理**（第 3、6 条共识）：去重、supersede 清理、把高频召回的
   事实晋级进画像层。启发式门槛先行，LLM 只做可回退的合并重写，保留率校验失败
   回退追加式。可复用 `smart_push` 的调度设施，模型走便宜档。
2. **记忆进备份**：用户选了「先纯本地」，后续再接 `backup_service` 的导出/恢复。
3. **会话结束后的后台提炼**：首版只有模型主动调 `remember`，覆盖率依赖模型主动性。
4. **注入层冻结快照 + prompt caching**：现在每轮重取画像；provider 支持
   `cache_control` 后再优化。
5. **设置页的记忆管理列表**：当前用户只能通过跟 Thoughter 对话来改记忆，
   加不加可视化列表看实际使用反馈。
