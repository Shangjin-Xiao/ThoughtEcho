# ThoughtEcho v3.7.0 发布说明 / Release Notes

> 📖用户指南/User Guide: https://note.shangjinyun.cn/user-guide.html

> ⚠️ **重要通知**：引入 Sentry 错误追踪服务（**默认关闭**）并同步更新《隐私政策》，强烈建议升级以提升稳定性。
> 
> 🎉 **本次更新修复了较多已知问题并进行了底层架构重构，为下一个大版本的全新 AI 功能做准备，敬请期待！**

> [English Version](#english-version)

---

## 🙋 用户篇：体验优化与新功能

- **更流畅的滑动**：优化了笔记列表的滚动体验，缓解了快速滑动长列表时的卡顿。
- **界面排版修正**：修复了安卓端升级后出现的字体偏粗问题，以及输入法键盘弹出时的画面抖动。
- **智能推送调整**：调整了智能推送算法，使推荐内容和提醒更加准确。
- **WebDAV 同步 (Beta)**：新增 WebDAV 云端同步功能，附带冲突保护与移动网络流量保护开关（响应社区长期呼声 [#270]）。
- **原生 PDF 导出**：支持标准 A4 尺寸富文本 PDF 导出及系统打印预览，改善了中文导出时的乱码现象。
- **无障碍体验 (A11y)**：为诸多无文本交互按钮补充了读屏提示，改进操作体验。
- **已知问题修复**：集中修复了此前版本中影响日常使用的各类 Bug。

---

## 💻 开发者篇：底层重构与安全加固

- **大体量数据流式处理**：重写了备份、导出与 WebDAV 链路，摒弃旧版聚合路径（已标记废弃）。全线转用流式 ZIP 写入与异步流处理（`ZipStreamProcessor` / `StreamFileSelector`），有效避免了处理海量笔记时的 OOM 内存峰值。
- **安全加固 (Security)**：
  - 修补 SQL 注入隐患（修复 `DatabaseSchemaManager` 及移除暴露参数的 `EXPLAIN QUERY PLAN` 调试日志）。
  - 封堵临时目录文件路径可预测（Predictable File Path）的漏洞。
  - 修复 `APIKeyManager` 密钥泄露风险，核心网络请求（APK 检查、WebDAV）强制使用 HTTPS。
- **性能优化 (Performance)**：
  - 针对位置追踪模块，将引发全表扫描的旧逻辑修改为针对性批量 SQL 更新（Batch Update）。
  - 移除 `QuoteItemWidget` 构建期间针对 `TextPainter` 的过早计算，降低长列表帧生成时间。
  - 优化 `getUserQuotes` 的标签条件查询及 SVG 解析中重复的正则编译开销。
- **架构与依赖升级**：
  - Flutter SDK 升级至 3.44.0，启用新渲染引擎，修复内置 Kotlin 及 NDK 兼容性问题。
  - 引入 Sentry SDK 并限制在安全上下文中初始化，加入防性能抖动的 Jank Detector。
  - 清理代码库，移除无用 `ignore` 指令与废弃组件。

---

<h2 id="english-version">English Version</h2>

> ⚠️ **Important Notice**: We have integrated the Sentry error tracking SDK (**disabled by default**) and updated our Privacy Policy. We strongly recommend upgrading for maximum stability.
>
> 🎉 **This update fixes several known issues and refactors the underlying architecture in preparation for new AI features in the next major release. Stay tuned!**

### 🙋 User Section: Experience & New Features

- **Smoother Scrolling**: Optimized the list scrolling rendering, reducing stuttering and jank during fast browsing.
- **UI & Typography Fixes**: Fixed the abnormal font weight issue on certain Android devices, and mitigated visual jitter during keyboard pop-ups.
- **Smart Push Adjustments**: Refined the recommendation algorithm for more accurate content delivery.
- **WebDAV Sync (Beta)**: Added WebDAV cloud synchronization with conflict isolation and a cellular data usage toggle (closes #270).
- **Native PDF Export**: Supports standard A4 rich-text PDF export and native system print preview, resolving font rendering issues for CJK characters.
- **Accessibility (A11y)**: Added screen reader support (Semantics/Tooltip) for interactive UI components lacking text labels.
- **Bug Fixes**: Addressed multiple legacy bugs affecting daily usage.

### 💻 Developer Section: Under the Hood & Security

- **Streaming Data Processing**: Overhauled backup, export, and WebDAV pipelines. Deprecated legacy aggregation paths in favor of asynchronous streaming ZIP compilation (`ZipStreamProcessor` / `StreamFileSelector`), effectively preventing OOM memory spikes during massive vault exports.
- **Security Hardening**:
  - Patched SQL injection vulnerabilities in `DatabaseSchemaManager` and removed unsafe `EXPLAIN QUERY PLAN` database logging.
  - Mitigated predictable file path vulnerabilities in temporary directories.
  - Resolved API key leakage risks within `APIKeyManager` and enforced HTTPS across WebDAV and APK checks.
- **Performance Optimizations**:
  - Replaced full-table retroactive location scans with targeted batch SQL updates.
  - Removed premature `TextPainter` calculations in `QuoteItemWidget` to reduce frame build times during long list scrolling.
  - Optimized database tag queries and avoided redundant RegExp compilation during SVG parsing.
- **Framework & SDK Upgrades**:
  - Upgraded Flutter SDK to 3.44.0, migrating to built-in Kotlin and resolving NDK version incompatibilities.
  - Integrated Sentry SDK strictly within a safe context sandbox, alongside a performance jank detector.
  - Cleaned up the codebase by removing stale `ignore` directives and dead code paths.

---

**Full Changelog**: `3.6.5...3.7.0`


