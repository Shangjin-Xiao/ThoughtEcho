# 心迹（ThoughtEcho）AI 协作指南

## 项目概述

心迹（ThoughtEcho）是一款基于Flutter的本地优先笔记应用，专注于捕捉思维火花、整理个人思考，并通过AI技术提供内容分析和智能洞察。采用本地存储优先策略，确保用户数据隐私和离线可用性。

**重要原则**：在响应用户进行代码更改时，请务必使用最佳实现，注意程序原有逻辑，不要引入重复代码，不要简单问题复杂化。优先使用项目现有的服务和工具类。请你不要生成冗长的项目总结文档

**最新发展**：项目已支持多媒体笔记（图片、音频、视频）、AI卡片生成、大文件流式处理、智能内存管理等高级功能。
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

### 多媒体文件管理架构
项目实现了完整的多媒体文件管理系统：
- **LargeFileManager**: 流式文件处理，支持大文件的内存安全操作
- **StreamFileProcessor**: 分块文件处理，支持进度回调和取消操作
- **MediaFileService**: 统一的媒体文件服务，支持图片、音频、视频
- **IntelligentMemoryManager**: 智能内存管理，动态调整处理策略

### 备份系统架构
支持新旧版本兼容的备份系统：
- **新版ZIP格式**: 包含媒体文件的完整备份（推荐）
- **旧版JSON格式**: 纯数据备份，向后兼容
- **流式处理**: 大文件分块处理，支持进度显示和中断恢复

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

### AI卡片生成服务
新增`AICardGenerationService`支持AI生成可视化卡片：
- **智能风格选择**: AI根据内容自动选择合适的卡片风格
- **SVG生成**: 使用AI生成可缩放的SVG格式卡片
- **批量处理**: 支持为多条笔记批量生成特色卡片
- **图片导出**: 支持将SVG卡片转换为图片保存到相册

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

### 大文件处理模式
使用专门的`LargeFileManager`处理内存敏感操作：

```dart
// 大文件流式处理标准模式
try {
  await LargeFileManager.encodeJsonToFileStreaming(
    data, outputFile,
    onProgress: (current, total) => _updateProgress(current / total),
  );
} catch (e) {
  if (e is OutOfMemoryError) {
    // 内存不足时的专门处理
    await _handleOutOfMemoryError();
  }
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

### 大文件处理工具
- **LargeFileManager**: 流式JSON编解码，内存安全的大文件操作
- **StreamFileProcessor**: 可中断的分块文件处理
- **IntelligentMemoryManager**: 智能内存管理和优化策略

## 开发注意事项

1. **平台检查**：始终使用`kIsWeb`和`Platform.isXxx`进行平台特定逻辑
2. **异步操作**：所有数据库操作必须使用`async/await`并包含错误处理
3. **UI更新**：修改数据后必须调用`notifyListeners()`
4. **API密钥**：永远不要在配置文件中存储API密钥，使用`APIKeyManager`
5. **富文本**：新建富文本功能时使用`NoteFullEditorPage`而非简单文本框
6. **流式AI**：AI功能优先使用流式响应提升用户体验
7. **大文件处理**：使用`LargeFileManager`处理可能导致内存不足的操作
8. **媒体文件**：使用`MediaFileService`统一处理图片、音频、视频文件

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

### MediaFileService
- **多媒体支持**：统一处理图片、音频、视频文件
- **内存优化**：大文件使用流式处理避免内存溢出
- **缓存管理**：智能缓存策略提升性能
- **格式支持**：支持多种主流媒体格式

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

### 添加多媒体功能
1. 使用`MediaFileService`进行文件管理
2. 大文件必须使用`LargeFileManager`进行流式处理
3. 在`Quote`模型中添加媒体文件字段
4. 更新备份服务以包含媒体文件（ZIP格式）

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

### 内存调试
- `IntelligentMemoryManager`提供内存使用监控
- `OutOfMemoryError`专门用于内存不足场景
- 大文件操作会自动检测并处理内存压力

这些指南涵盖了项目的核心架构、关键实现模式和常见开发场景，帮助AI代理快速理解项目结构并提供准确的代码建议。
