# ThoughtEcho v3.6.5 发布说明 / Release Notes
> 📖用户指南/User Guide: https://note.shangjinyun.cn/user-guide.html

> 🎉 **本次更新专注于系统稳定性与流畅度提升，带来了重构后的回收站界面、智能推送体验优化、防止笔记重复保存等重要修复，并解决了多项底层安全隐患。**
>
> 🎉 **This update focuses on system stability and smoothness, bringing a redesigned Trash UI, optimized Smart Push experience, fixes for duplicate note saves, and critical security patches.**

> [English Version](#english-version)

---

## 中文版

### 用户篇

#### ♻️ 回收站与数据安全
- **回收站 UI 全面重构**：采用更简约的设计风格，并统一了回收站内的卡片渲染逻辑，提供与主列表一致的视觉体验。
- **防止笔记重复保存**：修复了在特定网络环境下或快速点击保存时可能产生的笔记副本问题，确保数据唯一性。
- **清理性能提升**：优化了“清空回收站”时的缓存清理逻辑，大批量删除时更加高效。

#### 🔔 智能推送与交互优化
- **智能推送算法增强**：优化了通知文案生成逻辑，并引入了笔记高亮重试机制，确保推送内容更加精准且易于访问。
- **流畅度持续优化**：针对笔记列表滚动进行了专项改进，通过预热富文本控制器、优化缓存长度及保留模糊滤镜图层，减少滑动时的视觉抖动与卡顿。
- **编辑器响应提升**：修复了非全屏编辑器在键盘弹出时的动画冲突问题，使编辑入口切换更加自然。

#### ✨ 视觉与无障碍
- **自适应头部排版**：优化笔记卡片的日期、位置与天气信息的排列逻辑，提升小屏幕设备上的显示效果。
- **语义化提示增强**：为代码块复制、媒体播放器等图标按钮补充了本地化 Tooltip，持续提升无障碍交互体验。
- **Material 3 进度条**：APK 下载对话框升级为 M3 风格实时进度条，状态展示更清晰。

### 开发者篇

#### 🔒 安全补丁
- **同步服务安全修复**：解决了 LocalSendServer 中潜在的 CORS 配置缺陷及明文 HTTP 传输风险，保障局域网同步安全。
- **数据库 SQL 注入防护**：修复了 `getQuotes` 查询中的潜在注入漏洞。

#### ⚡ 性能与工程化
- **数据库查询 (N+1) 专项治理**：针对备份合并、多标签筛选、回收站清理等场景，系统性地优化了 SQLite 查询逻辑，大幅降低 I/O 开销。
- **媒体引用管理**：重构了媒体清理机制，实施批量引用校验，减少后台资源占用。
- **自动化测试增强**：补充了 NetworkService、AppSettings 及搜索状态控制器的测试用例，确保逻辑变更的稳定性。

---

<h2 id="english-version">English Version</h2>

### Quick Overview

**Experience Improvements**:
- **Trash UI Redesign**: A more minimalist aesthetic with consistent card rendering.
- **Smart Push Enhancements**: Improved notification body construction and retry logic for note highlighting.
- **Smooth Scrolling**: Reduced jank in the note list through controller pre-warming and optimized cache management.
- **Duplicate Save Prevention**: Fixed edge cases causing duplicate note entries.

**Security & Stability**:
- **Security Patches**: Fixed CORS, Cleartext HTTP, and SQL injection vulnerabilities.
- **Database Optimization**: Eliminated N+1 query loops in backup, filtering, and trash cleanup processes.
- **UI Refinements**: Adaptive note headers and localized accessibility tooltips.

**User Guide**: [https://note.shangjinyun.cn/user-guide.html](https://note.shangjinyun.cn/user-guide.html)

---

### For Users

#### ♻️ Data Safety & UI
- **Redesigned Recycle Bin**: Fresh minimalist UI for the Trash page with improved consistency in note rendering.
- **Save Reliability**: Implemented safeguards to prevent duplicate note creation during rapid interactions or network instability.

#### ⚡ Performance & Polish
- **Scrolling Smoothness**: Continuous optimizations to the main note list to minimize frame drops and layout jumps during fast scrolling.
- **Keyboard & Editor Transitions**: Resolved animation conflicts when opening the quick editor, ensuring a smoother typing start.
- **Adaptive Layouts**: Note headers now intelligently arrange metadata to maximize readability across different screen sizes.

### For Developers

#### 🔒 Security & Architecture
- **Protocol Security**: Hardened LocalSend implementation against insecure CORS and plain-text communication.
- **SQL Optimization**: Systematic removal of N+1 query patterns in core database services.
- **Testing**: Expanded coverage for AppSettings, NetworkService headers, and search state logic.

---

**Full Changelog**: `3.6.0...3.6.5`
