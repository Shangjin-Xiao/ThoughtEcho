# 心迹（ThoughtEcho）项目综合文档

## 1. 项目概述

### 1.1 项目定位
心迹（ThoughtEcho）是一款基于Flutter开发的本地优先笔记应用，专注于帮助用户捕捉思维火花，整理个人思考，并通过AI技术提供内容分析和智能洞察。应用采用本地存储优先策略，确保用户数据隐私和离线可用性。

### 1.2 核心理念
- **简洁高效**：专注于内容本身，简洁的界面设计，高效的操作流程
- **智能赋能**：AI辅助分析，提供内容洞察，增强笔记价值
- **个性化体验**：丰富的自定义选项，满足不同用户需求
- **数据安全**：本地优先存储，保障用户数据隐私

## 2. 需求文档

### 2.1 功能需求

#### 2.1.1 笔记管理
- **创建笔记**：支持多种方式添加笔记，包括手动输入、剪贴板导入和一言转存
- **编辑笔记**：内容编辑、标签添加、位置记录等全面的编辑功能
- **富文本支持**：基于FlutterQuill的富文本编辑器，支持格式化文本
- **笔记列表**：支持分页加载、多种排序方式和灵活的筛选条件
- **笔记搜索**：基于关键词的笔记内容搜索
- **笔记详情**：可折叠/展开的笔记卡片，查看完整内容和元数据

#### 2.1.2 分类与标签
- **分类管理**：创建、编辑和删除笔记分类
- **自定义图标**：为分类选择合适的图标
- **多标签关联**：一个笔记可以关联多个标签
- **标签筛选**：通过标签快速筛选笔记

#### 2.1.3 AI功能
- **内容分析**：分析笔记内容，提取关键词和摘要
- **情感识别**：识别笔记的情感倾向和语气
- **AI问答**：基于笔记内容的智能问答功能
- **文本润色**：提供文本润色和改写建议
- **智能续写**：基于现有内容智能续写功能
- **个性化设置**：可配置AI分析风格和参数

#### 2.1.4 环境感知
- **位置记录**：记录笔记创建时的地理位置
- **天气记录**：记录当前天气状况和温度
- **时间记录**：详细的时间戳记录
- **智能关联**：基于环境信息生成相关建议

#### 2.1.5 数据管理
- **数据备份**：导出笔记和设置到JSON文件
- **数据恢复**：从备份文件恢复数据
- **选择性导入**：合并导入或覆盖导入选项
- **紧急恢复**：数据库损坏时的应急恢复机制

#### 2.1.6 个性化
- **主题设置**：浅色/深色模式，可自定义主题颜色
- **动态颜色**：支持Material You动态颜色(Android 12+)
- **布局选项**：可调整列表视图和卡片样式
- **启动页设置**：可自定义默认启动页面

#### 2.1.7 智能助手
- **每日一言**：自动获取精选内容，提供灵感
- **智能提醒**：基于时间和位置的上下文提醒
- **剪贴板监控**：智能检测剪贴板文本并提供快速添加选项
- **智能建议**：根据用户习惯提供操作建议

### 2.2 非功能需求

#### 2.2.1 性能需求
- **响应速度**：界面操作响应时间不超过300ms
- **启动时间**：冷启动时间控制在3秒内
- **滚动流畅度**：列表滚动保持60fps以上
- **内存占用**：控制在合理范围内，避免内存泄漏

#### 2.2.2 可靠性
- **数据安全**：防止数据丢失，提供故障恢复机制
- **崩溃处理**：全局错误捕获，提供友好的错误信息
- **异常状态处理**：优雅处理网络异常、权限受限等特殊状态

#### 2.2.3 兼容性
- **平台支持**：Android、iOS和Web平台
- **设备适配**：支持手机、平板等不同屏幕尺寸设备
- **系统版本**：Android 5.0+、iOS 12.0+

## 3. 技术栈文档

### 3.1 核心技术栈

| 类别 | 技术/库 | 说明 |
|------|-------|------|
| 框架 | Flutter | 跨平台UI框架 |
| 编程语言 | Dart | Flutter开发语言 |
| 状态管理 | Provider | 轻量级状态管理方案 |
| 本地数据库 | sqflite | SQLite数据库的Flutter插件 |
| 数据库适配 | sqflite_common_ffi | 非移动平台的SQLite支持 |
| 数据库Web支持 | sqflite_common_ffi_web | Web平台的SQLite支持 |
| 路径管理 | path_provider | 文件系统路径获取 |
| UI组件 | flutter_markdown | Markdown渲染支持 |
| 网络请求 | http | HTTP请求处理 |
| 唯一标识符 | uuid | 生成唯一ID |
| 数据持久化 | shared_preferences | 键值对存储 |
| 本地存储加密 | flutter_secure_storage | 安全存储敏感信息 |
| URL处理 | url_launcher | 打开URL链接 |
| 文件选择 | file_selector | 文件选择器 |
| 内容分享 | share_plus | 分享功能 |
| 主题管理 | flex_color_scheme | 高级主题方案 |
| 动态颜色 | dynamic_color | Material You动态颜色 |
| 位置信息 | geolocator | 地理位置获取 |
| 地理编码 | geocoding, geocode | 地理位置编码与解码 |
| 权限管理 | permission_handler | 系统权限请求与管理 |
| 高性能存储 | mmkv | 高性能键值对存储 |
| 富文本编辑 | flutter_quill | 富文本编辑器 |
| 动画效果 | lottie | 复杂动画支持 |
| 加载动画 | flutter_spinkit | 加载指示器集合 |
| 矢量图形 | flutter_svg | SVG图像支持 |
| 颜色选择器 | flex_color_picker | 颜色选择组件 |

### 3.2 开发环境

| 类别 | 工具/版本 | 说明 |
|------|----------|------|
| SDK | Flutter 3.19+ | Flutter SDK |
| IDE | VS Code / Android Studio | 开发环境 |
| 调试工具 | Flutter DevTools | 性能分析和调试 |
| 版本控制 | Git | 源代码管理 |
| CI/CD | GitHub Actions | 自动化构建和测试 |

## 4. 系统架构与流程

### 4.1 系统架构

```
┌─────────────────────────────────────────────────────────────────┐
│                           表示层 (UI)                           │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐  ┌────────────┐ │
│  │   Pages    │  │  Widgets   │  │  Dialogs   │  │   Theme    │ │
│  └────────────┘  └────────────┘  └────────────┘  └────────────┘ │
└───────────────────────────────┬─────────────────────────────────┘
                                │
┌───────────────────────────────▼─────────────────────────────────┐
│                        业务逻辑层 (BLL)                         │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐  ┌────────────┐ │
│  │  Services  │  │ Controllers │  │  Providers │  │   Utils    │ │
│  └────────────┘  └────────────┘  └────────────┘  └────────────┘ │
└───────────────────────────────┬─────────────────────────────────┘
                                │
┌───────────────────────────────▼─────────────────────────────────┐
│                          数据层 (DAL)                           │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐  ┌────────────┐ │
│  │   Models   │  │ Repository │  │ Database   │  │  Storage   │ │
│  └────────────┘  └────────────┘  └────────────┘  └────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

### 4.2 数据模型

#### 笔记模型（Quote）
```dart
class Quote {
  String? id;            // 唯一标识符
  String content;        // 笔记内容
  String date;           // 创建日期
  String source;         // 来源
  String? sourceAuthor;  // 作者
  String? sourceWork;    // 作品名
  String? tagIds;        // 标签ID列表（逗号分隔）
  String? aiAnalysis;    // AI分析结果
  String? sentiment;     // 情感分析
  String? keywords;      // 关键词
  String? summary;       // 摘要
  String? categoryId;    // 分类ID
  String? colorHex;      // 颜色（十六进制）
  String? location;      // 位置
  String? weather;       // 天气
  String? temperature;   // 温度
}
```

#### 标签模型（NoteCategory）
```dart
class NoteCategory {
  String id;             // 唯一标识符
  String name;           // 分类名称
  bool isDefault;        // 是否为默认分类
  String iconName;       // 图标名称
}
```

### 4.3 数据库表结构

#### quotes表
```sql
CREATE TABLE quotes(
  id TEXT PRIMARY KEY,
  content TEXT NOT NULL,
  date TEXT NOT NULL,
  source TEXT,
  source_author TEXT,
  source_work TEXT,
  tag_ids TEXT DEFAULT "",
  ai_analysis TEXT,
  sentiment TEXT,
  keywords TEXT,
  summary TEXT,
  category_id TEXT,
  color_hex TEXT,
  location TEXT,
  weather TEXT,
  temperature TEXT
)
```

#### categories表
```sql
CREATE TABLE categories(
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  is_default INTEGER NOT NULL,
  icon_name TEXT NOT NULL
)
```

### 4.4 应用界面流程图

```
                             ┌─────────────┐
                             │   主应用    │
                             │  MyApp     │
                             └──────┬──────┘
                                    │
                                    ▼
                             ┌─────────────┐
                             │   首页     │
                             │  HomePage  │
                             └──────┬──────┘
                                    │
                   ┌────────────────┼───────────────┬───────────────────┐
                   │                │               │                   │
                   ▼                ▼               ▼                   ▼
         ┌──────────────┐    ┌─────────────┐    ┌─────────┐     ┌─────────────┐
         │  每日一言    │    │  笔记列表   │    │  AI页面 │     │  设置页面   │
         │DailyQuoteView│    │NoteListView │    │Insights │     │SettingsPage │
         └───────┬──────┘    └───────┬─────┘    │  Page   │     └──────┬──────┘
                 │                   │          └────┬────┘            │
                 │                   │               │                 │
                 ▼                   ▼               ▼                 │
         ┌──────────────┐    ┌─────────────┐    ┌─────────┐           │
         │  添加笔记    │    │  笔记详情   │    │ AI分析  │           │
         │AddNoteDialog │    │QuoteItemView│    │生成洞察 │           │
         └──────────────┘    └───────┬─────┘    └────┬────┘           │
                                     │               │                 │
                                     ▼               │                 ▼
                             ┌─────────────┐         │          ┌─────────────┐
                             │  编辑笔记   │         │          │  主题设置   │
                             │EditNotePage │         │          │ThemeSettings│
                             └─────────────┘         │          └──────┬──────┘
                                                     │                 │
                                                     ▼                 ▼
                                            ┌─────────────┐    ┌─────────────┐
                                            │  AI设置    │    │备份与恢复   │
                                            │AISettingsP │    │BackupRestore│
                                            └─────────────┘    └─────────────┘
```

### 4.5 核心功能流程

#### 4.5.1 笔记添加流程
```
用户发起添加笔记
  ├── 方式1: 点击添加按钮
  │   └── 打开AddNoteDialog
  ├── 方式2: 剪贴板监测
  │   ├── 检测到新内容
  │   ├── 显示提示
  │   └── 用户确认后打开AddNoteDialog(预填内容)
  └── 方式3: 从每日一言添加
      └── 直接添加一言内容为新笔记

AddNoteDialog
  ├── 输入笔记内容和元数据
  │   ├── 内容(必填)
  │   ├── 来源、作者、作品(可选)
  │   └── 选择分类/标签(可选)
  ├── 记录环境信息
  │   ├── 获取位置信息(如已授权)
  │   └── 获取天气信息(如可用)
  ├── 保存笔记
  │   ├── 生成唯一ID
  │   ├── 保存到数据库
  │   └── 更新笔记列表
  └── 可选的AI分析
      └── 调用AI服务分析笔记内容
```

#### 4.5.2 数据备份流程
```
备份流程
  ├── 用户请求备份
  ├── 生成备份文件
  │   ├── 查询所有笔记和分类数据
  │   ├── 转换为JSON格式
  │   ├── 添加版本信息和时间戳
  │   └── 写入文件
  └── 导出备份文件
      ├── 方式1: 保存到本地文件系统
      └── 方式2: 分享到其他应用

恢复流程
  ├── 用户选择备份文件
  ├── 验证备份文件格式和版本
  ├── 选择恢复方式
  │   ├── 清空并恢复: 删除现有数据后导入
  │   └── 合并导入: 与现有数据合并
  ├── 执行数据导入
  │   ├── 导入分类数据
  │   ├── 导入笔记数据
  │   └── 处理冲突(如有)
  └── 重新加载应用数据
```

#### 4.5.3 AI功能流程
```
AI分析流程
  ├── 用户请求AI分析
  ├── 检查AI设置
  │   ├── 已配置API Key -> 继续
  │   └── 未配置 -> 提示配置AI设置
  ├── 准备分析请求
  │   ├── 选择分析类型(情感/关键词/摘要)
  │   ├── 构建提示词
  │   └── 收集笔记内容
  ├── 发送API请求
  │   ├── 显示加载状态
  │   ├── 处理请求超时和错误
  │   └── 接收API响应
  └── 处理分析结果
      ├── 解析响应数据
      ├── 保存分析结果到笔记
      └── 显示分析内容
```

## 5. 设计指南

### 5.1 设计原则

- **简洁至上**：减少视觉噪音，专注于内容展示
- **一致性**：保持视觉和交互的一致性，降低用户学习成本
- **反馈性**：所有操作提供及时明确的反馈
- **可访问性**：支持辅助功能，确保多样性用户可用
- **沉浸感**：提供沉浸式的内容创作和阅读体验

### 5.2 色彩系统

#### 5.2.1 浅色主题
```
--primary-color: #1976D2;
--primary-light: #BBDEFB;
--primary-dark: #0D47A1;
--accent-color: #FF4081;
--secondary-color: #49454F;
--background-color: #F8FAFD;
--surface-color: #FFFFFF;
--error-color: #B3261E;
--text-primary: #1C1B1F;
--text-secondary: #49454F;
--border-color: #E7E0EC;
```

#### 5.2.2 深色主题
```
--primary-color: #90CAF9;
--primary-light: #E3F2FD;
--primary-dark: #42A5F5;
--accent-color: #FF80AB;
--secondary-color: #CCC2DC;
--background-color: #121212;
--surface-color: #1E1E1E;
--error-color: #F2B8B5;
--text-primary: #E6E1E5;
--text-secondary: #CAC4D0;
--border-color: #49454F;
```

### 5.3 组件规范

#### 5.3.1 笔记卡片
- 圆角: 16px
- 内边距: 16px
- 阴影: 小型浮动阴影
- 展开/折叠动画: 300ms缓动

#### 5.3.2 按钮样式
- 主按钮: 填充背景+白色文字
- 次按钮: 轮廓边框+主色文字
- 文本按钮: 仅文字无背景
- 按钮高度: 48px
- 圆角: 24px

#### 5.3.3 输入框
- 样式: Material 3 轮廓输入框
- 高度: 56px
- 标签: 浮动标签
- 错误提示: 底部红色文字

## 6. 项目文件结构

```
lib/
├── main.dart                 # 应用入口点
├── models/                   # 数据模型
│   ├── ai_settings.dart      # AI设置模型
│   ├── app_settings.dart     # 应用设置模型
│   ├── note_category.dart    # 笔记分类/标签模型
│   └── quote_model.dart      # 笔记模型
├── pages/                    # 页面组件
│   ├── ai_settings_page.dart # AI设置页面
│   ├── backup_restore_page.dart   # 备份恢复页面
│   ├── category_settings_page.dart # 分类管理页面
│   ├── edit_page.dart        # 编辑页面
│   ├── hitokoto_settings_page.dart # 一言设置页面
│   ├── home_page.dart        # 主页
│   ├── insights_page.dart    # AI洞察页面
│   ├── logs_page.dart        # 日志页面
│   ├── note_full_editor_page.dart # 全屏编辑器
│   ├── settings_page.dart    # 设置页面
│   └── theme_settings_page.dart # 主题设置页面
├── services/                 # 服务类
│   ├── ai_service.dart       # AI服务
│   ├── api_service.dart      # API服务
│   ├── clipboard_service.dart # 剪贴板服务
│   ├── database_service.dart # 数据库服务
│   ├── location_service.dart # 位置服务
│   ├── log_service.dart      # 日志服务
│   ├── mmkv_service.dart     # 高性能存储服务
│   ├── secure_storage_service.dart # 安全存储服务
│   ├── settings_service.dart # 设置服务
│   └── weather_service.dart  # 天气服务
├── theme/                    # 主题相关
│   └── app_theme.dart        # 应用主题定义
├── utils/                    # 工具类
│   ├── color_utils.dart      # 颜色工具
│   ├── http_utils.dart       # HTTP请求工具
│   ├── icon_utils.dart       # 图标工具
│   ├── mmkv_adapter.dart     # MMKV适配器
│   └── string_utils.dart     # 字符串工具
└── widgets/                  # UI组件
    ├── add_note_dialog.dart  # 添加笔记对话框
    ├── app_empty_view.dart   # 空状态组件
    ├── app_loading_view.dart # 加载状态组件
    ├── daily_quote_view.dart # 每日一言组件
    ├── hitokoto_widget.dart  # 一言展示组件
    ├── note_filter_sort_sheet.dart # 笔记筛选排序表单
    ├── note_list_view.dart   # 笔记列表组件
    ├── quote_card.dart       # 笔记卡片组件
    └── weather_widget.dart   # 天气展示组件
```

## 7. 路线图

### 7.1 近期计划（1-3个月）
- 优化富文本编辑器体验
- 完善AI分析功能
- 提升数据库性能
- 增强备份恢复功能
- 改进错误处理和日志系统

### 7.2 中期计划（3-6个月）
- **自然语言搜索功能**：实现基于AI的语义搜索，支持自然语言查询笔记
- **周期性智能报告**：自动生成周报、月报、年报，提供个人思考模式和成长洞察
- 增加数据可视化功能
- 添加基于时间的笔记回顾功能
- 完善跨平台体验
- 增加更多AI模型支持
- 优化大数据量下的应用性能

### 7.3 长期愿景（6个月以上）
- 探索选择性云同步功能
- 添加端到端加密支持
- 增加笔记间的关联和链接功能
- 扩展到更多平台
- 考虑协作功能
- **高级分析仪表板**：提供更深入的个人数据分析和可视化
- **智能写作助手**：基于个人写作风格的AI写作建议和改进

## 8. 开发指南

### 8.1 代码风格与约定
- 遵循Dart官方代码风格指南
- 使用flutter_lints包确保代码质量
- 类和方法添加文档注释
- 使用Provider进行状态管理

### 8.2 Git工作流
- 主分支: `main` - 保持稳定可发布状态
- 开发分支: `develop` - 最新开发进度
- 功能分支: `feature/xxx` - 新功能开发
- 修复分支: `bugfix/xxx` - 问题修复
- 发布分支: `release/vX.X.X` - 版本发布准备

### 8.3 版本命名约定
- 主版本: 重大功能变更或架构调整
- 次版本: 新功能添加
- 补丁版本: 错误修复和小改进
- 例如: v1.2.3

### 8.4 关键API参考
- 数据库操作: `DatabaseService`
- 设置管理: `SettingsService`, `MMKVService`
- AI功能: `AIService`
- 位置与天气: `LocationService`, `WeatherService`
- 系统交互: `ClipboardService`

## 9. 每日一言多语言 API 规划（2026-03）

### 9.1 目标与约束
- 在不大改现有“每日一言”架构的前提下，为应用增加中文之外的 quote provider 支持。
- 保留现有 `hitokotoType`、默认分类/默认标签、双击保存、离线回退和本地“每日一言”逻辑。
- 统一继续输出当前 UI 和保存流程已依赖的数据结构：
  - `content`
  - `source`
  - `author`
  - `type`
  - `from_who`
  - `from`

### 9.2 现有实现中的关键耦合点
- `lib/services/api_service.dart` 当前直接绑定 Hitokoto，并将响应归一化为兼容结构。
- `lib/models/app_settings.dart` 使用 `hitokotoType` 保存逗号分隔的内部类型码。
- `lib/pages/home_page.dart` 和 `lib/widgets/add_note_dialog.dart` 会根据 `type` 把每日一言保存到固定默认分类 ID。
- `lib/services/database_service.dart` 初始化固定默认分类；`lib/services/database_health_service.dart` 的本地回退还依赖分类名 `每日一言`。
- `lib/widgets/daily_quote_view.dart` 默认按 `——作者 《出处》` 渲染来源，所以新的 provider 最好至少返回作者，出处没有时要允许空值优雅降级。

### 9.3 候选 API 对比

| Provider | 语言/范围 | 随机能力 | 分类/标签过滤 | 关键字段 | 鉴权 | 大陆可用性判断 | 适配结论 |
|---|---|---|---|---|---|---|---|
| Hitokoto | 中文为主 | 强 | 强，`c=` 多分类 | `hitokoto/from/from_who/type` | 无 | 最优 | 继续作为中文默认源 |
| Quotable | 英文 | 强，`/quotes/random` | 强，`tags/author/length` | `content/author/tags[]` | 无 | `.io` 存在不稳定风险 | 最适合做首个英文公共 provider |
| API Ninjas Quotes | 英文 | 强，`/v2/randomquotes` | 强，`categories/author/work` | `quote/author/work/categories[]` | `X-Api-Key` | 海外商业服务，需实机验证 | 最完整英文增强源 |
| TheySaidSo | 英文为主，QOD 场景强 | 有，但随机/搜索多为私有能力 | 有，QOD 分类 + 搜索分类/作者/长度 | `quote/author/tags/category/language/date/permalink` | QOD 文档称可公开限流；随机/搜索依赖 Key | 海外服务；当前环境直连 `qod/random/search` 均 401 | 适合“Quote of the Day”可选源，不适合首发默认替代 |
| Forismatic | 英/俄 | 有 | 弱 | `quoteText/quoteAuthor` | 无 | 海外服务，稳定性一般 | 可做实验性语言源，但不适合默认标签体系 |
| Animechan | 动漫台词 | 强 | 按 `anime/character` | `quote/anime/character` | 无 | 海外服务 | 适合作为动漫垂直 provider，不是通用多语言方案 |
| FavQs / ZenQuotes / DummyJSON | 英文或样例数据 | 有 | 较弱 | 多数只有 quote + author + tags/分类片段 | 多数无或能力受限 | 海外服务 | 可作补充候选，不宜作为主方案 |

### 9.4 TheySaidSo 详细判断
- 官方文档：`https://theysaidso.com/api/?shell`
- 文档能力：
  - `GET /qod(.json)`：按 `category` 获取每日一句
  - `GET /qod/categories.json`：获取 QOD 分类
  - `GET /quote/random.json`：随机 quote
  - `GET /quote/search.json`：按 `category`、`author`、`minlength`、`maxlength` 检索
- 官方文档示例返回：
  - `quote`
  - `author`
  - `tags[]`
  - `category`
  - `language`
  - `date`
  - `permalink`
  - `id`
  - `background`
  - `title`
- 优势：
  - 比普通 quotes API 更像“内容平台”，带有 QOD 分类、图片背景和 permalink。
  - 如果后续想要做“今天固定一句 + 配图分享”，扩展潜力不错。
- 问题：
  - 没有 `work/source` 字段，不如 API Ninjas 贴合当前 UI 的出处展示。
  - 文档明确提醒公共客户端不要直接暴露 API Key；对于 Web 端尤其不友好。
  - 免费公开限流低（文档写 10 次/小时），随机/搜索能力更依赖 API Key。
  - 当前环境直连 `https://quotes.rest/qod?category=inspire`、`/quote/random.json`、`/quote/search.json` 都返回 `401`，因此实际接入前必须再做真实终端验证。
- 结论：
  - **如果目标是“固定的 Quote of the Day”**，TheySaidSo 值得保留为可选 provider。
  - **如果目标是“尽量贴近现在可刷新、可随机、无感切换的一言体验”**，它优先级低于 Quotable 和 API Ninjas。

### 9.5 实现多 provider 的三种方案

#### 方案 A：最小改动的 provider 适配层（推荐）
1. 在设置中新增 `dailyQuoteProvider`、`dailyQuoteLanguage`（或 `dailyQuoteLocale`）。
2. 保留 `hitokotoType` 作为应用内部稳定分类码。
3. 在 `ApiService` 前增加 provider adapter，将各家响应归一化为当前结构。
4. 当第三方不支持分类或缺少出处时，用内部默认映射兜底。

**优点**
- 改动面最小。
- 不破坏默认标签设计。
- `home_page.dart` / `add_note_dialog.dart` 基本可不动。

**缺点**
- 需要维护 provider 能力差异映射。

#### 方案 B：能力驱动的 provider 配置层
1. 为每个 provider 定义能力描述：是否支持随机、QOD、分类、作者过滤、出处字段、API Key。
2. 设置页根据 provider 能力动态展示可用选项。
3. 请求层根据能力降级。

**优点**
- 可扩展性好，后续接更多 provider 时更清晰。

**缺点**
- UI 和设置逻辑改动比方案 A 略大。

#### 方案 C：统一后端/自托管聚合层
1. 服务端统一接多个外部 provider。
2. 客户端永远请求自己的统一接口。
3. 在服务端处理 API Key、速率限制、缓存与大陆可达性。

**优点**
- 线上可控性最佳。
- 对大陆访问和第三方 API 波动最友好。

**缺点**
- 明显超出当前“少改设计”的范围。
- 需要额外部署和维护成本。

### 9.6 推荐路线
1. **第一阶段**：继续保留 Hitokoto，新增 Quotable 作为首个英文公共 provider。
2. **第二阶段**：新增 API Ninjas 作为“更完整但需要 Key”的英文增强 provider。
3. **第三阶段**：如果产品要强调“每日固定一句”或配图分享，再新增 TheySaidSo 作为可选 QOD provider。
4. **第四阶段**：视大陆访问和稳定性情况，预留自托管/镜像能力。

### 9.7 推荐的内部映射原则
- 不把第三方原始 tag/category 直接写入 `type`。
- `type` 始终映射回应用内部稳定类型码（优先沿用 `a-k/l`）。
- 无法可靠映射时，回退到用户当前已选类型中的首个类型码。

示例：
- Hitokoto：继续用原始 `type`
- Quotable：`philosophy/wisdom -> k`，`poetry -> i`，其他无法稳定映射时回退
- API Ninjas：`philosophy -> k`，`art/writing -> d`，`humor -> l`
- TheySaidSo：`inspire/life/management/funny` 等先映射到最接近的内部类型；若无法稳定映射则回退到首选类型码
- Animechan：固定映射 `a`

### 9.8 预计改动面
**需要改动**
- `lib/models/app_settings.dart`
- `lib/services/settings_service.dart`
- `lib/services/api_service.dart`
- `lib/pages/hitokoto_settings_page.dart`
- `lib/l10n/app_zh.arb`
- `lib/l10n/app_en.arb`

**尽量不动**
- `lib/pages/home_page.dart`
- `lib/widgets/add_note_dialog.dart`
- `lib/services/database_service.dart`
- `lib/services/database_health_service.dart`

### 9.9 测试与验收重点
- 各 provider 响应的统一归一化测试
- 类型码映射测试
- provider 失败 -> 本地笔记 -> 默认文案的回退链测试
- 设置迁移测试，确保不破坏现有 `hitokotoType`
- 双击每日一言保存后的默认分类/默认标签落库回归测试
