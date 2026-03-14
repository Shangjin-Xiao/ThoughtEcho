# SERVICES 模块

## 概览
业务逻辑服务层（65+ 文件），全部继承 `ChangeNotifier`，通过 Provider 在 `main.dart` 注入。

## 目录结构

```
services/
├── database_service.dart          # 核心数据库（5820+ 行，part 拆分）
├── database/                      # DB mixin 文件（11 个）
│   ├── database_cache_mixin.dart
│   ├── database_query_mixin.dart
│   ├── database_crud_mixin.dart
│   └── ...（共 11 个）
├── ai_service.dart                # AI 多 provider 流式请求
├── api_key_manager.dart           # API 密钥安全存储
├── settings_service.dart          # 应用设置（MMKV/SharedPreferences）
├── backup_service.dart            # ZIP 流式备份
├── note_sync_service.dart         # 设备同步（LWW 策略）
├── localsend/                     # LocalSend 协议实现
│   ├── localsend_server.dart
│   ├── localsend_receive_controller.dart
│   └── ...
├── smart_push_service.dart        # 智能推送（2560+ 行，part 拆分）
├── smart_push/                    # 推送策略拆分（6 个）
├── unified_log_service.dart       # 日志系统
├── large_file_manager.dart        # 大文件流式处理
└── intelligent_memory_manager.dart # 内存动态管理
```

## 快速定位

| 任务 | 文件 |
|------|------|
| 笔记 CRUD | `database_service.dart` + `database/database_crud_mixin.dart` |
| AI 流式请求 | `ai_service.dart` → `utils/ai_request_helper.dart` |
| API 密钥读写 | `api_key_manager.dart` |
| 应用设置持久化 | `settings_service.dart` |
| 备份/恢复 | `backup_service.dart` |
| 设备间同步 | `note_sync_service.dart` + `localsend/` |
| 日志记录 | `unified_log_service.dart` |
| 大文件写入 | `large_file_manager.dart` |

## 标准 Service 模式

```dart
class XxxService extends ChangeNotifier {
  // 服务层禁止 import flutter/widgets.dart，使用 scheduler.dart
  // import 'package:flutter/scheduler.dart';

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  Future<void> doSomething() async {
    _isLoading = true;
    notifyListeners(); // 写操作后必须调用！
    try {
      // 业务逻辑
      notifyListeners();
    } catch (e, stack) {
      logError('XxxService.doSomething', e, stack);
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
```

## AI 架构链路

```
MultiAISettings → AIProviderSettings → AINetworkManager → APIKeyManager
                                             ↓
                               _requestHelper.makeStreamRequestWithProvider
```

### 新增 AI Provider 步骤
1. 在 `AIProviderSettings.getPresetProviders()` 添加预设配置
2. 实现 `buildHeaders()` + `adjustData()` 适配特定 API 格式
3. 在 `lib/pages/ai_settings_page.dart` 添加对应配置 UI

## 错误处理规范
- 所有异常先通过 `logError('服务名.方法名', e, stack)` 记录，再 rethrow 或降级
- 网络请求使用 `dio_network_utils.dart` 中的 retry 逻辑
- 数据库操作失败触发 `DatabaseHealthService` 进行健康检查

## 禁止事项

| 禁止 | 替代方案 |
|------|----------|
| `File.writeAsString` 写大文件 | `LargeFileManager.encodeJsonToFileStreaming` |
| 硬编码 API 密钥 | `APIKeyManager` + flutter_secure_storage |
| 同步阻塞文件 IO | `SafeCompute` isolate |
| 忽略 `notifyListeners()` | 每次写操作后调用 |
| `import 'package:flutter/widgets.dart'` | `import 'package:flutter/scheduler.dart'` |

## 废弃 API
- `AIService.generateDailyPrompt` → 使用 `streamGenerateDailyPrompt`
- `NoteSyncService.receiveAndMerge` → 已废弃，不再使用
