# UTILS 模块

共享工具类（纯函数/静态方法，**不持有持久状态**）。

## 分类指引

| 类别 | 入口文件 |
|------|----------|
| AI 通信 | `ai_network_manager.dart`、`ai_request_helper.dart`、`ai_prompt_manager.dart` |
| 流式处理 | `streaming_utils.dart`、`dio_network_utils.dart`、`zip_stream_processor.dart` |
| 平台适配 | `platform_helper.dart`、`mmkv_adapter.dart`、`optimized_image_loader.dart`（条件导入模式） |
| 内存性能 | `device_memory_manager.dart`、`memory_optimization_helper.dart`、`safe_compute.dart` |
| UI 辅助 | `color_utils.dart`、`icon_utils.dart`、`time_utils.dart`、`string_utils.dart` |
| 编辑器 | `quill_editor_extensions.dart`、`quill_ai_apply_utils.dart` |
| 调试 | `app_logger.dart`（`logDebug/logError/logInfo`）、`global_exception_handler.dart` |

## 规范
- **无状态**：Utils 只做纯函数或静态方法，禁止持有持久状态
- **异常**：抛出具体自定义异常，禁止吞掉，不持有 BuildContext
- **跨平台**：条件导入模式 `export 'x_io.dart' if (dart.library.html) 'x_web.dart'`
- **依赖方向**：Service 调用 Utils，**禁止反向引用**

## 禁止事项
| 禁止 | 替代方案 |
|------|----------|
| 持有 BuildContext 为成员变量 | 作为方法参数传入 |
| 直接 `print()` | `logDebug()` |

## 已删除 API
- `TimeUtils.formatTime` → 已删除，改用 `formatRelativeDateTime` 或 `formatQuoteTime`
