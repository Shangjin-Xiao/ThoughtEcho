# SERVICES 模块

业务逻辑服务层，全部继承 `ChangeNotifier`，通过 Provider 在 `main.dart` 注入。

## 快速定位

| 任务 | 关键文件 |
|------|----------|
| 笔记 CRUD | `database/database_quote_crud_mixin.dart` |
| 查询/筛选/搜索 | `database/database_query_mixin.dart` + `_helpers_mixin.dart` |
| 分页/收藏/回收站 | `database/database_pagination/favorite/trash_mixin.dart` |
| AI 流式请求 | `ai_service.dart` → `utils/ai_request_helper.dart` |
| AI 卡片生成 | `ai_card_generation_service.dart` |
| 备份/恢复 | `backup_service.dart` + `database_backup_service.dart` |
| 设备同步 | `note_sync_service.dart` + `localsend/` |
| 智能推送 | `smart_push_service.dart` + `smart_push/` |
| 日志 | `unified_log_service.dart` + `log_database_service.dart` |
| 媒体管理 | `media_file/reference/cleanup_service.dart` |
| Schema 迁移 | `database_schema_manager.dart` + `database_migration_mixin.dart` |

## 标准 Service 模式
```dart
class XxxService extends ChangeNotifier {
  // 服务层禁止 import flutter/widgets.dart，用 scheduler.dart
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
`MultiAISettings → AIProviderSettings → AINetworkManager → APIKeyManager`
新增 Provider：1. `getPresetProviders()` 添加预设 → 2. `buildHeaders()` + `adjustData()` → 3. `ai_settings_page.dart` 配置 UI

## 禁止事项
| 禁止 | 替代方案 |
|------|----------|
| `File.writeAsString` 写大文件 | `LargeFileManager.encodeJsonToFileStreaming` |
| 硬编码 API 密钥 | `APIKeyManager` + flutter_secure_storage |
| 忽略 `notifyListeners()` | 每次写操作后调用 |

## 已删除 API
- `AIService.generateDailyPrompt` → 已删除，改用 `streamGenerateDailyPrompt`
- `NoteSyncService.receiveAndMerge` → 已删除
