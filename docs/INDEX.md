# ThoughtEcho 知识库与历史文档索引 (Docs Index)

> 本文档是 ThoughtEcho 研发知识库的全局导航索引（已 100% 覆盖全库 77 篇技术文档与资产）。在开展复杂功能开发、性能优化、主题改造或架构重构前，请先查阅对应主题的历史记录与审计文档，避免推翻既有决策或重复踩坑。

---

## 快速导航

- [一、核心规范与发布文档 (11 篇)](#一核心规范与发布文档)
- [二、性能分析与优化演化链 (9 篇)](#二性能分析与优化演化链)
- [三、主题系统与 UI 现代化 (9 篇)](#三主题系统与-ui-现代化)
- [四、Thoughter 与 AI 记忆体系 (7 篇)](#四thoughter-与-ai-记忆体系)
- [五、同步、网络与核心架构 (12 篇)](#五同步网络与核心架构)
- [六、架构决策总账与 AI 团队资产 (29 篇)](#六架构决策总账与-ai-团队资产)
- [七、新增文档命名与归档规范](#七新增文档命名与归档规范)

---

## 一、核心规范与发布文档

| 文档名称 | 路径 | 类型 / 状态 | 适用场景 / 核心内容 |
|---|---|:---:|---|
| **v4.0.0 发版说明** | [`Release_4.0.0.md`](Release_4.0.0.md) | 🟢 **最新发布** | v4.0.0 重大里程碑发版日志、Thoughter 思考伴侣、纸墨素笺主题与架构改造总结 |
| **双语用户手册** | [`USER_MANUAL.md`](USER_MANUAL.md) | 🟢 活跃 | 用户端双语完整使用指南（中文 + 英文），涵盖所有端侧功能与快捷操作 |
| **商店上架与合规指南** | [`STORE_SUBMISSION_GUIDE.md`](STORE_SUBMISSION_GUIDE.md) | 🟢 活跃 | Windows Microsoft Store、Google Play 与 App Store 合规、文案与截图指南 |
| **设备与测试环境说明** | [`DEVICE_INFO.md`](DEVICE_INFO.md) | 🟢 活跃 | 本地测试设备、硬件资源、冷启动耗时与测试运行约束（由 `.gitignore` 忽略） |
| **项目全景综述与核心架构** | [`project-overview.md`](project-overview.md) | 🟢 活跃 | 项目整体分层架构、核心服务分布、技术选型与多端支持全景概览 |
| **项目摘要 [已归档]** | [`PROJECT_SUMMARY.md`](PROJECT_SUMMARY.md) | 📦 归档 | 早期项目概况与模块设计速查（包含早期架构与代码统计历史记录） |
| **v3.7.0 发版说明 [已归档]** | [`Release_3.7.0.md`](Release_3.7.0.md) | 📦 归档 | v3.7.0 版本发布日志、重大特性清单与修复记录 |
| **v3.6.5 发版说明 [已归档]** | [`Release_3.6.5.md`](Release_3.6.5.md) | 📦 归档 | v3.6.5 版本发布日志与变更清单 |
| **v3.6.0 发版说明 [已归档]** | [`Release_3.6.0.md`](Release_3.6.0.md) | 📦 归档 | v3.6.0 版本发布日志与变更清单 |
| **v3.5.5 发版说明 [已归档]** | [`Release_3.5.5.md`](Release_3.5.5.md) | 📦 归档 | v3.5.5 版本发布日志与变更清单 |
| **v3.5.0 发版说明 [已归档]** | [`Release_3.5.0.md`](Release_3.5.0.md) | 📦 归档 | v3.5.0 版本发布日志与变更清单 |

---

## 二、性能分析与优化演化链

针对列表渲染卡顿、Quill 富文本冷启动、首屏耗时与预热失效的一系列深度分析与优化记录：

| 文档名称 | 路径 | 日期 | 状态 | 核心内容 / 结论 |
|---|---|---|:---:|---|
| **记录页：预热在空转与刷新率适配** | [`note-list-warmup-invalidation-2026-08-22.md`](note-list-warmup-invalidation-2026-08-22.md) | 2026-08-22 | 🟢 **最新事实源** | 列表预热空转根因分析、120Hz 动态刷新率适配、SpreadFromAnchorCursor 扩散预热与分段计时验证 |
| **首屏渲染成本剖析与卡片瘦身** | [`note-list-first-paint-cost-2026-08-19.md`](note-list-first-paint-cost-2026-08-19.md) | 2026-08-19 | 🟢 事实源 | 首屏构建帧开销、组件树挂载耗时剖析、卡片 Element 瘦身 38%（146→90）与空闲预热基准 |
| **列表深层性能分析** | [`note-list-perf-analysis-2026-08-13.md`](note-list-perf-analysis-2026-08-13.md) | 2026-08-13 | 🔍 调研分析 | 列表滚动掉帧、重绘范围、CPU/GPU 瓶颈与 Layout 耗时深度追踪 |
| **列表优化阶段交接 [已归档]** | [`note-list-perf-handoff-2026-08-12.md`](note-list-perf-handoff-2026-08-12.md) | 2026-08-12 | 📦 阶段交接 | 列表卡顿治理、渲染预算控制与阶段性优化成果交接 |
| **冷启动帧预算优化交接 [已归档]** | [`note-list-cold-quill-frame-budget-handoff-2026-07-30.md`](note-list-cold-quill-frame-budget-handoff-2026-07-30.md) | 2026-07-30 | 📦 阶段交接 | Quill 冷启动帧开销切片、时间分片与帧预算平衡交接 |
| **Quill 延迟物化交接 [已归档]** | [`note-list-cold-quill-materialization-handoff-2026-07-15.md`](note-list-cold-quill-materialization-handoff-2026-07-15.md) | 2026-07-15 | 📦 阶段交接 | 滚动期间延后冷 Quill 物化、停止后逐帧恢复策略交接 |
| **折叠态 Quill 宽度感知前缀交接 [已归档]** | [`note-list-visible-quill-prefix-handoff-2026-07-12.md`](note-list-visible-quill-prefix-handoff-2026-07-12.md) | 2026-07-12 | 📦 阶段交接 | 截取宽度感知可见前缀减少 Delta 解析与首次布局开销交接 |
| **新增弹窗与 Firebase 性能优化交接 [已归档]** | [`add-note-dialog-firebase-perf-handoff-2026-07-25.md`](add-note-dialog-firebase-perf-handoff-2026-07-25.md) | 2026-07-25 | 📦 阶段交接 | 新增笔记弹窗渲染耗时优化与 Firebase 初始化解耦交接 |
| **早期列表滚动优化与 Firebase 交接 [已归档]** | [`note-list-performance-firebase-handoff-2026-06-09.md`](note-list-performance-firebase-handoff-2026-06-09.md) | 2026-06-09 | 📦 阶段交接 | 早期列表滑动手感优化、Firebase Test Lab A/B 实测与实验开关 |

---

## 三、主题系统与 UI 现代化

关于 Material 3 动态取色、纸墨/素笺三大手工主题风格、GB2312 衬线字体子集及 `AppShapeTokens` 令牌体系：

| 文档名称 | 路径 | 日期 | 状态 | 核心内容 / 结论 |
|---|---|---|:---:|---|
| **纸与墨主题实现交接** | [`paper-ink-theme-handoff-2026-07-31.md`](paper-ink-theme-handoff-2026-07-31.md) | 2026-07-31 | 🔒 **唯一事实源** | 三套主题设计推导、`ThemeStyleForm` 与 `AppShapeTokens` 令牌下发机制、随包 GB2312 衬线字体子集定案与禁踩红线 |
| **纸墨主题规划方案 [已归档 / 方案原案]** | [`paper-ink-theme-plan-2026-07-30.md`](paper-ink-theme-plan-2026-07-30.md) | 2026-07-30 | 📦 方案原案 | 纸与墨风格设计草案、色板选型推导过程与已否决设想记录 |
| **纸墨主题形状/阴影迁移审计 [已归档]** | [`theme-shape-migration-audit-2026-08-01.md`](theme-shape-migration-audit-2026-08-01.md) | 2026-08-01 | 📦 **归档 / 审计记录** | `AppShapeTokens` 令牌重构全量组件排查清单（6 批迁移已全量合入，归档存档） |
| **Material 3 现代化改造审计 [已归档]** | [`m3-modernization-audit-2026-08-11.md`](m3-modernization-audit-2026-08-11.md) | 2026-08-11 | 📦 **归档 / 历史审计** | M3 控件、无障碍色差、动态取色规范审计（预测式返回、MenuAnchor、SearchBar 等改造已落地） |
| **卡片重构进展记录 [已归档]** | [`card-redesign-progress-2026-07-28.md`](card-redesign-progress-2026-07-28.md) | 2026-07-28 | 📦 过程记录 | AI 智能卡片视觉层级、边框与统一布局重构记录 |
| **UI 清理交接记录 [已归档]** | [`ui-cleanup-handoff-2026-07-31.md`](ui-cleanup-handoff-2026-07-31.md) | 2026-07-31 | 📦 阶段交接 | 历史硬编码颜色、无用布局样式的统一清理交接 |
| **字体变粗问题交接 [已归档]** | [`font-issue-handoff-2026-07-25.md`](font-issue-handoff-2026-07-25.md) | 2026-07-25 | 📦 过程记录 | 平台字体缺失、衬线字体加载异常排查记录 |
| **FontWeight 重构完成交接 [已归档]** | [`font-refactor-handoff-2026-07-25.md`](font-refactor-handoff-2026-07-25.md) | 2026-07-25 | 📦 过程记录 | 字重体系标准化与可变字重补偿交接 |
| **字体重构提示词与指令记录 [已归档]** | [`font-refactor-prompt-2026-07-25.md`](font-refactor-prompt-2026-07-25.md) | 2026-07-25 | 📦 过程记录 | 字体重构期间的提示词设计与执行指令归档 |

---

## 四、Thoughter 与 AI 记忆体系

关于智能助理 Thoughter、多 AI Provider 接入以及长期记忆库 `agent_memory.db` 的设计与实践：

| 文档名称 | 路径 | 日期 | 状态 | 核心内容 / 结论 |
|---|---|---|:---:|---|
| **Thoughter 长期记忆系统深度调研与设计** | [`agent-memory-research-2026-08-08.md`](agent-memory-research-2026-08-08.md) | 2026-08-08 | 🔒 **唯一事实源** | 独立物理数据库 `agent_memory.db` 隔离机制、用户画像独立 user 消息包裹、原位 supersede 与事实层打分检索定案 |
| **共享记忆系统构想 [已废弃 / 已被取代]** | [`memory-system-plan-2026-07-31.md`](memory-system-plan-2026-07-31.md) | 2026-07-31 | 📦 **归档 / 已废弃方案** | 早期三层共享记忆构想原案（已被 08-08 独立库架构完全取代） |
| **探索页与 Thoughter 联动改造交接 [已归档]** | [`explore-thoughter-handoff-2026-07-31.md`](explore-thoughter-handoff-2026-07-31.md) | 2026-07-31 | 📦 **归档 / 阶段交接** | 探索页周期统计聚合与 Thoughter 交互入口改造交接（已完成合入） |
| **编辑器 AI 功能迁移至 Thoughter 方案 [已归档]** | [`editor-ai-to-thoughter-plan.md`](editor-ai-to-thoughter-plan.md) | 2026-07-29 | 📦 **归档 / 已完成方案** | 编辑器独立 AI 功能全量统一跳转 Thoughter 实施方案（6 项改造已全量落地） |
| **Agent 模式参考与调研** | [`agent-reference-patterns-2026-07.md`](agent-reference-patterns-2026-07.md) | 2026-07-27 | 🔍 调研参考 | 多智能体上下文管理、ReAct 工具链与流式生成模式调研 |
| **Thoughter Agent 问题探查报告 [已归档]** | [`thoughter-agent-issues-report-2026-07-26.md`](thoughter-agent-issues-report-2026-07-26.md) | 2026-07-26 | 📦 **归档 / 问题核销** | 早期 Agent 循环、卡片协议与错误恢复探查（32 项中 31 项已闭环，1 项 Thinking 待办） |
| **Thoughter Agent 工作交接 [已归档]** | [`agent-handoff-2026-07-31.md`](agent-handoff-2026-07-31.md) | 2026-07-31 | 📦 阶段交接 | Thoughter 会话上下文流转、工具链调度与测试密钥配置交接 |

---

## 五、同步、网络与核心架构

关于 WebDAV、LocalSend 局域网同步、数据库架构、专项实现方案与产品路线演进：

### 5.1 核心架构与审计报告

| 文档名称 | 路径 | 日期 | 状态 | 核心内容 / 结论 |
|---|---|---|:---:|---|
| **全代码库深度审计与问题分析报告** | [`codebase-comprehensive-audit-2026-08-28.md`](codebase-comprehensive-audit-2026-08-28.md) | 2026-08-28 | 🟢 **最新事实源** | 全库安全、数据一致性、生命周期/内存泄露、UI主题令牌与代码风格全维度审计与整改路线图 |
| **研发知识库全景审计与全维度存活待办报告** | [`codebase-roadmap-and-issues-2026-08-28.md`](codebase-roadmap-and-issues-2026-08-28.md) | 2026-08-28 | 🟢 事实源 | 全库 76 篇文档全景分类、隐私审计、历史 31 项核销证据、4 大 ADR 与 16 项存活待办路线图 |
| **代码库架构深化与待办核销审计报告** | [`codebase-architecture-and-tasks-audit-2026-08-23.md`](codebase-architecture-and-tasks-audit-2026-08-23.md) | 2026-08-23 | 🟢 事实源 | 模块解耦、大文件与复杂文件监控、依赖反转钩子解耦与技术债核销总清单 |
| **WebDAV、LocalSend 与备份模块审计重构报告** | [`WebDAV_LocalSend_Backup_Code_Audit_and_Refactoring_Report.md`](WebDAV_LocalSend_Backup_Code_Audit_and_Refactoring_Report.md) | 2026-07-25 | 🟢 事实源 | ETag 并发控制、If-Match 安全锁、凭据加密存储、Zip Slip 防御与 SQLite 读快照重构报告 |
| **早期代码库深度架构与质量审计报告 [已归档]** | [`architecture-audit-2026-07-26.md`](architecture-audit-2026-07-26.md) | 2026-07-26 | 📦 历史参考 | 早期分层结构、代码异味与服务层解耦审计（P0/P1 已全量清零） |
| **增长与产品路线规划** | [`growth-and-product-direction-2026-07-26.md`](growth-and-product-direction-2026-07-26.md) | 2026-07-26 | 🟢 参考 | 产品定位、用户增长策略、跨平台分发与核心功能路线 |

### 5.2 专项设计与实现方案 (docs/plans/ 7 篇)

| 文档名称 | 路径 | 日期 | 状态 | 核心内容 / 结论 |
|---|---|---|:---:|---|
| **AI助手对话历史搜索高亮设计方案 [已实现]** | [`plans/2026-07-10-chat-history-search-highlight.md`](plans/2026-07-10-chat-history-search-highlight.md) | 2026-07-10 | 📦 已完成方案 | 对话历史搜索多关键字高亮匹配与展示方案（已在 `session_history_page_content.dart` 落地） |
| **LocalSend 同步生命周期控制实施计划 [已实现]** | [`plans/2026-07-10-localsend-sync-lifecycle.md`](plans/2026-07-10-localsend-sync-lifecycle.md) | 2026-07-10 | 📦 已完成方案 | 严格审批门禁、级联取消传播、动态端口广播与 PopScope 拦截生命周期方案 |
| **AI 智能结果卡片交互优化实施计划 [已实现]** | [`plans/2026-07-10-smart-result-card-ux.md`](plans/2026-07-10-smart-result-card-ux.md) | 2026-07-10 | 📦 已完成方案 | 卡片三态元数据裁决、单状态指示与去内联编辑（已统一演进为 `NoteProposalCard`） |
| **Agent 原生富文本结构化编辑实施计划 [已实现]** | [`plans/2026-07-11-agent-rich-edit.md`](plans/2026-07-11-agent-rich-edit.md) | 2026-07-11 | 📦 已完成方案 | 基于 Quill Delta 结构化操作、SHA-256 冲突检测与零 Markdown 损耗编辑方案 |
| **LocalSend 增量媒体同步设计 [已实现]** | [`plans/2026-07-11-localsend-incremental-media-design.md`](plans/2026-07-11-localsend-incremental-media-design.md) | 2026-07-11 | 📦 已完成方案 | 仅传输缺失/大小变动的增量媒体清单设计与向前兼容方案 |
| **LocalSend 增量媒体同步实现计划 [已实现]** | [`plans/2026-07-11-localsend-incremental-media.md`](plans/2026-07-11-localsend-incremental-media.md) | 2026-07-11 | 📦 已完成方案 | 增量媒体同步逐步实施清单与任务分解 |
| **列表折叠态 Quill 可见前缀提取方案 [已实现]** | [`plans/2026-07-12-note-list-visible-quill-prefix.md`](plans/2026-07-12-note-list-visible-quill-prefix.md) | 2026-07-12 | 📦 已完成方案 | 宽度感知最小 Delta 前缀截取与 96px 安全余量实施计划 |

---

## 六、架构决策总账与 AI 团队资产

### 6.1 架构决策总账 (ADR)

| 文件名称 | 路径 | 核心作用 |
|---|---|---|
| **架构决策总账 (ADR)** | [`decisions.md`](decisions.md) | 🔒 **团队所有重大架构决议（ADR）权威真源**，完整记录 29+ 项决策的背景、选型、详细实施、生效事实源及已推翻历史决策总账 |

### 6.2 团队协作规程、路由与过程配置 (7 篇)

| 文件名称 | 路径 | 类型 | 核心作用 |
|---|---|:---:|---|
| **团队花名册与分工** | [`squad/team.md`](squad/team.md) | 🟢 活跃 | 11 个智能体角色定义、职责边界、模型偏好与指令总览 |
| **协作信号与路由表** | [`squad/routing.md`](squad/routing.md) | 🟢 活跃 | 任务信号到对应 Agent 的自动路由、流转与跨角色审核规则 |
| **协作仪式配置** | [`squad/ceremonies.md`](squad/ceremonies.md) | 🟢 活跃 | 设计评审、发版检查、回顾会等团队协作仪式触发与执行规则 |
| **智能体花名注册表** | [`squad/casting/registry.json`](squad/casting/registry.json) | 📦 过程配置 | 团队各角色代号、花名、职责与状态注册配置数据 |
| **角色分派策略配置** | [`squad/casting/policy.json`](squad/casting/policy.json) | 📦 过程配置 | 团队角色分派规则、模型分派策略与权限控制配置 |
| **角色分派历史记录** | [`squad/casting/history.json`](squad/casting/history.json) | 📦 过程数据 | 历史任务分派追踪与角色执行记录数据 |
| **列表语义裁剪性能修复日志 [已归档]** | [`squad/log/2026-05-31-note-list-semantics-trimming.md`](squad/log/2026-05-31-note-list-semantics-trimming.md) | 📦 历史日志 | 2026-05-31 列表无障碍语义树裁剪性能优化现场排查与实测日志 |

### 6.3 团队智能体章程与会话演进历史 (docs/squad/agents/ 21 篇)

| 智能体角色 | 角色定位 / 职责 | 角色章程 (Charter) | 演进历史 (History) |
|---|---|:---:|:---:|
| **AUTO** | 技术主管 (Tech Lead / Architecture) | [`squad/agents/auto/charter.md`](squad/agents/auto/charter.md) | [`squad/agents/auto/history.md`](squad/agents/auto/history.md) |
| **BURN-E** | 市场营销与增长 (Marketing & Growth) | [`squad/agents/burn-e/charter.md`](squad/agents/burn-e/charter.md) | [`squad/agents/burn-e/history.md`](squad/agents/burn-e/history.md) |
| **EVE** | UI / UX 设计专家 (Design Lead) | [`squad/agents/eve/charter.md`](squad/agents/eve/charter.md) | [`squad/agents/eve/history.md`](squad/agents/eve/history.md) |
| **GO-4** | 代码审查与规范 (Code Reviewer) | [`squad/agents/go-4/charter.md`](squad/agents/go-4/charter.md) | [`squad/agents/go-4/history.md`](squad/agents/go-4/history.md) |
| **GOPHER** | 产品经理 (Product Manager) | [`squad/agents/gopher/charter.md`](squad/agents/gopher/charter.md) | [`squad/agents/gopher/history.md`](squad/agents/gopher/history.md) |
| **HAN-S** | 内容策划与本地化 (Content & Localization) | [`squad/agents/han-s/charter.md`](squad/agents/han-s/charter.md) | [`squad/agents/han-s/history.md`](squad/agents/han-s/history.md) |
| **M-O** | 质量保证与测试 (QA Tester) | [`squad/agents/m-o/charter.md`](squad/agents/m-o/charter.md) | [`squad/agents/m-o/history.md`](squad/agents/m-o/history.md) |
| **PR-T** | 商店发布与运营 (Store Manager) | [`squad/agents/pr-t/charter.md`](squad/agents/pr-t/charter.md) | [`squad/agents/pr-t/history.md`](squad/agents/pr-t/history.md) |
| **Scribe** | 记录员与文档维护 (Logger & Docs) | [`squad/agents/scribe/charter.md`](squad/agents/scribe/charter.md) | — |
| **VN-GO** | 用户体验研究员 (User Researcher) | [`squad/agents/vn-go/charter.md`](squad/agents/vn-go/charter.md) | [`squad/agents/vn-go/history.md`](squad/agents/vn-go/history.md) |
| **WALL·E** | 产品顾问 (Product Advisor) | [`squad/agents/wall-e/charter.md`](squad/agents/wall-e/charter.md) | [`squad/agents/wall-e/history.md`](squad/agents/wall-e/history.md) |

---

## 七、新增文档命名与归档规范

为了保持知识库的清晰与可检索性，后续新增文档请遵守以下规范：

### 1. 命名格式
`docs/<topic>-<type>-YYYY-MM-DD.md`

- `<topic>`：模块或主题（如 `note-list`, `theme`, `thoughter`, `sync`, `database`）
- `<type>`：文档类型：
  - `audit`（代码或架构审计）
  - `perf` / `analysis`（性能排查与数据分析）
  - `plan`（方案规划与设计原案，复杂子计划放入 `docs/plans/`）
  - `handoff`（跨会话/阶段性技术交接）
  - `research`（技术调研与架构对比）
- `YYYY-MM-DD`：创建日期

### 2. 状态标签定义
- 🔒 **唯一事实源**：已结案并形成权威约束的最终设计文档（修改前必须通读）。
- 🟢 **活跃 / 事实源**：当前正在生效的最新规范或设计。
- 📦 **归档 / 过程记录**：历史方案、中间推导或单轮冲刺记录，仅用于追溯决策原因（需带标准归档警示块）。
- 🔍 **调研 / 分析**：性能数据评测与技术选型分析。

### 3. 闭环流转
新增技术文档后，请使用 `project-docs-manager` 技能自动在本文档中登记，并将关键决策点提炼追加至 [`docs/decisions.md`](decisions.md)。
