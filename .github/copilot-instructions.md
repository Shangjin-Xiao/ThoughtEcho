# 心迹（ThoughtEcho）开发指南

## 项目概述

心迹（ThoughtEcho）是一款基于Flutter开发的本地优先笔记应用，专注于捕捉思维火花、整理个人思考，并通过AI技术提供内容分析和智能洞察。采用本地存储优先策略，确保用户数据隐私和离线可用性。

要求：在响应用户进行代码更改时，请务必使用最佳实现，并且注意程序原有逻辑，不要引入重复代码，不要简单问题复杂化，如果必要可以使用pub包，如果你有任何不确定的信息，请使用工具检索互联网
## 核心命令

### 构建与运行
```bash
# 依赖安装
flutter pub get
注意：一般情况下，你无须执行依赖安装命令，编辑器会在你添加依赖后自动安装
# 开发运行
flutter run                    # 默认设备
flutter run -d windows         # Windows桌面
flutter run -d chrome         # Web浏览器
flutter run -d android        # Android设备

# 生产构建
flutter build apk --release   # Android APK
flutter build windows         # Windows桌面
flutter build web             # Web部署
```
注意:除非用户要求,请勿使用构建或运行命令

### 代码质量检查
```bash
# 代码格式化
dart format .

# 代码分析
flutter analyze
注意：请尽可能使用编辑器工具而非运行命令进行代码分析
# 依赖检查
flutter pub deps

# 单元测试（目前无测试文件）
flutter test

# 构建修复
flutter clean && flutter pub get
```

### 数据库相关
```bash
# 数据库文件位置（开发时）
# Android: /data/data/com.example.thoughtecho/databases/
# Windows: Documents/databases/
# Web: 内存数据库
```

## 高层架构

### 核心技术栈
- **Framework**: Flutter 3.7.2+ (Dart)
- **状态管理**: Provider
- **本地数据库**: sqflite (移动端), sqflite_common_ffi (桌面端)
- **网络**: Dio HTTP客户端
- **UI**: Material 3, flex_color_scheme, dynamic_color
- **富文本**: flutter_quill富文本编辑器
- **地理位置**: geolocator, geocoding
- **存储**: flutter_secure_storage, MMKV高性能存储
- **文件操作**: file_selector, share_plus

### 主要服务层
- `DatabaseService`: 核心数据存储，SQLite数据库操作
- `AIService`: AI功能集成，支持多provider
- `LocationService`: 位置服务，地理定位
- `WeatherService`: 天气数据获取
- `SettingsService`: 应用设置管理
- `UnifiedLogService`: 统一日志系统
- `ClipboardService`: 剪贴板监听与处理

### 数据模型
- `Quote`: 笔记模型，支持富文本、标签、位置、天气等元数据
- `NoteCategory`: 笔记分类/标签模型
- `AIAnalysis`: AI分析结果模型
- `AIProviderSettings`: AI服务提供商配置

### 外部集成
- **AI Services**: OpenAI、Anthropic、OpenRouter等多种AI提供商
- **一言API**: hitokoto.cn 每日一言集成
- **天气API**: 第三方天气服务集成

## 代码风格规范

### Dart/Flutter约定
- 遵循`flutter_lints`规范，使用`analysis_options.yaml`配置
- 类使用`PascalCase`，方法和变量使用`camelCase`
- 文件使用`snake_case`命名
- 私有成员使用下划线前缀(`_private`)
- 所有公共API必须提供文档注释

### 导入顺序
```dart
// 1. Dart core库
import 'dart:async';
import 'dart:io';

// 2. Flutter框架
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

// 3. 第三方包
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';

// 4. 项目内部导入
import '../services/database_service.dart';
import '../models/quote_model.dart';
```

### 异步处理模式
```dart
// 推荐：使用async/await
Future<void> saveQuote(Quote quote) async {
  try {
    await databaseService.addQuote(quote);
    notifyListeners();
  } catch (e) {
    logError('保存笔记失败: $e', error: e);
    rethrow;
  }
}

// 错误处理：始终包含try-catch
Future<List<Quote>> loadQuotes() async {
  try {
    return await databaseService.getUserQuotes();
  } catch (e) {
    logError('加载笔记失败: $e', error: e);
    return []; // 提供合理的默认值
  }
}
```

### 状态管理模式
```dart
// 使用Provider进行状态管理
class DatabaseService extends ChangeNotifier {
  Future<void> addQuote(Quote quote) async {
    // 执行操作
    notifyListeners(); // 通知UI更新
  }
}

// 在Widget中使用
Consumer<DatabaseService>(
  builder: (context, db, child) {
    return ListView.builder(/* ... */);
  },
)
```

### 错误处理规范
- 所有异步操作必须包含错误处理
- 使用`UnifiedLogService`记录错误日志
- 向用户显示友好的错误信息
- 实现数据库操作的事务回滚机制

### UI组件约定
- 使用Material 3设计规范
- 优先使用`AppTheme`中定义的颜色和样式
- 支持响应式设计，适配不同屏幕尺寸
- 使用`AppLoadingView`和`AppEmptyView`等通用组件

## 仓库特定规则

### 文件组织结构
```
lib/
├── main.dart                 # 应用入口，多provider初始化
├── models/                   # 数据模型
│   ├── quote_model.dart      # 笔记模型，支持JSON序列化
│   ├── note_category.dart    # 分类标签模型
│   └── ai_analysis_model.dart # AI分析结果模型
├── pages/                    # 页面组件
│   ├── home_page.dart        # 主页面，笔记列表和一言展示
│   ├── edit_page.dart        # 编辑页面，笔记编辑功能
│   ├── insights_page.dart    # AI洞察页面
│   └── settings_page.dart    # 设置页面
├── services/                 # 业务逻辑服务
│   ├── database_service.dart # 核心数据库服务
│   ├── ai_service.dart       # AI功能服务
│   └── settings_service.dart # 设置管理服务
├── widgets/                  # 可重用UI组件
├── utils/                    # 工具类
└── theme/                    # 主题配置
    └── app_theme.dart        # 应用主题定义
```

### 数据库架构
- **quotes表**: 存储核心笔记数据。
  - `id` (TEXT, PK): 唯一标识符。
  - `content` (TEXT): 笔记的纯文本内容。
  - `delta_content` (TEXT): 富文本内容 (Quill Delta格式的JSON字符串)。
  - `date` (TEXT): ISO 8601格式的日期字符串。
  - `category_id` (TEXT): 关联的分类ID。
  - `tag_ids` (TEXT): 逗号分隔的标签ID字符串 (待优化)。
  - `source` (TEXT): 来源信息。
  - `source_author` (TEXT): 来源作者。
  - `source_work` (TEXT): 来源作品。
  - `location` (TEXT): 地理位置。
  - `weather` (TEXT): 天气信息。
  - `temperature` (TEXT): 温度信息。
  - `day_period` (TEXT): 时间段标识 (如 'morning', 'evening')。
  - `color_hex` (TEXT): 笔记的自定义颜色。
  - `edit_source` (TEXT): 编辑来源 (如 'manual', 'ai')。
  - `ai_analysis`, `sentiment`, `keywords`, `summary`: AI分析相关字段。
- **categories表**: 存储笔记分类/标签。
  - `id` (TEXT, PK): 唯一标识符。
  - `name` (TEXT): 分类名称。
  - `is_default` (BOOLEAN): 是否为默认分类。
  - `icon_name` (TEXT): 关联的图标名称。
- **ai_analyses表**: AI分析结果存储（独立数据库文件）。

### 平台适配策略
- 使用条件导入处理平台差异：`if (dart.library.io)`
- Web平台使用内存数据库替代SQLite文件存储
- 桌面平台使用`sqflite_common_ffi`支持
- 移动平台使用标准`sqflite`

### AI功能实现
- 支持多provider配置（OpenAI、Anthropic、OpenRouter等）
- 使用流式响应提升用户体验
- 实现故障转移机制确保服务可用性
- 提供自定义提示词模板

### 性能优化要点
- 数据库查询使用索引优化
- 实现分页加载避免内存压力
- 使用缓存机制减少重复计算
- 异步加载提升UI响应性

### 数据备份机制
- JSON格式导出，包含元数据、分类、笔记数据
- 支持增量导入和覆盖导入两种模式
- 提供数据验证和冲突解决策略
- 实现紧急数据恢复功能

### 日志系统
- 使用`UnifiedLogService`统一日志管理
- 支持不同日志级别：verbose/debug/info/warning/error
- 日志持久化存储，支持查询和导出
- 错误堆栈追踪和上下文记录

### 国际化支持
- 使用`flutter_localizations`支持多语言
- 主要面向中文用户，提供英文支持
- 适配不同地区的日期时间格式

### 测试策略
- 关键业务逻辑需要单元测试覆盖
- 数据库操作需要集成测试验证
- UI组件需要Widget测试确保功能正常
- AI功能提供手动测试工具页面

这些指南将帮助AI代理更好地理解项目结构、编码规范和业务逻辑，从而提供更准确和一致的代码建议。
