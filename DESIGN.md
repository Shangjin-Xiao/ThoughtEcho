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

> **取值真源在代码里，不在这份文档里。** 下面出现的数值是为了讲清设计意图，
> 真正生效的是 `lib/theme/theme_style.dart` 的常量。两者冲突时以代码为准，
> 并回来修这份文档。禁止把这里的数值抄成 widget 里的字面量——具体禁令见
> `AGENTS.md` 的「UI 硬性约束」。

### 5.1 设计原则

- **简洁至上**：减少视觉噪音，专注于内容展示
- **一致性**：保持视觉和交互的一致性，降低用户学习成本
- **反馈性**：所有操作提供及时明确的反馈
- **可访问性**：支持辅助功能，确保多样性用户可用
- **沉浸感**：提供沉浸式的内容创作和阅读体验
- **纸感优先于拟物**：品牌观感靠色温、行高、发丝边框这些**排版层面**的选择建立，
  不靠贴纸纹图片、翻页动效或投影堆叠。唯一的纹理破例是纸张横线（见 5.4）。

### 5.2 主题风格维度

主题风格是**和亮暗、动态取色并列的第三个维度**，不是配色预设。三选一：

| 风格 | 气质 | 色板来源 | 卡片圆角 | 层次手段 | 正文字体 | 正文行高 |
| --- | --- | --- | --- | --- | --- | --- |
| `material` | 系统观感 | 动态取色 / 用户 seed | 18 | 投影 | 系统默认（黑体） | 1.5 |
| `paper` 纸与墨 | 暖、温润 | 手工色板 | 6 | 发丝边框 + 极淡投影 | 系统衬线 | 1.75 |
| `plain` 素笺 | 冷、硬朗 | 手工色板 | 3 | 同上，更硬 | 系统衬线 | 1.6 |

**默认是 `paper`**（`ThemeStyle.defaultStyle`）。Material 是"想要系统观感"时的退路，
不是基准。老用户升级后外观直接变，由升级引导页告知可切回。

架构上只有一条铁律：**品牌差异全部通过令牌取值表达，widget 里绝不写
`if (style == ThemeStyle.paper)`。** 连"用边框还是用投影"的判据都是 `borderWidth > 0`
这个取值，不是风格身份。加第四套风格 = 新增两组常量并登记，不碰构建逻辑、不碰任何 widget。

### 5.3 色彩系统

**不存在一张全局色值表**——Material 风格的颜色由取色算法运行时生成，写死任何十六进制
色值都会和它冲突。页面取色一律走 `Theme.of(context).colorScheme`。

手工色板（`ThemeStylePalette`）按**纸与墨的语汇**定义角色，再映射到 `ColorScheme`：

| 角色 | 含义 | 映射到 |
| --- | --- | --- |
| `background` | 页面底色（纸） | `surface`、`surfaceContainer` |
| `card` | 卡片底色，比页面**更亮** | `surfaceContainerLowest`、`surfaceBright` |
| `ink` / `inkMuted` | 正文墨色 / 次要墨色 | `onSurface` / `onSurfaceVariant` |
| `outline` | 常规发丝边框，也是**纸张横线的颜色** | `outlineVariant` |
| `outlineStrong` | 强调边框 | `outline` |
| `accent` | 强调色 | `primary`、`surfaceTint` |

注意最后两行是**交叉映射**：色板里叫 `outline` 的角色落到 `ColorScheme.outlineVariant`，
`outlineStrong` 才是 `ColorScheme.outline`（M3 的 outline 比 outlineVariant 更重）。
画纸张横线时取的是 `colorScheme.outlineVariant`。

两处刻意偏离 M3 规范，改动前先读注释：

- **卡片色不落在 M3 的 surfaceContainer 梯度上**：两套手工色板都让卡片比页面底色更亮
  （纸叠在桌面上，暗色模式同理），而 M3 暗色下期望 `surfaceContainerLowest` 最暗。
  测试校验的是"卡片比底色亮且可区分"，不是 M3 的梯度假设。
- **手工色板不能喂给 seed 生成器**：亮色路径必须按风格关掉 `keyColors` 和表面混合，
  否则 FlexColorScheme 会拿 primary 当种子把整套色调重新推导掉。

语义状态色（成功/警告/收藏）走 `AppSemanticColors` 这个 `ThemeExtension`，
不用 `Colors.green` 一类的 Material 命名色——它们不随取色变化，换主题色后会突兀。

**改色板必须先过 `test/theme/theme_style_contrast_test.dart`**（WCAG AA + 令牌不变量）。
原始设计稿有多处不达 AA，已按验算收紧。

### 5.4 形状、层次与纹理

形状令牌由 `AppShapeTokens` 这个 `ThemeExtension` 下发，widget 读
`AppShapeTokens.of(context).cardRadius`：

- 圆角五档：`cardRadius` / `dialogRadius` / `buttonRadius` / `inputRadius` / `fabRadius`。
  FAB 单独一档不是遗漏——M3 里 FAB 圆角本就独立于卡片和按钮。
- **层次二选一，由 `borderWidth` 决定**：Material 用投影，手工风格用发丝边框 +
  近乎为零的投影。纸是叠在桌上的，不是浮起来的。
- 投影四档（`restShadow` / `lowShadow` / `raisedShadow` / `accentShadow`）由
  `shadowOpacity` 和 `shadowBlur` 按固定比例推导，风格一变自动跟着压扁。
- **纸张横线**是唯一的纹理破例（令牌表达不了纹理本身），但"画不画、多密、多淡"仍是
  令牌取值：`ruleSpacing` 为 0 就不插入任何绘制层。只用在笔记卡片和每日一言卡两处，
  不要铺开。**素笺刻意不画横线**——"素"就是素的。

### 5.5 排版

字体、行高、字重是这套主题里辨识度最高的部分，比颜色更能拉开风格差距。

- **字体走零字节路线**：手工风格的首选族名是**通用族 `serif`**，具名字体
  （Songti SC / SimSun 等）留在回退链里。顺序不能调换——Flutter 的
  `fontFamilyFallback` 不是 CSS 的 font-family，只有首选族名就是 `serif` 时，
  Android 才会命中 AOSP 给 NotoSerifCJK 标的 `fallbackFor="serif"`。
  代价是各家 ROM 的衬线体长相不一致，要统一只能打包子集化字体。
- **行高由 `bodyLineHeight` 令牌下发**，只作用于 `body*` 三级。中文衬线体字面率高、
  笔画密，M3 给黑体调的 1.5 偏挤。**纸张横线间距是从正文行高推导的**——写死会让
  文字逐行相对横线漂移，卡片看起来像背了一张格子图。
- **字重补偿是给黑体的**：Android 上 Impeller 精准映射 wght 轴后 Roboto 偏粗，
  正文压到 350 还原视觉。衬线体横画本就细，再减就发灰发虚，所以手工风格用
  `variableWeightCompensation: 0` 关掉它。
- **富文本是独立的一条路**：quill 的段落基准样式不继承 `textTheme`
  （`fontSize` / `height` 被硬写成 16 / 1.15），需要在
  `quote_content_widget.dart` 单独注入，才能和纯文本、横线间距对齐。
- ❌ **不用斜体做 UI 装饰**：中文字体没有真斜体字形，Flutter 会做合成倾斜，
  小字号下明显发虚。要弱化层次用 `onSurfaceVariant` + 字号或字重差。
  用户在编辑器里手动标记的斜体是内容格式，必须保留。
- 间距用 4 的倍数（4/8/12/16/24/32）。

### 5.6 组件规范

**一律优先复用现成组件**，不要另搓一套——同屏时圆角和高光会对不齐：
`Card`（已配好 `cardTheme`）、`AppSnackBar`、`AppLoadingView` / `AppEmptyView` /
`AppErrorView`。

- **笔记卡片**：圆角随风格（18 / 6 / 3），展开折叠 170ms、淡入 130ms。
  卡片增删动画的不变量锁在 `test/widget/note_item_motion_test.dart`——
  反复复发的问题是"包装层进出树 + `Align` 放松宽度约束"，不是曲线时长。
- **按钮**：主按钮填充、次按钮轮廓、文本按钮无背景；圆角读 `buttonRadius`。
- **输入框**：M3 轮廓输入框 + 浮动标签，圆角读 `inputRadius`。
  **`OutlineInputBorder` 不能删**——项目未设置 `inputDecoratorBorderType`，
  FlexColorScheme 该参数默认是 `underline`，删掉会变成下划线输入框。

### 5.7 明确否决过的方向

不要重新提案，除非有新的理由：

- **渐变背景、多层 `RadialGradient` 光晕、"大数字 + 小标签 + 渐变强调色"的统计卡**——
  AI 生成设计的通用模板，与本项目气质无关。视觉重点靠留白、字号层级和单一强调色。
- **便签纸色**（按标签给卡片自动上色）——和用户已有的单条笔记手动配色
  （`quote.colorHex`）打架。
- **打包字体**——目前走零字节路线；真机观察到各 ROM 差异不可接受时才启用，
  方案（Noto Serif SC 可变字体子集，保留 wght 轴）已写在交接文档里。

> 主题相关的完整设计推导、色板沿革和踩过的坑见
> `docs/paper-ink-theme-handoff-2026-07-31.md`，那是**唯一事实来源**，动主题前先读。

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

