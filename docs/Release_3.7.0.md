# ThoughtEcho v3.7.0 发布说明 / Release Notes
> 📖用户指南/User Guide: https://note.shangjinyun.cn/user-guide.html

> 🎉 **本次更新重点打磨了核心体验，进一步提升了笔记浏览的流畅度并修复了大量已知 Bug。同时带来了备受期待的 WebDAV 云端同步以及 A4 原生 PDF 导出与打印功能。**
>
> 🎉 **This update focuses on polishing the core experience, bringing smoother note browsing and significantly fewer bugs. It also introduces the highly anticipated WebDAV cloud synchronization and native A4 PDF export capabilities.**

> [English Version](#english-version)

---

## 中文版

### ⚡ 体验优化与打磨
- **浏览更流畅**：重点优化了笔记列表的滚动表现，大幅缓解了之前的滑动卡顿现象，让日常阅览体验更加顺心。
- **动画与细节打磨**：修缮了界面上的多处交互动画与排印细节，修正了部分设备上升起键盘时的视觉抖动以及 Android 端字体异常加粗的问题。
- **Bug 修复专场**：集中修复了历史版本中遗留的大量影响体验的 Bug，全面提升了基础操作的可靠性。
- **无障碍体验提升 (A11y)**：为诸多交互组件（如引导遮罩、关闭按钮等）补充了语义化提示，提升不同设备与人群的操作体验。

### ☁️ 云端同步与导出
- **WebDAV 云端同步**：全新支持 WebDAV 协议的云端同步，拥有专属配置面板、冲突隔离与移动网络流量保护功能，确保您的数据能够安全、可靠地备份到个人的云盘中。
- **大体量导出优化**：重写了备份与导出底层的执行方式，在处理极多笔记时不再产生导致应用崩溃的性能峰值。
- **原生 PDF 导出与打印**：实现了标准 A4 尺寸的富文本 PDF 导出，支持批量选择笔记合并导出，修复了中文导出的乱码问题，并内置系统级原生打印预览。

### 🔒 开发者与底层安全
- **零容忍的安全加固**：彻底修复了部分场景下的 SQL 注入风险及明文传输漏洞，WebDAV 与应用内更新检查强制使用 HTTPS。
- **引入 Sentry 监控**：为了更好地定位线上问题，底层引入了 Sentry 错误追踪 SDK（**注：该功能目前默认处于关闭状态**）。
- **性能引擎升级**：Flutter SDK 与 CI 全线升级至最新版 3.44.0；核心位置服务优化为精准的批量 SQL 更新。

---

<h2 id="english-version">English Version</h2>

### Quick Overview

**Experience Optimization**:
- **Smoother Browsing**: Heavily optimized note list scrolling, drastically reducing jank and stutter for a much more comfortable reading experience.
- **Polished Animations & UI**: Refined UI interactions, fixed keyboard animation glitches, and resolved Android font weight issues.
- **Bug Fixes**: Squashed numerous known bugs from previous versions, ensuring rock-solid daily usage.

**WebDAV & Export Features**:
- **WebDAV Sync**: Brand new WebDAV support for reliable cloud synchronization, featuring conflict isolation and cellular data protection.
- **Native PDF Export**: Standard A4 rich-text PDF export with native system print preview, batch selection, and proper Chinese font rendering.
- **Export Reliability**: Rewrote the underlying backup engine to handle massive note vaults without crashing.

**Security & Stability**:
- **Security Hardening**: Enforced HTTPS for WebDAV and updates, patched SQL injection risks, and secured plaintext vulnerabilities.
- **Sentry Integration**: Introduced Sentry SDK for crash reporting (**Note: This feature is currently disabled by default**).
- **Performance Engine**: Upgraded to Flutter 3.44.0. Transitioned large-scale database operations to targeted batch SQL updates.

**User Guide**: [https://note.shangjinyun.cn/user-guide.html](https://note.shangjinyun.cn/user-guide.html)

---

**Full Changelog**: `3.6.5...3.7.0`
