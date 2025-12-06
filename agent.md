# ThoughtEcho AI 协作指南

## 项目概览
- 心迹（ThoughtEcho）是 Flutter 3.x 跨平台应用，主入口 `lib/main.dart`，在 `initializeDatabasePlatform()` 处理平台差异后通过 `Future.microtask` 启动重量级服务（数据库、AI 存储等）。
- UI 分布在 `lib/pages` 与 `lib/widgets`，业务逻辑集中在 `lib/services` 与 `lib/controllers`。服务通常继承 `ChangeNotifier`，并通过 Provider 在 `main.dart` 中注入。

## 重要原则
- 响应需求时优先复用现有服务/工具类，保持架构一致，避免重复轮子。
- 任何写操作后务必调用 `notifyListeners()` 或对应回调，保持 UI 同步。
- 遵循“先恢复旧逻辑再扩展”的策略，改动前理解上下游数据流，谨慎修改初始化流程。
- AI/密钥相关逻辑严禁硬编码敏感信息，统一通过 `APIKeyManager` 与安全存储。
- 文档或命令给出后应在实际环境验证；对用户或 CI 依赖的命令，保持与 `scripts/`、`test/all_tests.dart` 一致。
- 非用户明确要求时，不主动运行全量 `flutter test`、`flutter run` 或构建命令，也不要生成额外总结文档。
## 国际化规范
- **严禁在 UI 代码中硬编码中文或任何用户可见文本**。所有用户界面文字必须通过 `AppLocalizations.of(context).keyName` 获取。
- 新增 UI 文案时，先在 `lib/l10n/app_zh.arb`（中文）与 `lib/l10n/app_en.arb`（英文）中添加对应键值对，然后执行 `flutter gen-l10n` 生成代码后再使用。
- 带占位符的翻译使用 ARB 的 `{placeholder}` 语法，并在 `@keyName` 中声明 `placeholders` 元数据。
- 注释、日志、调试输出等非用户可见内容可使用中文，但 SnackBar、Dialog、Tooltip 等任何展示给用户的内容必须国际化。
## 架构总览
- 启动阶段：`main()` 建立基础 Provider、主题、路由后，使用 microtask 初始化 `DatabaseService`、`AIService` 等重量组件，期间 UI 通过 `ValueListenableBuilder` 等方式等待完成。
- 依赖注入：`lib/controllers` 将服务组合成 UI 可消费的控制器；Provider 使用 `ChangeNotifierProvider`、`ProxyProvider` 来串联服务与控制器。
- 日志系统：`UnifiedLogService` 负责记录/查询日志，所有异常先记录再抛出，便于紧急恢复页面分析。

## 平台与存储策略
- Windows：必须执行 `sqfliteFfiInit()` 并设定 `databaseFactory = databaseFactoryFfi`，否则数据库连接会失败。
- Web：禁用文件 IO，数据库使用内存模式；键值对直接走 `SharedPreferences`。
- 移动端：标准 `sqflite` + `MMKV`；32 位 ARM 设备 `SafeMMKV` 自动回退 `SharedPreferences`。
- 文件路径/权限统一通过 `MediaFileService` 与 `path_provider`，不要直接操作 `dart:io`。

## 数据模型与富文本
- 核心模型 `Quote` 同时保存 `content`（纯文本）与 `deltaContent`（Quill Delta JSON）；`editSource == 'fullscreen'` 表示富文本编辑器来源。
- 修改模型字段时，先更新 `lib/models`，再处理 `DatabaseService` 迁移、缓存刷新，并 bump 数据库版本。
- 富文本编辑流程：使用 `NoteFullEditorPage` 保持双格式同步，避免只更新单一字段。

## 多媒体与大文件
- 媒体管理：`MediaFileService` + `LargeFileManager` 统一处理图片/音频/视频路径、缓存与清理。
- 大文件读写：使用 `LargeFileManager.encodeJsonToFileStreaming` 或 `StreamFileProcessor`，提供进度、取消与 OOM 兜底逻辑；直接 `File.writeAsString` 可能触发内存溢出。
- 内存监控：`IntelligentMemoryManager` 根据可用内存调整批大小，捕获 `OutOfMemoryError` 后提供回退方案。

## AI 服务链路
- 架构链路：`MultiAISettings -> AIProviderSettings -> AINetworkManager -> APIKeyManager`。任何请求通过 `_requestHelper.makeStreamRequestWithProvider` 发起，自动处理流式块和故障转移。
- Provider 扩展：新增 AI 服务商需同步更新 `AIProviderSettings.getPresetProviders()`、`buildHeaders()`、`adjustData()` 并在设置页配置 UI。
- API 密钥：使用 `flutter_secure_storage` 加密保存，读取写入均走 `APIKeyManager`；调试可使用 `ApiKeyDebugger`。
- 流式交互：UI 通过 `StreamingTextDialog` 或 `StreamController` 响应块状数据，保证提示即时显示。

## 备份与恢复
- 备份 ZIP：`lib/services/backup` 提供媒体 + 元数据完整备份，使用流式压缩以避免 OOM。
- JSON 兼容：旧版备份仅含 JSON 数据，导入时需处理双存储字段；保持路径兼容，避免破坏历史数据。
- 紧急恢复：`EmergencyRecoveryPage` 会检测数据库损坏并触发恢复流程；相关逻辑在 `DatabaseService` 与 `backup/recovery_manager.dart`。

## 开发工作流
- 依赖安装：`flutter pub get`
- 常规运行：`flutter run`
- 常用测试：`flutter test test/all_tests.dart`（集中触发单元/服务/Widget 测试）；复杂场景参考 `scripts/test_ci_improvements.sh`。
- 数据库或模型变更后补充 `test/unit` 对应测试并执行 `flutter test`，防止 CI 回归。
- 大文件/备份调试可监听 `LargeFileManager` 的进度回调，在 UI 层刷新。

## 测试与调试建议
- 分析：`flutter analyze`；格式化检查 `dart format --set-exit-if-changed .`。
- 日志调试：使用 `UnifiedLogService.logError/Info` 记录上下文，再于日志页面或调试工具查看。
- 平台差异：所有平台判断使用 `kIsWeb` 与 `Platform.isXxx`；Web 代码禁止引用 `dart:io`。
- 集成测试：`test/all_tests.dart` 聚合入口，桌面集成测试需开启目标平台支持并遵循 CI 的 `flutter config --enable-linux-desktop` 流程。

## 快速定位
- 启动与 Provider 注入：`lib/main.dart`
- 数据库与迁移：`lib/services/database_service.dart`
- AI 设置与网络：`lib/services/ai` 目录
- 媒体/大文件：`lib/services/media`、`lib/services/backup`
- 控制器逻辑：`lib/controllers`
- 常用工具：`TimeUtils`（时间段）、`IconUtils`（图标）、`ColorUtils`（颜色）
