# ThoughtEcho v4.1.5 · 轻量动效与底层打底更新 / Release Notes

> [!NOTE]
> ### 🚀 ThoughtEcho v4.1.5 版本发布
> 本次是一次侧重底层升级与日常流畅度的常规维护版本：我们完成了核心配置与草稿数据的存储结构升级，用按主题实时绘制的自绘动画替换了原有的固定贴图加载动画，并集中优化了笔记列表滑动、Windows 桌面端交互与同步性能。
>
> 📖 **用户指南**: https://note.shangjinyun.cn/user-guide.html  
> 💡 **Thoughter 专属介绍**: https://note.shangjinyun.cn/thoughter/  
> 🌐 **官方网站**: https://note.shangjinyun.cn/

> [English Version](#english-version)

---

## 🙋 用户篇：平稳过渡与细节打磨

> 💡 **升级建议**：**建议正在使用旧版本的用户及时更新至 v4.1.5。** 这次更新完成了应用配置、编辑草稿与洞察历史等数据的存储架构整理，现在升级可以让你的设置、草稿与使用记录平稳衔接到后续的新版本与新特性中。

本次更新没有堆砌大型新功能，主要把精力放在了视觉细节、滑动手感和底层流畅度上：

### 🎨 自绘加载与空状态动效
- **告别固定贴图，跟随你的纸墨与墨色**：
  - 将原本的静态素材动画全面替换为代码实时绘制的自绘动画，包括翻书等待、毛笔落笔、墨滴涟漪以及搜索无结果时的放大镜寻字画面。
  - 所有动画都会直接读取你当前选用的主题色板，无论切换浅色、深色，还是「纸与墨」「素笺」与四款墨色，都能自然融入画面。
  - 若系统开启了「减少动态效果」，动画会自动停留在安静的静止帧上，不打扰阅读。

### ⚡ 滑动手感与桌面体验
- **长列表滚动更轻快**：
  - 梳理了首页与笔记列表的绘制层级和局部刷新范围，减少快速滑动、搜索筛选以及展示流式思考卡片时的偶发掉帧。
- **Windows 桌面端交互完善**：
  - 在设置页、笔记列表与对话历史等长页面恢复了桌面端原生滚动条，并支持鼠标拖拽滚动，移动端继续保持清爽的无滚动条滑动。
- **小细节更顺手**：
  - 「探索」页现在会记住你上次选择的时间周期（周 / 月 / 年），下次打开直接延续查看。
  - 筛选标签加入轻柔的按压缩放与触觉反馈；「今日思考」卡片文字流式输出时过渡更平稳。
  - 「地图回忆」支持深色模式下的暗色底图与更平顺的瓦片渐显过渡。

### 🌐 多语言与提示文案
- **繁体中文与多语言补齐**：
  - 补全了繁体中文（`zh_Hant`）词条，并补齐了日语、韩语、法语共 129 条界面文案。
- **更直观的界面提示**：
  - 优化了存储管理、紧急恢复与语音转文字等页面的说明文案，去掉生涩技术词汇；关闭隐藏笔记保护前现在会要求通过生物识别验证。

---

## 💻 开发者篇：存储迁移、同步管道与渲染优化

> 📑 **研发知识库与全量技术文档索引**：[`docs/INDEX.md`](INDEX.md)

### 🗄️ 存储架构现代化（Phase 1 & Phase 2）
- **配置存储迁移与诊断（`#901`, `#909`）**：
  - 完成 Phase 1 主配置从 MMKV 向 `SharedPreferences` 热缓存的平滑迁移，新增纯 Dart 二进制解析工具 `MmkvBinaryReader` 与异常恢复修复逻辑，并在实验室设置中提供可本地化的迁移诊断页（`MmkvMigrationDiagnosticPage`）。
- **统一偏好门面与业务数据落库（`#915`）**：
  - 完成 Phase 2：引入统一的 `AppPreferencesService` 门面解耦各业务服务对底层 KV 引擎的直接调用，并将编辑草稿（`DraftService`）与周期洞察历史（`InsightHistoryService` / `PeriodicInsight`）完整迁移至 SQLite（`AIAnalysisDatabaseService`），同时为日志级别持久化加入事务性回滚校验。

### 🔄 WebDAV 媒体同步与 Isolate 并发安全
- **倒排索引与有界并发下载池（`#923`）**：
  - 在 `MediaReferenceService` 与 `WebDavSyncService` 中引入全量笔记媒体引用倒排索引预加载和 `BoundedExecutor` 有界并发下载池，消除同步扫描阶段的性能瓶颈。
  - 远端媒体拉取改为先写入 `.tmp` 临时文件并执行 SHA-256 / MD5 哈希校验，验证通过后再原子重命名落盘，杜绝中断产生半截损坏文件。
- **批量引用与 Isolate 边界修复（`#911`, `#916`）**：
  - 优化全量迁移时的媒体引用批量同步，校验笔记存活性并消除 N+1 查询与写锁竞争。
  - 修复 `NoteSyncService` 中 `Isolate.run` 隐式捕获服务实例导致的跨 isolate 发送失败问题；重构 `WebDAV` 响应有界 XML 解析（`#844`）、后台 ZIP 解压（`#847`）及 `webdav_sync_tmp` 隔离工作目录（`#857`）。

### ⚡ 列表渲染流水线与内存减负
- **列表重建拦截与局部隔离（`#922`, `#919`, `#920`, `#921`, `#917`）**：
  - 将笔记列表核心切换为 `ListView.custom`，配合外置 `SliverChildBuilderDelegate` 与 `shouldRebuild` 拦截阻断无关子项重建，移除 `NoteListView` 中冗余 `LayoutBuilder`。
  - 在 `ExploreOverview`、加载指示器、音视频嵌入组件、`AnimatedFilterChip` 及卡片预览中精细部署 `RepaintBoundary` 与 `Selector`，并持久化行键索引缓存（`#894`）、消除 `Quote.hasSameContentAs` 的 `toJson` Map 分配（`#899`）、将实况照片检测下沉至 `compute` 后台 Isolate（`#895`）。
- **彻底移除 Lottie 依赖（`#925`, `7f10e223`）**：
  - 基于 `CustomPainter` 实现主题感知的 `AppLoadingAnimation` 与 `AppEmptyAnimation`，移除 `lottie` 第三方包、`assets/lottie/` 静态资源及旧版封装代码（净删减 2,000+ 行）。

### 🔒 安全脱敏、Android 合规与测试覆盖
- **全链路异常脱敏（`#903`, `#906`）**：
  - 抽取公共 `SanitizationUtils`，统一 `SentryHelper` 与 `AppTracer` 的正则清洗规则，覆盖 HTTP `Bearer`/`Basic` 凭证、API Key、绝对路径、引用 JSON 字段与 `Hint`/`extra`/`contexts` 递归过滤。
- **数据边界与存储安全（`#811`–`#848`）**：
  - 加固 `ALTER TABLE` DDL 标识符校验、ZIP 解压路径穿越与软链接拦截、备份还原时跨 Origin API Key 隔离、隐藏笔记鉴权以及 `ZipStreamProcessor` 文件句柄 `try-finally` 释放。
- **Android API 36 与 Google Play 多渠道隔离（`#908`, `331a6eb1`）**：
  - 将 Android `targetSdkVersion` 升级至 36，清理未使用的前台服务声明，新增 `DistributionConfig` 与 `play` flavor 隔离逻辑以符合商店分发合规要求，并解耦原生多语言清单（`#881`）。
- **自动化测试扩展**：
  - 新增并扩充了存储迁移、二进制解析、同步流水线、异常脱敏、自绘动效及多渠道配置等大量单元与组件测试，目前全仓测试文件已达 429 个。

---

<a id="english-version"></a>

## 🌐 English Version

### 🚀 ThoughtEcho v4.1.5 Release Notes · Lightweight Animations & Foundational Storage Upgrade

ThoughtEcho v4.1.5 is a focused maintenance and foundational release. It upgrades how app preferences and drafts are stored, replaces static animation assets with custom theme-drawn animations, and refines scrolling smoothness, Windows desktop ergonomics, and sync reliability.

---

### 🙋 For Users: Smooth Upgrade & Everyday Polish

> 💡 **Update Recommendation**: **We encourage all existing users to update to v4.1.5 promptly.** This release brings an important foundational upgrade to how ThoughtEcho stores preferences, drafts, and insight history, ensuring your settings and records carry forward smoothly into upcoming releases.

While this update does not introduce major headline features, it brings noticeable polish across visuals, scrolling, and daily use:

#### 🎨 Custom Theme-Drawn Animations
- **Native animations that match your paper and ink**:
  - Replaced legacy static animation assets with custom-drawn animations for loading and empty search states, including page-flipping, brush writing, ink-drop ripples, and a magnifying glass scanning blank ruled paper.
  - Every animation reads directly from your active color scheme, adapting seamlessly to Light, Dark, Paper & Ink, Plain, and all four ink palettes.
  - When system Reduced Motion is enabled, animations stay cleanly on a calm resting frame.

#### ⚡ Smoother Scrolling & Desktop Experience
- **Less stutter on long lists**:
  - Refined list rendering boundaries and selective state updates so scrolling, searching, filtering, and streaming AI cards feel steadier.
- **Better Windows desktop navigation**:
  - Restored native desktop scrollbars and mouse-drag scrolling on long views such as settings, note lists, and chat history, while keeping mobile scrolling clean and uncluttered.
- **Thoughtful refinements**:
  - The Explore tab now remembers your selected period (week, month, or year) between visits.
  - Filter chips respond with subtle press scaling and haptic feedback, and the Daily Prompt card transitions more smoothly while streaming.
  - Map Memories now adapts its map tiles to dark mode with smoother fade-in transitions.

#### 🌐 Localization & Clearer Prompts
- **Expanded language support**:
  - Completed Traditional Chinese (`zh_Hant`) translations and filled 129 missing entries across Japanese, Korean, and French.
- **Clearer wording and privacy locks**:
  - Rewrote storage management and emergency recovery messages in plain language, and added biometric verification before disabling hidden-note protection.

---

### 💻 For Developers: Storage Migration, Sync Pipeline & Rendering

> 📑 **Documentation Index & Technical Specifications**: [`docs/INDEX.md`](INDEX.md)

#### 🗄️ Storage Modernization (Phase 1 & Phase 2)
- **Preference Migration & Diagnostics (`#901`, `#909`)**:
  - Completed Phase 1 migration from MMKV to a `SharedPreferences` hot cache, backed by a pure-Dart `MmkvBinaryReader` and a localized `MmkvMigrationDiagnosticPage`.
- **Unified Facade & SQLite Migration (`#915`)**:
  - Completed Phase 2 by introducing `AppPreferencesService` to decouple callers from direct KV storage, migrating drafts (`DraftService`) and periodic insight history (`InsightHistoryService`, `PeriodicInsight`) into SQLite (`AIAnalysisDatabaseService`) with transactional rollback checks for log-level persistence.

#### 🔄 WebDAV Sync Pipeline & Isolate Safety
- **Inverted Reference Index & Bounded Download Pool (`#923`)**:
  - Preloads a full media reference inverted index in `MediaReferenceService` and downloads media through `BoundedExecutor` in `WebDavSyncService`.
  - Streams downloads to `.tmp` files and verifies SHA-256 or MD5 digests before atomically renaming into place.
- **Batch Reference Sync & Isolate Fixes (`#911`, `#916`)**:
  - Eliminated N+1 queries and write-lock contention during bulk media reference synchronization.
  - Fixed `Isolate.run` implicit service capture in `NoteSyncService`, bounded WebDAV XML parsing (`#844`), offloaded ZIP expansion off the UI isolate (`#847`), and isolated sync temp files in `webdav_sync_tmp` (`#857`).

#### ⚡ List Rendering & Dependency Cleanup
- **Rebuilds & Repaints Isolated (`#922`, `#919`, `#920`, `#921`, `#917`)**:
  - Migrated the note list core to `ListView.custom` with externalized `SliverChildBuilderDelegate` and `shouldRebuild` gating, removed redundant `LayoutBuilder` wrappers, added `RepaintBoundary` and `Selector` guards, persisted row-key index caches (`#894`), removed `toJson` map allocations in `Quote.hasSameContentAs` (`#899`), and moved motion-photo detection into `compute` isolates (`#895`).
- **Lottie Dependency Removed (`#925`, `7f10e223`)**:
  - Replaced all Lottie animations with `CustomPainter`-based `AppLoadingAnimation` and `AppEmptyAnimation`, removing the `lottie` package, `assets/lottie/`, and over 2,000 lines of legacy wrapper code.

#### 🔒 Sanitization, Android API 36 & Test Coverage
- **Unified Exception Sanitization (`#903`, `#906`)**:
  - Extracted shared `SanitizationUtils` used by both `SentryHelper` and `AppTracer` to scrub Bearer/Basic headers, API keys, file paths, quoted JSON credentials, and `Hint`/`extra`/`contexts` payloads.
- **Security & Boundary Hardening (`#811`–`#848`)**:
  - Validated `ALTER TABLE` DDL identifiers, blocked ZIP path traversal and symlinks, isolated imported API keys across origins, enforced hidden-note visibility guards, and ensured `try-finally` handle cleanup in `ZipStreamProcessor`.
- **Android API 36 & Google Play Flavor (`#908`, `331a6eb1`)**:
  - Raised Android `targetSdkVersion` to 36, stripped unused foreground service declarations, and added `DistributionConfig` with a dedicated `play` flavor and decoupled native metadata localization (`#881`).
- **Testing**:
  - Expanded unit and widget test coverage across storage migration, binary parsing, WebDAV sync pipelines, sanitization, self-drawn animations, and distribution configuration (429 `*_test.dart` files total).

---

**Full Changelog**: `4.1.0...4.1.5`
