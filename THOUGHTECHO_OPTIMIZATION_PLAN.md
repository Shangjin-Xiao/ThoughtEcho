# ThoughtEcho UI/UX 与底层架构深度优化指南

基于对 Google AI Gallery (前端交互极致) 和 Claude Code (顶尖 Agent 架构) 源码的深度对标分析，为 ThoughtEcho 梳理出的核心优化方案。

---

## 🎨 第一部分：UI/UX 体验优化 (借鉴 Google AI Gallery)

### 1. 探索页 (Explore Page) 的沉浸感升级
目前 `ExplorePage` 结构清晰，但缺乏现代 AI 产品的“生命力”。
*   **动态背景氛围**：引入缓慢旋转、缩放的极大高斯模糊块 (BackdropFilter) 作为页面底图，随滑动产生视差，打破纯色背景的沉闷。
*   **交错式入场动效 (Staggered Entrance)**：统计数据（笔记数、天气等）摒弃整体渐显，改为 100ms 间隔的交错滑入 (Slide-up + Fade-in)，提升页面展开时的呼吸感。
*   **任务卡片化驱动 (Task-Centric)**：将“AI 对话”单调入口，横向展开为多个具体场景卡片（如“总结本周记录”、“分析地图足迹”），降低用户冷启动思考成本。

### 2. 输入区与历史面板 (Message Input & History)
*   **富媒体缩略图预览**：废弃 `Chip(label: file.name)`。为选中的图片渲染真实的圆角缩略图卡片（带右上角移除按钮），音频渲染波形占位符，实现“所见即所得”。
*   **历史 Prompt 抽屉 (Input History Sheet)**：在输入框侧边增加“历史/灵感”按钮，以 BottomSheet 形式缓存并展示用户过去的高频优质 Prompt，支持一键复用和滑动删除。

### 3. AI 思考与工具反馈的视觉降噪
*   **手风琴式思考折叠 (Collapsable Thinking)**：生成中，展开显示灰色小号思考文字（左侧带 2dp 辅线）；生成完毕，**自动折叠**为单行胶囊按钮（“💡 已深度思考”），保持对话流的绝对清爽。
*   **破坏性操作的安全感视图 (Diff/Confirm View)**：当 AI 调用 `propose_edit` 或试图覆写笔记时，弹出一个代码对比视图（左侧标红旧文本，右侧标绿新文本），并提供明确的 `Allow` / `Reject` 按钮。
*   **丝滑键盘收起 (Nested Scroll)**：拦截列表的向下滚动意图 (`ScrollUpdateNotification`)，只要手指向下滑动查看历史，瞬间收起键盘 (`unfocus`)，提升阻尼跟手感。

### 4. 颜色管理现代化
*   **废除色彩硬编码**：清理 `ai_assistant_page_ui.dart` 中的硬编码色值（如 `Color(0xFF1f3760)`），全面拥抱 Material 3 的语义 Token（如 `colorScheme.primary` 和 `colorScheme.surfaceContainerHigh`），确保在所有动态取色和暗色模式下的完美对比度。

---

## ⚙️ 第二部分：核心架构演进 (借鉴 Claude Code)

### 1. 工具抽象的终极形态 (ToolDef 与 UI 倒置)
目前 ThoughtEcho 的工具渲染逻辑集中在巨大的 `switch` 语句中，违反开闭原则。
*   **重构方案**：将 UI 渲染下沉到各个 `AgentTool` 实现类中。每个工具自行定义其本地化名称 (`getDisplayName`)、摘要文案 (`getSummary`) 以及专属的结果渲染卡片 (`buildResultWidget`)。未来新增工具时，核心 UI 代码无需修改。

### 2. 权限拦截与 Human-in-the-loop (安全挂起机制)
面对敏感的写入操作，当前系统缺乏明确的过程阻断。
*   **重构方案**：引入 `ToolPermissionInterceptor`。在 Agent 试图执行写操作（如修改笔记）前抛出 `AgentToolPermissionRequestEvent`，使 Agent 挂起 (Suspend)。UI 弹出前述的 Diff 对比视图，用户点击 Allow 后再 Resume 执行；若 Reject，则优雅降级，让 Agent 自行处理被拒逻辑，而非直接报错崩溃。

### 3. 复杂任务解耦 (Sidechain Context 与 Worker Agents)
为了避免大段检索 JSON 污染主会话上下文 (Token 爆炸)。
*   **重构方案**：拆分主协调者 (Orchestrator) 与后台工作者 (Worker Agent)。如遇“联网搜索”或“检索海量笔记”，在后台 Fork 一个影子线程 (Sidechain)，让小模型专门负责阅读和提炼，最后只将几句“精华总结”返回给主对话流。

### 4. 高效记忆管理 (Memory Strategy)
摆脱将 AI 当“垃圾桶”的低效模式。
*   **严格的分类学**：强制区分记忆类型（如 `user` 偏好、`feedback` 纠正），拒绝存储可通过搜索获取的原始事实。
*   **幽灵抽取 (Ghost Extraction)**：对话积累一定轮次后，后台静默启动一个小模型读取历史，抽取用户偏好写入数据库，实现真正的 Zero-interruption。
*   **两段式极速召回**：在拉取全量笔记前，先拉取近 50 条笔记的“标题+摘要”；让廉价大模型作为“裁判”选出绝对相关的 3 条，再将完整内容注入主 Prompt，彻底解决长文本注意力分散与幻觉问题。
