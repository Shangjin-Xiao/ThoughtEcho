# 用户手册 / User Manual

[中文版](#-中文版本) | [English Version](#-english-version)

---

<div id="-中文版本">

# 心迹 (ThoughtEcho) 用户手册

欢迎使用心迹，您的专属 AI 灵感笔记本。本手册将帮助您快速了解应用的全部功能。

> 💡 **提示**：详细中文手册请查看 [完整中文版](../assets/docs/user_manual_zh.md)

## 目录

1. [快速入门](#1-快速入门)
2. [AI 服务配置](#2-ai-服务配置)
3. [富文本编辑器](#3-富文本编辑器)
4. [笔记管理](#4-笔记管理)
5. [AI 功能](#5-ai-功能)
6. [同步与备份](#6-同步与备份)
7. [设置详解](#7-设置详解)
8. [开发者模式](#8-开发者模式)
9. [常见问题](#9-常见问题)

---

## 1. 快速入门

### 首次启动
- 应用会显示引导页面，介绍核心功能
- 可选择语言偏好和一言类型
- 如有旧版数据，支持自动迁移

### 主页界面
- **底部导航**：首页、笔记列表、洞察、设置
- **每日灵感**：显示一言和 AI 生成的写作提示
- **快速捕获按钮（+）**：
  - 短按：快速添加笔记
  - 长按：语音输入
- **剪贴板检测**：切回应用时自动检测剪贴板内容

---

## 2. AI 服务配置

**访问路径**：设置 → AI 助手设置

### 支持的服务商

| 服务商 | API 地址 | 默认模型 |
|--------|----------|----------|
| OpenAI | `https://api.openai.com/v1/chat/completions` | gpt-4o |
| OpenRouter | `https://openrouter.ai/api/v1/chat/completions` | openai/gpt-4o |
| SiliconFlow | `https://api.siliconflow.cn/v1/chat/completions` | (自选) |
| DeepSeek | `https://api.deepseek.com/v1/chat/completions` | deepseek-chat |
| Anthropic Claude | `https://api.anthropic.com/v1/messages` | claude-3.7-sonnet-latest |
| Ollama (本地) | `http://localhost:11434/v1/chat/completions` | (自选) |
| LMStudio (本地) | `http://localhost:1234/v1/chat/completions` | (自选) |

### 配置步骤
1. 打开「设置」→「AI 助手设置」
2. 选择预设服务商或自定义
3. 填入 API Key
4. 点击「测试连接」验证
5. 保存设置

> 🔐 **安全说明**：API Key 使用系统安全存储加密，不会明文存储或导出

---

## 3. 富文本编辑器

### 工具栏功能
- **基础样式**：加粗、斜体、下划线、删除线
- **标题**：H1、H2 多级标题
- **字体**：字体选择、字号调整
- **颜色**：文字颜色、背景高亮
- **布局**：对齐、列表、缩进
- **特殊格式**：引用块、代码块、链接

### 媒体插入
- 图片、视频、音频

### AI 辅助功能（✨ 按钮）
- **智能分析来源**：猜测作者和出处
- **润色文本**：改进文字表达
- **续写**：AI 继续你的思路
- **深度分析**：总结和洞察
- **问笔记**：针对内容提问

### 自动保存
每 2 秒自动保存草稿，防止意外丢失

---

## 4. 笔记管理

### 排序与筛选
- **排序**：按时间、名称、喜爱度
- **筛选**：按标签、天气、时间段

### 笔记操作
- 左滑删除
- 点击爱心增加喜爱度
- 分享为文本或精美卡片（15+ 模板）

---

## 5. AI 功能

- **每日灵感**：基于时间、天气生成写作提示
- **周期性报告**：周报/月报/年报统计 + 诗意洞察
- **智能洞察**：情感分析、思维导图、成长分析
- **年度报告**：精美 HTML 年度总结

---

## 6. 同步与备份

### 设备同步
- 基于 LocalSend 协议的局域网同步
- 支持 Android、iOS、Windows
- 使用「最后写入者胜」策略合并

### 备份与恢复
- 创建 ZIP 备份（含所有笔记和媒体）
- 支持「覆盖」或「合并」恢复
- 兼容旧版 JSON 格式

---

## 7. 设置详解

- **位置与天气**：开关定位、手动选择城市
- **语言**：中文/英文/日文/韩文/西班牙文/法文/德文
- **主题**：Material 3 设计、自定义颜色、深色模式
- **偏好设置**：剪贴板监控、生物识别保护
- **智能推送**：基于时间或位置的提醒
- **一言设置**：配置每日一言类型

---

## 8. 开发者模式

### 激活方法
1. 进入「设置」→「关于心迹」
2. 连续点击应用图标 **3 次**
3. 看到「开发者模式已启用」提示

### 开发者功能
- 日志中心
- 本地 AI（实验性）
- 存储管理
- 数据库调试

---

## 9. 常见问题

**Q: AI 功能无法使用？**  
A: 检查 AI 设置中的 API Key 是否正确，使用「测试连接」验证。

**Q: 如何保护隐私笔记？**  
A: 使用隐藏标签，并开启生物识别保护。

**Q: 同步失败？**  
A: 确保两台设备在同一网络，关闭防火墙/VPN 后重试。

</div>

---

<div id="-english-version">

# ThoughtEcho User Manual

Welcome to ThoughtEcho, your personal AI-powered inspiration notebook. This manual will help you understand all features of the app.

> 💡 **Tip**: For the detailed English manual, see [Full English Version](../assets/docs/user_manual_en.md)

## Table of Contents

1. [Getting Started](#1-getting-started)
2. [AI Service Configuration](#2-ai-service-configuration)
3. [Rich Text Editor](#3-rich-text-editor)
4. [Note Management](#4-note-management)
5. [AI Features](#5-ai-features)
6. [Sync & Backup](#6-sync--backup)
7. [Settings Guide](#7-settings-guide)
8. [Developer Mode](#8-developer-mode)
9. [FAQ](#9-faq)

---

## 1. Getting Started

### First Launch
- App displays onboarding pages introducing core features
- Choose language preferences and Hitokoto types
- Supports automatic migration from older versions

### Home Interface
- **Bottom Navigation**: Home, Notes, Insights, Settings
- **Daily Inspiration**: Shows Hitokoto quote and AI writing prompts
- **Quick Capture Button (+)**:
  - Short press: Quick add note
  - Long press: Voice input
- **Clipboard Detection**: Auto-detects clipboard content when returning to app

---

## 2. AI Service Configuration

**Access Path**: Settings → AI Assistant Settings

### Supported Providers

| Provider | API URL | Default Model |
|----------|---------|---------------|
| OpenAI | `https://api.openai.com/v1/chat/completions` | gpt-4o |
| OpenRouter | `https://openrouter.ai/api/v1/chat/completions` | openai/gpt-4o |
| SiliconFlow | `https://api.siliconflow.cn/v1/chat/completions` | (custom) |
| DeepSeek | `https://api.deepseek.com/v1/chat/completions` | deepseek-chat |
| Anthropic Claude | `https://api.anthropic.com/v1/messages` | claude-3.7-sonnet-latest |
| Ollama (Local) | `http://localhost:11434/v1/chat/completions` | (custom) |
| LMStudio (Local) | `http://localhost:1234/v1/chat/completions` | (custom) |

### Configuration Steps
1. Open "Settings" → "AI Assistant Settings"
2. Select a preset provider or custom
3. Enter your API Key
4. Click "Test Connection" to verify
5. Save settings

> 🔐 **Security Note**: API Keys are encrypted using system secure storage, never stored in plain text or exported

---

## 3. Rich Text Editor

### Toolbar Features
- **Basic Styles**: Bold, Italic, Underline, Strikethrough
- **Headers**: H1, H2 multi-level headings
- **Typography**: Font family, font size
- **Colors**: Text color, background highlight
- **Layout**: Alignment, lists, indentation
- **Special Formats**: Blockquote, code block, links

### Media Insertion
- Images, Video, Audio

### AI Assistant Features (✨ button)
- **Smart Analyze Source**: Guess author and origin
- **Polish Text**: Improve writing style
- **Continue Writing**: AI continues your thoughts
- **Deep Analysis**: Summarize and provide insights
- **Ask Note**: Ask questions about content

### Auto-save
Drafts saved every 2 seconds to prevent data loss

---

## 4. Note Management

### Sorting & Filtering
- **Sort**: By time, name, favorite count
- **Filter**: By tags, weather, time of day

### Note Operations
- Swipe left to delete
- Tap heart to increase favorite count
- Share as text or beautiful cards (15+ templates)

---

## 5. AI Features

- **Daily Inspiration**: Writing prompts based on time and weather
- **Periodic Reports**: Weekly/Monthly/Yearly stats + poetic insights
- **Intelligent Insights**: Emotional, Mindmap, Growth analysis
- **Annual Report**: Beautiful HTML year-end summary

---

## 6. Sync & Backup

### Device Sync
- LocalSend protocol for LAN sync
- Supports Android, iOS, Windows
- Uses "Last Write Wins" merge strategy

### Backup & Restore
- Create ZIP backup (all notes and media)
- "Overwrite" or "Merge" restore modes
- Legacy JSON format compatible

---

## 7. Settings Guide

- **Location & Weather**: Toggle location, manual city selection
- **Language**: EN / ZH / JA / KO / ES / FR / DE
- **Theme**: Material 3 design, custom colors, dark mode
- **Preferences**: Clipboard monitoring, biometric protection
- **Smart Push**: Time or location-based reminders
- **Hitokoto Settings**: Configure daily quote types

---

## 8. Developer Mode

### Activation
1. Go to "Settings" → "About ThoughtEcho"
2. Triple-tap the app icon **3 times**
3. See "Developer mode enabled" message

### Developer Features
- Logs Center
- Local AI (Experimental)
- Storage Management
- Database Debugging

---

## 9. FAQ

**Q: AI features not working?**  
A: Check AI settings for correct API Key, use "Test Connection" to verify.

**Q: How to protect private notes?**  
A: Use hidden tags and enable biometric protection.

**Q: Sync failing?**  
A: Ensure both devices on same network, disable firewall/VPN and retry.

</div>
