# Utils 模块

本目录包含共享算法、格式化、网络辅助、平台适配和少量 UI helper。并非所有 Utils 都是纯函数，
但新增工具应尽量无状态、依赖明确，并避免演变成隐藏的 Service。

## 分类指引

| 类别 | 入口示例 |
|---|---|
| AI 通信 | `ai_network_manager.dart`、`ai_request_helper.dart`、`ai_prompt_manager.dart` |
| 流式/网络 | `streaming_utils.dart`、`dio_network_utils.dart`、`zip_stream_processor.dart` |
| 平台适配 | `platform_helper.dart`、`mmkv_adapter.dart`、`optimized_image_loader.dart` |
| 内存/性能 | `device_memory_manager.dart`、`memory_optimization_helper.dart`、`safe_compute.dart` |
| 编辑器 | `quill_editor_extensions.dart`、`quill_ai_apply_utils.dart`、`quill_delta_builder.dart` |
| 日志/追踪 | `app_logger.dart`、`global_exception_handler.dart`、`sentry_*` |

## 规则

- 纯转换优先顶层函数、静态方法或不可变小类；需要持久状态、生命周期或 I/O 编排时应放入
  Service，而不是藏在全局 Utils 单例里。
- 不持有 `BuildContext`；仅用于即时 UI 计算的 helper 可以把 context 作为参数，但不得跨异步
  生命周期保存。
- 抛出具体异常或返回项目既有结果类型，保留原始 stack trace；禁止静默吞错和直接 `print()`。
- 依赖方向通常为 Service/Page → Utils。Utils 不应反向依赖具体页面或有状态业务 Service。
- 平台差异沿用现有 IO/stub 条件导出模式。项目不支持 Web：现存 `*_web.dart` 是历史兼容代码，
  不要照着旧示例新增 Web 实现。
- 缓存必须定义 key、容量/过期、并发和清理策略；不要缓存含 API 密钥或完整私人内容的数据。
- AI/网络 helper 修改时同步检查超时、取消、流关闭、UTF-8 分块和 Provider 差异。

已删除的 `TimeUtils.formatTime` 不得恢复，使用 `formatRelativeDateTime` 或 `formatQuoteTime`。
测试放在 `test/unit/utils/`，对边界输入、空值、异常和平台分支做针对性覆盖。
