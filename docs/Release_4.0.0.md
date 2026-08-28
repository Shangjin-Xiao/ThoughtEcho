# ThoughtEcho v4.0.0 · Thoughter 思考伴侣与全新纸墨主题 / Release Notes

> [!NOTE]
> ### 🚀 ThoughtEcho v4.0.0 重大版本发布
> 本次更新带来深度联动本地笔记的 Thoughter AI 思考伴侣、全新「纸与墨 / 素笺」手感排版风格、更流畅的列表阅读体验，以及更稳固的私有同步。
> 
> 📖 **用户指南**: https://note.shangjinyun.cn/user-guide.html  
> 💡 **Thoughter 专属介绍**: https://note.shangjinyun.cn/thoughter/  
> 🌐 **官方网站**: https://note.shangjinyun.cn/

> [English Version](#english-version)

---

## 🙋 用户篇：全新特性与沉浸体验

### 🎨 纸墨素笺 | 全新手感排版系统
- **三套主题风格，三重阅读心境**：
  - **Material (跟随系统)**：延续 Material 3 动态取色，经典现代。
  - **纸与墨 (Paper & Ink)**：暖调手工色板、随包分发的精选中文衬线体，以及按正文字号与行高精密推导的浅淡纸纹横线，还原伏案书写的温润质感。
  - **素笺 (Plain)**：冷调极简，硬朗利落的线条与克制留白，适合专注理性的文字梳理。
- **墨色自选**：手工风格提供「赭石、黛青、靛蓝、朱砂」四支精选墨色，换墨不换纸，随心变换书写基调。
- **随包衬线字体**：全平台内置精简高质中文衬线字体子集，无需联网下载即可获得温润典雅的排版效果，导出 PDF 与打印同样忠实呈现。
- **更新说明页行内试用**：升级后可在更新说明页直接点击切换预览新风格，Material 仍为默认风格，老用户外观平滑过渡。

### 💡 Thoughter 思考搭档 | 住在摘录本里的灵感伴侣
- **深度联动本地笔记**：ThoughtEcho 的 AI 助手全面升级为 **Thoughter 智能伴侣**。不再只是单调的问答框，而是能基于你的本地 SQLite 笔记库进行语义探索、旧笔记打捞与灵感串联。
- **提案卡片与安全审查 (Proposal & Review)**：AI 生成的所有新笔记与修改均以清晰的「建议卡片」呈现，修改前后一目了然；必须经过你的逐条确认与采纳，绝不悄悄改动你的任何文字。
- **专属长期记忆**：开启后，Thoughter 会在跨会话中逐渐记住你的文风习惯与创作偏好。记忆采用独立物理数据库隔离存储，随时可查、可清空，不上传云端，不进备份。
- **单篇笔记深聊 (Ask Thoughter)**：在编辑器内点击 ✨ 即可直接就当前笔记展开对话，支持一键润色、追问背景或延伸续写。
- **周期洞察与探索页焕新**：以第二人称视角定期梳理你的思考轨迹与灵感沉淀，探索页全新改版，集中呈现周期洞察与思维足迹。

### 📝 列表排版与极致流畅
- **图文错落更清爽**：笔记列表折叠卡片中的配图全面改版为右侧紧凑缩略图，根据正文高度智能分档，彻底消除上下大面积空白，翻阅更整洁。双击卡片即可随时展开全文与高清大图。
- **长列表顺滑如丝**：自研轻量化折叠富文本解析渲染引擎（`CollapsedRichText`），配合视口智能预热与真实屏幕刷新率（60Hz/90Hz/120Hz）帧预算调度，告别快速滑动卡顿。

### 🔄 本地优先与私密同步
- **LocalSend 增量媒体传输**：局域网设备间直传升级为增量传输机制，已传输过的多媒体附件无需重复拉取，跨端同步秒级完成。
- **WebDAV 云同步加固**：优化冲突检测与断点防护，提供移动网络流量保护与清晰直观的连接排查指引。

### 🌟 细节体验与无障碍优化
- **周年庆典**：庆典动态按届数推算，全新立体数字蜡烛造型与天蓝配色。
- **全方位无障碍 (A11y)**：为界面中所有无文本按钮、工具调用状态面板与更多选项补充读屏 Tooltip 提示。
- **多语言完备支持**：全面补全中文、英文、法文、日文、韩文的多语言词条。

---

## 💻 开发者篇：底层重构、性能飞跃与安全加固

> 📑 **研发知识库与全量技术文档索引**：[`docs/INDEX.md`](INDEX.md)

### 💡 Thoughter Agent 架构与物理隔离
- **ReAct 智能体与工具链调度**：构建统一的 `AgentService` 编排层，支持流式并发、工具调用回执（`SearchNotesTool`, `GetNoteDetailTool`, `ExploreNotesTool`, `CreateNoteTool`, `UpdateNoteTool`, `WebFetchTool`）与结构化思考进度呈现。
- **独立长期记忆库 (`agent_memory.db`)**：记忆体系从主库物理剥离至独立 SQLite 实例，严格遵循「不进备份、不跨设备同步、支持整库销毁」的隐私约束；用户画像通过独立 user 消息及 `wrapUserProfile` 沙箱注入，偏好变化采用原位 supersede 策略。
- **AI 统一请求链路**：重构 `AIConnectionTester` 与 `OpenAIStreamService`，消除测试按钮与正式请求的链路分家问题；超时控制严格下沉至客户端层面，根除长连接泄露。

### ⚡ 列表渲染性能与富文本架构革命
- **折叠态 Quill 轻量化 (`CollapsedRichText`)**：在折叠列表卡片中彻底剔除重量级 Quill Controller 与 Document 实例，自研宽感知前缀截取与轻量渲染管道，将卡片 Element 数量削减 38%（146 → 90）。
- **视口智能预热与刷新率帧预算**：引入 `NoteListWarmup` 与 `SpreadFromAnchorCursor`，在空闲帧沿可视视口双向预热测量缓存；基于 `FrameTimingStats` 与 `JankDetector` 动态计算 120Hz/90Hz 真实帧预算，杜绝滚动掉帧。

### 🔒 数据库迁移不变量与坏行容错
- **不可逆写入整列快照**：确立不可逆数据修复迁移的基准约束——写入前必须将整列完整镜像至 `<列名>_backup`，并在二次迁移中保持原地留底。
- **迁移顺序防御定案**：通过测试硬性约束遗留列清理（如 `_removeTagIdsColumn`）必须排在所有快照列创建之前，防止后悔药被误抹除。
- **逐行反序列化兜底**：主列表与查询全线迁移至 `_parseQuoteRows` / `_tryParseQuoteRow`，单条坏行自动隔离并上报计数，彻底杜绝单条脏数据导致整页列表白屏的级联故障。
- **校验对齐与清洗可见性**：严格对齐 `Quote.fromJson` 与 `Quote.validationError` 校验边界，外来数据清洗仅限导入边界并产出结构化清洗报告（`MergeReport.sanitizedFields`）。

### 🛡️ 安全加固与多端合规
- **SQL 注入全量防御**：对全库动态 SQL 排序字段实施 `sanitizeOrderBy()` 白名单机制，修复 `ChatSessionService` 与 `DatabaseSchemaManager` 中的参数拼接隐患。
- **SSRF 深度防御**：`WebFetchService` 全面加入 IPv4/IPv6 Link-Local、Multicast 与内网保留地址过滤及单元测试覆盖。
- **平台合规升级**：Windows MSIX 商店配置声明日语与韩语支持；iOS 完善隐私清单与多语言权限声明。

---

<h2 id="english-version">English Version</h2>

> [!NOTE]
> ### 🚀 ThoughtEcho v4.0.0 Major Release
> This milestone introduces the Thoughter AI thinking companion connected to your local notes, brand new "Paper & Ink / Plain" handcrafted typography styles, fluid list scrolling, and hardened private sync.
> 
> 📖 **User Guide**: https://note.shangjinyun.cn/user-guide.html  
> 💡 **Thoughter Overview**: https://note.shangjinyun.cn/thoughter/  
> 🌐 **Official Site**: https://note.shangjinyun.cn/

---

### 🙋 User Section: New Features & Refined Experience

#### 🎨 Artisan Typography | Tactile Reading & Writing
- **Three Distinct Styles, Three States of Mind**:
  - **Material (System Follow)**: Classic Material 3 dynamic color theming.
  - **Paper & Ink**: Warm handcrafted palette, bundled Chinese serif typography, and subtle paper rules calculated precisely from font size and line height.
  - **Plain**: Cool minimalist aesthetic with crisp edges and generous breathing room.
- **Selectable Inks**: Handcrafted styles feature four curated inks (Umber, Celadon, Indigo, Cinnabar) — switch the ink without altering the paper tone.
- **Bundled Serif Font**: High-quality serif font subset bundled across all platforms for consistent book-like typography without extra downloads; faithfully preserved in PDF exports and print previews.
- **Inline Theme Switcher**: Preview and switch styles directly on the Release Notes page. Material remains default for seamless upgrades.

#### 💡 Thoughter AI Companion | A Thinking Partner Inside Your Notes
- **Connected to Your Local Vault**: Our AI assistant evolves into **Thoughter**, an active thinking partner. Instead of a detached chatbot, Thoughter understands your local SQLite vault to retrieve notes, surface forgotten ideas, and make meaningful connections.
- **Proposal & Review Cards**: All AI-suggested notes and edits arrive as clear visual proposal cards with side-by-side diffs. Nothing is modified without your explicit approval — you maintain 100% control.
- **Isolated Long-Term Memory**: When enabled, Thoughter remembers your preferred tone and writing habits across sessions. Memory is stored in a separate local database, never uploaded to clouds, never included in backups, and clearable at any time.
- **Ask Thoughter on Single Notes**: Tap ✨ inside the editor to polish, question, or extend the open note with contextual focus.
- **Periodic Insights & Rebuilt Explore Page**: Explore page is completely reimagined to aggregate periodic reflections and thinking trends written in a reflective second-person voice.

#### 📝 Streamlined Layout & Pure Fluidity
- **Compact Media Thumbnails**: Note card photos in the list now render neatly as right-side thumbnails with adaptive heights based on text volume, eliminating awkward vertical whitespace. Double-tap any card to view full text and media.
- **Silky Smooth Scrolling**: Powered by `CollapsedRichText`, our lightweight prefix rendering engine, paired with viewport warmup and dynamic 120Hz/90Hz frame budgeting.

#### 🔄 Local-First & Hardened Sync
- **LocalSend Incremental Media Transfer**: LAN P2P transfer now sends media attachments incrementally, skipping already synchronized files for instant transfers.
- **WebDAV Private Cloud Hardening**: Improved conflict isolation, mobile cellular data protection, and friendly diagnostic guides.

#### 🌟 Polished Details & Accessibility
- **Anniversary Milestones**: Dynamic edition calculation, dimensional 3D digital candles, and celestial blue accents.
- **Comprehensive Accessibility (A11y)**: Screen reader tooltips added across all icon buttons, progress panels, and dialog actions.
- **Complete Internationalization**: Fully localized across Chinese, English, French, Japanese, and Korean.

---

### 💻 Developer Section: Under the Hood, Performance & Security

> 📑 **Documentation Index & Technical Specifications**: [`docs/INDEX.md`](INDEX.md)

#### 💡 Thoughter Agent Architecture & Memory Isolation
- **ReAct Agent & Tool Orchestration**: Unified `AgentService` orchestration engine supporting concurrent streaming, structured tool execution (`SearchNotesTool`, `GetNoteDetailTool`, `ExploreNotesTool`, `CreateNoteTool`, `UpdateNoteTool`, `WebFetchTool`), and transparent progress states.
- **Isolated Memory Database (`agent_memory.db`)**: Agent memory is physically separated into a standalone SQLite instance to guarantee strict privacy (excluded from backup/sync, easily purgeable). User profiles are wrapped in isolated user messages via `wrapUserProfile` with in-place superseding.
- **Unified AI Request Pipeline**: Consolidated `AIConnectionTester` and `OpenAIStreamService` to ensure connection tests reflect real production calls; timeouts pushed directly to client configurations.

#### ⚡ List Rendering Engine & Lightweight Quill Pipeline
- **Collapsed Rich Text (`CollapsedRichText`)**: Replaced heavyweight Quill controllers and documents in list view with a width-aware prefix parser, slashing widget element overhead by 38% (146 → 90 elements per card).
- **Viewport Warmup & Adaptive Frame Budgets**: Integrated `NoteListWarmup` and `SpreadFromAnchorCursor` to warm measurement caches during idle frames. Utilized `FrameTimingStats` and `JankDetector` for real-time 120Hz/90Hz frame budget enforcement.

#### 🔒 Database Migration Invariants & Row-Level Resilience
- **Immutable Backup Columns (`*_backup`)**: Enforced snapshotting original values prior to irreversible updates, ensuring idempotent second-pass safety.
- **Deterministic Migration Ordering**: Verified that legacy column cleanups run strictly before snapshot migrations to preserve rollback integrity.
- **Row-by-Row Parse Fallback**: Standardized database queries on `_parseQuoteRows` / `_tryParseQuoteRow`, gracefully skipping corrupted rows and logging metrics to prevent whole-page crashes.
- **Validation Alignment & Sanitization Transparency**: Aligned `Quote.fromJson` and `Quote.validationError` boundaries. Restricted sanitization to import boundaries with structured `MergeReport.sanitizedFields`.

#### 🛡️ Security Hardening & Platform Compliance
- **Comprehensive SQL Injection Defense**: Enforced `sanitizeOrderBy()` whitelisting on dynamic SQL order clauses; secured `ChatSessionService` and `DatabaseSchemaManager`.
- **SSRF Filtering**: Enhanced `WebFetchService` with IPv4/IPv6 link-local, multicast, and private range filters with comprehensive unit test coverage.
- **Platform Packaging**: Added Japanese and Korean store declarations in Windows MSIX; enhanced iOS privacy manifests and permission descriptions.

---

**Full Changelog**: `3.7.0...4.0.0`
