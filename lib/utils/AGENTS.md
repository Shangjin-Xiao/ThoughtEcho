# UTILS MODULE

## OVERVIEW
共享工具类 (50+ files)，涵盖 AI 通信、IO 处理、平台适配和内存优化。

## CATEGORIES
- **AI Utils**: `ai_network_manager.dart`, `ai_request_helper.dart` (处理流式请求与重试)。
- **Memory & Performance**: `device_memory_manager.dart`, `intelligent_memory_manager.dart` (动态内存控制)。
- **Platform**: `platform_helper.dart`, `database_platform_init.dart` (处理 Windows/Web/Mobile 差异)。
- **IO & Files**: `dio_network_utils.dart`, `zip_stream_processor.dart` (流式文件处理)。
- **UI Helpers**: `color_utils.dart`, `icon_utils.dart`, `time_utils.dart`.

## CONVENTIONS
- **无状态**: Utils 尽量保持为纯函数或静态方法，避免持有持久状态。
- **跨平台**: 涉及文件操作时，必须区分 Web 和 IO 环境，优先使用 `PlatformHelper`。
- **异常处理**: 底层工具应抛出具体的自定义异常，便于上层服务处理。

## ANTI-PATTERNS
- 禁止在 Utils 中直接持有 `BuildContext`（除非是 UI Helper 且作为参数传入）。
- 避免在 Utils 中直接引用 Service 层，防止循环依赖。
