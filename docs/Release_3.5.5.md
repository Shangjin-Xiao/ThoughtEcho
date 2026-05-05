# ThoughtEcho v3.5.5 体验优化版 发布说明 / Experience Optimization Edition Release Notes
> 📖用户指南/User Guide: https://note.shangjinyun.cn/user-guide.html

> 🎉 **本次更新带来了更好的编辑体验、智能推送逻辑优化以及多项性能与安全修复。**
>
> 🎉 **This update brings better editing experiences, optimized smart push logic, and multiple performance and security fixes.**

> [English Version](#english-version)

---

## 中文版

### 用户篇

#### ✨ 编辑与记录体验升级
- **显示笔记编辑时间**：新增设置选项，支持在笔记内显示上次编辑时间。
- **草稿箱与未保存状态优化**：大幅优化了草稿判定逻辑，修复了在无修改时错误弹出未保存提示的问题。

#### 🔔 智能推送与每日一言优化
- **智能推送算法升级**：收紧了“此时此刻”的触发条件，使推送内容更加精准；“每日一言”限制每天最多推送一次，避免过度打扰。
- **离线每日一言**：离线状态下每日一言支持自定义数据源，相关设置已移至偏好设置中。

### 开发者篇

#### 性能优化
- **备份性能提升**：统一了服务与 UI 层的备份进度阈值并对齐阶段映射，大幅减少了在包含大量多媒体文件的备份过程中的 UI 卡顿。

#### 安全与网络
- **XSS 漏洞修复**：修复了 `ContentSanitizer` 和 WebView 渲染中的一处高危跨站脚本攻击 (XSS) 漏洞。
- 移除了导致重复处理的冗余 CSP 清理逻辑。

#### 架构与工程化
- **Android SDK 升级**：最低支持版本 (`minSdkVersion`) 提升至 28。
- **SQLite 兼容性**：回退 `pragma_table_info` 为传统 `PRAGMA` 写法，以兼容旧版 SQLite 3.8。
- 修复了若干 CI 代码格式检查及静态分析警告，提高了测试用例 (`WeatherCodeMapper`, `HttpUtils`) 的覆盖率。

---

<h2 id="english-version">English Version</h2>

### Quick Overview

**Features**:
- New "Show Note Edit Time" setting and UI.
- Improved draft and unsaved changes detection (no more false prompts).
- Offline fallback source customization for Daily Quotes.
- Smarter push notification algorithm limits daily quote to once per day.

**Improvements**:
- Smoother backup progress with reduced UI jank during media-heavy backups.
- Android `minSdkVersion` bumped to 28.
- SQLite 3.8 compatibility fixes.

**Security**:
- Fixed a high-severity XSS vulnerability in `ContentSanitizer` and WebViews.

**User Guide**: User manual is available at [https://note.shangjinyun.cn/user-guide.html](https://note.shangjinyun.cn/user-guide.html)

> ⚠️ **Installation Notes**
> - Current version is **3.5.5**
> - Android users can download the latest APK from the releases.
> - iOS updates are rolling out to the App Store.

---

### For Users

#### ✨ Editing & Capture Experience
- **Show Note Edit Time**: Added a new setting to display the last edit time on your notes.
- **Drafts & Unsaved States**: Substantially optimized draft detection logic, fixing annoying false "unsaved changes" prompts when no edits were made.

#### 🔔 Smart Push & Daily Quotes
- **Optimized Push Algorithm**: Tightened the conditions for "this exact moment" pushes to make them more relevant. "Daily Quotes" are now limited to a maximum of 1 push per day to prevent notification fatigue.
- **Offline Daily Quotes**: Moved offline quote fallback settings to preferences, providing more reliable behavior when disconnected.

---

### For Developers

#### Performance
- **Backup Process Optimization**: Aligned backup progress stages and shared thresholds between the core service and UI layer. This drastically reduces UI stuttering (jank) during massive media backups.

#### Security & Network
- **XSS Vulnerability Patch**: Resolved a high-severity Cross-Site Scripting (XSS) vulnerability within `ContentSanitizer` and the WebView component.
- Removed redundant CSP sanitization that was causing double-processing of content.

#### Architecture & Engineering
- **Android Upgrades**: Raised `minSdkVersion` to 28.
- **Database Compatibility**: Reverted parameterized `pragma_table_info` to raw `PRAGMA` to maintain compatibility with legacy SQLite 3.8 environments.
- Addressed multiple CI formatting and analyzer warnings, alongside introducing new test coverage for `WeatherCodeMapper` and `HttpUtils`.
- Fixed Smart Push note deep-link alignment.

---

**Full Changelog**: `3.5.0...3.5.5`