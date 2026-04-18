# ThoughtEcho AI Agent Design Specification

## 1. 触发入口设计 (Entry Points)
**决定**: 全局 + 编辑器内 (Global + In-Editor)
* **全局入口** (如悬浮窗/底部Tab)：用于随时唤起对话，主要用于生成全新笔记、查询知识、检索历史记录。
* **编辑器内入口** (如工具栏或划词菜单)：专门用于针对当前正在编辑的笔记进行局部或全文的润色、修正、续写和追加。
## 2. 新生成笔记保存 (Saving New Notes)
**决定**: 直接保存 + 打开编辑器并修缮 (Direct Save + Open Editor)
* **交互卡片**: 当 AI 提议新建笔记 (`propose_new_note` 工具) 时，对话区出现预览卡片。
* **直接保存 (Save)**: 点击后静默保存至 SQLite，当前停留在对话页，适合快速记录。
* **打开编辑器 (Open Editor)**: 携带生成的正文和相关属性 (Tags, Location 等) 跳入全功能编辑器 (`NoteFullEditorPage`) 供用户进一步排版、增删。

## 3. 润色替换与续写追加 (Polish & Append)
**决定**: 两种应用模式 (直接保存 vs. 打开编辑器应用)
根据用户的具体场景，当 AI 提出针对某篇笔记的修改建议（生成 `action: "replace"` 或 `action: "append"` 的 `smart_result` 卡片）时，卡片提供两种选择：
* **直接保存 (Direct Save)**: 直接在后台将修改内容更新到数据库对应笔记中，界面上给出提示。适合简单的修正或续写，不打断当前的对话流。
* **打开编辑器应用 (Open Editor & Apply)**: 携带 AI 给出的修改文本跳转至全功能编辑器页 (`NoteFullEditorPage`)。在编辑器中，新内容会被自动带入并提供确认/对比机制，适合需要人工二次审校的大段落润色。

## 4. 与现有编辑器模块的整合 (Integration with Existing Editors)
**决定**: 按轻重区分，复用现有双编辑器模式 (Differentiate by complexity, reuse existing dual-editor modes)
* **短文本/快捷记录**: 如果 AI 生成的内容较短（如一句话总结、想法提炼），且主要为纯文本，当用户点击“打开编辑器”时，唤起轻量级的快捷记录弹窗 (`AddNoteDialog`)。AI 返回的 `tag_ids`、`include_location`、`include_weather` 属性将直接预填到该弹窗的对应组件中。
* **长文本/富文本润色**: 若 AI 提议是对已有长篇笔记进行大段落润色、结构梳理（生成 `deltaContent`），或者生成的全新笔记篇幅较长，则自动跳转全屏富文本编辑器 (`NoteFullEditorPage`)，并将元数据 (Metadata) 携带到全屏编辑器的属性面板中。这样能很好地保持现有应用“快捷记录 vs. 深度编辑”的心智模型。

## 5. 与现有孤立 AI 功能的兼容 (Compatibility with Existing AI Features)
**决定**: 保持现状，各自独立运行 (Keep as is, independent operation)
* 现有的“AI 周期报告 (`ai_periodic_report_page.dart`)”、“智能推送”、“全屏编辑器侧滑栏里的 AI 分析”、“每日灵感提问”等独立 AI 功能，维持其现有的调用逻辑 (`ai_service.dart`) 与展现形式，互不干扰。
* 全新的 `AgentService` 主要承载全局对话式的“问笔记”助手，以及由助手对话引发的“生成新笔记”、“提议修改笔记”这套 Tool Calling 循环。这样可以避免引入不必要的重构风险，保障已有稳定功能的运行。

## 6. AI 卡片反馈与迭代机制 (Feedback Loop for Agent Tools)
**决定**: 自然对话追加 (Natural conversational iteration)
* **极简交互**: 当用户对 AI 触发 `propose_edit` 或 `propose_new_note` 生成的提议卡片（如一段不太通顺的润色）感到不满意时，不需要卡片内的复杂重新生成弹窗，而是直接在下方对话框内发送诸如“这段太长了，缩短点”等指令。
* **Agent 状态机接管**: Agent 会结合上一轮成功或失败的 tool call 历史，理解用户的上下文意图，自动生成并发送一张**新的**功能卡片。这保证了交互心智的统一，同时使多轮多步骤的迭代能在同一个对话流内顺畅进行。

## 7. Agent 检索本地笔记的权限边界 (Privacy & Scope of Search)
**决定**: 默认授权搜索并自动过滤敏感/隐藏笔记 (Default authorization with hidden filtering)
* **默认授权**: Agent 在需要辅助创作、查阅上下文或回应用户需求时，允许在对话后台自主调用 `explore_notes` 搜索全部普通类别的本地笔记。无需用户每次明确下达“搜索”指令，增强助手的“主动性”与“懂我”。
* **强制过滤**: 底层 `explore_notes` 工具及相关查询必须严格并永久过滤掉带有系统隐藏标签 (`system_hidden_tag`) 或用户标记为私密/锁定的分类及笔记。这属于不可动摇的安全底线。

## 8. 更改现有笔记的粒度 (Granularity of Editing Existing Notes)
**决定**: 仅干预文本片段，未来支持按行/精准片段替换 (Text-only intervention, future line-by-line replacement)
* 无论是“润色”还是“续写”，AI Agent 都**只允许操作纯文本内容**，绝对不应该让它重写或覆盖整篇包含复杂排版（Delta JSON）的笔记。
* 远期规划：实现基于 Diff 的局部替换（按行或精准片段），AI 只需要输出被修改的那一小段话，而不需要把整个长笔记重新生成一遍，以防破坏上下文的富文本格式。

## 9. AI 提议新建笔记的元数据控制 (Metadata Control for New Notes)
**待决定**: (正在讨论) 关于标签、位置、天气的赋予权归属。

## 9. AI 提议新建笔记的元数据控制 (Metadata Control for New Notes)
**决定**: AI 负责标签，环境信息(位置/天气)由卡片按钮交互决定 (AI tags, Card Buttons for Env)
* **标签提取 (Tags)**: Agent 应像人一样通过标签名称 (Name) 来理解和建议标签，并在【直接保存】时将这些建议的标签一并存入数据库。
* **作者 (Author)**: 默认不进行预填充。
* **位置与天气 (Location & Weather) 的卡片化交互**:
  * 在 AI 提议新建笔记的 `smart_result` 卡片上，额外提供两个显眼的快捷按钮：【📍 添加位置】和【🌤️ 添加天气】。
  * 用户在点击“直接保存”之前或之后，可以通过点击这两个按钮，灵活地将当前的环境信息附加上去。
  * 当点击【打开编辑器】进入全屏编辑器时，位置和天气的处理逻辑也与卡片保持一致，以小按钮的形式提供“点击即添加”的体验。

## 10. AI 与编辑器草稿冲突的防线设计 (Draft Conflict Prevention)
**决定**: 进入 AI 前强制保存草稿 (Force save before entering AI)
* 为了防止 AI 在 `AgentService` 中直接通过提议卡片修改了 SQLite 数据库，而导致背后的 `NoteFullEditorPage`（可能包含未保存内容）发生脏写和版本分叉（Split-Brain），采用“前置拦截”策略。
* **具体交互**: 当用户在编辑器内产生修改但未保存时，若点击触发 AI 助理（如润色、续写），系统会弹窗提示“进入 AI 助手前需先保存当前笔记内容”，并提供一个【直接保存】按钮。用户确认保存后，笔记正式落库，随后再携带最新内容跳转到 AI 对话页。

## 11. AI 提议卡片的视觉呈现 (AI Card UX)
**决定**: 流式解析展示 `smart_result` (Streaming JSON parsing)
* 虽然 AI 工具输出的是 JSON 代码块 (````smart_result {...} ````)，但在前端渲染卡片时，需要实现容错流式解析，让卡片内的标题、正文等字段能够像打字机一样逐字出现，避免长时间“正在思考…”然后突然弹出一大段文本的割裂体验。
