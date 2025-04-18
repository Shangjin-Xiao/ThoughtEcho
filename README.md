<p align="center">
  <img src="res/icon.png" alt="心迹 Logo / ThoughtEcho Logo" width="120">
</p>
<h1 align="center">心迹 (ThoughtEcho)</h1>

<p align="center">
  <a href="https://github.com/Shangjin-Xiao/ThoughtEcho/blob/main/LICENSE">
    <img src="https://img.shields.io/github/license/Shangjin-Xiao/ThoughtEcho" alt="License: MIT">
  </a>
  <a href="https://github.com/Shangjin-Xiao/ThoughtEcho/releases/latest">
    <img src="https://img.shields.io/github/v/release/Shangjin-Xiao/ThoughtEcho?include_prereleases&label=latest version / 最新版本" alt="Latest Release / 最新版本">
  </a>
  <!-- TODO: If CI is set up later, uncomment and potentially update the workflow filename -->
  <!-- <img src="https://github.com/Shangjin-Xiao/ThoughtEcho/actions/workflows/ci.yml/badge.svg" alt="Build Status / 构建状态"> -->
  <img src="https://img.shields.io/github/stars/Shangjin-Xiao/ThoughtEcho?style=social" alt="Stars">
  <img src="https://img.shields.io/github/forks/Shangjin-Xiao/ThoughtEcho?style=social" alt="Forks">
</p>

<p align="center">
  <strong class="content-zh">一款使用 Flutter 构建的本地优先笔记应用，助你捕捉、整理思绪，并集成了 ✨ AI 洞察 (开发中) 与 Hitokoto 功能。</strong>
  <strong class="content-en">A local-first note-taking app built with Flutter, designed to help you capture and organize thoughts, featuring ✨ AI insights (WIP) and Hitokoto integration.</strong>
</p>

<p align="center">
  <a href="#-english-version">English Version</a> | <a href="#-中文版本">中文版本</a>
</p>

---

<div id="-中文版本">

## ✨ 当前功能

以下是心迹当前已实现的核心功能：

- **✍️ 笔记管理**: 创建、编辑、查看和删除纯文本笔记。
- **🏷️ 标签系统**: 为笔记添加、管理标签，方便分类与检索。
- **🎨 个性化主题**:
    - 支持浅色与深色模式切换。
    - 提供多种预设主题颜色供选择。
    - 支持通过颜色选择器自定义主题颜色。
- **💬 一言 (Hitokoto)**:
    - 集成 Hitokoto 接口，在应用内展示句子。
    - 支持按类型筛选偏好的句子。
- **💾 数据备份与恢复**:
    - 提供手动备份所有笔记数据到本地文件的功能。
    - 支持从备份文件恢复数据。
- **✨ AI 洞察 (开发中)**:
    - 提供了集成 AI 服务的基础框架 (需在设置中配置 API Key)。*具体 AI 服务待定或由用户配置。*
- **⚙️ 设置选项**:
    - 包含主题、一言、AI (API Key 配置) 及备份恢复等相关设置。
- **🔔 本地通知**: (用于特定事件，如每日一言推送 - *如果已实现*)
- **📲 分享**: 支持将笔记内容分享到其他应用。

*(请注意：当前编辑器仅支持纯文本输入，Markdown 功能仍在规划中。)*

## 📸 应用截图

| 主页 (Homepage)                             | 添加/编辑笔记 (Add/Edit Note)                | 标签管理 (Tag Management)                   |
| :-----------------------------------------: | :--------------------------------------: | :--------------------------------------: |
| <img src="res/homepage.jpg" width="250" alt="主页"> | <img src="res/add.jpg" width="250" alt="添加/编辑笔记"> | <img src="res/tags.jpg" width="250" alt="标签管理"> |

| 主题设置 (Theme Settings)                   | 一言类型选择 (Hitokoto Types)             | 设置与备份 (Settings & Backup)              |
| :------------------------------------------: | :------------------------------------------: | :--------------------------------------: |
| <img src="res/theme_setting.jpg" width="250" alt="主题设置"> | <img src="res/choose_yiyan.jpg" width="250" alt="一言类型选择"> | <img src="res/settingpage.jpg" width="250" alt="设置与备份"> |


## 🛠️ 技术栈

- **框架**: Flutter (使用 Dart 语言)
- **状态管理 / 服务定位**: `provider`, `get_it`
- **本地数据库**: `sqflite` (配合 `path`)
- **API 调用**:
    - `http` (用于 Hitokoto 等)
    - *(用于 AI 服务的库 - 如果有特定库，请补充)*
- **核心依赖库**:
    - `file_picker`, `path_provider` (文件选择与路径)
    - `permission_handler` (权限请求)
    - `flutter_colorpicker` (颜色选择器)
    - `share_plus` (分享功能)
    - `flutter_local_notifications` (本地通知)
    - *(其他依赖请参考 `pubspec.yaml`)*

## 🚀 快速开始

1.  **环境准备**: 确保你已正确安装并配置了 Flutter 开发环境 (建议 Flutter 3.x 或更高版本)。可以通过运行 `flutter doctor` 来检查。
2.  **获取代码**: 克隆本仓库到你的本地：
    ```bash
    git clone https://github.com/Shangjin-Xiao/ThoughtEcho.git
    cd ThoughtEcho
    ```
3.  **安装依赖**: 在项目根目录下运行：
    ```bash
    flutter pub get
    ```
4.  **配置 API Key (可选, 若需使用 ✨ AI 功能)**:
    *   如果你打算接入某个 AI 服务，请获取相应的 API Key。
    *   运行应用后，进入 **设置 -> AI 设置** 页面。
    *   将你的 API Key 粘贴到指定的输入框中并保存。*(注意：应用本身不默认集成特定需付费的 AI 服务)*
5.  **运行应用**: 连接你的设备（模拟器或真机），然后运行：
    ```bash
    flutter run
    ```

## 🗺️ 发展路线图

我们对心迹的未来充满期待，以下是部分规划中的功能：

**近期 (Q2 2024 - 进行中 🚧)**
- [ ] ✨ 新用户启动引导流程 (介绍应用、请求权限、引导设置)
- [ ] ✨ 剪切板智能检测 (方便快速从剪切板添加内容)
- [ ] ✨ 每日一言推送通知 (完善通知逻辑)
- [ ] ⚡ 优化数据库查询性能
- [ ] 🐛 持续修复已知 Bug 并改进稳定性

**中期 (Q3 2024 - 计划中 📅)**
- [ ] ✍️ **Markdown 支持**: 实现完整的 Markdown 编辑与预览功能。
- [ ] 🖼️ **图片与文件支持**: 允许在笔记中插入图片或其他附件 (需要数据库结构调整)。
- [ ] ✨ **AI 功能增强**: 优化 AI 交互，探索更多智能辅助功能 (如自动标签、内容关联等)。
- [ ] 🎨 **界面深度自定义**: 增加字体、显示间距、交互方式 (如双击操作) 等更多自定义选项。

**未来探索 (计划中 💡)**
- [ ] ✨ **本地 AI 分析**: 探索使用 TensorFlow Lite 或设备端模型进行离线的笔记内容分析。
- [ ] ⚙️ **底层优化**: 根据需要进行代码重构，引入原生库以提升关键性能。
- [ ] ☁️ **云同步**: (优先级较低，待未来评估) 提供跨设备的数据同步选项。

*路线图并非固定不变，会根据实际开发进度和用户反馈进行调整。欢迎在 [Issues](https://github.com/Shangjin-Xiao/ThoughtEcho/issues) 中分享你的想法！*

## 🤝 如何贡献

我们非常欢迎社区的贡献，无论是 Bug 反馈、功能建议还是代码提交！

1.  **反馈问题或建议**: 请先在 [GitHub Issues](https://github.com/Shangjin-Xiao/ThoughtEcho/issues) 中查找是否已有类似内容。如果没有，欢迎创建新的 Issue。
2.  **贡献代码**:
    *   Fork 本仓库。
    *   基于 `main` 分支创建你的新分支 (`git checkout -b feature/YourFeature` 或 `fix/BugDescription`)。
    *   进行代码修改和完善。
    *   提交你的更改 (`git commit -m 'feat: Add some amazing feature'`)。建议遵循 Conventional Commits 规范。
    *   将你的分支推送到你的 Fork 仓库 (`git push origin feature/YourFeature`)。
    *   创建 Pull Request 到主仓库的 `main` 分支，并清晰描述你的改动。

感谢所有为心迹添砖加瓦的贡献者！

## 📄 许可证

本项目基于 [MIT 许可证](LICENSE) 发布。
</div>

---

<details id="-english-version">
<summary><strong>English Version (Click to expand)</strong></summary>

## ✨ Current Features

Here are the core features currently implemented in ThoughtEcho:

- **✍️ Note Management**: Create, edit, view, and delete plain text notes.
- **🏷️ Tag System**: Add and manage tags for notes, facilitating organization and retrieval.
- **🎨 Personalized Themes**:
    - Supports switching between light and dark modes.
    - Offers multiple preset theme colors to choose from.
    - Allows defining custom theme colors via a color picker.
- **💬 Hitokoto Integration**:
    - Integrates the Hitokoto API to display quotes within the app.
    - Supports filtering preferred quote types.
- **💾 Data Backup & Restore**:
    - Provides functionality to manually back up all note data to a local file.
    - Supports restoring data from a backup file.
- **✨ AI Insights (WIP)**:
    - Provides the basic framework for integrating AI services (Requires API Key configuration in settings). *Specific AI service is TBD or user-configured.*
- **⚙️ Settings Options**:
    - Includes settings related to themes, Hitokoto, AI (API Key configuration), backup, and restore.
- **🔔 Local Notifications**: (For specific events, e.g., daily Hitokoto push - *if implemented*)
- **📲 Sharing**: Supports sharing note content to other applications.

*(Please note: The current editor only supports plain text input. Markdown functionality is planned for future updates.)*

## 📸 Application Screenshots

| Homepage                                   | Add/Edit Note                            | Tag Management                           |
| :-----------------------------------------: | :--------------------------------------: | :--------------------------------------: |
| <img src="res/homepage.jpg" width="250" alt="Homepage"> | <img src="res/add.jpg" width="250" alt="Add/Edit Note"> | <img src="res/tags.jpg" width="250" alt="Tag Management"> |

| Theme Settings                             | Hitokoto Types                           | Settings & Backup                        |
| :------------------------------------------: | :------------------------------------------: | :--------------------------------------: |
| <img src="res/theme_setting.jpg" width="250" alt="Theme Settings"> | <img src="res/choose_yiyan.jpg" width="250" alt="Hitokoto Types"> | <img src="res/settingpage.jpg" width="250" alt="Settings & Backup"> |


## 🛠️ Tech Stack

- **Framework**: Flutter (using Dart language)
- **State Management / Service Location**: `provider`, `get_it`
- **Local Database**: `sqflite` (with `path`)
- **API Calls**:
    - `http` (for Hitokoto, etc.)
    - *(Library for AI service - please add if a specific one is used)*
- **Core Dependencies**:
    - `file_picker`, `path_provider` (File Picking & Paths)
    - `permission_handler` (Permission Request)
    - `flutter_colorpicker` (Color Picker)
    - `share_plus` (Sharing)
    - `flutter_local_notifications` (Local Notifications)
    - *(Refer to `pubspec.yaml` for other dependencies)*

## 🚀 Quick Start

1.  **Prerequisites**: Ensure you have the Flutter development environment set up correctly (Flutter 3.x or higher recommended). You can check by running `flutter doctor`.
2.  **Get the Code**: Clone this repository to your local machine:
    ```bash
    git clone https://github.com/Shangjin-Xiao/ThoughtEcho.git
    cd ThoughtEcho
    ```
3.  **Install Dependencies**: In the project root directory, run:
    ```bash
    flutter pub get
    ```
4.  **Configure API Key (Optional, if using ✨ AI features)**:
    *   If you plan to connect to an AI service, obtain the corresponding API Key.
    *   After running the app, navigate to the **Settings -> AI Settings** page.
    *   Paste your API Key into the designated input field and save. *(Note: The app itself does not bundle a specific paid AI service by default)*
5.  **Run the App**: Connect your device (emulator or physical device) and run:
    ```bash
    flutter run
    ```

## 🗺️ Development Roadmap

We have exciting plans for ThoughtEcho! Here are some features we're working on or planning:

**Near Term (Q2 2024 - In Progress 🚧)**
- [ ] ✨ New User Onboarding Flow (Introduce the app, request permissions, guide settings)
- [ ] ✨ Smart Clipboard Detection (Easily add content from the clipboard)
- [ ] ✨ Daily Hitokoto Push Notifications (Refine notification logic)
- [ ] ⚡ Optimize database query performance
- [ ] 🐛 Continuous bug fixing and stability improvements

**Mid Term (Q3 2024 - Planned 📅)**
- [ ] ✍️ **Markdown Support**: Implement full Markdown editing and preview capabilities.
- [ ] 🖼️ **Image & File Support**: Allow inserting images and other attachments into notes (requires database structure adjustments).
- [ ] ✨ **AI Feature Enhancement**: Optimize AI interactions, explore more smart assistance features (like auto-tagging, content linking, etc.).
- [ ] 🎨 **Deep UI Customization**: Add more options for customizing fonts, spacing, interactions (like double-tap actions), etc.

**Future Exploration (Planned 💡)**
- [ ] ✨ **Local AI Analysis**: Explore using technologies like TensorFlow Lite or on-device models for offline note content analysis.
- [ ] ⚙️ **Underlying Optimization**: Refactor code and introduce native libraries as needed to enhance critical performance aspects.
- [ ] ☁️ **Cloud Sync**: (Lower priority, to be evaluated later) Offer options for cross-device data synchronization.

*The roadmap is subject to change based on development progress and user feedback. Feel free to share your ideas in the [Issues](https://github.com/Shangjin-Xiao/ThoughtEcho/issues)!*

## 🤝 How to Contribute

Contributions are highly welcome, whether it's bug reports, feature suggestions, or code submissions!

1.  **Reporting Issues or Suggesting Features**: Please check the [GitHub Issues](https://github.com/Shangjin-Xiao/ThoughtEcho/issues) first to see if a similar topic exists. If not, feel free to create a new Issue.
2.  **Contributing Code**:
    *   Fork this repository.
    *   Create your feature branch based on the `main` branch (`git checkout -b feature/YourFeature` or `fix/BugDescription`).
    *   Make your changes and commit them (`git commit -m 'feat: Add some amazing feature'`). Following Conventional Commits is recommended.
    *   Push your branch to your Fork (`git push origin feature/YourFeature`).
    *   Open a Pull Request to the `main` branch of the original repository, clearly describing your changes.

Thank you to all contributors who help make ThoughtEcho better!

## 📄 License

This project is licensed under the [MIT License](LICENSE).
