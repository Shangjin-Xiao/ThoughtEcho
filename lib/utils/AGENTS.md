# UTILS 模块

## 概览
共享工具类（62 个文件），涵盖 AI 通信、IO 处理、平台适配、内存优化和 UI 辅助。

## 分类目录

### AI 通信
| 文件 | 说明 |
|------|------|
| `ai_network_manager.dart` | HTTP 客户端管理，支持 dio / rhttp 双引擎 |
| `ai_request_helper.dart` | 流式请求核心：`makeStreamRequestWithProvider` |
| `ai_prompt_manager.dart` | Prompt 模板管理 |
| `ai_dialog_helper.dart` | AI 功能弹窗辅助 |
| `multi_provider_manager.dart` | 多 AI Provider 切换逻辑 |
| `ai_connection_test.dart` | AI 连接诊断 |

### 内存与性能
| 文件 | 说明 |
|------|------|
| `device_memory_manager.dart` | 设备内存检测与限制 |
| `memory_optimization_helper.dart` | 批处理大小动态调整 |
| `safe_compute.dart` | isolate 安全计算封装 |

### 平台适配（条件导入模式）
| 文件组 | 说明 |
|--------|------|
| `platform_helper.dart` / `_io.dart` / `_web.dart` | 平台差异抹平 |
| `mmkv_adapter.dart` / `_io.dart` / `_web.dart` | MMKV vs SharedPreferences |
| `optimized_image_loader.dart` / `_io.dart` / `_stub.dart` / `_base.dart` | 平台图片加载 |
| `local_video_controller.dart` / `_io.dart` / `_stub.dart` | 本地视频控制 |
| `motion_photo_utils.dart` / `_base.dart` / `_io.dart` / `_stub.dart` | 动态照片 |

### IO 与流处理
| 文件 | 说明 |
|------|------|
| `dio_network_utils.dart` | 网络请求 retry 逻辑 |
| `zip_stream_processor.dart` | ZIP 流式解压 |
| `streaming_json_parser.dart` | 流式 JSON 解析 |
| `stream_file_selector.dart` | 大文件流式选择 |

### UI 辅助
| 文件 | 说明 |
|------|------|
| `color_utils.dart` | 颜色工具函数 |
| `icon_utils.dart` | 图标映射 |
| `time_utils.dart` | 时间格式化（`formatRelativeDateTime`, `formatQuoteTime`） |
| `string_utils.dart` | 字符串工具 |
| `i18n_language.dart` | 语言代码与名称映射 |

### 调试（仅 Debug 模式）
| 文件 | 说明 |
|------|------|
| `app_logger.dart` | `logDebug` / `logError` / `logInfo` 全局函数 |
| `global_exception_handler.dart` | 全局未捕获异常处理 |
| `api_key_debugger.dart` | API 密钥存储验证 |

## 规范

### 无状态原则
```dart
// 正确：纯函数或静态方法
class TimeUtils {
  static String formatRelativeDateTime(DateTime dt) { ... }
}

String formatDuration(Duration d) { ... }  // 顶层函数

// 错误：持有持久状态（禁止）
class XxxUtils {
  String _cachedResult = '';  // 不允许
}
```

### 跨平台条件导入模式
```dart
// 统一入口文件（platform_helper.dart）
export 'platform_helper_io.dart'
    if (dart.library.html) 'platform_helper_web.dart';

// IO 实现
class PlatformHelper {
  static Future<String> getDataDirectory() async {
    // dart:io 实现
  }
}

// Web Stub
class PlatformHelper {
  static Future<String> getDataDirectory() async {
    return ''; // Web 不支持
  }
}
```

### 异常处理规范
- Utils 层抛出具体的自定义异常（如 `FileNotFoundException`），便于上层 Service 处理
- 禁止吞掉异常（catch 后不处理）
- 底层工具函数不直接显示 UI（不持有 BuildContext）

## 禁止事项

| 禁止 | 原因 | 替代方案 |
|------|------|----------|
| 持有 `BuildContext` 为成员变量 | 生命周期问题 | 作为方法参数传入 |
| 引用 Service 层 | 循环依赖 | Service 调用 Utils，不反向 |
| Web 环境使用 `dart:io` | 编译失败 | 条件导入 + stub 实现 |
| 在 Utils 中直接 `print()` | 生产环境输出 | 使用 `logDebug()` |

## 废弃 API
- `TimeUtils.formatTime` → 使用 `formatRelativeDateTime` 或 `formatQuoteTime`
