# ThoughtEcho v3.6.0 发布说明 / Release Notes
> 📖用户指南/User Guide: https://note.shangjinyun.cn/user-guide.html

> 🎉 **本次更新带来了更多元的每日一言服务商支持、全新的用户反馈功能、编辑体验优化以及全方位的稳定性能提升。**
>
> 🎉 **This update brings support for more daily quote providers, a brand new user feedback feature, editing experience optimizations, and overall stability improvements.**

> [English Version](#english-version)

---

## 中文版

### 用户篇

#### 📖 灵感获取与推送
- **每日一言服务商扩展**：新增支持 **ZenQuotes** 和 **API Ninjas**，为您提供跨语言、多分类的丰富灵感来源。
- **智能推送算法升级**：收紧了“此时此刻”的触发条件，使推送内容更贴合当前时境；每日一言推送限制为每天最多一次，减少打扰。
- **引导页个性化**：根据系统语言自动推荐最合适的每日一言服务商，优化新用户配置体验。

#### ✨ 记录与编辑体验升级
- **显示笔记编辑时间**：新增设置选项，支持在笔记列表轻量化显示上次编辑时间，方便追踪内容更新。
- **快速进入全屏编辑器**：新增设置选项，支持点击添加按钮后直接进入功能最全的全屏编辑器。
- **草稿箱逻辑优化**：大幅优化了草稿自动保存与恢复逻辑，清空正文将自动清理无效草稿，防止过期内容干扰。
- **未保存检测增强**：修复了笔记编辑器在无实际修改（如仅打开查看或自动补全元数据后）错误弹出未保存提示的问题。

#### 💬 反馈与支持
- **专属反馈页面**：整合了 GitHub Issue 模板和 Discussions 入口，支持一键生成包含系统信息的 Bug 报告或功能建议。
- **实况照片预览优化**：为预览界面的关闭按钮添加了语义提示符 (Tooltip)，无障碍体验更佳。

### 开发者篇


#### 性能与架构
- **模块化重构**：将庞大的 `ApiService` 拆分为多个功能模块，优化了 `HitokotoSettingsPage` 的布局与逻辑解耦。
- **健壮性增强**：在笔记同步与网络请求中加入更完善的结构化日志；修复了 `RetryInterceptor` 中的不可达代码。
- **测试驱动**：大幅补充了关于草稿行为、每日一言配置、引导页偏好设置及编辑时间显示的 Widget 测试与单元测试。

---

<h2 id="english-version">English Version</h2>

### Quick Overview

**Features**:
- **Rich Inspirations**: Added ZenQuotes and API Ninjas as daily quote providers with language-aware defaults.
- **Better Editing**: Option to show last edit time, skip to full editor, and improved draft cleaning logic.
- **Smart Feedback**: Dedicated Feedback & Contact page with integrated GitHub templates and Discussions.
- **Enhanced Algorithms**: Smarter push notification logic to minimize noise and improve relevance.

**Improvements**:
- Fixed false "unsaved changes" prompts in the note editor.
- Massive expansion of automated test coverage for core UI and logic.
- Architecture refactoring for better maintainability (ApiService split).

**User Guide**: User manual is available at [https://note.shangjinyun.cn/user-guide.html](https://note.shangjinyun.cn/user-guide.html)

> ⚠️ **Installation Notes**
> - Current version is **3.6.0**
> - Android users can download the latest APK from the releases.
> - iOS updates are rolling out to the App Store.

---

### For Users

#### 📖 Inspiration & Smart Push
- **New Quote Providers**: Integrated ZenQuotes and API Ninjas, providing a wider variety of global and categorized quotes.
- **Smarter Notifications**: Refined "this moment" triggers for more contextual pushes. Daily quotes are now limited to once per day.
- **Personalized Onboarding**: Automatically recommends the best quote provider based on your system language.

#### ✨ Editing & Capture Experience
- **Show Note Edit Time**: A new setting to display the last modification time on notes, making it easier to track updates.
- **Fast Full Editor**: Option to jump directly into the full-screen editor when adding a new note.
- **Optimized Drafts**: Improved draft auto-save and recovery. Clearing the note body now automatically cleans up associated drafts.
- **No More False Prompts**: Fixed annoying "unsaved changes" alerts when no actual edits were made.

#### 💬 Feedback & Support
- **Integrated Support**: New Feedback & Contact page with direct links to GitHub Issue templates (pre-filled with system info) and Discussions.
- **Accessibility**: Added tooltips to the Live Photo preview close buttons.

### For Developers

#### Performance & Testing
- **Refactoring**: Decoupled the massive `ApiService` and `HitokotoSettingsPage` for better code health.
- **Observability**: Added detailed structured logging for `NetworkService` and sync processes.
- **Testing**: Significant boost in test coverage, including new tests for draft behaviors, onboarding preferences, and UI components.

---

**Full Changelog**: `3.5.5...3.6.0`
