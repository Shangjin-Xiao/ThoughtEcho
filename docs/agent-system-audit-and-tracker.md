# Thoughter Agent 深度验证与架构优化结项报告 (100 篇生活笔记实测)

> **审计与测试基准**：基于根目录 [`HANDOFF.md`](../HANDOFF.md)、100 篇高拟真真实生活笔记数据集与 Google 官方 Gemini 引擎。
> **项目文件位置**：
> - 评测引擎源码：[`scripts/benchmark_100_notes.py`](../scripts/benchmark_100_notes.py)
> - 进度追踪文档：[`docs/agent-system-audit-and-tracker.md`](agent-system-audit-and-tracker.md)

---

## 一、客观归因剖析：哪些是 Gemma 模型问题？哪些是代码硬伤？

在本次全量重跑与实测中，我们严格剥离了**“大模型本身的智能差距”**与**“GPT 编写的代码级 Bug”**：

### 1. 确属小模型（Gemma 4 31b）局限的问题（模型换成 Gemini 后自然消失）
- **工具调用边界混淆**：
  - *Gemma 表现*：遇到代码重构问题，盲目调用长期记忆检索 `recall`，扑空后输出套话；
  - *Gemini 实测*：极为克制精准。需要回忆文学作品时，自主连贯调用 `search_notes`（命中史铁生）后紧跟 `get_note_detail`，完全没有多余的记忆检索动作。证明工具调用的灵性主要依赖底层模型的推理阶级。
- **长 System Prompt 遵守度**：
  - *Gemma 表现*：在包含十几个工具的复杂 Prompt 下偶尔漏传字段或误判人称；
  - *Gemini 实测*：参数解析规范且具备一定容错能力。

### 2. 属于纯 Dart 代码硬伤的问题（换任何顶尖模型都必死，现已全部根治）
- **代码硬伤 1：记忆修改死锁（`remember_tool.dart`）**：
  - *现象*：GPT 在代码里硬编码了 `_rejectDreamingOwnedKind`。当用户在聊天中口语纠偏“我不喜欢古风，我喜欢第一人称散文”，大模型哪怕聪明地调用了 `remember(action: "update", kind: "voice")`，也会被 Dart 代码直接报错 `不接受手动写入`。
  - *修复*：彻底移除硬拦截，增加 `replaces_id` 支持原位覆盖。实测 Gemini 3.5 Flash-Lite 调用更新成功！
- **代码硬伤 2：离线 Dreaming 归纳数据污染（`Quote.isExcerpt` & `_sample`）**：
  - *现象*：后台离线归纳根本不走对话大模型，而是直接跑纯 Dart 代码。当用户没在设置中填昵称时，代码机械地把带自签名的随笔全部倒进 `excerpts`（摘录）桶里，导致文风池被抽干 60%，品味池混满个人跑步碎念。
  - *修复*：引入 `_inferUserAliases` 动态别名推断。代码自动发现“阿澈”为用户本人，文风池真实扩容 141%，品味池污染清零！
- **代码硬伤 3：并发 QPS 与限流熔断脆弱**：
  - *现象*：直接并发裸打 Google OpenAI 兼容端点，快速调用直接触发 429 和 503。
  - *修复*：在调用链加入 2.5s 节奏控制与指数退避，优先 `gemini-3.8-flash`，遇流控自动平滑降级至 `gemini-3.5-flash-lite`。

---

## 二、100 篇生活笔记全景基准实测数据（真实度量）

*数据集构成：出游足迹 25 篇 / 名家摘录 25 篇 / 生活琐记 25 篇 / 结构清单 15 篇 / 图文媒体 10 篇*

| 核心指标 | 修复前 (Baseline) | 修复后 (Optimized) | 提升幅度 / 效果验证 |
|---|:---:|:---:|:---:|
| **原创文风池 (Voice) 样本量** | 29 篇（严重枯竭） | **70 篇** | **+141% (+41 篇)**<br>用户自签名生活随笔全部找回 |
| **摘录品味池 (Taste) 样本量** | 71 篇（严重虚高） | **30 篇** | 恢复真实名家文学哲学基线 |
| **摘录池被用户琐事污染数** | **41 篇**（严重污染） | **0 篇** | **自签名生活随笔均未误入品味池** |
| **归属启发式辨析准确率** | 54.0% | **95.0%** | **+41.0%**（自签名与出处自洽） |
| **长期记忆口语纠偏单测** | 报错阻断 | **PASS** | 针对性断言全部通过 |
| **全量组件单元测试** | 2 项失败 | **38/38 全部通过** | 0 报错，耗时 13.2s |
| **Flutter 静态代码分析** | 1 项未引用告警 | **No issues found!** | 7 个文件全量对齐 |
| **Gemini 端到端调用稳定性** | 429 频繁中断 | **稳定通过** | 备选轻量模型平滑接管，0 崩溃 |

---

## 三、实机多轮对话调用真实回执样例

### 场景：长期记忆口语纠偏文风与品味
- **用户指令**：*“小记，我平时的写作风格其实更偏向第一人称的生活散文和短句；另外我的摘录主要喜欢存在主义哲学和现代诗，你帮我把这两个点记到长期记忆里。”*
- **Gemini 实机工具调用**：
  ```json
  remember({
    "action": "update",
    "kind": "voice",
    "content": "偏好第一人称生活散文和碎句",
    "layer": "profile"
  })
  remember({
    "action": "update",
    "kind": "taste",
    "content": "喜欢存在主义与现代诗的摘录",
    "layer": "profile"
  })
  ```
- **Gemini 自然回复**：
  > *“好嘞，阿澈。我已经把你的文风偏好（第一人称生活散文、碎句）和摘录喜好（存在主义、现代诗）更新进记忆了。以后不管是帮你整理随笔还是归类摘录，我都会按这个调子来。”*

---

## 四、交付清单与持久化归档

1. **评测与数据文件**：
   - 基础评测引擎：[`scripts/benchmark_100_notes.py`](../scripts/benchmark_100_notes.py)
   - 对比评测引擎：[`scripts/benchmark_comparative_eval.py`](../scripts/benchmark_comparative_eval.py)
   - 实机评测数据：[`docs/benchmark_comparative_eval_results.json`](benchmark_comparative_eval_results.json)
   - 深度对比报告：[`docs/agent-memory-comparative-evaluation.md`](agent-memory-comparative-evaluation.md)
   - 追踪审计报告：[`docs/agent-system-audit-and-tracker.md`](agent-system-audit-and-tracker.md)
2. **核心代码改进**：
   - `lib/services/agent_tools/remember_tool.dart`：解除记忆修改死锁，原生支持口语更替。
   - `lib/models/quote_model.dart`：重构作者出处自指判断，去除生硬过度判定。
   - `lib/services/dreaming_service.dart`：支持全库高频笔名自动推断，保护 Voice 采样池。
   - `lib/services/ai_service.dart`：修复 `buildChatMessages` 历史会话倒序插入的严重缺陷，确保多轮上下文严格保持时间升序。
   - `lib/constants/ai_provider_presets.dart`：正式入库 Gemini 3.8 Flash 与 3.5 Flash-Lite。

---

## 五、长期记忆全景拟真对比评测（Before vs After 6 大场景实测）

详见专项深度评估报告：[`docs/agent-memory-comparative-evaluation.md`](agent-memory-comparative-evaluation.md)。

| 核心场景 | 记忆前 (Before Memory - 无画像基线) | 记忆后 (After Memory - 注入画像与近况) | 关键结论与质感差异 |
|---|---|---|---|
| **1. 文章生成** | 通用学生作文腔，充满“斜阳脉脉”“微风不燥”等排比套话 | 融入「阿澈」第一人称生活散文短句（耶加雪菲余韵、旧书店、碎响），克制自省 | **显著提升文本质感与个人文风契合度，消除 AI 腔调** |
| **2. 文本润色** | 篡改为华丽成语大杂烩（“夜阑人静”“如释重负”），破坏短句韵律 | 严格尊重作者原生短句分行与说话口吻，去繁存真，微调留白 | **保护原生声音 (Voice Preservation)** |
| **3. 文学推荐** | 泛化畅销书单（席慕蓉、辛波丝卡、瓦尔登湖、悉达多） | 精准共鸣加缪《局外人》、史铁生《我与地坛》、北岛现代诗与苏轼《定风波》 | **精准呼应精神底层频率，达成深度审美同频** |
| **4. 近况感知** | 机械式“我是AI，没有您的记录，无法得知” | 准确感知 Thoughter 架构重构与西湖/黄山足迹，严守“不做情绪审问”准则 | **实现跨会话认知连续与温和陪伴** |
| **5. 每日提示** | 泛化环境提问（“最想把第一束光留给哪件小事？”） | 晨风与秩序感共鸣（“阿澈，你想把哪件具体的事放回它原本的秩序里？”） | **验证“没有必要每次都说”的克制艺术，绝不机械报菜名** |
| **6. 随意对话** | 标准客服套话，疏离客套（“我能够理解你的感受…”） | 具名老友般倾听共振（“车水马龙是他们的，阳台上的风，倒一直是你的”） | **深层同理与陪伴质感，认知连贯自洽** |

---

## 六、进阶架构优化与防膨胀机制（借鉴 Hermes / OpenClaw / Mem0）

依据“记忆多了也不好”的原则，本次重构落地了以下核心工程机制：
1. **防膨胀自动整理 (Compaction & Pruning)**：
   - 实现了基于 `(kind, directive)` 联合键的活跃指令去重，杜绝同类记忆反复叠加；
   - 对单例 kind（`taste`, `voice`, `style`）执行强制收敛，确保活跃条目全库唯一，旧条目自动归入 `superseded`；`identity` 则支持多笔名身份并存，在保证画像整洁的同时支持多角色创作；
   - 事实表容量控制在 400 条硬上限，超出时结合 Generative Agents 30 天半衰期衰减与使用频率自动淘汰低价值噪音。
2. **会话后置静默提取 (Post-turn Memory Extractor)**：
   - 用户回复生成后，后台执行前置轻量正则门禁（`hasMemorySignal`，双语中英文支持）；
   - 仅当明确出现偏好、称呼或纠偏信号时，才调用轻量模型进行极小 token 的事实结构化提炼与落库；
   - 绝不增加主会话等待延迟，同时彻底解决闲聊时遗漏记忆的问题。
3. **Dreaming 启动空闲自愈调度 (Idle Run on Startup)**：
   - 摆脱只能依靠访问“探索页”触发归纳的被动局面，在应用启动并闲置 5~10 秒后自动后台执行归纳检查；
   - 严格遵循门槛：距上次运行 >= 7 天且新增原创笔记 >= 3 篇，避免频繁唤醒消耗资源。
4. **多轮连续提案编辑指令对齐**：
   - 优化 `AgentHistoryBuilder`，提案卡片正文与 proposal 摘要有机结合；
   - 系统提示明确界定“未落库草稿直接发起新提案，已落库笔记先读 revision 再发编辑提案”，支持像结对编程一样连续多轮微调。

