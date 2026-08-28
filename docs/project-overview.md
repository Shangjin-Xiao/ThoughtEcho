# 心迹（ThoughtEcho）项目综合文档

> **2026-08 架构审计与对齐说明**：本文档已依据当前 `lib/` 源码架构、`AGENTS.md` 规范与最新事实源全面核验对齐（Windows/Android/iOS 多端支持，排除 Web 平台，主干开发流程）。
> 准确信息以代码、`AGENTS.md`、`docs/INDEX.md` 及各专题交接文档为准。

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
- **平台支持**：Windows、Android、iOS（**明确不支持 Web**。不要新增 Web 入口、Web 专用实现、Web 构建或 Web 测试；仓库中现存的 `kIsWeb`、`*_web.dart` 和 Web 依赖属于历史兼容代码，不代表支持 Web）
- **设备适配**：支持手机、平板、桌面多窗口等不同屏幕尺寸与形态设备
- **系统版本**：Android 5.0+、iOS 12.0+、Windows 10+

## 3. 技术栈文档

### 3.1 核心技术栈

| 类别 | 技术/库 | 说明 |
|------|-------|------|
| 框架 | Flutter | 跨平台UI框架（Flutter 3.x） |
| 编程语言 | Dart | Flutter开发语言（Dart 3.x） |
| 状态管理 | Provider | 页面级状态与服务依赖注入 |
| 本地数据库 | sqflite / sqflite_common_ffi | 移动端 SQLite / Windows 桌面端 FFI SQLite |
| SQLite 原生库 | sqlite3_flutter_libs | 平台原生 SQLite 动态库 |
| 路径管理 | path_provider | 文件系统路径获取与跨平台目录适配 |
| UI组件 | flutter_markdown_plus | Markdown 渲染支持 |
| 网络请求 | dio / http | RESTful 请求、LocalSend 通信与 WebDAV 云同步 |
| AI 客户端 | openai_dart | 多模型 OpenAI 协议适配与流式生成 |
| 唯一标识符 | uuid | 生成唯一ID |
| 数据持久化 | shared_preferences | 基础配置键值对存储 |
| 本地存储加密 | flutter_secure_storage | 安全存储 API Key 及敏感信息 |
| URL处理 | url_launcher | 打开外部 URL 链接 |
| 文件选择与分享 | file_picker / file_selector / share_plus | 多平台安全文件选择与系统分享 |
| 主题管理 | flex_color_scheme | M3 动态取色与多风格主题 |
| 主题扩展与形状 | AppShapeTokens / ThemeStyleForm | 纸墨/素笺/Material 主题风格与动态圆角/行高/字阶 |
| 动态颜色 | dynamic_color | Android 12+ Material You 动态取色 |
| 位置与天气 | geolocator / geocoding | 地理位置获取与原生反向地理编码 |
| 权限管理 | permission_handler | 运行时系统权限请求与状态管理 |
| 高性能存储 | mmkv | 高性能键值对存储（支持 32 位设备回退） |
| 富文本编辑 | flutter_quill | 富文本编辑器（Quill Delta JSON） |
| 列表分页 | infinite_scroll_pagination | 笔记列表高性能流式分页 |
| 动画与视觉 | lottie / flutter_svg | Lottie 动画与 SVG 矢量图渲染 |
| 媒体与音频 | video_player / chewie / audioplayers / photo_view | 多媒体预览与播放 |
| 导出与打印 | pdf / printing | A4 / 便签纸 PDF 导出与打印支持 |
| 错误监控 | sentry_flutter / sentry_dio / sentry_sqflite | Sentry 异常与网络性能追踪 |
| 本地搜索与提取 | ddgs / html2md / html | 联网搜索辅助与网页提炼工具 |
| 硬件交互 | flutter_blue_plus | BLE 蓝牙通信（墨水屏/Pico 设备联动） |

> **注**：`sqflite_common_ffi_web` 等 Web 相关包在依赖中仅作历史兼容保留，Web 端并非支持平台。

### 3.2 开发环境

| 类别 | 工具/版本 | 说明 |
|------|----------|------|
| SDK | Flutter 3.29+ / Dart 3.5+ | Flutter 与 Dart SDK，依赖 Impeller 渲染与现代排版特性 |
| IDE | VS Code / Android Studio | 主力开发环境 |
| 调试工具 | Flutter DevTools | 性能分析与内存调试 |
| 版本控制 | Git (Trunk-based) | 基于主干的轻量开发工作流 |
| CI/CD | GitHub Actions | 自动化分片静态分析、单元测试与跨平台打包 |

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

## 6. 项目文件结构

```
lib/
├── main.dart                 # 应用入口点与服务 Provider 注入
├── controllers/              # 页面级 UI 状态与交互编排控制器
├── models/                   # 领域模型、持久化与传输对象
│   ├── ai_settings.dart      # AI Provider 配置模型
│   ├── app_settings.dart     # 应用全局设置模型
│   ├── note_category.dart    # 笔记分类/标签模型（NoteTag）
│   ├── quote_model.dart      # 笔记核心模型（Quote，含纯文本与 Quill Delta）
│   ├── rich_text_edit.dart   # 原生富文本结构化编辑模型
│   └── merge_report.dart     # 同步与合并报告模型
├── pages/                    # 页面组件与子模块
│   ├── thoughter/            # Thoughter 智能体对话与工作流页面（7 个 part 拆分）
│   ├── note_editor/          # 笔记全屏富文本编辑模块（10 个 part 拆分）
│   ├── explore/              # 探索与灵感统计聚合模块（5 个 part 拆分）
│   ├── home_page.dart        # 应用主页
│   ├── settings_page.dart    # 系统设置与各功能入口
│   ├── note_sync_page.dart   # LocalSend 局域网同步页面
│   ├── webdav_sync_page.dart # WebDAV 云同步页面
│   ├── logs_page.dart        # 日志查看页面
│   ├── trash_page.dart       # 回收站页面
│   └── theme_settings_page.dart # 主题设置页面
├── services/                 # 业务逻辑与数据持久化服务
│   ├── database/             # 数据库模块化拆分（12 个 mixin）
│   ├── database_service.dart # 数据库服务门面
│   ├── database_schema_manager.dart # 数据库建表与迁移真源
│   ├── agent_memory_service.dart # Thoughter 长期记忆独立库（agent_memory.db）
│   ├── note_sync_service.dart# LocalSend 局域网同步编排服务
│   ├── webdav_service.dart   # WebDAV 云同步服务
│   ├── smart_push/           # 智能推送模块（6 个 part 拆分）
│   ├── smart_push_service.dart # 智能推送调度服务
│   ├── backup_service.dart   # 数据备份与恢复服务
│   ├── unified_log_service.dart # 统一日志记录服务
│   ├── settings_service.dart # 系统设置服务
│   └── location_service.dart # 地理位置服务
├── theme/                    # 主题与排版令牌
│   ├── app_theme.dart        # 主题构建与 FlexColorScheme 配置
│   ├── app_shape_tokens.dart # 形状与排版令牌（圆角、横线间距等 ThemeExtension）
│   ├── app_semantic_colors.dart # 语义状态颜色扩展
│   └── theme_style.dart      # 主题风格枚举（material/paper/plain）与表单配置
├── utils/                    # 基础与通用工具库
│   ├── quill_structured_edit.dart # Quill Delta 结构化无损编辑
│   ├── ai_smart_result_utils.dart # AI 智能结果元数据裁决
│   ├── large_file_manager.dart    # 大文件与大 JSON 流式处理
│   └── icon_utils.dart       # 图标映射与渲染工具
└── widgets/                  # 可复用 UI 视图组件
    ├── note_list/            # 笔记列表高性能自绘（4 个 part + 1 个辅助文件）
    ├── note_list_view.dart   # 笔记列表视图容器
    ├── ai/                   # AI 提议卡片（NoteProposalCard）与工具视图
    ├── add_note_dialog.dart  # 笔记快速新增弹窗
    └── app_snackbar.dart     # 统一语义 SnackBar
```

## 7. 路线图

### 7.1 已实现能力
- **Thoughter 智能体**：多 Provider 接入、原生富文本结构化编辑与草稿卡片提议
- **长期记忆体系**：物理隔离独立库 `agent_memory.db`、画像包裹与原位覆盖
- **多端同步与备份**：LocalSend 局域网增量媒体同步、WebDAV 云同步与流式 ZIP 备份
- **极致排版与主题**：三套完整主题风格（纸墨、素笺、Material 3）与 `AppShapeTokens` 令牌化
- **极致性能自绘**：折叠卡片纯自绘 `CollapsedRichText`，彻底剔除折叠态 Quill 实例

### 7.2 后续规划
- 增加更多模型与本地离线 LLM（Ollama 等）交互优化
- 进一步优化大数据量下的大规模全文检索
- 扩展硬件联动（如 BLE 墨水屏、外接微控制器展示）

## 8. 开发指南

### 8.1 代码风格与约定
- 遵循 `analysis_options.yaml` 与 `dart format`
- 公共 API 编写清晰的 `///` 文档注释
- 可观察应用状态使用 `ChangeNotifier` 并通过 Provider 注入
- 严守 `AGENTS.md` 架构与 UI 约束（无硬编码 Material 命名色、通过 `AppShapeTokens` 取圆角）

### 8.2 Git工作流
- **主干开发（Trunk-based Development）**：日常功能开发与缺陷修复直接提交至 `main` 主干分支，不使用冗余复杂的 `develop` / `feature` / `release` 多分支流程。
- **CI 自动化门禁**：每次提交与合并由 GitHub Actions 分目录执行静态分析（`flutter analyze --no-fatal-infos`）和自动化测试套件。
- **发布自动化**：通过 CI 与平台打包脚本（如 `./scripts/build_ios_unsigned.sh`、`pwsh ./scripts/build_msix_ci.ps1`）编译产出 Android、iOS 及 Windows 正式发布包。

### 8.3 版本命名约定
- 遵循语义化版本号（Semantic Versioning）：`v主版本.次版本.修订号`（如 `v3.7.0`、`v4.0.0`）

### 8.4 关键API参考
- 数据库与存储: `DatabaseService`、`DatabaseSchemaManager`、`MMKVService`、`LargeFileManager`
- AI 智能体与长期记忆: `ThoughterPage`、`AgentMemoryService` (独立库 `agent_memory.db`)、`OpenAIStreamService`、`QuillStructuredEdit`
- 数据同步与备份: `NoteSyncService` (LocalSend 局域网)、`WebDavService` (WebDAV 云同步)、`BackupService`
- 状态与设置: `SettingsService`、`AppShapeTokens`、`UnifiedLogService`
- 环境与外设: `LocationService`、`WeatherService`、`ClipboardService`、`BlePicoManager`

---

## 8.5 知识库与规范索引

关于各专项能力的权威设计事实源与历史推导过程，请查阅知识库总索引 [`docs/INDEX.md`](INDEX.md)：
- **主题系统与排版事实源**：[`docs/paper-ink-theme-handoff-2026-07-31.md`](paper-ink-theme-handoff-2026-07-31.md)
- **Thoughter 记忆体系事实源**：[`docs/agent-memory-research-2026-08-08.md`](agent-memory-research-2026-08-08.md)
- **列表滚动与首绘性能事实源**：[`docs/note-list-warmup-invalidation-2026-08-22.md`](note-list-warmup-invalidation-2026-08-22.md)
- **同步与备份安全审计事实源**：[`docs/WebDAV_LocalSend_Backup_Code_Audit_and_Refactoring_Report.md`](WebDAV_LocalSend_Backup_Code_Audit_and_Refactoring_Report.md)
- **架构决议真源**：[`docs/decisions.md`](decisions.md)
