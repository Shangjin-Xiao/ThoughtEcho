# ThoughtEcho 知识库与历史文档索引 (Docs Index)

> 本文档是 ThoughtEcho 研发知识库的全局导航索引。在开展复杂功能开发、性能优化、主题改造或架构重构前，请先查阅对应主题的历史记录与审计文档，避免推翻既有决策或重复踩坑。

---

## 快速导航

- [一、核心规范与发布文档](#一核心规范与发布文档)
- [二、性能分析与优化演化链](#二性能分析与优化演化链)
- [三、主题系统与 UI 现代化](#三主题系统与-ui-现代化)
- [四、Thoughter 与 AI 记忆体系](#四thoughter-与-ai-记忆体系)
- [五、同步、网络与核心架构](#五同步网络与核心架构)
- [六、架构决策总账与 AI 团队资产](#六架构决策总账与-ai-团队资产)
- [七、新增文档命名与归档规范](#七新增文档命名与归档规范)

---

## 一、核心规范与发布文档

| 文档名称 | 路径 | 类型 | 适用场景 / 核心内容 |
|---|---|---|---|
| **双语用户手册** | [`USER_MANUAL.md`](USER_MANUAL.md) | 🟢 活跃 | 用户端双语完整使用指南（中文 + 英文） |
| **商店上架指南** | [`STORE_SUBMISSION_GUIDE.md`](STORE_SUBMISSION_GUIDE.md) | 🟢 活跃 | 各应用商店文案、合规与截图要求 |
| **设备与测试环境** | [`DEVICE_INFO.md`](DEVICE_INFO.md) | 🟢 活跃 | 本地测试设备、硬件资源与运行约束（Git 忽略） |
| **项目全景综述** | [`project-overview.md`](project-overview.md) | 🟢 活跃 | 项目整体架构设计、技术全景与能力分布 |
| **项目摘要** | [`PROJECT_SUMMARY.md`](PROJECT_SUMMARY.md) | 📦 归档 | 早期项目概况与模块设计速查 |
| **版本发布记录** | [`Release_3.7.0.md`](Release_3.7.0.md)<br>[`Release_3.6.5.md`](Release_3.6.5.md)<br>[`Release_3.6.0.md`](Release_3.6.0.md)<br>[`Release_3.5.5.md`](Release_3.5.5.md)<br>[`Release_3.5.0.md`](Release_3.5.0.md) | 📦 归档 | v3.5.0 ~ v3.7.0 各版本发布日志与变更清单 |

---

## 二、性能分析与优化演化链

针对列表渲染卡顿、Quill 富文本冷启动、首屏耗时与预热失效的一系列深度分析与优化记录：

| 文档名称 | 路径 | 日期 | 状态 | 核心内容 / 结论 |
|---|---|---|---|---|
| **列表预热失效与重构** | [`note-list-warmup-invalidation-2026-08-22.md`](note-list-warmup-invalidation-2026-08-22.md) | 2026-08-22 | 🟢 事实源 | 列表预热失效根因分析及状态管理重构 |
| **首屏渲染成本剖析** | [`note-list-first-paint-cost-2026-08-19.md`](note-list-first-paint-cost-2026-08-19.md) | 2026-08-19 | 🟢 参考 | 首屏构建帧开销、组件树瘦身与优化测算 |
| **列表深层性能分析** | [`note-list-perf-analysis-2026-08-13.md`](note-list-perf-analysis-2026-08-13.md) | 2026-08-13 | 🟢 参考 | 列表滚动掉帧、重绘范围与 CPU 瓶颈分析 |
| **列表优化阶段交接** | [`note-list-perf-handoff-2026-08-12.md`](note-list-perf-handoff-2026-08-12.md) | 2026-08-12 | 📦 阶段交接 | 第一阶段列表卡顿治理与渲染预算控制交接 |
| **冷启动帧预算优化** | [`note-list-cold-quill-frame-budget-handoff-2026-07-30.md`](note-list-cold-quill-frame-budget-handoff-2026-07-30.md) | 2026-07-30 | 📦 过程记录 | Quill 冷启动帧开销切片与时间分片 |
| **Quill 延迟实例化** | [`note-list-cold-quill-materialization-handoff-2026-07-15.md`](note-list-cold-quill-materialization-handoff-2026-07-15.md) | 2026-07-15 | 📦 过程记录 | 纯文本与富文本延迟按需实例化策略 |
| **Quill 可见前缀提取** | [`note-list-visible-quill-prefix-handoff-2026-07-12.md`](note-list-visible-quill-prefix-handoff-2026-07-12.md) | 2026-07-12 | 📦 过程记录 | 截取可见前缀减少 Delta 解析开销 |
| **新增弹窗性能优化** | [`add-note-dialog-firebase-perf-handoff-2026-07-25.md`](add-note-dialog-firebase-perf-handoff-2026-07-25.md) | 2026-07-25 | 📦 过程记录 | 新增弹窗渲染耗时与 Firebase 初始化解耦 |
| **早期列表性能交接** | [`note-list-performance-firebase-handoff-2026-06-09.md`](note-list-performance-firebase-handoff-2026-06-09.md) | 2026-06-09 | 📦 过程记录 | 早期列表滑动手感与渲染优化过程 |

---

## 三、主题系统与 UI 现代化

关于 Material 3 动态取色、纸墨/素笺三大手工主题风格及圆角令牌体系：

| 文档名称 | 路径 | 日期 | 状态 | 核心内容 / 结论 |
|---|---|---|---|---|
| **纸与墨主题实现交接** | [`paper-ink-theme-handoff-2026-07-31.md`](paper-ink-theme-handoff-2026-07-31.md) | 2026-07-31 | 🔒 **唯一事实源** | 三套主题设计推导、令牌分发机制及禁踩红线 |
| **纸与墨主题规划方案** | [`paper-ink-theme-plan-2026-07-30.md`](paper-ink-theme-plan-2026-07-30.md) | 2026-07-30 | 📦 方案原案 | 纸与墨风格设计草案与色板选型过程 |
| **全局形状与圆角迁移** | [`theme-shape-migration-audit-2026-08-01.md`](theme-shape-migration-audit-2026-08-01.md) | 2026-08-01 | 🟢 事实源 | `AppShapeTokens` 令牌重构全量组件排查清单 |
| **M3 现代化改造审计** | [`m3-modernization-audit-2026-08-11.md`](m3-modernization-audit-2026-08-11.md) | 2026-08-11 | 🟢 事实源 | M3 控件、无障碍色差、动态取色规范审计 |
| **卡片重构进展记录** | [`card-redesign-progress-2026-07-28.md`](card-redesign-progress-2026-07-28.md) | 2026-07-28 | 📦 过程记录 | 笔记卡片视觉层级与边框重构记录 |
| **UI 清理交接记录** | [`ui-cleanup-handoff-2026-07-31.md`](ui-cleanup-handoff-2026-07-31.md) | 2026-07-31 | 📦 阶段交接 | 历史硬编码颜色、无用布局样式的统一清理 |
| **字体与排版重构交接** | [`font-issue-handoff-2026-07-25.md`](font-issue-handoff-2026-07-25.md)<br>[`font-refactor-handoff-2026-07-25.md`](font-refactor-handoff-2026-07-25.md)<br>[`font-refactor-prompt-2026-07-25.md`](font-refactor-prompt-2026-07-25.md) | 2026-07-25 | 📦 过程记录 | 平台字体缺失、衬线字体加载与斜体渲染修复 |

---

## 四、Thoughter 与 AI 记忆体系

关于智能助理 Thoughter、多 AI Provider 接入以及长期记忆库 `agent_memory.db` 的设计：

| 文档名称 | 路径 | 日期 | 状态 | 核心内容 / 结论 |
|---|---|---|---|---|
| **Thoughter 长期记忆调研** | [`agent-memory-research-2026-08-08.md`](agent-memory-research-2026-08-08.md) | 2026-08-08 | 🔒 **唯一事实源** | 长期记忆独立库、画像包裹、原位覆盖机制定案 |
| **记忆系统早期规划** | [`memory-system-plan-2026-07-31.md`](memory-system-plan-2026-07-31.md) | 2026-07-31 | 📦 方案原案 | 记忆系统架构分层与数据库模型原案 |
| **探索页与 Thoughter 联动** | [`explore-thoughter-handoff-2026-07-31.md`](explore-thoughter-handoff-2026-07-31.md) | 2026-07-31 | 🟢 参考 | 探索页周期统计聚合与 Thoughter 交互交接 |
| **编辑器 AI 迁移 Thoughter** | [`editor-ai-to-thoughter-plan.md`](editor-ai-to-thoughter-plan.md) | 2026-07-29 | 🟢 参考 | 编辑器独立 AI 功能整合进 Thoughter 规划 |
| **Agent 模式参考与调研** | [`agent-reference-patterns-2026-07.md`](agent-reference-patterns-2026-07.md) | 2026-07-27 | 🟢 参考 | 多智能体上下文管理与工具链模式调研 |
| **Agent 系统重构交接** | [`agent-handoff-2026-07-31.md`](agent-handoff-2026-07-31.md) | 2026-07-31 | 📦 阶段交接 | Thoughter 会话上下文与工具流转重构交接 |

---

## 五、同步、网络与核心架构

关于 WebDAV、LocalSend 局域网同步、数据库架构与产品路线演进：

| 文档名称 | 路径 | 日期 | 状态 | 核心内容 / 结论 |
|---|---|---|---|---|
| **代码库最新架构与任务审计** | [`codebase-architecture-and-tasks-audit-2026-08-23.md`](codebase-architecture-and-tasks-audit-2026-08-23.md) | 2026-08-23 | 🟢 最新事实源 | 模块解耦、大文件监控与后续重构路线总清单 |
| **WebDAV 与 LocalSend 审计** | [`WebDAV_LocalSend_Backup_Code_Audit_and_Refactoring_Report.md`](WebDAV_LocalSend_Backup_Code_Audit_and_Refactoring_Report.md) | 2026-07-25 | 🟢 事实源 | 同步并发、断点续传、冲突解决与重构报告 |
| **早期系统架构审计** | [`architecture-audit-2026-07-26.md`](architecture-audit-2026-07-26.md) | 2026-07-26 | 📦 历史参考 | 早期分层结构与服务层重构审计 |
| **增长与产品路线规划** | [`growth-and-product-direction-2026-07-26.md`](growth-and-product-direction-2026-07-26.md) | 2026-07-26 | 🟢 参考 | 产品定位、用户增长策略与核心功能路线 |
| **专项功能规划清单 (plans)** | [`plans/2026-07-10-localsend-sync-lifecycle.md`](plans/2026-07-10-localsend-sync-lifecycle.md)<br>[`plans/2026-07-11-localsend-incremental-media-design.md`](plans/2026-07-11-localsend-incremental-media-design.md)<br>[`plans/2026-07-11-localsend-incremental-media.md`](plans/2026-07-11-localsend-incremental-media.md)<br>[`plans/2026-07-10-chat-history-search-highlight.md`](plans/2026-07-10-chat-history-search-highlight.md)<br>[`plans/2026-07-10-smart-result-card-ux.md`](plans/2026-07-10-smart-result-card-ux.md)<br>[`plans/2026-07-11-agent-rich-edit.md`](plans/2026-07-11-agent-rich-edit.md)<br>[`plans/2026-07-12-note-list-visible-quill-prefix.md`](plans/2026-07-12-note-list-visible-quill-prefix.md) | 2026-07 | 📦 方案原案 | LocalSend 生命周期、增量媒体同步、聊天高亮等 |

---

## 六、架构决策总账与 AI 团队资产

| 文件名称 | 路径 | 核心作用 |
|---|---|---|
| **架构决策总账 (ADR)** | [`decisions.md`](decisions.md) | **团队所有架构决议（ADR）真源**，记录了每一次决策的背景、选型与结论 |
| **团队花名册与分工** | [`squad/team.md`](squad/team.md) | 11 个 Agent 的角色定义、模型偏好与指令 |
| **协作信号与路由表** | [`squad/routing.md`](squad/routing.md) | 任务信号到对应 Agent 的自动路由与审核流 |
| **协作仪式配置** | [`squad/ceremonies.md`](squad/ceremonies.md) | 设计评审、发版检查、回顾会等团队仪式触发规则 |
| **角色章程与历史** | [`squad/agents/`](squad/agents/) | 各角色独立的 `charter.md` 与会话演化 `history.md` |

---

## 七、新增文档命名与归档规范

为了保持知识库的清晰与可检索性，后续新增文档请遵守以下规范：

### 1. 命名格式
`docs/<topic>-<type>-YYYY-MM-DD.md`

- `<topic>`：模块或主题（如 `note-list`, `theme`, `thoughter`, `sync`, `database`）
- `<type>`：文档类型：
  - `audit`（代码或架构审计）
  - `perf` / `analysis`（性能排查与数据分析）
  - `plan`（方案规划与设计原案，复杂子计划可放入 `docs/plans/`）
  - `handoff`（跨会话/阶段性技术交接）
  - `research`（技术调研与对比）
- `YYYY-MM-DD`：创建日期

### 2. 状态标签定义
- 🔒 **唯一事实源**：已结案并形成权威约束的最终设计文档（修改前必须通读）。
- 🟢 **活跃 / 事实源**：当前正在生效的最新规范或设计。
- 📦 **归档 / 过程记录**：历史方案、中间推导或单轮冲刺记录，仅用于追溯决策原因。
- 🔍 **调研 / 分析**：性能数据评测与技术选型分析。

### 3. 闭环流转
新增技术文档后，请使用 `project-docs-manager` 技能自动在本文档中登记，并将关键决策点提炼追加至 [`docs/decisions.md`](decisions.md)。
