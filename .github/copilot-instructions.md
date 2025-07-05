# 心迹（ThoughtEcho）AI 协作指南

## 项目概述

心迹（ThoughtEcho）是一款基于Flutter的本地优先笔记应用，专注于捕捉思维火花、整理个人思考，并通过AI技术提供内容分析和智能洞察。采用本地存储优先策略，确保用户数据隐私和离线可用性。

**重要原则**：在响应用户进行代码更改时，请务必使用最佳实现，注意程序原有逻辑，不要引入重复代码，不要简单问题复杂化。优先使用项目现有的服务和工具类。请你不要生成冗长的项目总结文档
## 关键架构模式

### 平台适配策略
- **移动端**: 使用标准`sqflite`和`MMKV`
- **桌面端**: 使用`sqflite_common_ffi`和`databaseFactoryFfi`  
- **Web端**: 使用内存数据库和`SharedPreferences`
- **关键初始化**：`initializeDatabasePlatform()`在Windows上调用`sqfliteFfiInit()`

```dart
// 在Windows平台必须先初始化FFI
if (Platform.isWindows) {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
}
```

### 存储抽象层
项目使用`SafeMMKV`包装类实现存储抽象，自动处理32位ARM设备兼容性：
- 32位ARM设备：自动回退到`SharedPreferences`
- 其他平台：优先使用`MMKV`，失败时回退到`SharedPreferences`
- Web平台：直接使用`SharedPreferences`

### 富文本编辑器架构
使用`flutter_quill`实现双格式存储：
- `content`字段：存储纯文本（用于搜索和显示）
- `deltaContent`字段：存储Quill Delta JSON（富文本格式）
- `editSource`字段：标识编辑来源（`'fullscreen'`表示富文本编辑）

## AI服务架构

### 多Provider配置
项目采用多AI服务商架构，支持故障转移：

```dart
// 核心类层次
MultiAISettings -> AIProviderSettings -> AINetworkManager
              -> APIKeyManager (安全存储)
```

- **API密钥管理**：使用`flutter_secure_storage`安全存储，配置文件中不保存敏感信息
- **故障转移**：当前provider失败时自动切换到其他可用provider
- **支持的服务商**：OpenAI、Anthropic、OpenRouter、DeepSeek、硅基流动等

### 流式响应处理
AI功能全面支持流式响应，使用`StreamController`和自定义`StreamingTextDialog`：

```dart
// 流式请求模式
Stream<String> streamAnalyzeContent(String content) {
  return _requestHelper.executeStreamOperation(
    operation: (controller) async {
      await _requestHelper.makeStreamRequestWithProvider(
        // ...处理流式数据块
      );
    }
  );
}
```

## 核心开发模式

### 异步初始化模式
应用使用分阶段初始化以优化启动性能：

```dart
// 关键模式：先显示UI，后台初始化重量级服务
Future.microtask(() async {
  // 初始化数据库等重量级服务
  await databaseService.init();
  servicesInitialized.value = true;
});
```

### Provider状态管理
使用`MultiProvider`统一管理所有服务，继承`ChangeNotifier`：

```dart
// 服务必须继承ChangeNotifier并在操作后调用notifyListeners()
class DatabaseService extends ChangeNotifier {
  Future<void> addQuote(Quote quote) async {
    // 执行数据库操作
    notifyListeners(); // 关键：通知UI更新
  }
}
```

### 错误处理与日志
使用`UnifiedLogService`统一日志管理，支持持久化存储：

```dart
// 错误处理标准模式
try {
  await databaseService.addQuote(quote);
} catch (e) {
  logError('保存笔记失败: $e', error: e, source: 'QuoteEditor');
  rethrow; // 重新抛出让上层处理
}
```

## 数据模型设计

### Quote模型核心字段
```dart
class Quote {
  final String content;        // 纯文本内容（必须）
  final String? deltaContent;  // 富文本JSON（可选）
  final String date;           // ISO 8601格式日期
  final List<String> tagIds;   // 标签ID列表
  final String? categoryId;    // 分类ID
  final String? editSource;    // 编辑来源标识
  final String? dayPeriod;     // 时间段标识
  // ...位置、天气、AI分析等元数据
}
```

### 数据库schema要点
- **quotes表**：包含富文本双存储字段（`content` + `deltaContent`）
- **categories表**：支持图标和默认分类标识
- **版本管理**：使用数据库版本控制进行schema升级
- **Web平台**：使用内存存储替代SQLite文件操作

## 关键工具类

### 时间处理
`TimeUtils`提供本地化时间段识别（晨曦、午后、黄昏、夜晚）

### 图标工具
`IconUtils`统一处理MaterialIcons和Emoji图标显示

### 颜色工具  
`ColorUtils`提供颜色选择和预设管理

### 网络适配
`AINetworkManager`统一管理所有AI请求，支持多provider故障转移

## 开发注意事项

1. **平台检查**：始终使用`kIsWeb`和`Platform.isXxx`进行平台特定逻辑
2. **异步操作**：所有数据库操作必须使用`async/await`并包含错误处理
3. **UI更新**：修改数据后必须调用`notifyListeners()`
4. **API密钥**：永远不要在配置文件中存储API密钥，使用`APIKeyManager`
5. **富文本**：新建富文本功能时使用`NoteFullEditorPage`而非简单文本框
6. **流式AI**：AI功能优先使用流式响应提升用户体验

## 重要服务详解

### DatabaseService
- **初始化**：支持平台特定数据库路径和FFI配置
- **数据流**：使用`StreamController`提供响应式笔记列表
- **缓存策略**：实现查询结果缓存和分页加载
- **迁移逻辑**：自动处理数据库schema升级和旧数据迁移

### AIService 
- **多Provider架构**：`MultiAISettings`统一管理多个AI服务商
- **安全存储**：API密钥通过`APIKeyManager`存储在`flutter_secure_storage`
- **流式响应**：所有AI功能支持流式输出，使用`StreamingTextDialog`
- **故障转移**：当前provider失败时自动切换到备用provider

### SettingsService
- **存储适配**：使用`SafeMMKV`包装类处理平台差异
- **配置管理**：统一管理应用设置、AI配置、主题设置等
- **数据持久化**：设置变更立即保存并通知监听者

## 常见开发任务

### 添加新的笔记功能
1. 在`Quote`模型中添加新字段
2. 更新数据库schema（增加版本号和迁移逻辑）
3. 修改`DatabaseService`的增删改查方法
4. 在UI中添加对应的输入/显示组件

### 集成新的AI Provider
1. 在`AIProviderSettings.getPresetProviders()`中添加预设配置
2. 在`buildHeaders()`和`adjustData()`中添加特定请求格式
3. 在AI设置页面的`aiPresets`列表中添加UI选项
4. 测试API兼容性并处理响应格式差异

### 添加新的平台支持
1. 在`initializeDatabasePlatform()`中添加平台检查
2. 在`SafeMMKV`中添加平台特定存储逻辑
3. 更新相关的条件导入和平台检查代码
4. 测试平台特定功能（如文件选择、分享等）

## 测试与调试

### 日志系统
- 使用`logDebug()`, `logInfo()`, `logError()`等函数
- 日志自动持久化到本地数据库
- 支持按级别、来源、时间范围查询日志

### API Key调试
- `ApiKeyDebugger`提供专门的API密钥调试工具
- 可以追踪API密钥的保存、读取、使用流程
- 帮助排查provider切换和认证问题

### 数据库调试
- 支持数据备份和恢复功能
- 紧急模式：数据库损坏时显示恢复界面
- 提供数据库文件导出功能用于调试

这些指南涵盖了项目的核心架构、关键实现模式和常见开发场景，帮助AI代理快速理解项目结构并提供准确的代码建议。
