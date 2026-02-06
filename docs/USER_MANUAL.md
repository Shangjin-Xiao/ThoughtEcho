# 用户手册 / User Manual

[中文版](#-中文版本) | [English Version](#-english-version) | [网页版 / Web Version](https://shangjin-xiao.github.io/ThoughtEcho/user-guide.html)

---

<div id="-中文版本">

# 心迹 (ThoughtEcho) 用户手册

欢迎使用心迹，您的专属 AI 灵感笔记本。本手册将帮助您快速了解应用的全部功能。

## 目录

1. [快速入门](#1-快速入门)
2. [AI 服务配置](#2-ai-服务配置)
3. [富文本编辑器](#3-富文本编辑器)
4. [笔记管理](#4-笔记管理)
5. [AI 功能](#5-ai-功能)
6. [设备同步](#6-设备同步)
7. [备份与恢复](#7-备份与恢复)
8. [设置详解](#8-设置详解)
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
- **剪贴板检测**：切回应用时自动检测剪贴板内容并提示保存

![主页界面](../res/screenshot/home_page.jpg)

---

## 2. AI 服务配置

> ⚠️ **重要**：AI 功能需要配置 API Key 才能使用

**访问路径**：设置 → AI 助手设置

### 支持的服务商

心迹支持多种主流 AI 服务：

- **OpenAI** - ChatGPT 背后的官方服务
- **Anthropic Claude** - 智能对话助手
- **DeepSeek** - 国产大语言模型
- **OpenRouter** - 可选择多种模型的聚合平台
- **SiliconFlow** - 国内 AI 服务
- **Ollama / LMStudio** - 在您自己的电脑上免费运行 AI（无需联网）
- **自定义服务** - 支持其他兼容服务

### 详细配置步骤

#### 云服务商配置（以 OpenAI 为例）
1. 打开「设置」→「AI 助手设置」
2. 点击「添加服务商」或选择预设服务商
3. 选择「OpenAI」预设
4. 在 API Key 输入框中填入您的密钥
5. 可选：选择其他模型
6. 点击「测试连接」验证配置
7. 保存设置

#### 本地 AI 配置（Ollama）

本地 AI 可以在您的电脑上免费运行，无需付费，也不需要联网。

1. **安装 Ollama**
   - 访问 [ollama.ai](https://ollama.ai) 下载安装

2. **在心迹中配置**
   - 打开「AI 助手设置」
   - 选择「Ollama」预设
   - 填写您下载的模型名称
   - 测试连接并保存

#### 本地 AI 配置（LMStudio）

1. **安装 LMStudio**
   - 访问 [lmstudio.ai](https://lmstudio.ai) 下载安装
   - 下载您需要的模型
   - 启动本地服务器

2. **在心迹中配置**
   - 选择「LMStudio」预设
   - 填写已加载的模型名称
   - 测试连接并保存

### API Key 安全说明

> 🔐 **您的密钥是安全的**：
> - 您的 API Key 安全地保存在您的设备上。
> - 密钥不会被包含在备份文件中
> - 应用会自动验证密钥格式

### 多服务商支持

心迹支持同时配置多个 AI 服务商：
- 当一个服务不可用时，自动切换到其他服务
- 可设置服务商的使用优先级

---

## 3. 富文本编辑器

![富文本编辑器](../res/screenshot/note_full_editor_page.dart.jpg)

### 工具栏功能

编辑器提供丰富的文字排版工具：

- **撤销/重做** - 撤销或恢复操作
- **文字样式** - 加粗、斜体、下划线、删除线
- **标题** - 支持多级标题
- **字体控制** - 调整字号和字体
- **文字颜色** - 设置文字颜色和背景高亮
- **文本对齐** - 左对齐、居中、右对齐、两端对齐
- **列表** - 有序列表、无序列表、缩进控制
- **引用和代码** - 添加引用块或代码格式
- **链接** - 插入或编辑链接
- **媒体** - 插入图片、视频、音频
- **清除格式** - 移除所有格式
- **搜索** - 在文档中搜索内容

### AI 辅助功能（✨ 按钮）

点击编辑器顶部的 ✨ 按钮，可使用以下 AI 功能：

| 功能 | 说明 |
|------|------|
| **自动查找作者和出处** | 自动识别笔记的作者和出处 |
| **润色文本** | AI 帮您改进文字表达 |
| **续写** | AI 根据上下文继续您的思路 |
| **深度分析** | 生成笔记的总结和洞察 |
| **问笔记** | 针对笔记内容与 AI 对话交流 |

### 附加信息编辑面板

点击编辑器顶部的 ✏️ 按钮或「编辑附加信息」，可编辑笔记的附加信息：

#### 来源信息
- **作者**：填写笔记的作者姓名
- **出处**：填写来源作品、书籍或网站
- 可以点击 AI 按钮自动识别作者和出处

#### 颜色标记
- 提供 21 种预设颜色供选择
- 也可以使用颜色选择器自定义颜色
- 点击「移除」可清除颜色标记

#### 标签选择
- 可以为笔记添加多个标签
- 支持搜索查找标签
- 标签区域可以展开或折叠
- 顶部会显示已选择的标签数量

#### 位置和天气
- **位置开关**：开启后会自动获取您当前的位置
- **天气开关**：开启后会自动获取当前天气信息
- 在编辑模式下可以手动修改位置
- 如果是记录过去的事情，可以手动选择当时的天气

### 自动保存

- **草稿自动保存**：每 2 秒自动保存草稿到本地存储
- **草稿恢复**：重新打开编辑器时可恢复上次草稿
- **手动保存**：点击顶部工具栏的 💾 按钮
- **保存进度**：显示实时保存状态和进度条

---

## 4. 笔记管理

![笔记列表](../res/screenshot/note_list_view.jpg)

### 排序选项（3 种）

| 排序方式 | 说明 |
|----------|------|
| **时间排序** | 按创建/修改时间排序（默认降序） |
| **名称排序** | 按笔记标题字母顺序排序 |
| **喜爱度排序** | 按收藏次数排序 |

每种排序均支持升序/降序切换。

### 筛选选项（3 类）

![筛选与排序](../res/screenshot/note_filter_sort_sheet.dart.jpg)

#### 标签筛选
- 按自定义分类标签筛选
- 支持隐藏标签（需生物识别验证）
- 横向滚动的标签选择器
- 支持 emoji 和 Material 图标

#### 天气筛选
- 按天气类型筛选：晴天、阴天、雨天、雪天、雾天等
- 选择某一天气类别会包含该类别下所有天气
- 图标化显示

#### 时间段筛选
- 早晨、下午、傍晚、夜间
- 可多选
- 用于按创作时段查找笔记

所有筛选条件可组合使用，支持重置。

### 笔记操作

#### 主要操作
| 操作 | 方式 | 说明 |
|------|------|------|
| **编辑** | 菜单 → 编辑 | 打开富文本编辑器 |
| **问 AI** | 菜单 → 问 AI | 与 AI 对话讨论笔记 |
| **生成卡片** | 菜单 → 生成卡片 | AI 生成精美分享卡片 |
| **删除** | 菜单 → 删除 / 左滑 | 删除笔记 |
| **收藏** | 点击 ❤️ | 增加喜爱度（最高显示 99+） |

### AI 卡片生成（20 种模板）

点击「生成卡片」后，AI 会根据笔记内容生成 SVG 格式的精美卡片。

**卡片风格**：
- **Knowledge** - 极光渐变、玻璃拟态、高对比度
- **SOTA Modern** - 网格渐变、浮动卡片、动态阴影
- **Mindful** - 有机形状、大地色系、纸张纹理
- **Neon Cyber** - 深色网格、霓虹线条、等宽字体
- **Quote** - 居中文字、蓝色网格背景
- **Philosophical** - 极简主义与象征元素
- **Minimalist** - 简约排版
- **Nature** - 自然元素、自然色彩
- **Retro** - 复古设计美学
- **Ink** - 传统水墨风格
- **Cyberpunk** - 高科技美学
- **Geometric** - 几何图案设计
- **Academic** - 学术研究风格
- **Emotional** - 柔和渐变、温暖圆角
- **Dev** - 代码/技术笔记风格
- **Classic Serif** - 传统衬线字体
- **Modern Pop** - 现代流行色彩
- **Soft Gradient** - 柔和渐变
- **Polaroid** - 拍立得风格
- **Magazine** - 杂志排版风格

**卡片附加信息**：自动包含作者、日期、位置、天气、温度、时段等信息。

---

## 5. AI 功能

### 每日灵感

AI 会根据时间、天气、位置等情况，为您生成个性化的写作提示。

**特点**：
- 早晨/白天的提示更偏向行动（目标、勇气、选择、专注）
- 傍晚/夜间的提示更偏向反思（情感、意义、宽恕、感恩）
- 支持中英文等多种语言
- 没有网络时也可以使用本地生成功能

### 周期性报告

**访问路径**：洞察 → 周期报告

**报告类型**：
- **周报**：过去 7 天的笔记统计
- **月报**：过去 30 天的笔记统计
- **年报**：全年笔记统计

**报告内容**：
- 笔记总数、总字数、活跃天数统计
- 最常见的创作时段（早晨/下午/傍晚/夜间）
- 天气模式分析
- 常用标签统计
- AI 生成的诗意洞察
- 精选笔记卡片展示

### AI 洞察分析

![洞察分析](../res/screenshot/insights_page.jpg)

**访问路径**：洞察 → AI 洞察

#### 分析类型（4 种）

| 类型 | 说明 |
|------|------|
| **综合分析** | 整合主题、情感、价值观、行为模式，全方位概览 |
| **情感分析** | 识别表层和深层情感、触发因素、未满足需求，提供情绪调节策略 |
| **思维导图** | 提取 5-9 个核心思想节点，绘制 8-15 个连接关系（因果、对比、递归） |
| **成长分析** | 识别驱动力/价值观、形成中的能力/习惯，制定 30 天行动计划 |

#### 分析风格（4 种）

| 风格 | 说明 |
|------|------|
| **专业** | 清晰、客观的专业分析 |
| **友好** | 温暖、鼓励的建议 |
| **幽默** | 轻松有趣的表达方式 |
| **文学** | 富有诗意的语言风格 |

分析结果以清晰的结构呈现，包含洞察、证据、建议和反思问题。

### 年度报告

**功能说明**：生成精美的 HTML 格式年度总结。

**报告内容**：
- 渐变色头部设计
- 年度统计卡片（笔记数、字数、活跃天数）
- AI 生成的年度洞察
- 数据回顾区域
- 鼓励性结语

**特点**：
- 响应式设计，适配移动端（最大宽度 414px）
- 现代 CSS 设计（flexbox、圆角、阴影、emoji 图标）
- 优化后的设置确保生成的内容稳定且准确。

### 问笔记聊天

![AI 问答](../res/screenshot/note_qa_chat_page.jpg)

**功能说明**：针对特定笔记内容与 AI 进行对话。

**特点**：
- AI 能够理解笔记内容并回答相关问题
- 只回答与笔记相关的内容，不会随意扩展
- 如果笔记中没有相关信息，AI 会直接告诉您
- 您可以边看边读 AI 生成的回答。

---

## 6. 设备同步

![设备同步](../res/screenshot/note_sync.jpg)

### 同步方式

心迹支持在同一 WiFi 网络下的设备间直接同步，无需云服务器。

### 同步流程

1. **寻找设备**：应用会自动在同一 WiFi 网络中寻找您的其他心迹设备
2. **选择设备**：从列表中选择要同步的目标设备
3. **传输数据**：发送或接收笔记数据
4. **自动合并**：智能合并两台设备的笔记

### 合并规则

当两台设备有相同笔记时，应用会：
- 应用会保留您最后一次修改的内容
- 如果修改时间相同但内容不同，会记录为冲突供您处理

同步完成后会显示：
- 新增了多少条笔记
- 更新了多少条笔记
- 跳过了多少条笔记（因为本地版本更新）
- 是否有冲突需要处理

### 支持平台

| 平台 | 支持情况 |
|------|----------|
| Android | ✅ 完整支持 |
| iOS | ✅ 完整支持 |
| Windows | ✅ 完整支持 |
| macOS | ✅ 完整支持 |
| Linux | ✅ 完整支持 |
| Web | ⚠️ 功能受限 |

---

## 7. 备份与恢复

![备份与恢复](../res/screenshot/backup_restore_page.jpg)

### 备份格式

心迹的备份文件为 ZIP 格式，包含：
- 所有笔记数据
- 图片、视频、音频等媒体文件

旧版本的 JSON 格式备份也可以导入，应用会自动识别和转换。

### 备份的优势

- 备份过程会显示进度
- 即使笔记很多也不会卡顿
- 应用会自动为您管理大型文件

### 恢复模式

导入备份时可以选择三种模式：

| 模式 | 说明 | 适用场景 |
|------|------|----------|
| **覆盖** | 清空当前所有数据，完全替换为备份内容 | 换新设备，想完整恢复数据 |
| **合并** | 智能合并备份和当前数据 | 从其他设备同步数据 |
| **追加** | 直接添加备份中的笔记 | 导入补充数据 |

### 备份操作步骤

**访问路径**：设置 → 备份与恢复

#### 创建备份
1. 点击「创建备份」按钮
2. 选择保存位置
3. 等待备份完成（会显示进度条）
4. 备份文件会保存为 `.zip` 格式

#### 恢复备份
1. 点击「恢复备份」按钮
2. 选择备份文件（支持 `.zip` 或旧版 `.json` 格式）
3. 选择恢复模式（覆盖、合并或追加）
4. 等待恢复完成

---

## 8. 设置详解

![设置界面](../res/screenshot/preferences_detail_page.jpg)

### 位置与天气

- **位置服务开关**：控制是否允许应用获取您的位置
- **位置状态**：
  - ✅ 位置功能已开启
  - ⚠️ 已允许权限但功能未启用
  - ❌ 未允许位置权限
- **城市搜索**：可以手动搜索并设置位置
- **当前地址**：显示您设置的位置或「未设置」

### 语言设置

应用支持多种语言，包括中文、英文、日文、韩文、西班牙文、法文、德文等。也可以选择跟随系统语言。

### 主题设置

![主题设置](../res/screenshot/theme_settings_page.jpg)

#### 主题模式
- 🌞 **浅色模式**：手动浅色主题
- 🌙 **深色模式**：手动深色主题
- 🔄 **跟随系统**：自动跟随系统设置

#### 颜色自定义
- **动态颜色**：从您的手机壁纸提取颜色作为主题色（Android 12+ 支持）
- **自定义主题色**：
  - 10 种预设颜色可选
  - 也可以使用颜色选择器自由选择任意颜色

### 偏好设置

| 设置 | 类型 | 说明 |
|------|------|------|
| 剪贴板监控 | 开关 | 自动捕获剪贴板文本 |
| 显示收藏按钮 | 开关 | 在 UI 中显示收藏功能 |
| 显示精确时间 | 开关 | 显示精确时间戳 vs 相对时间 |
| 优先显示加粗内容 | 开关 | 折叠视图中优先显示加粗文本 |
| 仅使用本地笔记 | 开关 | 限制为本地笔记 vs 云同步 |
| 自动附加位置 | 开关 | 自动为笔记添加位置 |
| 自动附加天气 | 开关 | 自动为笔记添加天气信息 |
| 每日提示生成 (AI) | 开关 | 启用 AI 每日提示 |
| 周期报告 AI 洞察 | 开关 | 启用周期报告的 AI 分析 |
| AI 卡片生成 | 开关 | 启用 AI 卡片生成功能 |
| 生物识别认证 | 开关 | 需要指纹/面部解锁查看隐藏笔记 |

### 一言设置

**可用一言类型**：

| 代码 | 类型 |
|------|------|
| a | 动画 |
| b | 漫画 |
| c | 游戏 |
| d | 文学 |
| e | 原创 |
| f | 网络 |
| g | 哲学 |
| h | 笑话 |
| i | 谚语 |
| j | 创业 |
| k | 励志 |
| l | 名言 |

**功能**：
- 多选类型筛选
- 全选/清除按钮
- 确保至少选择一种类型
- 标题显示类型数量

### 智能推送设置

#### 推送模式

| 模式 | 说明 |
|------|------|
| **智能** | 根据时间/位置/天气自动选择内容 |
| **自定义** | 用户手动选择推送类型和筛选器 |
| **仅每日一言** | 只推送一言 |
| **仅过去笔记** | 随机历史笔记 |
| **两者** | 随机混合一言和历史笔记 |

#### 推送频率
- 每天
- 工作日（周一至周五）
- 周末（周六和周日）
- 自定义

#### 推送时间配置
- 每天多个时间段
- 时/分选择器
- 可选标签（如「早间灵感」）
- 每个时间段可启用/禁用

#### 过去笔记类型
- **去年今日**：去年同一日期
- **上月今日**：上月同一日期
- **上周今日**：上周同一日期
- **随机回忆**：完全随机的旧笔记
- **相同位置**：来自当前位置的历史笔记
- **相同天气**：匹配当前天气的历史笔记

#### 高级选项
- 标签筛选
- 天气类型筛选
- 最近推送历史（最多 30 条，防止重复）

### 分类与标签管理

**访问路径**：设置 → 分类管理 / 标签管理

- 创建新分类（最多 50 字符）
- 图标选择（emoji 或 Material 图标）
- 现有分类列表显示
- 分类 CRUD 操作（创建、读取、更新、删除）

---

## 9. 常见问题

### AI 相关

**Q: AI 功能无法使用？**  
A: 
1. 检查 AI 设置中的 API Key 是否正确
2. 使用「测试连接」验证
3. 确保网络连接正常
4. 检查 API Key 余额是否充足

**Q: 本地 AI (Ollama/LMStudio) 无法连接？**  
A:
1. 确保本地 AI 服务已启动
2. 检查连接地址是否正确
3. 确保防火墙允许连接
4. 检查模型是否已下载并加载

**Q: AI 响应很慢？**  
A:
1. 本地 AI 取决于您的电脑性能，可尝试使用更小的模型
2. 云服务可能因网络问题较慢
3. 您可以尝试在设置中降低回复长度

**Q: 同步失败？**  
A: 
1. 确保两台设备在同一网络
2. 关闭防火墙或网络代理后重试
3. 检查设备是否出现在列表中
4. 尝试手动输入对方设备的地址

**Q: 设备发现不到？**  
A:
1. 检查 WiFi 是否连接到同一网络
2. 部分路由器设置可能会影响设备发现
3. 苹果设备（iOS）请确保已允许访问本地网络权限

### 隐私安全

**Q: 如何保护隐私笔记？**  
A: 
1. 使用隐藏标签标记敏感笔记
2. 在偏好设置中开启生物识别保护
3. 查看隐藏笔记需要指纹/面部验证

**Q: 数据存储在哪里？**  
A:
1. 所有数据本地存储，不会自动上传云端
2. AI 功能会将笔记内容发送到 AI 服务商处理
3. 您的 API Key 安全地保存在设备上，不会导出

### 其他

**Q: 如何完全删除应用数据？**  
A:
1. 在设置中使用「清除所有数据」
2. 或卸载应用后重新安装

**Q: 支持哪些设备？**  
A: Android、iOS、Windows、macOS、Linux、Web（部分功能受限）

</div>

---

<div id="-english-version">

# ThoughtEcho User Manual

Welcome to ThoughtEcho, your personal AI-powered inspiration notebook. This manual will help you understand all features of the app.

## Table of Contents

1. [Getting Started](#1-getting-started)
2. [AI Service Configuration](#2-ai-service-configuration)
3. [Rich Text Editor](#3-rich-text-editor)
4. [Note Management](#4-note-management)
5. [AI Features](#5-ai-features)
6. [Device Sync](#6-device-sync)
7. [Backup & Restore](#7-backup--restore)
8. [Settings Guide](#8-settings-guide)
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

![Home Interface](../res/screenshot/home_page.jpg)

---

## 2. AI Service Configuration

> ⚠️ **Important**: AI features require API Key configuration

**Access Path**: Settings → AI Assistant Settings

### Supported Providers

ThoughtEcho supports various mainstream AI services:

- **OpenAI** - The official service behind ChatGPT
- **Anthropic Claude** - Intelligent conversation assistant
- **DeepSeek** - Chinese large language model
- **OpenRouter** - Multi-model aggregation platform
- **SiliconFlow** - China-based AI service
- **Ollama / LMStudio** - Run AI for free on your own computer (no internet needed)
- **Custom Services** - Supports other compatible services

### Configuration Steps

#### Cloud Provider Setup (OpenAI Example)
1. Open "Settings" → "AI Assistant Settings"
2. Click "Add Provider" or select a preset
3. Choose "OpenAI" preset
4. Enter your API Key
5. Optional: Select a different model
6. Click "Test Connection" to verify
7. Save settings

#### Local AI Setup (Ollama)

Local AI runs on your own computer for free, no internet or payment required.

1. **Install Ollama**
   - Visit [ollama.ai](https://ollama.ai) to download

2. **Configure in ThoughtEcho**
   - Open "AI Assistant Settings"
   - Select "Ollama" preset
   - Enter your downloaded model name
   - Test connection and save

#### Local AI Setup (LMStudio)

1. **Install LMStudio**
   - Visit [lmstudio.ai](https://lmstudio.ai) to download
   - Download your preferred model
   - Start local server

2. **Configure in ThoughtEcho**
   - Select "LMStudio" preset
   - Enter loaded model name
   - Test connection and save

### API Key Security

> 🔐 **Your keys are safe**:
> - Your API Keys are saved safely on your device.
> - Keys are not included in backup files
> - Automatic key format validation

### Multi-Provider Support

ThoughtEcho supports configuring multiple AI providers:
- Automatically switches to another service when one is unavailable
- Provider priority can be configured

---

## 3. Rich Text Editor

![Rich Text Editor](../res/screenshot/note_full_editor_page.dart.jpg)

### Toolbar Features

The editor provides rich text formatting tools:

- **Undo/Redo** - Undo or redo operations
- **Text Styling** - Bold, italic, underline, strikethrough
- **Headers** - Multiple heading levels
- **Font Controls** - Adjust font size and family
- **Text Colors** - Set text color and background highlight
- **Alignment** - Left, center, right, justify
- **Lists** - Ordered lists, unordered lists, indent control
- **Quotes and Code** - Add blockquote or code formatting
- **Links** - Insert or edit links
- **Media** - Insert images, videos, audio
- **Clear Formatting** - Remove all formatting
- **Search** - Search within document

### AI Assistant Features (✨ Button)

Click the ✨ button at the top of the editor for:

| Feature | Description |
|---------|-------------|
| **Automatically find author and origin** | Automatically identify author and source |
| **Polish Text** | AI helps improve your writing |
| **Continue Writing** | AI continues your thoughts based on context |
| **Deep Analysis** | Generate summary and insights |
| **Ask Note** | Chat with AI about note content |

### Extra Information Panel

Click ✏️ button or "Edit Extra Information" to edit note information:

#### Source Information
- **Author**: Enter the author's name
- **Source**: Enter the source work, book, or website
- Click AI button to auto-detect author and source

#### Color Tags
- 21 preset colors available
- Custom color picker for any color
- Click "Remove" to clear color tag

#### Tag Selection
- Add multiple tags to notes
- Search to find tags
- Tag section can be expanded or collapsed
- Shows count of selected tags at top

#### Location & Weather
- **Location Toggle**: Auto-fetch your current location when enabled
- **Weather Toggle**: Auto-fetch current weather when enabled
- Can manually modify location in edit mode
- Manual weather selection for past events

### Auto-Save

- **Draft Auto-Save**: Automatically saves draft every 2 seconds
- **Draft Recovery**: Restore last draft when reopening editor
- **Manual Save**: Click 💾 button in toolbar
- **Save Progress**: Shows real-time save status and progress

---

## 4. Note Management

![Note List](../res/screenshot/note_list_view.jpg)

### Sorting Options (3 Types)

| Sort Type | Description |
|-----------|-------------|
| **Time** | Sort by creation/modification date (default descending) |
| **Name** | Sort alphabetically by title |
| **Favorite** | Sort by favorite count |

Each supports ascending/descending toggle.

### Filter Options (3 Categories)

![Filter & Sort](../res/screenshot/note_filter_sort_sheet.dart.jpg)

#### Tag Filtering
- Filter by custom category tags
- Hidden tags (requires biometric verification)
- Horizontal scrollable tag selector
- Emoji and Material icon support

#### Weather Filtering
- Filter by weather type: Sunny, Cloudy, Rainy, Snowy, Foggy, etc.
- Selecting a category includes all weather in that category
- Icon-based display

#### Time Period Filtering
- Morning, Afternoon, Evening, Night
- Multiple selections allowed
- Find notes by creation time period

All filters can be combined and reset.

### Note Operations

#### Main Operations
| Action | Method | Description |
|--------|--------|-------------|
| **Edit** | Menu → Edit | Open rich text editor |
| **Ask AI** | Menu → Ask AI | Chat with AI about note |
| **Generate Card** | Menu → Generate Card | AI creates beautiful share card |
| **Delete** | Menu → Delete / Swipe left | Delete note |
| **Favorite** | Tap ❤️ | Increase favorite count (max display 99+) |

### AI Card Generation (20 Templates)

Clicking "Generate Card" creates SVG format cards based on note content.

**Card Styles**:
- **Knowledge** - Aurora gradients, glassmorphism, high contrast
- **SOTA Modern** - Mesh gradients, floating card, dynamic shadows
- **Mindful** - Organic shapes, earth tones, paper texture
- **Neon Cyber** - Dark grid, neon lines, monospace font
- **Quote** - Centered text, blue grid background
- **Philosophical** - Minimalist with symbolic elements
- **Minimalist** - Simple typography focus
- **Nature** - Organic elements, natural colors
- **Retro** - Vintage design aesthetic
- **Ink** - Traditional brush/ink style
- **Cyberpunk** - High-tech aesthetic
- **Geometric** - Math/pattern-based design
- **Academic** - Research/study focused layout
- **Emotional** - Soft gradients, warmth, rounded shapes
- **Dev** - Code/technical note focus
- **Classic Serif** - Traditional typography
- **Modern Pop** - Contemporary vibrant colors
- **Soft Gradient** - Pastel, smooth transitions
- **Polaroid** - Instant photo aesthetic
- **Magazine** - Publication-style layout

**Card extra information**: Automatically includes author, date, location, weather, temperature, time period.

---

## 5. AI Features

### Daily Inspiration

AI generates personalized writing prompts based on time, weather, and location.

**Features**:
- Morning/daytime prompts focus on action (goals, courage, choices, focus)
- Evening/night prompts focus on reflection (emotions, meaning, forgiveness, gratitude)
- Supports multiple languages including Chinese and English
- Works offline with local generation

### Periodic Reports

**Access Path**: Insights → Periodic Reports

**Report Types**:
- **Weekly**: Past 7 days statistics
- **Monthly**: Past 30 days statistics
- **Yearly**: Full year statistics

**Report Content**:
- Total notes, word count, active days statistics
- Most common creation time period (morning/afternoon/evening/night)
- Weather pattern analysis
- Frequently used tags
- AI-generated poetic insights
- Featured note cards display

### AI Insight Analysis

![Insights](../res/screenshot/insights_page.jpg)

**Access Path**: Insights → AI Insights

#### Analysis Types (4 Types)

| Type | Description |
|------|-------------|
| **Comprehensive** | Integrates themes, emotions, values, behavior patterns for full overview |
| **Emotional** | Identifies surface/deep emotions, triggers, unmet needs, provides regulation strategies |
| **Mindmap** | Extracts 5-9 core thought nodes, maps 8-15 connections (causal, contrasting, recursive) |
| **Growth** | Identifies drivers/values, forming abilities/habits, creates 30-day action plan |

#### Analysis Styles (4 Styles)

| Style | Description |
|-------|-------------|
| **Professional** | Clear, objective professional analysis |
| **Friendly** | Warm, encouraging advice |
| **Humorous** | Light-hearted, witty observations |
| **Literary** | Poetic, aesthetic language |

Analysis results are presented in a clear structure with insights, evidence, suggestions, and reflection questions.

### Annual Report

Generates a beautiful annual summary in HTML format.

**Report Content**:
- Beautiful header design with gradients
- Annual statistics (notes, words, active days)
- AI-generated annual insights
- Data overview section
- Encouraging closing message

**Features**:
- Mobile-friendly responsive design
- Modern, clean visual style

### Note Q&A Chat

![AI Q&A](../res/screenshot/note_qa_chat_page.jpg)

Chat with AI about specific note content.

**Features**:
- AI understands note content and answers related questions
- Only answers questions related to the note
- Tells you directly if information isn't in the note
- You can see the results as they appear.

---

## 6. Device Sync

![Device Sync](../res/screenshot/note_sync.jpg)

## 6. Device Sync

![Device Sync](../res/screenshot/note_sync.jpg)

### Sync Method

ThoughtEcho supports direct sync between devices on the same WiFi network, no cloud server required.

### Sync Process

1. **Looking for Devices**: The app will look for your other devices automatically
2. **Select Device**: Choose target device from list
3. **Transfer Data**: Send or receive note data
4. **Auto-Merge**: Intelligently merge notes from both devices

### Merge Rules

When both devices have the same note:
- The app keeps your most recent changes.
- If modified at the same time but different content, log as conflict for your review

After sync completes, shows:
- How many notes were added
- How many notes were updated
- How many notes were skipped (because local version was newer)
- Whether there are conflicts to resolve

### Supported Platforms

| Platform | Support |
|----------|---------|
| Android | ✅ Full Support |
| iOS | ✅ Full Support |
| Windows | ✅ Full Support |
| macOS | ✅ Full Support |
| Linux | ✅ Full Support |
| Web | ⚠️ Limited |

---

## 7. Backup & Restore

![Backup & Restore](../res/screenshot/backup_restore_page.jpg)

### Backup Formats

ThoughtEcho backup files are in ZIP format, containing:
- All note data
- Media files (images, videos, audio)

Legacy JSON format backups can also be imported, the app will automatically recognize and convert them.

### Backup Advantages

- Backup process shows progress
- Handles large amounts of notes without slowing down
- The app automatically handles large files for you.

### Restore Modes

When importing a backup, you can choose from three modes:

| Mode | Description | Use Case |
|------|-------------|----------|
| **Overwrite** | Clear all current data and replace with backup | Switching to new device, want complete restore |
| **Merge** | Intelligently merge backup with current data | Syncing data from another device |
| **Append** | Directly add notes from backup | Importing supplemental data |

### Backup Operation Steps

**Access Path**: Settings → Backup & Restore

#### Create Backup
1. Click "Create Backup" button
2. Select save location
3. Wait for completion (progress bar shown)
4. Backup file saved as `.zip` format

#### Restore Backup
1. Click "Restore Backup" button
2. Select backup file (supports `.zip` or legacy `.json` format)
3. Choose restore mode (Overwrite, Merge, or Append)
4. Wait for completion

---

## 8. Settings Guide

![Settings](../res/screenshot/preferences_detail_page.jpg)

### Location & Weather

- **Location Service Toggle**: Control whether app can access your location
- **Location Status**:
  - ✅ Location feature enabled
  - ⚠️ Permission granted but feature not enabled
  - ❌ Location permission not granted
- **City Search**: Manually search and set location
- **Current Address**: Shows your set location or "Not Set"

### Language Settings

The app supports multiple languages including Chinese, English, Japanese, Korean, Spanish, French, German, etc. You can also choose to follow system language.

### Theme Settings

![Theme Settings](../res/screenshot/theme_settings_page.jpg)

#### Theme Modes
- 🌞 **Light Mode**: Manual light theme
- 🌙 **Dark Mode**: Manual dark theme
- 🔄 **Follow System**: Auto-sync with system setting

#### Color Customization
- **Dynamic Color**: Extract colors from your phone wallpaper as theme color (Android 12+ support)
- **Custom Theme Color**:
  - 10 preset colors available
  - Use color picker to freely choose any color

### Preferences

| Setting | Type | Description |
|---------|------|-------------|
| Clipboard Monitoring | Toggle | Auto-capture clipboard text |
| Show Favorite Button | Toggle | Display favorites in UI |
| Show Exact Time | Toggle | Precise timestamps vs relative time |
| Prioritize Bold Content | Toggle | Show bold text first in collapsed view |
| Use Local Notes Only | Toggle | Restrict to local quotes vs cloud sync |
| Auto-Attach Location | Toggle | Automatically add location to notes |
| Auto-Attach Weather | Toggle | Automatically add weather info to notes |
| Daily Prompt Generation (AI) | Toggle | Enable AI daily prompts |
| Periodic Report AI Insights | Toggle | Enable AI analysis for periodic reports |
| AI Card Generation | Toggle | Enable AI card generation feature |
| Biometric Authentication | Toggle | Require fingerprint/face unlock for hidden notes |

### Hitokoto Settings

**Available Hitokoto Types**:

| Code | Type |
|------|------|
| a | Anime |
| b | Comics |
| c | Games |
| d | Literature |
| e | Original |
| f | Network |
| g | Philosophy |
| h | Jokes |
| i | Proverbs |
| j | Startup |
| k | Encouragement |
| l | Famous Quotes |

**Features**:
- Multi-select type filtering
- Select All / Clear All buttons
- Ensures at least one type selected
- Header shows type count

### Smart Push Settings

#### Push Modes

| Mode | Description |
|------|-------------|
| **Smart** | Auto-select content based on time/location/weather |
| **Custom** | User manually selects push types and filters |
| **Daily Quote Only** | Just Hitokoto pushes |
| **Past Notes Only** | Random historical notes |
| **Both** | Random mix of daily quotes and past notes |

#### Push Frequency
- Daily
- Weekdays (Mon-Fri)
- Weekends (Sat-Sun)
- Custom

#### Push Time Configuration
- Multiple time slots per day
- Hour/minute selectors
- Optional labels (e.g., "Morning Inspiration")
- Enable/disable per slot

#### Past Note Types
- **Year Ago Today**: Same date from previous year
- **Month Ago Today**: Same date from previous month
- **Week Ago Today**: Same date last week
- **Random Memory**: Completely random old note
- **Same Location**: Historical notes from current location
- **Same Weather**: Historical notes matching current weather

#### Advanced Options
- Tag filtering
- Weather type filtering
- Recent push history (max 30 notes, prevents duplicates)

### Category & Tag Management

**Access Path**: Settings → Category Management / Tag Management

- Create new categories (max 50 characters)
- Icon selection (emoji or Material icons)
- List display of existing categories
- Category CRUD operations (Create, Read, Update, Delete)

---

## 9. FAQ

### AI Related

**Q: AI features not working?**  
A: 
1. Check AI settings for correct API Key
2. Use "Test Connection" to verify
3. Ensure network connection is stable
4. Check if API Key has sufficient balance

**Q: Can't connect to local AI (Ollama/LMStudio)?**  
A:
1. Ensure local AI service is running
2. Check if the connection address is correct
3. Ensure firewall allows the connection
4. Check if model is downloaded and loaded

**Q: AI responses are slow?**  
A:
1. Local AI depends on your computer's performance, try using a smaller model
2. Cloud services may be slow due to network issues
3. You can try reducing the response length in settings

### Sync Related

**Q: Sync failing?**  
A: 
1. Ensure both devices are on the same network
2. Try disabling firewall or VPN
3. Check if the device appears in the list
4. Try manually entering the other device's address

**Q: Device not discovered?**  
A:
1. Check if WiFi is connected to the same network
2. Some router settings might interfere with discovery
3. For iPhone/iPad (iOS): ensure local network permission is granted

### Privacy & Security

**Q: How to protect private notes?**  
A: 
1. Use hidden tags to mark sensitive notes
2. Enable biometric protection in preferences
3. Viewing hidden notes requires fingerprint/face verification

**Q: Where is data stored?**  
A:
1. All data stored locally, not auto-uploaded to cloud
2. AI features send note content to AI provider for processing
3. Your API Keys are saved safely on your device, not exported

### Other

**Q: How to completely delete app data?**  
A:
1. Use "Clear All Data" in settings
2. Or uninstall and reinstall the app

**Q: What devices are supported?**  
A: Android, iOS, Windows, macOS, Linux, Web (limited features)

</div>
