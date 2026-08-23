<div align="center">
  <a href="https://note.shangjinyun.cn/">
    <img src="res/readme-banner.png" alt="ThoughtEcho 心迹 - AI-Powered Inspiration Notebook" width="100%">
  </a>
  
  # ThoughtEcho (心迹)
  
  <p align="center">
    <b>📝 你的专属 AI 灵感摘录本 · Your Personal AI-Powered Inspiration Notebook</b><br>
    <b>想到就记，读到就摘，剩下的交给 AI · Jot it down, clip what you read, let AI sort out the rest.</b>
  </p>

  <p align="center">
    <a href="https://github.com/Shangjin-Xiao/ThoughtEcho/releases/latest">
      <img src="https://img.shields.io/github/v/release/Shangjin-Xiao/ThoughtEcho?style=flat-square&color=3cb371" alt="Latest Release">
    </a>
    <a href="https://github.com/Shangjin-Xiao/ThoughtEcho/releases">
      <img src="https://img.shields.io/github/downloads/Shangjin-Xiao/ThoughtEcho/total?style=flat-square&color=0078D7" alt="Total Downloads">
    </a>
    <a href="https://www.microsoft.com/store/apps/9NC7GDG6KFMC">
      <img src="https://img.shields.io/badge/Microsoft_Store-0078D7?style=flat-square&logo=windows&logoColor=white" alt="Microsoft Store">
    </a>
    <a href="https://flutter.dev/">
      <img src="https://img.shields.io/badge/Flutter-3.24+-02569B?style=flat-square&logo=flutter&logoColor=white" alt="Flutter 3.24+">
    </a>
    <a href="https://github.com/Shangjin-Xiao/ThoughtEcho">
      <img src="https://img.shields.io/badge/Platform-Windows%20%7C%20Android%20%7C%20iOS-informational?style=flat-square" alt="Platform: Windows | Android | iOS">
    </a>
    <a href="https://github.com/Shangjin-Xiao/ThoughtEcho/stargazers">
      <img src="https://img.shields.io/github/stars/Shangjin-Xiao/ThoughtEcho?style=flat-square&color=FFD700" alt="GitHub Stars">
    </a>
    <a href="https://github.com/Shangjin-Xiao/ThoughtEcho/blob/main/LICENSE">
      <img src="https://img.shields.io/github/license/Shangjin-Xiao/ThoughtEcho?style=flat-square" alt="License: MIT">
    </a>
  </p>

  <p align="center">
    <a href="README.md"><b>📖 English</b></a> • 
    <a href="README_CN.md"><b>🇨🇳 简体中文</b></a> •
    <a href="https://note.shangjinyun.cn/"><b>🌐 Official Website</b></a> •
    <a href="docs/USER_MANUAL.md"><b>📘 User Manual</b></a> •
    <a href="https://shangjin-xiao.github.io/ThoughtEcho/user-guide.html"><b>🧭 Web Guide</b></a>
  </p>

  <h3>📥 Download Channels / 下载安装</h3>
  <p align="center">
    <a href="https://www.microsoft.com/store/apps/9NC7GDG6KFMC"><img src="https://get.microsoft.com/images/zh-cn%20dark.svg" width="160" alt="Get from Microsoft Store"></a>
    &nbsp;&nbsp;&nbsp;
    <a href="https://github.com/Shangjin-Xiao/ThoughtEcho/releases/latest"><img src="https://img.shields.io/badge/Android_APK-3DDC84?style=for-the-badge&logo=android&logoColor=white" alt="Android APK"></a>
    &nbsp;&nbsp;&nbsp;
    <a href="https://github.com/Shangjin-Xiao/ThoughtEcho/releases"><img src="https://img.shields.io/badge/GitHub_Releases-181717?style=for-the-badge&logo=github&logoColor=white" alt="GitHub Releases"></a>
  </p>

  <p><sub>💻 Windows: Recommended from Microsoft Store (auto-update) · 📱 Android: Download 64-bit APK · 🍎 iOS: Build with scripts</sub></p>
  <p><sub>🌍 <b>Localization:</b> Full support for <b>English</b>, <b>简体中文</b>, <b>日本語</b>, and <b>한국어</b> (German, Spanish, French in progress)</sub></p>
  
</div>

---

> **ThoughtEcho（心迹）** 是一款优雅、本地优先、AI 赋能的跨平台灵感笔记与知识摘录应用，专为捕捉瞬间灵感、沉淀阅读摘录与激发深度思考而设计。  
> **ThoughtEcho** is an elegant, local-first, AI-powered cross-platform inspiration and quote notebook designed to capture fleeting thoughts, organize reading excerpts, and unlock deeper creative potential.

---

## 🌟 Why ThoughtEcho? / 核心特色

- 🔒 **Local-First & Privacy (本地优先 & 隐私守护)**: 100% data ownership stored locally with SQLite and MMKV. Sensitive notes can be hidden and locked behind biometric authentication (Fingerprint / Face ID). No tracking, no forced cloud lock-in.
- 🧠 **Thoughter AI Agent & Long-Term Memory (Thoughter 智能体 & 长期记忆)**: Multi-provider AI architecture (OpenAI, DeepSeek, Ollama, Gemini, Claude, OpenRouter, SiliconFlow, etc.). Features an autonomous Thoughter agent with cross-session long-term memory that understands your writing personality.
- ✍️ **Rich Multimedia & Context Capture (富文本与灵感情境捕获)**: Quill rich formatting with multimedia attachments (images, audio, video). Automatically captures geocoding location, weather, and time-of-day inspiration context.
- 📊 **Periodic Insights & Card Generation (周期洞察与灵感卡片)**: Automated weekly and monthly reflection insights, annual review reports, thinking pattern analysis, and one-click AI quote share card generation.
- 🔄 **Zero-Config Multi-Device Sync (零配置局域网与云端同步)**: High-speed LocalSend LAN direct sync (mDNS discovery & encrypted transfer) plus flexible WebDAV cloud backup and restore.
- 🎨 **Artistic Themes & Typography (纸墨质感与主题美学)**: Signature handcrafted "Paper & Ink" (纸与墨) and "Plain" (素笺) styles with specialized reading typography, plus dynamic Material 3 color palettes.

<br>

## ✨ Feature Matrix / 功能矩阵

<div align="center">
  <table>
    <tr>
      <td align="center" width="33%"><b>✍️ Rich Text Notes (富文本笔记)</b><br>Quill rich formatting, multimedia attachments (images/audio/video), plain & rich dual storage</td>
      <td align="center" width="33%"><b>✨ Thoughter AI Agent (AI 智能助手)</b><br>Agent tool calling, dedicated long-term memory database, interactive creative assistant</td>
      <td align="center" width="33%"><b>📊 Insights & Reports (洞察与报告)</b><br>AI periodic insights, annual review reports, creative rhythm & writing trend analysis</td>
    </tr>
    <tr>
      <td align="center"><b>🏷️ Tags & Full-Text Search (标签与搜索)</b><br>Multi-tag filters, intelligent sorting, fast local SQLite full-text search</td>
      <td align="center"><b>🎯 AI Card Generation (AI 卡片生成)</b><br>Convert notes into beautiful, customizable shareable cards with artistic templates</td>
      <td align="center"><b>📦 Media & Backup Hub (存储与备份)</b><br>Streaming chunked large-file processing, full ZIP import/export, incremental sync</td>
    </tr>
    <tr>
      <td align="center"><b>🌍 Context Sensing (情境自动记录)</b><br>Auto-captures location, weather, and time-of-day inspiration context</td>
      <td align="center"><b>🙈 Privacy Protection (隐私安全锁)</b><br>Hidden tags + biometric (Fingerprint / Face ID / Windows Hello) unlock</td>
      <td align="center"><b>💾 Auto-Save Drafts (草稿自动保存)</b><br>Real-time draft auto-saving with instant crash recovery; never lose a thought</td>
    </tr>
    <tr>
      <td align="center"><b>⚡ Quick Capture (灵感快速捕获)</b><br>Smart clipboard watcher, daily quotes (Hitokoto / ZenQuotes / etc.), AI writing prompts</td>
      <td align="center"><b>🎨 Handcrafted Themes (特色主题风格)</b><br>Paper & Ink (纸与墨), Plain (素笺), and Material 3 dynamic color tokens</td>
      <td align="center"><b>🔄 Multi-Device Sync (多端数据同步)</b><br>LocalSend LAN high-speed direct transfer + WebDAV cloud backup & restore</td>
    </tr>
  </table>
</div>

## 📸 Application Screenshots / 应用预览

### Core Experience / 核心功能
| Homepage (主页) | Note List (笔记列表) |
|:---:|:---:|
| ![Homepage](res/screenshot/home_page.jpg) | ![Note List](res/screenshot/note_list_view.jpg) |

### Editing & AI Features / 编辑与 AI
| Rich Text Editor (富文本编辑) | AI Q&A Chat (AI 对话) | Filter & Sort (筛选与排序) |
|:---:|:---:|:---:|
| ![Rich Text Editor](res/screenshot/note_full_editor_page.jpg) | ![AI Q&A Chat](res/screenshot/note_qa_chat_page.jpg) | ![Filter & Sort](res/screenshot/note_filter_sort_sheet.jpg) |

### Insights & Sync / 洞察与同步
| Insights Analysis (洞察分析) | Period Report (周期报告) | Device Sync (设备同步) |
|:---:|:---:|:---:|
| ![Insights Analysis](res/screenshot/insights_page.jpg) | ![Period Report](res/screenshot/period_report.jpg) | ![Device Sync](res/screenshot/note_sync.jpg) |

### Settings & Management / 设置与管理
| Theme Settings (主题设置) | Daily Quote Settings (一言设置) | Preferences (偏好设置) |
|:---:|:---:|:---:|
| ![Theme Settings](res/screenshot/theme_settings_page.jpg) | ![Hitokoto Settings](res/screenshot/hitokoto_settings_page.jpg) | ![Preferences](res/screenshot/preferences_detail_page.jpg) |

### Storage & Backup / 存储与备份
| Backup & Restore (备份与恢复) | Storage Management (存储管理) |
|:---:|:---:|
| ![Backup & Restore](res/screenshot/backup_restore_page.jpg) | ![Storage Management](res/screenshot/storage_management_page.jpg) |

## 🛠️ Tech Stack / 技术架构

<div align="center">
  <table>
    <tr>
      <td align="center"><b>Framework (应用框架)</b></td>
      <td>Flutter (Dart) - Modern reactive cross-platform framework</td>
    </tr>
    <tr>
      <td align="center"><b>State Management (状态管理)</b></td>
      <td>Provider, GetIt - Reactive orchestration & dependency injection</td>
    </tr>
    <tr>
      <td align="center"><b>Local Database (本地数据库)</b></td>
      <td>sqflite (Mobile) & sqflite_common_ffi (Desktop SQLite FFI)</td>
    </tr>
    <tr>
      <td align="center"><b>Rich Text Engine (富文本引擎)</b></td>
      <td>flutter_quill - Rich typography with images, audio, and video embeds</td>
    </tr>
    <tr>
      <td align="center"><b>AI Architecture (AI 服务集成)</b></td>
      <td>OpenAI-compatible protocol architecture (Presets: Ollama, OpenAI, DeepSeek, Gemini, Claude, OpenRouter, SiliconFlow)</td>
    </tr>
    <tr>
      <td align="center"><b>Storage & Security (存储与安全)</b></td>
      <td>MMKV (High-performance KV caching) + flutter_secure_storage (Encrypted API keys)</td>
    </tr>
    <tr>
      <td align="center"><b>Multi-Device Sync (多端同步)</b></td>
      <td>LocalSend (LAN mDNS discovery & encrypted TLS transfer) + WebDAV cloud sync</td>
    </tr>
    <tr>
      <td align="center"><b>Media Processing (媒体处理)</b></td>
      <td>Streaming chunked processing for large files, smart caching, compression</td>
    </tr>
    <tr>
      <td align="center"><b>Supported Platforms (支持平台)</b></td>
      <td>Windows, Android, iOS (Web is not supported)</td>
    </tr>
  </table>
</div>

## 🚀 Quick Start / 快速开始

1. **Prerequisites**
   
   Ensure Flutter 3.24+ and Dart 3.5+ are installed. Run `flutter doctor` to verify your environment:
   ```bash
   flutter doctor
   ```

2. **Clone the Repository**
   ```bash
   git clone https://github.com/Shangjin-Xiao/ThoughtEcho.git
   cd ThoughtEcho
   ```

3. **Install Dependencies**
   ```bash
   flutter pub get
   ```

4. **Run the Application**
   ```bash
   flutter run
   ```

5. **Configure AI Services (Optional)**
   
   Navigate to **Settings → AI Settings**, choose an AI provider preset (e.g., DeepSeek, Ollama, OpenAI), paste your API Key, and start using AI Q&A, Thoughter agent, and periodic insights.

## 🗺️ Development Roadmap / 发展路线图

<div align="center">
  <table>
    <tr>
      <th>Completed / 已完成 ✅</th>
      <th>Long Term / 长期规划 💡</th>
    </tr>
    <tr>
      <td>
        • Rich text editor with multimedia (images, audio, video)<br>
        • OpenAI-compatible multi-AI provider architecture<br>
        • Thoughter AI agent with dedicated long-term memory<br>
        • Paper & Ink / Plain / Material 3 signature theme tokens<br>
        • AI card generation with customizable share templates<br>
        • Large file streaming & full ZIP backup/restore<br>
        • LocalSend LAN direct transfer & WebDAV cloud sync<br>
        • Smart geocoding search & automatic weather logging<br>
        • Smart clipboard detection & quick capture on launch<br>
        • Periodic intelligent insights & annual reports<br>
        • Hidden notes with biometric (Fingerprint/Face ID) protection<br>
        • Real-time auto-saving drafts & crash recovery<br>
        • Multilingual support (Full EN/ZH/JA/KO; fallback to EN)<br>
        • Windows desktop application (MSIX installer)<br>
        • iOS platform support & CI build pipeline<br>
        • In-app Release Notes page with theme live preview
      </td>
      <td>
        <b>🔥 Smart Input Upgrades (智能输入升级)</b><br>
        • AI natural language semantic search<br>
        • Voice-to-text quick capture<br>
        • Camera OCR text recognition<br>
        • AI automatic author & source extraction<br><br>
        <b>🌍 User Experience & Knowledge (用户体验与知识体系)</b><br>
        • Interactive notebook themes & custom paper textures<br>
        • Knowledge graph linking & topic clustering<br>
        • Map location picker & memory footprints<br><br>
        <b>✨ On-Device AI Exploration (端侧 AI 探索)</b><br>
        • On-device lightweight offline LLM inference<br>
        • Local offline OCR & offline speech-to-text<br>
        • More third-party note import/export formats
      </td>
    </tr>
  </table>
</div>

> 📝 For in-depth technical documentation, see [Project Overview](docs/project-overview.md) and [User Manual](docs/USER_MANUAL.md).

## 🤝 How to Contribute / 如何贡献

We welcome contributions of all kinds! / 我们非常欢迎社区参与 ThoughtEcho 的建设！

1. **Report Issues or Suggestions**: Open an issue on [GitHub Issues](https://github.com/Shangjin-Xiao/ThoughtEcho/issues)
2. **Help with Localization 🌍**:
   - Help complete and refine translation strings (German, Spanish, French, etc.)
   - Review and improve existing translations (English, Chinese, Japanese, Korean)
3. **Contribute Code**:
   - Fork the repository and create a feature branch `feature/YourFeature` or `fix/YourBugFix`
   - Ensure your code passes analysis and tests
   - Open a Pull Request with a clear description of the changes
4. **Spread the Word**: Star ⭐ the repository and share ThoughtEcho with others!

## 📄 License / 开源许可

This project is licensed under the [MIT License](LICENSE) - feel free to use, modify, and distribute.

## 🙏 Acknowledgments / 鸣谢

Thanks to the following open-source projects and service providers:
- [Flutter](https://flutter.dev/) - Cross-platform UI framework
- [LocalSend](https://github.com/localsend/localsend) - Local network sync protocol
- [Sentry](https://sentry.io/) - Application crash & structured log monitoring
- [Hitokoto](https://hitokoto.cn/) - Chinese daily quote provider
- [ZenQuotes](https://zenquotes.io/) - English daily quote provider
- [API Ninjas Quotes API](https://api-ninjas.com/api/quotes) - Category-based quote provider
- [Meigen Oshieruyo](https://meigen.doodlenote.net/) - Japanese daily quote provider
- [Korean Advice](https://korean-advice-open-api.vercel.app/) - Korean daily quote provider
- [Open-Meteo](https://open-meteo.com/) - Weather data service
- [OpenStreetMap Nominatim](https://nominatim.openstreetmap.org/) - Geocoding service
