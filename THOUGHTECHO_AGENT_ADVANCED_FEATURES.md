# ThoughtEcho Agent 框架进阶功能与现有工具优化建议

在完成了核心调度框架（并发、权限、流式输出、错误处理）的对标分析后，基于对您项目中具体工具实现（`explore_notes_tool.dart`, `propose_edit_tool.dart` 等）的阅读，我为您整理了**现有功能优化**与**未来进阶功能演进**的深度建议。

---

## 🚀 一、 现有工具的深度优化 (Existing Tool Optimizations)

### 1. `explore_notes` 工具：从“精准搜索”向“语义搜索”升级
**现状分析**：
目前的 `ExploreNotesTool` 依赖于 SQLite 的传统过滤（时间、标签、关键词模糊匹配）。这要求大模型必须精准“猜”出用户当时记录的关键词，这在 AI Agent 中效率很低。同时，大笔记的预览仅截取前 200 个字符：
```dart
'content_preview': q.content.length > 200 ? '${q.content.substring(0, 200)}...' : q.content,
```
如果用户的关键信息在笔记末尾，Agent 将永远找不到它。

**优化建议**：
- **引入向量检索 (Semantic Search)**：利用本地模型 (如 Ollama) 生成笔记的 Embeddings 并存入 SQLite VSS 扩展中。让工具支持自然语言匹配（例如查“关于未来职业发展的思考”，而不是死板的查 tag）。
- **智能高亮摘要 (BM25 / Highlight)**：不要死板截取前 200 字，而是返回包含搜索关键词/语义最相关的**上下文片段 (Snippets)**。

### 2. `propose_edit` 工具：支持局部差异化编辑 (Diff-based Editing)
**现状分析**：
目前的 `ProposeEditTool` 只支持 `replace` (全量替换) 和 `append` (追加)。
```dart
'action': { 'enum': ['replace', 'append'] }
```
如果用户有一篇 2000 字的长笔记，只让 AI 帮忙修正一个错别字，AI 必须通过 `replace` 返回完整的 2000 字。这极其浪费 Token、极慢，且极其容易因为大模型的注意力分散导致内容丢失。

**优化建议**：
- **引入 Diff 或 Block Replace 机制**：参考 Claude Code 的文件编辑思路，新增一个 `modify` action，要求模型传入 `old_text`（原文片段）和 `new_text`（修改后片段）。UI 接收到这个提议后，只替换对应的片段，不仅节省 Token，还能在 UI 上渲染出精美的“代码对比 (Diff View)”让用户确认。

---

## 🌟 二、 进阶 Agent 架构与新功能建议 (Advanced Features)

### 1. 记忆暂存区与 Scratchpad (Agent Memory)
**现状**：目前 Agent 只能把检索到的内容直接放在对话上下文中，一旦对话过长，早期检索到的笔记上下文就会被挤出上下文窗口。
**建议**：
- **新增 `agent_memory` 工具**：允许 Agent 主动将查阅到的大量资料浓缩总结后，写入一个独立于对话的临时“白板”或 SQLite 表中。
- 当处理“帮我写一份本月工作年报，参考我过去一个月的笔记”这样宏大的任务时，Agent 可以先花 5 轮调用 `explore_notes`，将总结提炼到 Memory 中，最后一轮直接读取 Memory 来生成年报，突破模型的原生上下文窗口限制。

### 2. 本地小模型 (Local LLM) 的特殊工具适配
**现状**：ThoughtEcho 支持 Ollama 等本地模型。但是 7B/8B 级别的本地模型在处理复杂 Tool Schema 时很容易出现 JSON 格式错乱或幻觉。
**建议**：
- **动态 Schema 简化**：在 `agent_service.dart` 构建 tools 列表时，如果检测到当前使用的是 `Ollama` 等小模型，动态裁剪 `parametersSchema` 的描述（去掉复杂的 enum 或非必须字段），甚至只暴露最核心的 2 个工具。
- **强制 JSON 引导**：在发送给小模型的 System Prompt 中动态注入工具的 One-Shot 示例（举一个正确调用工具的完整 JSON 例子），能将本地模型的工具调用成功率提升 50% 以上。

### 3. 多智能体协作 (Multi-Agent Routing)
**现状**：只有一个大而全的单体 Agent。随着功能增加（画图、搜索、写笔记、查日历），将所有系统提示词和工具都塞给一个模型会严重拖慢首字响应速度 (TTFT) 并降低智商。
**建议**：
- **引入意图路由 (Intent Router)**：将任务下发给专门的 Sub-Agent。
  - *检索型 Agent*：只包含 `explore_notes` 工具，System Prompt 专门优化为图书管理员角色。
  - *创作型 Agent*：只包含 `propose_edit` 工具，专门负责文字排版和润色。
- 前端对话首先通过一个轻量级的判断（或基于规则的分类器），决定激活哪个 Agent，从而大幅节省 Prompt Token。

### 4. 后台主动式智能体 (Proactive Background Agents)
**现状**：Agent 只有在用户发消息时才被动触发。
**建议**：
- **实现“夜间整理者” (Nightly Organizer)**：利用 Dart 的后台隔离区 (Isolates) 或 Workmanager，在设备充电/空闲时，唤醒无 UI 的 Background Agent。
- 主动调用 `explore_notes` 扫描当天未分类、未打标签的碎片化笔记，主动调用分类工具打标签，甚至主动生成“今日日报总结”存入数据库。当用户第二天打开 App 时，笔记已经自动井井有条。

---

## 📊 优先级落地建议

如果您的团队资源有限，建议按以下顺序落地：

1. **(极高性价比)** 改造 `propose_edit`，支持局部 `search_and_replace` 机制，这能立刻解决长文章修改慢、易截断的痛点。
2. **(极高性价比)** 修改 `explore_notes`，对于超长笔记不要直接 substring，改为利用 Dart 代码在本地进行正则匹配关键词，返回关键词前后 100 字的上下文片段 (Snippet)。
3. **(中长线)** 引入 Agent 记忆白板 (Scratchpad) 工具，解决“跨月度/跨年度总结”的长文本处理瓶颈。
4. **(长线)** 引入后台整理 Agent 和向量检索，彻底让 ThoughtEcho 从“工具”进化为“贴身智能秘书”。