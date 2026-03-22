# ThoughtEcho v3.5.0 一周年纪念版 发布说明 / 1st Anniversary Edition Release Notes
> 📖用户指南/User Guide: https://note.shangjinyun.cn/user-guide.html

> 🎉 **本版本为心迹一周年特别版，包含重大功能更新和底层架构升级，建议立即更新。**
>
> 🎉 **This is the special 1st Anniversary edition of ThoughtEcho, featuring major updates and architecture upgrades. Please update immediately.**

> [English Version](#english-version)

---

## 中文版

### 用户篇

#### 🎉 一周年庆典
- 庆祝心迹上线一周年！新增应用内专属一周年庆祝动画

#### ✨ AI 功能大升级
- 草稿箱管理新增 AI 分析支持
- 流式文本对话框 UI 焕新，全面支持 Markdown 渲染，元数据栏新增专属 AI 星星图标

#### 📸 丰富的媒体与浏览体验
- **支持在笔记中直接查看和播放实况照片 (Live Photos)**：心迹现已深度适配您的视频转实况工具 [FrameEcho (帧迹)](https://github.com/Shangjin-Xiao/FrameEcho)，支持 Google Motion Photo 格式，让捕捉到的精彩瞬间在笔记中鲜活呈现
- 引入图片延迟加载机制，大幅优化长列表滚动性能，浏览前所未有的丝滑
- 引用卡片新增精致的模糊背景效果

#### 📝 编辑与记录体验升级
- **系统级文本摘录 (Android 专属)**：支持在其他应用中选中文本后直接分享至心迹进行摘录，并自动预填充作者、来源和标签信息
- **默认模板**：新增笔记默认填充功能，新建笔记时可自动带入预设格式

#### 🔔 更智能的推送通知
- **智能推送系统全面重构**：更聪明地优先推送过往珍贵笔记
- 独立推送极具诗意的“每日一言”
- 点击推送通知可直达对应的笔记详情或每日一言专属页面

#### 🌍 全球本地化
- 新增**法语、日语和韩语**的全面本地化翻译
- 改进位置和天气信息的显示格式，特别优化日本等地区的地址层级显示

---

### 开发者篇

#### 性能优化
- **数据库架构升级**：全新引入数据库备份、恢复与健康检查服务，显著优化应用启动速度和数据库加载性能
- 数据库查询优化：消除标签迁移中的 N+1 查询问题，优化循环中的连续 I/O 操作
- 缓存机制：剪贴板服务缓存 `RegExp` 对象，防止频繁重新编译
- 列表渲染：引入 `OptimizedImageLoaderBase`，通过 `NotificationListener` 延迟高负载 UI 操作至滚动结束，消除卡顿
- 并发处理：多媒体文件存在性检查并行化，提升效率
- AI 分析：优化 Web 端批量导入大数据的性能

#### 架构重构
- 拆分巨型类：解耦并拆分 `DatabaseService` (利用 private mixins)
- UI 组件解耦：重构拆分庞大的 `NoteFullEditorPage` (3738行拆分为 293 + 9个部分) 和 `NoteListView` (2118行拆分)
- 异步 Isolate 隔离：将 SmartPush 内容过滤逻辑通过 `compute()` 移至后台 Isolate，避免阻塞 UI 线程
- 代码清理：移除废弃的网络诊断代码、无用弃用代码，并统一 HTTP 库

#### 安全与网络
- **SQL 注入防护**：修复多列 `ORDER BY` 字符串等多个高危 SQL 注入漏洞
- 路径与解压安全：修复 `StreamingBackupProcessor` 中的 Zip Slip 漏洞，加强入口点的路径安全校验
- 平台安全加固：禁用不必要的系统级备份，精简 iOS 权限请求
- 网络安全：默认 OpenAPI 服务器 URL 强制使用 HTTPS，AI 年报 WebView 增加 CSP (Content Security Policy) 限制

#### 测试与工程化
- 测试覆盖率：大幅提升各工具类 (`TimeUtils`, `ColorUtils`, `IconUtils`, `StringUtils`, `LWWUtils`, `PathSecurityUtils`) 的单元测试覆盖率
- 异常处理：修复多个被吞噬的 `Future` 异常，为 21 个文件中的 46 个空 catch 块补充完整日志
- CI/CD 升级：Flutter 环境更新至 `3.38.6` 并调整相关依赖

---

<h2 id="english-version">English Version</h2>

### Quick Overview

**Features**:
- 1st Anniversary Celebration (In-app Animations)
- Live Photos playback support (powered by FrameEcho)
- System-wide Text Excerpt (Android Only)
- Redesigned Smart Push & independent Daily Quotes

**Improvements**:
- Database architecture upgrade with backup/restore services
- Major scroll and image loading performance leap
- Streaming Text Dialog Markdown support
- Significant architecture refactoring (DatabaseService split, UI decoupling)
- Complete French, Japanese, and Korean translations

**Languages**: Added French, Japanese, Korean translations.

**User Guide**: User manual is available at [https://note.shangjinyun.cn/user-guide.html](https://note.shangjinyun.cn/user-guide.html)

> ⚠️ **Installation Notes**
> - Current version is **3.5.0**
> - Android users can download the latest APK from the releases.
> - iOS updates are rolling out to the App Store.

---

### For Users

#### 🎉 1st Anniversary Celebration
- Happy 1st Anniversary! Added special in-app celebratory animations to mark the occasion.

#### ✨ Enhanced AI Capabilities
- Added AI analysis support to Draft Management.
- Streaming Text Dialog completely revamped with Markdown rendering and a new AI star icon in the metadata bar.

#### 📸 Media & Browsing Experience
- **Live Photos support:** View and play Google Motion Photos directly in your notes. Perfectly integrated with [FrameEcho](https://github.com/Shangjin-Xiao/FrameEcho) to bring your captured moments to life.
- Introduced deferred image loading and drastic scrolling optimizations for a perfectly smooth browsing experience.
- Added a refined blurred background effect to quote items.

#### 📝 Editing & Capture Experience
- **System-wide Text Extraction (Android Only):** Select text in any app and share directly to ThoughtEcho, automatically pre-populating author, source, and tag information.
- **Default Note Templates:** Added functionality to automatically populate new notes with default pre-configured text.

#### 🔔 Smarter Push Notifications
- **Smart Push System Overhauled:** Intelligently prioritizes your past notes for rediscovery.
- Poetic "Daily Quotes" are now pushed independently.
- Clicking a notification navigates you directly to the specific note or the daily quote page.

#### 🌍 Global Localization
- Completed comprehensive translations for **French, Japanese, and Korean**.
- Improved location and weather formatting, specifically optimizing for regions like Japan.

---

### For Developers

#### Performance
- **Database Architecture Upgrade:** New database backup, recovery, and health check services introduced to keep your precious data secure. Enjoy faster app startup times and significantly optimized database loading speeds.
- Database optimization: Eliminated N+1 queries in tag migration and optimized sequential I/O loops.
- Regex Caching: Cached `RegExp` objects in `ClipboardService` to prevent recompilation jank.
- Rendering & Scrolling: Introduced `OptimizedImageLoaderBase` and deferred heavy UI operations until scrolling ends via `NotificationListener` to eliminate lag.
- Concurrency: Parallelized media file existence checks.
- AI Import: Optimized AI analysis batch importing specifically for Web.

#### Architecture Refactoring
- Split God Classes: Decoupled and split the massive `DatabaseService` into smaller files with private mixins.
- UI Decoupling: Refactored massive UI files like `NoteFullEditorPage` (3738 lines to 293 + 9 parts) and `NoteListView` (2118 lines to 450 + 4 parts).
- Isolate Processing: Moved SmartPush content filters to background Isolates via `compute()` to prevent UI thread blocking.
- Cleanup: Removed dead network diagnostics code, zero-usage deprecated methods, and unified HTTP libraries.

#### Security & Network
- **SQL Injection Prevention:** Fixed critical SQL injection risks, especially in multi-column `ORDER BY` clauses.
- Path & Extraction Safety: Patched Zip Slip vulnerabilities in `StreamingBackupProcessor` and enforced strict input validations across entry points.
- Platform Hardening: Disabled unintended system backups and trimmed aggressive iOS permissions.
- Network: Enforced HTTPS for default OpenAPI servers and enhanced CSP (Content Security Policy) enforcement in the annual report webview.

#### Testing & Engineering
- Test Coverage: Vastly improved unit test coverage across all utility functions (`TimeUtils`, `ColorUtils`, `IconUtils`, etc.).
- Error Handling: Addressed swallowed `Future`s and added robust logging to 46 empty catch blocks across 21 files.
- CI/CD: Updated Flutter environment to `3.38.6` and adjusted CI workflows.

---

**Full Changelog**: `3.4.0...3.5.0`