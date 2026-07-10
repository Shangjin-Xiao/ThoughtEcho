# Services 模块

本目录承载数据库、AI、网络、文件、同步和设备能力。Service 分为两类：供 Provider 监听的
有状态 Service，以及纯操作/计算 Service。不要强迫所有 Service 继承 `ChangeNotifier`。

## 快速定位

| 任务 | 关键文件 |
|---|---|
| 笔记 CRUD/查询 | `database_service.dart` + `database/` |
| Schema 与版本升级 | `database_schema_manager.dart` |
| AI 通用能力 | `ai_service.dart`、`openai_stream_service.dart`、`agent_service.dart` |
| Agent 工具 | `agent_tool.dart` + `agent_tools/` |
| AI 卡片 | `ai_card_generation_service.dart` + `ai_card_generation_strategies/` |
| 备份/恢复 | `backup_service.dart`、`database_backup_service.dart` |
| 局域网同步 | `note_sync_service.dart` + `localsend/` |
| WebDAV 同步 | `webdav_sync_service.dart` |
| 智能推送 | `smart_push_service.dart` + `smart_push/` |
| 日志 | `unified_log_service.dart`、`log_database_service.dart` |
| 媒体 | `media_file_service.dart`、`media_reference_service.dart`、`media_cleanup_service.dart` |

## 设计边界

- 有状态 Service 只在可观察状态改变后 `notifyListeners()`；无状态操作不要制造通知。异步流程
  中的 loading/error 状态要在成功、失败和 `finally` 路径保持一致。
- Service 不持有页面 `BuildContext`，不直接显示 Dialog/SnackBar。平台能力通过现有适配层或
  小型接口隔离。
- 写操作先保证持久化成功，再更新内存状态和通知；若采用乐观更新，必须有明确回滚路径。
- 异常通过项目日志封装记录操作名和必要上下文，再 rethrow 或返回明确结果；禁止吞错和记录
  API 密钥、完整私人内容或认证头。
- 可取消的网络/文件操作继续传递取消信号；重试必须有上限、退避和明确的可重试错误范围。
- 大文件、备份和媒体处理使用流式/Isolate 能力，避免一次性读入内存。

## AI 与外部协议

Provider 配置以 `AIProviderSettings` 为中心，密钥由 `APIKeyManager` 单独管理；请求路径可能经过
`AINetworkManager`、`OpenAIStreamService` 或 Agent 流程。新增 Provider 或修改 SSE/REST 字段
前查询当前官方协议，并覆盖请求头、请求体、错误映射、流结束、取消和测试。

已删除的 `AIService.generateDailyPrompt` 和 `NoteSyncService.receiveAndMerge` 不得恢复；使用当前
调用链和同步合并流程。

## 测试

测试路径优先镜像 `test/unit/services/`。外部 I/O 用现有 mock/fake 边界，至少覆盖成功、失败、
超时/取消和状态通知；数据库批量逻辑增加查询次数或迁移路径回归测试。
