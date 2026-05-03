# SERVICES 模块

## 概览
业务逻辑服务层（65+ 文件），全部继承 `ChangeNotifier`，通过 Provider 在 `main.dart` 注入。

## 目录结构

```
services/
├── database_service.dart              # 核心数据库（33k+ 行，part 拆分为 database/）
├── database/                           # DB mixin 文件（12 个）
│   ├── database_quote_crud_mixin.dart     # 笔记增删改查
│   ├── database_query_mixin.dart          # 复杂查询（分类、标签、搜索）
│   ├── database_query_helpers_mixin.dart   # 查询构建辅助
│   ├── database_cache_mixin.dart           # 内存缓存层
│   ├── database_pagination_mixin.dart     # 分页加载
│   ├── database_favorite_mixin.dart        # 收藏管理
│   ├── database_category_mixin.dart        # 分类 CRUD
│   ├── database_category_init_mixin.dart   # 默认分类初始化
│   ├── database_hidden_tag_mixin.dart      # 隐藏标签管理
│   ├── database_import_export_mixin.dart    # 数据导入导出
│   ├── database_migration_mixin.dart        # 版本迁移
│   └── database_trash_mixin.dart            # 回收站
├── database_schema_manager.dart            # Schema 管理（57k+ 行）
├── database_backup_service.dart             # 数据库备份
├── database_health_service.dart            # 数据库健康检查
├── ai_service.dart                         # AI 多 provider 流式请求
├── ai_analysis_database_service.dart       # AI 分析结果存储
├── ai_card_generation_service.dart         # AI 卡片生成（49k+ 行）
├── api_key_manager.dart                    # API 密钥安全存储
├── settings_service.dart                   # 应用设置（34k+ 行，MMKV/SharedPreferences）
├── backup_service.dart                     # ZIP 流式备份（35k+ 行）
├── note_sync_service.dart                  # 设备同步（32k+ 行，LWW 策略）
├── localsend/                              # LocalSend 协议实现（见子目录 AGENTS.md）
├── smart_push_service.dart                 # 智能推送（21k+ 行，part 拆分）
├── smart_push/                             # 推送策略拆分（6 个）
│   ├── smart_push_content.dart                # 内容生成
│   ├── smart_push_execution.dart              # 执行逻辑
│   ├── smart_push_notification.dart            # 通知发送
│   ├── smart_push_permissions.dart              # 权限管理
│   ├── smart_push_platform.dart                # 平台适配
│   └── smart_push_scheduling.dart              # 调度策略
├── unified_log_service.dart                # 统一日志系统（36k+ 行）
├── log_service.dart                        # 日志服务
├── log_database_service.dart               # 日志数据库
├── log_service_adapter.dart                # 日志适配器
├── large_file_manager.dart                 # 大文件流式处理
├── intelligent_memory_manager.dart          # 内存动态管理
├── media_file_service.dart                 # 媒体文件管理
├── media_reference_service.dart             # 媒体引用管理（33k+ 行）
├── media_cleanup_service.dart              # 媒体清理
├── clipboard_service.dart                   # 剪贴板监控
├── location_service.dart                   # 位置服务（41k+ 行）
├── local_geocoding_service.dart             # 本地地理编码
├── weather_service.dart                    # 天气服务
├── weather_cache_manager.dart               # 天气缓存
├── version_check_service.dart              # 版本检查
├── secure_storage_service.dart              # 安全存储
├── mmkv_service.dart                       # MMKV 高性能存储
├── draft_service.dart                      # 草稿箱
├── connectivity_service.dart                # 网络连接检测
├── data_directory_service.dart              # 数据目录管理
├── apk_download_service.dart                # APK 下载
├── error_recovery_manager.dart              # 错误恢复
├── image_cache_service.dart                 # 图片缓存
├── svg_to_image_service.dart                # SVG 转图片
├── mdns_discovery_service.dart              # mDNS 设备发现
├── thoughtecho_discovery_service.dart        # ThoughtEcho 设备发现
├── network_service.dart                     # 网络状态
├── biometric_service.dart                   # 生物认证
├── streaming_backup_processor.dart           # 流式备份
└── feature_guide_service.dart                # 功能引导
```

## 快速定位

| 任务 | 文件 |
|------|------|
| 笔记 CRUD | `database_quote_crud_mixin.dart` |
| 复杂查询 | `database_query_mixin.dart` + `database_query_helpers_mixin.dart` |
| 分页 | `database_pagination_mixin.dart` |
| 收藏 | `database_favorite_mixin.dart` |
| 回收站 | `database_trash_mixin.dart` |
| AI 流式请求 | `ai_service.dart` → `utils/ai_request_helper.dart` |
| AI 卡片 | `ai_card_generation_service.dart` |
| API 密钥 | `api_key_manager.dart` + `secure_storage_service.dart` |
| 应用设置 | `settings_service.dart` |
| 备份/恢复 | `backup_service.dart` + `database_backup_service.dart` |
| 设备间同步 | `note_sync_service.dart` + `localsend/` |
| 推送 | `smart_push_service.dart` + `smart_push/` |
| 日志 | `unified_log_service.dart` + `log_service.dart` + `log_database_service.dart` |
| 大文件 | `large_file_manager.dart` |
| 媒体管理 | `media_file_service.dart` + `media_reference_service.dart` + `media_cleanup_service.dart` |
| 位置/天气 | `location_service.dart` + `weather_service.dart` + `local_geocoding_service.dart` |
| Schema 迁移 | `database_schema_manager.dart` + `database_migration_mixin.dart` |

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
