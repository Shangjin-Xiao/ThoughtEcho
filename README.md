<div align="center">
  <img src="res/icon.png" alt="心迹 Logo / ThoughtEcho Logo" width="120">
  
  # 心迹 (ThoughtEcho)
  
  <p>
    <a href="https://github.com/Shangjin-Xiao/ThoughtEcho/blob/main/LICENSE">
      <img src="https://img.shields.io/github/license/Shangjin-Xiao/ThoughtEcho?style=flat-square" alt="License: MIT">
    </a>
    <a href="https://github.com/Shangjin-Xiao/ThoughtEcho/releases/latest">
      <img src="https://img.shields.io/github/v/release/Shangjin-Xiao/ThoughtEcho?include_prereleases&style=flat-square&color=green&label=最新版本" alt="Latest Release / 最新版本">
    </a>
    <!-- TODO: If CI is set up later, uncomment and potentially update the workflow filename -->
    <!-- <img src="https://img.shields.io/github/workflow/status/Shangjin-Xiao/ThoughtEcho/CI?style=flat-square" alt="Build Status / 构建状态"> -->
    <a href="https://github.com/Shangjin-Xiao/ThoughtEcho/stargazers">
      <img src="https://img.shields.io/github/stars/Shangjin-Xiao/ThoughtEcho?style=flat-square&color=yellow" alt="Stars">
    </a>
    <a href="https://github.com/Shangjin-Xiao/ThoughtEcho/network/members">
      <img src="https://img.shields.io/github/forks/Shangjin-Xiao/ThoughtEcho?style=flat-square&color=blue" alt="Forks">
    </a>
  </p>

  <p>
    <b>📝 你的专属灵感摘录本<br>
    让我们一起随心记录，释放 AI 洞察的力量 ✨</b>
  </p>
  
  <p>
    <a href="#-english-version"><b>English</b></a> • 
    <a href="#-中文版本"><b>中文</b></a>
  </p>
  
</div>

---

<div id="-中文版本">

## ✨ 当前功能

<div align="center">
  <table>
    <tr>
      <td align="center" width="33%"><b>✍️ 富文本笔记</b><br>支持富文本编辑、图片、音频、视频</td>
      <td align="center" width="33%"><b>🏷️ 智能标签系统</b><br>便捷地分类与检索笔记</td>
      <td align="center" width="33%"><b>🎨 个性化主题</b><br>Material 3设计，自定义颜色</td>
    </tr>
    <tr>
      <td align="center"><b>🤖 多AI服务商支持</b><br>OpenAI、Anthropic、DeepSeek等</td>
      <td align="center"><b>🎯 AI卡片生成</b><br>将笔记转换为精美分享卡片</td>
      <td align="center"><b>� 多平台同步</b><br>Windows、Android、iOS、Web</td>
    </tr>
    <tr>
      <td align="center"><b>💾 智能备份系统</b><br>ZIP格式完整备份，支持大文件流式处理和操作取消</td>
      <td align="center"><b>🧠 智能内存管理</b><br>大文件流式处理，防止内存溢出</td>
      <td align="center"><b>📊 AI洞察分析</b><br>智能分析笔记内容与模式</td>
    </tr>
    <tr>
      <td align="center"><b>� 一言集成</b><br>展示精选句子，类型可筛选</td>
      <td align="center"><b>🌍 位置记录</b><br>自动获取地理位置和天气信息</td>
      <td align="center"><b>🔍 全文搜索</b><br>快速搜索笔记内容</td>
    </tr>
  </table>
</div>

## 📸 应用截图

| 主页 | 添加/编辑笔记 | 标签管理 |
|:---:|:---:|:---:|
| ![主页](res/homepage.jpg) | ![添加/编辑笔记](res/add.jpg) | ![标签管理](res/tags.jpg) |
| **主题设置** | **一言类型选择** | **设置与备份** |
| ![主题设置](res/theme_setting.jpg) | ![一言类型选择](res/choose_yiyan.jpg) | ![设置与备份](res/settingpage.jpg) |


## 🛠️ 技术栈

<div align="center">
  <table>
    <tr>
      <td align="center"><b>框架</b></td>
      <td>Flutter (Dart) - 跨平台UI框架</td>
    </tr>
    <tr>
      <td align="center"><b>状态管理</b></td>
      <td>provider, get_it - 依赖注入与状态管理</td>
    </tr>
    <tr>
      <td align="center"><b>本地数据库</b></td>
      <td>sqflite (移动端), sqflite_common_ffi (桌面端)</td>
    </tr>
    <tr>
      <td align="center"><b>富文本编辑</b></td>
      <td>flutter_quill - 支持富文本、图片、音视频</td>
    </tr>
    <tr>
      <td align="center"><b>AI集成</b></td>
      <td>多provider架构 - OpenAI、Anthropic、DeepSeek等</td>
    </tr>
    <tr>
      <td align="center"><b>存储优化</b></td>
      <td>MMKV (高性能), flutter_secure_storage (安全存储)</td>
    </tr>
    <tr>
      <td align="center"><b>多媒体处理</b></td>
      <td>大文件流式处理、智能内存管理、媒体压缩优化</td>
    </tr>
    <tr>
      <td align="center"><b>平台适配</b></td>
      <td>Windows、Android、iOS、Web全平台支持</td>
    </tr>
  </table>
</div>

## 🚀 快速开始

1. **环境准备** 
   
   确保已安装 Flutter 3.x+ 环境。运行 `flutter doctor` 检查配置。

2. **获取代码**
   ```bash
   git clone https://github.com/Shangjin-Xiao/ThoughtEcho.git
   cd ThoughtEcho
   ```

3. **安装依赖**
   ```bash
   flutter pub get
   ```

4. **运行应用**
   ```bash
   flutter run
   ```

5. **AI 功能配置** (可选)
   
   在应用设置中配置 API Key 以启用 AI 功能。

## 🗺️ 发展路线图

<div align="center">
  <table>
    <tr>
      <th>已完成 ✅</th>
      <th>进行中 (2024 Q4) 🚧</th>
      <th>计划中 (2025 Q1) 📅</th>
      <th>长期规划 💡</th>
    </tr>
    <tr>
      <td>
        • 富文本编辑器与多媒体支持<br>
        • 多AI服务商架构<br>
        • AI卡片生成功能<br>
        • 大文件流式处理<br>
        • 智能内存管理<br>
        • ZIP格式完整备份<br>
        • Material 3现代化界面<br>
        • 多平台数据库适配<br>
        • 位置与天气记录<br>
        • 剪贴板智能检测
      </td>
      <td>
        • AI年度报告生成<br>
        • 笔记内容智能分析<br>
        • 性能优化与稳定性提升<br>
        • 用户体验改进
      </td>
      <td>
        • 自然语言搜索增强<br>
        • AI聊天对话功能<br>
        • 地图选点添加位置<br>
        • 笔记分类管理优化<br>
        • 高级搜索功能
      </td>
      <td>
        • 离线AI分析能力<br>
        • 多设备实时同步<br>
        • 高级数据可视化<br>
        • 桌面端独立应用<br>
        • 更多AI集成服务<br>
        • 数据导出与迁移工具
      </td>
    </tr>
  </table>
</div>

## 🤝 如何贡献

1. **提交问题或建议**：通过 [GitHub Issues](https://github.com/Shangjin-Xiao/ThoughtEcho/issues) 反馈

2. **贡献代码**：
   - Fork 仓库并创建功能分支 `feature/YourFeature`
   - 提交更改 `git commit -m 'feat: Add feature'`
   - 创建 Pull Request 到主仓库

## 📄 许可证

本项目基于 [MIT 许可证](LICENSE) 发布。
</div>

---

<details id="-english-version">
<summary><h2>🇬🇧 English Version</h2></summary>

<div align="center">
  <p>
    <b>📝 Your Personal Inspiration Notebook with AI Power<br>
    Capture ideas effortlessly, unlock insights with AI ✨</b>
  </p>
</div>

## ✨ Current Features

<div align="center">
  <table>
    <tr>
      <td align="center" width="33%"><b>✍️ Rich Text Notes</b><br>Support for rich text, images, audio, video</td>
      <td align="center" width="33%"><b>🏷️ Smart Tag System</b><br>Organize and retrieve notes easily</td>
      <td align="center" width="33%"><b>🎨 Personalized Themes</b><br>Material 3 design with custom colors</td>
    </tr>
    <tr>
      <td align="center"><b>🤖 Multi-AI Provider Support</b><br>OpenAI, Anthropic, DeepSeek, and more</td>
      <td align="center"><b>🎯 AI Card Generation</b><br>Convert notes to beautiful shareable cards</td>
      <td align="center"><b>📱 Cross-Platform Sync</b><br>Windows, Android, iOS, Web</td>
    </tr>
    <tr>
      <td align="center"><b>💾 Smart Backup System</b><br>ZIP format complete backup with streaming</td>
      <td align="center"><b>🧠 Intelligent Memory Management</b><br>Large file streaming to prevent OOM</td>
      <td align="center"><b>📊 AI Insights Analysis</b><br>Smart analysis of note content & patterns</td>
    </tr>
    <tr>
      <td align="center"><b>� Hitokoto Integration</b><br>Display quotes with type filtering</td>
      <td align="center"><b>🌍 Location Recording</b><br>Auto-capture location and weather info</td>
      <td align="center"><b>🔍 Full-Text Search</b><br>Quick search through note content</td>
    </tr>
  </table>
</div>

## 📸 Application Screenshots

| Homepage | Add/Edit Note | Tag Management |
|:---:|:---:|:---:|
| ![Homepage](res/homepage.jpg) | ![Add/Edit Note](res/add.jpg) | ![Tag Management](res/tags.jpg) |
| **Theme Settings** | **Hitokoto Types** | **Settings & Backup** |
| ![Theme Settings](res/theme_setting.jpg) | ![Hitokoto Types](res/choose_yiyan.jpg) | ![Settings & Backup](res/settingpage.jpg) |


## 🛠️ Tech Stack

<div align="center">
  <table>
    <tr>
      <td align="center"><b>Framework</b></td>
      <td>Flutter (Dart) - Cross-platform UI framework</td>
    </tr>
    <tr>
      <td align="center"><b>State Management</b></td>
      <td>provider, get_it - Dependency injection & state management</td>
    </tr>
    <tr>
      <td align="center"><b>Local Database</b></td>
      <td>sqflite (mobile), sqflite_common_ffi (desktop)</td>
    </tr>
    <tr>
      <td align="center"><b>Rich Text Editor</b></td>
      <td>flutter_quill - Rich text with images, audio, video</td>
    </tr>
    <tr>
      <td align="center"><b>AI Integration</b></td>
      <td>Multi-provider architecture - OpenAI, Anthropic, DeepSeek</td>
    </tr>
    <tr>
      <td align="center"><b>Storage Optimization</b></td>
      <td>MMKV (high performance), flutter_secure_storage (secure)</td>
    </tr>
    <tr>
      <td align="center"><b>Media Processing</b></td>
      <td>Large file streaming, smart memory management, media optimization</td>
    </tr>
    <tr>
      <td align="center"><b>Platform Support</b></td>
      <td>Windows, Android, iOS, Web full platform support</td>
    </tr>
  </table>
</div>

## 🚀 Quick Start

1. **Prerequisites** 
   
   Ensure Flutter 3.x+ is installed. Run `flutter doctor` to check.

2. **Get the Code**
   ```bash
   git clone https://github.com/Shangjin-Xiao/ThoughtEcho.git
   cd ThoughtEcho
   ```

3. **Install Dependencies**
   ```bash
   flutter pub get
   ```

4. **Run the App**
   ```bash
   flutter run
   ```

5. **AI Feature Configuration** (Optional)
   
   Configure the API Key in app settings to enable AI features.

## 🗺️ Development Roadmap

<div align="center">
  <table>
    <tr>
      <th>Completed ✅</th>
      <th>In Progress (2024 Q4) 🚧</th>
      <th>Planned (2025 Q1) 📅</th>
      <th>Long Term 💡</th>
    </tr>
    <tr>
      <td>
        • Rich text editor with multimedia<br>
        • Multi-AI provider architecture<br>
        • AI card generation feature<br>
        • Large file streaming processing<br>
        • Intelligent memory management<br>
        • ZIP format complete backup<br>
        • Material 3 modern interface<br>
        • Multi-platform database adapter<br>
        • Location & weather recording<br>
        • Smart clipboard detection
      </td>
      <td>
        • AI annual report generation<br>
        • Smart note content analysis<br>
        • Performance optimization<br>
        • User experience improvements
      </td>
      <td>
        • Enhanced natural language search<br>
        • AI chat conversation feature<br>
        • Map location selection<br>
        • Note categorization optimization<br>
        • Advanced search features
      </td>
      <td>
        • Offline AI analysis capability<br>
        • Multi-device real-time sync<br>
        • Advanced data visualization<br>
        • Standalone desktop app<br>
        • More AI service integrations<br>
        • Data export & migration tools
      </td>
    </tr>
  </table>
</div>

## 🤝 How to Contribute

1. **Report Issues or Suggestions**: Via [GitHub Issues](https://github.com/Shangjin-Xiao/ThoughtEcho/issues)

2. **Contribute Code**:
   - Fork the repo and create feature branch `feature/YourFeature`
   - Commit changes `git commit -m 'feat: Add feature'`
   - Create Pull Request to main repository

## 📄 License

This project is licensed under the [MIT License](LICENSE).

</details>
