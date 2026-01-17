# SERVICES MODULE

## OVERVIEW

业务逻辑服务层 (78 files)，全部继承 `ChangeNotifier`，通过 Provider 注入。

## STRUCTURE

```
services/
├── database_service.dart       # 核心数据库 (5820 lines)
├── ai_service.dart             # AI 多 provider 架构
├── settings_service.dart       # 应用设置
├── backup_service.dart         # ZIP 备份
├── note_sync_service.dart      # 设备同步
├── localsend/                  # LocalSend 协议 → 见子目录 AGENTS.md
├── unified_log_service.dart    # 日志系统
├── location_service.dart       # 位置获取
├── weather_service.dart        # 天气服务
├── media_file_service.dart     # 媒体文件管理
├── large_file_manager.dart     # 大文件流式处理
├── intelligent_memory_manager.dart # 内存动态管理
└── api_key_manager.dart        # API 密钥安全存储
```

## WHERE TO LOOK

| Task | File | Notes |
|------|------|-------|
| CRUD 操作 | `database_service.dart` | 所有笔记/分类操作 |
| AI 请求 | `ai_service.dart` | `_requestHelper.makeStreamRequestWithProvider` |
| API 密钥 | `api_key_manager.dart` | flutter_secure_storage 加密 |
| 流式 AI | `AIService` + `StreamingTextDialog` | 实时显示生成内容 |
| 备份导出 | `backup_service.dart` | 媒体+元数据 ZIP |
| 同步协议 | `note_sync_service.dart` + `localsend/` | LWW 合并策略 |

## CONVENTIONS

### Service 模式
```dart
class XxxService extends ChangeNotifier {
  Future<void> doSomething() async {
    // 业务逻辑
    notifyListeners(); // 必须调用！
  }
}
```

### AI 架构链路
```
MultiAISettings → AIProviderSettings → AINetworkManager → APIKeyManager
                                            ↓
                              _requestHelper.makeStreamRequestWithProvider
```

### 新增 AI Provider
1. 更新 `AIProviderSettings.getPresetProviders()`
2. 实现 `buildHeaders()` + `adjustData()`
3. 在 AI 设置页配置 UI

### 错误处理
- 异常先记录 `logError()`，再抛出
- 网络错误使用 retry 逻辑 (`dio_network_utils.dart`)

## ANTI-PATTERNS

| 禁止 | 替代方案 |
|------|----------|
| `File.writeAsString` 大文件 | `LargeFileManager.encodeJsonToFileStreaming` |
| 硬编码 API 密钥 | `APIKeyManager` |
| 同步阻塞文件 IO | `SafeCompute` isolate |
| 忽略 `notifyListeners()` | 每次写操作后调用 |

## DEPRECATED

- `AIService.generateDailyPrompt` → `streamGenerateDailyPrompt`
- `NoteSyncService.receiveAndMerge` → 已废弃
