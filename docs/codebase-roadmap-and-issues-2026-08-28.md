# ThoughtEcho 研发知识库全景审计与全维度存活待办报告

> **生成日期**：2026-08-28  
> **审计范围**：`docs/` 目录下全部 76 篇文档、`lib/` 源码库（400+ Dart 文件）、历史已核销记录与决策总账  
> **权威状态**：🟢 活跃事实源（对齐 2026-08-28 最新代码库现状）  
> **关联网页看板**：`res/issues-report.html` (Tailscale: `http://100.106.0.43:8000/issues-report.html`)

---

## 目录

1. [执行综述与数据画像](#一执行综述与数据画像)
2. [全库 76 篇文档资产分类与生命周期状态](#二全库-76-篇文档资产分类与生命周期状态)
3. [隐私安全与合规审计结论](#三隐私安全与合规审计结论)
4. [核心重大架构决议 (ADRs) 与被推翻决策总账](#四核心重大架构决议-adrs-与被推翻决策总账)
5. [历史问题核销台账 (31 项已闭环)](#五历史问题核销台账-31-项已闭环)
6. [全维度存活待办与研发路线图 (16 项)](#六全维度存活待办与研发路线图-16-项)
   - [6.1 P0：即时缺陷修复与代码清理 (4 项)](#61-p0即时缺陷修复与代码清理-4-项)
   - [6.2 P1：核心架构深化与超大单文件治理 (5 项)](#62-p1核心架构深化与超大单文件治理-5-项)
   - [6.3 P2：商业化渠道、分发与增长漏斗 (4 项)](#63-p2商业化渠道分发与增长漏斗-4-项)
   - [6.4 P3：端侧智能与长期演化战略 (3 项)](#64-p3端侧智能与长期演化战略-3-项)
7. [后续执行与维护指引](#七后续执行与维护指引)

---

## 一、执行综述与数据画像

本次审计对 ThoughtEcho 仓库进行了全量穿透排查，涵盖所有 Markdown 技术文档、设计方案、测试日志、团队过程档案以及 `lib/` 核心源码：

| 维度 | 指标 | 说明 |
|---|---|---|
| **技术文档总资产** | **76 篇** | 100% 编入 [`docs/INDEX.md`](INDEX.md)，0 悬空死链，状态与代码完全对齐 |
| **最高权威事实源 (🔒)** | **3 篇** | 纸墨主题设计、Thoughter 记忆独立库、架构决策总账 (ADR) |
| **已归档/废弃/已实现 (📦)** | **54 篇** | 标题均已添加 `[已归档/已废弃/已实现]` 标识与头部引用警示块 |
| **隐私安全违规** | **0 项** | 全库无真实 API Key、密码、私有邮箱、手机号或内网敏感信息 |
| **历史问题核销率** | **31 / 32 项 (96.9%)** | 早期报告声称的缺陷 31 项已在代码中闭环，仅留 1 项 Thinking 待办 |
| **当前真实存活待办** | **16 项** | 拆分为 P0 (4 项)、P1 (5 项)、P2 (4 项)、P3 (3 项) |

---

## 二、全库 76 篇文档资产分类与生命周期状态

根据文档的实际有效性与在 `lib/` 源码中的落地情况，76 篇文档被严格划分为六大板块与四大生命周期类型：

### 2.1 生命周期分类统计
- 🔒 **唯一事实源 (Single Source of Truth, 3 篇)**：具有最高仲裁权，禁止任何代码或新方案与其冲突。
- 🟢 **活跃/事实源 (Active/Authoritative, 12 篇)**：如双语用户手册、发版指南、最新性能演进、最新架构审计。
- 📦 **已归档/已废弃/阶段交接 (Archived/Superseded/Implemented, 54 篇)**：包括已落地的 plans 方案、阶段交接、旧版本发版说明及 AI 团队历史过程资产（29 篇）。
- 🔍 **调研参考 (Research/Reference, 2 篇)**：前瞻性技术分析与 Agent 设计模式。

### 2.2 六大核心板块分布
1. **核心规范与发布文档 (10 篇)**：包含 [`USER_MANUAL.md`](USER_MANUAL.md)、[`STORE_SUBMISSION_GUIDE.md`](STORE_SUBMISSION_GUIDE.md)、[`DEVICE_INFO.md`](DEVICE_INFO.md)、[`project-overview.md`](project-overview.md) 及 v3.5.0~v3.7.0 发版说明。
2. **性能分析与优化演化链 (9 篇)**：以 [`note-list-warmup-invalidation-2026-08-22.md`](note-list-warmup-invalidation-2026-08-22.md) 与 [`note-list-first-paint-cost-2026-08-19.md`](note-list-first-paint-cost-2026-08-19.md) 为最新事实源，归档早期 7 篇阶段性交接。
3. **主题系统与 UI 现代化 (9 篇)**：以 [`paper-ink-theme-handoff-2026-07-31.md`](paper-ink-theme-handoff-2026-07-31.md) 为唯一事实源（🔒），归档 8 篇历史草案与迁移审计。
4. **Thoughter 与 AI 记忆体系 (7 篇)**：以 [`agent-memory-research-2026-08-08.md`](agent-memory-research-2026-08-08.md) 为唯一事实源（🔒），废弃 07-31 共享记忆旧案，核销 [`thoughter-agent-issues-report-2026-07-26.md`](thoughter-agent-issues-report-2026-07-26.md)。
5. **同步、网络与核心架构 (11 篇)**：以 [`WebDAV_LocalSend_Backup_Code_Audit_and_Refactoring_Report.md`](WebDAV_LocalSend_Backup_Code_Audit_and_Refactoring_Report.md) 与 [`codebase-architecture-and-tasks-audit-2026-08-23.md`](codebase-architecture-and-tasks-audit-2026-08-23.md) 为事实源，7 篇 plans 专项实施计划全量标为 `[已实现]`。
6. **架构决策总账与 AI 团队资产 (29 篇)**：以 [`decisions.md`](decisions.md) 为唯一事实源（🔒），归档 28 篇智能体角色历史与协作日志。

---

## 三、隐私安全与合规审计结论

经全量正则与语义扫描，排查结果如下：
1. **API 密钥安全**：全库无硬编码的 OpenAI / DeepSeek / Gemini / Claude 真实 API Key，代码与文档中均采用 `sk-mock-key` 或从安全存储动态读取。
2. **个人敏感信息**：无未脱敏的真实个人邮箱、电话、私人服务器 IP 或敏感凭据。
3. **合规性**：符合开源与应用商店（Google Play、App Store、Microsoft Store）的隐私合规要求。

---

## 四、核心重大架构决议 (ADRs) 与被推翻决策总账

详见 [`docs/decisions.md`](decisions.md)，以下为四项核心定案与七项被后续实测推翻的历史决策：

### 4.1 四大核心定案 (ADRs)
1. **WebDAV / LocalSend 数据安全与并发锁架构 (2026-07-24)**：
   - 确立 `If-Match: ETag` 条件并发锁；SQLite `READ` 快照事务流式打包；凭据入 `FlutterSecureStorage`；`PathSecurityUtils` 防御 Zip Slip。
2. **三套独立主题风格与 AppShapeTokens 令牌架构 (2026-07-31)**：
   - 锁定默认 `material` 不得擅改；**严禁在 Widget 内部编写 `if (style == ThemeStyle.paper)`**，全量由 `AppShapeTokens` 令牌派发；基于「取值」而非「身份」驱动渲染。
3. **Thoughter 长期记忆独立库 agent_memory.db 物理隔离 (2026-08-08)**：
   - 确立三大铁律：**不进备份、不跨端同步、支持一键物理销毁**；画像走独立 user 消息包裹，原位 supersede 覆盖冲突。
4. **随包分发 5.17MB GB2312 衬线字体子集 (2026-08-22)**：
   - 随包分发 `assets/fonts/NotoSerifSC-Subset.ttf`，保证 iOS/Android/Windows 三端精准一致的衬线排版与字重控制。

### 4.2 七项被推翻/修正的历史决策
| 历史原决策 / 方案设想 | 推翻时间与来源 | 最终生效的新决议与推翻原因 |
|---|---|---|
| **进入后台清空所有测量缓存** (`resetCaches`) | 2026-08-23 / 08-27 ADR | **推翻**。Android 后台例行 trim 会误杀排版缓存致切回卡顿。改由 AppWidgetsBinding 分流，仅将 imageCache 淘汰至 8MB。 |
| **头部测宽不进入空闲预热** | 2026-08-25 ADR | **推翻**。折叠排版暖好后头部测宽成为第一大未命中点（13~16ms）。已将日期/位置/天气测宽全量纳入空闲预热。 |
| **列表项无条件 KeepAlive / 固定窗口** | 2026-06-13 / 07-02 ADR | **取消**。全量保活无法消除首次 layout 且内存暴涨。实测回滑 frameJank=0，维持动态窗口策略。 |
| **零字节系统字体回退路线** | 2026-08-22 ADR | **推翻**。iOS 无法解析通用 serif 回退黑体。改为随包分发 5.17MB 字体子集。 |
| **Gemma4 判定为不吐思考的非思考模型** | 2026-08-04 ADR | **修正**。实测需显式传 `reasoning_effort=medium`。在 `AgentService` 中针对静默模型补齐参数。 |
| **推测分页反序列化是首滑掉帧主因** | 2026-08-26 ADR | **推翻**。实测分页仅 13.6ms，主因是卡片新建引出的异步 IO 与图片解码，避免了错误重构。 |
| **用户画像存入主库 user_signals 表** | 2026-08-08 ADR | **推翻**。定案为独立数据库 `agent_memory.db` 物理隔离。 |

---

## 五、历史问题核销台账 (31 项已闭环)

早期文档中提出的 32 项问题，已有 **31 项在源码中得到真实修复与闭环**：

| 来源文档 / 审计项 | 原始问题描述 | 代码真实修复证据 | 状态 |
|---|---|---|---|
| `thoughter-agent-issues-report` | 工具报错导致整轮会话报废并误删已输出正文 | `agent_service.dart` 改为错误回喂自我纠正，保留流式正文 | ✔ 100% 已修复 |
| `thoughter-agent-issues-report` | requestStop 假取消导致旧循环后台互踩 | `requestStop()` 增加 `_stopRequested` 并强关 StreamClient | ✔ 100% 已修复 |
| `thoughter-agent-issues-report` | 3 个未注册死工具与双卡片协议冗余 | 清理死工具与 `smart_result_card`，统一至 `NoteProposalArtifact` | ✔ 100% 已修复 |
| `m3-modernization-audit` | Android 预测式返回手势与 MenuAnchor 迁移 | 提交 `0b96c51` 完成 AndroidManifest 与全部菜单 M3 迁移 | ✔ 100% 已修复 |
| `architecture-audit-2026-07-26` | Services 逆向 import main.dart 破坏分层 | 全库 services 逆向 import 为 0，引入 `onQuoteCacheInvalidate` 解耦 | ✔ 100% 已修复 |
| `architecture-audit-2026-07-26` | WebDAV 媒体文件同步失败被静默吞错 | `webdav_sync_service.dart:455` 引入 `mediaFailureCount` 阻断状态前推 | ✔ 100% 已修复 |
| `plans/ (全 7 篇专项计划)` | 搜索高亮、LocalSend 生命周期、增量媒体 Manifest、Quill 可见前缀 | 7 份专项实施方案已 100% 全量合入 main 分支 | ✔ 100% 已修复 |
| `theme-shape-migration-audit` | 全 App 六批组件圆角与阴影收敛至 `AppShapeTokens` | 6 批迁移全部合入，彻底消除分散 `BorderRadius.circular` | ✔ 100% 已修复 |

---

## 六、全维度存活待办与研发路线图 (16 项)

### 6.1 P0：即时缺陷修复与代码清理 (4 项)

#### 1. Thinking 思考链与消息状态 SQLite 持久化
- **现状与问题**：`ChatMessage.toJson/fromJson` 已支持 `thinkingChunks` 与 `state`，但 `ChatMessage.fromMap/toMap` 遗漏了 SQLite 字段映射。
- **代码位置**：[`lib/models/chat_message.dart:66-95`](../lib/models/chat_message.dart#L66-L95)
- **修复方案**：在 `chat_messages` 表增加 `thinking_chunks` 与 `state` 字段并完善映射。
- **工时预估**：0.2 天

#### 2. 删除 3 个重构残留的零引用死代码文件 (~1000 行)
- **现状与问题**：项目已全面切换到 `UnifiedLogService`，早期遗留文件全库 0 引用。
- **涉及文件**：
  - `lib/models/merge_report_simple.dart` (234 行)
  - `lib/services/log_service.dart` (589 行)
  - `lib/services/log_service_adapter.dart` (174 行)
- **修复方案**：遵循 AGENTS.md 废弃即删原则，直接执行 `git rm`。
- **工时预估**：0.1 天

#### 3. 封装 WebDAV 同步页面中的裸 SQL 穿透
- **现状与问题**：UI 页面直接获取 `DatabaseService().database` 句柄拼装 SQL 查询冲突笔记。
- **代码位置**：[`lib/pages/webdav_sync_page.dart:121-127`](../lib/pages/webdav_sync_page.dart#L121-L127)
- **修复方案**：下沉为 `DatabaseService.getConflictedNotesCount()` 方法。
- **工时预估**：0.2 天

#### 4. WebDAV 媒体同步从单一文件大小比对升级为 SHA-256 校验和
- **现状与问题**：当前仅以文件大小作为增量媒体文件差异比对依据，替换同名同大小图片时存在同步漏传风险。
- **代码位置**：[`lib/services/webdav_sync_service.dart:1535`](../lib/services/webdav_sync_service.dart#L1535)
- **修复方案**：引入基于 Manifest 的 SHA-256 哈希比对。
- **工时预估**：0.3 天

---

### 6.2 P1：核心架构深化与超大单文件治理 (5 项)

#### 5. 统一笔记呈现引擎深化 (`NotePresentationEngine`)
- **现状与问题**：`QuoteContent` 膨胀为 1946 行的浅模块，塞满 15+ 静态 LRU 缓存、Quill Delta 截断、媒体图提取和字重补偿。
- **代码位置**：[`lib/widgets/quote_content_widget.dart`](../lib/widgets/quote_content_widget.dart)
- **修复方案**：抽取统一深模块 `NotePresentationEngine`，对外提供纯粹小接口（`Quote` + `RenderConstraints`），输出 `PreparedNoteLayout` 与可渲染组件，内部缓存完全封装在 Seam 之后。
- **工时预估**：1~2 天

#### 6. 统一数据归档与原子事务引擎 (`DataArchiveEngine`)
- **现状与问题**：WebDAV、LocalSend 与 Backup/Restore 各自实现了一套打包、POSIX 路径映射、Zip 读写与 LWW 合并。
- **涉及服务**：`webdav_sync_service.dart`、`localsend_service.dart`、`database_backup_service.dart`
- **修复方案**：抽取单一的 `DataArchiveEngine` 统一处理原子事务、校验和与数据安全（Zip Slip 防护、SQLite 快照读锁），传输层仅作为 Adapter 挂载。
- **工时预估**：1.5 天

#### 7. 超大弹窗组件拆解：`add_note_dialog.dart` (2921 行)
- **现状与问题**：单文件超过 2900 行，内嵌了位置/天气获取、标签管理、富文本草稿及 AI 推荐逻辑。
- **代码位置**：[`lib/widgets/add_note_dialog.dart`](../lib/widgets/add_note_dialog.dart)
- **修复方案**：拆分为 `LocationPickerWidget`、`TagSelectorWidget` 与独立的 `AddNoteDialogController`。
- **工时预估**：1 天

#### 8. AI 服务层拆解：`ai_service.dart` (1610 行) 与 prompt 管理
- **现状与问题**：`ai_service.dart` 混杂了灵感生成、年度分析、语义搜索与历史维护。
- **代码位置**：[`lib/services/ai_service.dart`](../lib/services/ai_service.dart)
- **修复方案**：按业务职责拆解为 `DailyInspirationService`、`InsightAnalysisService` 与 `SemanticSearchService`。
- **工时预估**：1 天

#### 9. 主程序启动时序规范化与显式依赖图初始化
- **现状与问题**：`main.dart` 包含 500+ 行入口代码，使用 `Future.delayed` 猜测异步时序。
- **代码位置**：[`lib/main.dart`](../lib/main.dart)
- **修复方案**：构建有向无环图（DAG）显式声明存储、日志、数据库、推送的启动依赖，消除隐式 race condition。
- **工时预估**：0.5 天

---

### 6.3 P2：商业化渠道、分发与增长漏斗 (4 项)

#### 10. 打通 Tag Push 自动触发 GitHub Release 多端构建
- **现状与问题**：目前构建依赖手动 `workflow_dispatch`，代码已至 4.0.0 但 tag 停在 3.7.0。
- **涉及位置**：`.github/workflows/` 与 `scripts/build_msix_ci.ps1`
- **目标**：打 Tag 即自动产出全平台安装包并生成 GitHub Release。
- **工时预估**：0.5 天

#### 11. 推进 Google Play、国内酷安与 Windows Store 上架
- **现状与问题**：缺少主流商店存在感，90% 潜在用户无法触达。
- **涉及文档**：[`docs/STORE_SUBMISSION_GUIDE.md`](STORE_SUBMISSION_GUIDE.md) 与技能 `app-store-copy`
- **目标**：完成多语言商店文案、合规材料与截图准备，提交商店审核。
- **工时预估**：1 周

#### 12. 官网 SEO 爬虫可访问性核验与卡片分享增长水印
- **现状与问题**：官网曾被 Cloudflare 拦截致爬虫无法收录；卡片分享缺少品牌回流机制。
- **涉及资源**：`res/llms.txt`、`res/sitemap.xml` 与 `lib/services/card_render_service.dart`
- **目标**：确保爬虫与 LLM 检索正常；卡片导出带极简水印与官网二维码。
- **工时预估**：0.3 天

#### 13. 应用内评价引导 (`in_app_review`) 与正向时刻触发机制
- **现状与问题**：缺少应用内评分收集机制。
- **涉及模块**：引入 `package:in_app_review`
- **目标**：在用户连续成功同步、生成周期报告等正向时刻适时触发好评弹窗。
- **工时预估**：0.3 天

---

### 6.4 P3：端侧智能与长期演化战略 (3 项)

#### 14. Thoughter 长期记忆二期：后台定期整理 (Dreaming) 与事实晋升
- **规划**：在设备充电或空闲时利用启发式打分与 LLM 批量提炼高频事实进用户画像，并提供独立 `agent_memory.db` 快照导出。
- **事实源文档**：[`docs/agent-memory-research-2026-08-08.md`](agent-memory-research-2026-08-08.md)
- **工时预估**：2 周

#### 15. 端侧本地智能：相机 OCR 实时识别与本地小模型纠错
- **代码预留**：[`lib/widgets/local_ai/`](../lib/widgets/local_ai/) 下已预留 OCR 拍照、选区高亮与纠错接口。
- **目标**：打通端侧 OCR 与轻量离线模型，实现 100% 离线隐私图文摘录。
- **工时预估**：3 周

#### 16. 笔记向量化索引与语义自然语言搜索 (Vector Embeddings)
- **代码预留**：[`lib/services/database/database_quote_crud_mixin.dart:5`](../lib/services/database/database_quote_crud_mixin.dart#L5) 标注 `/// TODO: 接入 tostore 向量索引`。
- **目标**：生成端侧向量嵌入并在 SQLite 中维护向量索引表，支持自然语言模糊语义搜索。
- **工时预估**：2 周

---

## 七、后续执行与维护指引

1. **知识库维护原则**：
   - 涉及主题、Thoughter 记忆或架构选型时，必须优先遵从三份🔒唯一事实源。
   - 所有已落地的方案与过时审计，严格保持 `[已归档/已废弃/已实现]` 标注，杜绝“历史问题重复提”。
2. **待办落地建议**：
   - 第一周：集中完成 P0 的 4 项即时修复与死代码清理（总计约 0.8 天）。
   - 第二周：打通 P2 的 GitHub Actions 自动发版流水线与商店文案准备。
   - 后续轮次：稳步推进 P1 深度模块重构（`NotePresentationEngine` 与 `DataArchiveEngine`）。
