# PAGES 模块

## 概览
页面组件层（35+ 文件），负责完整屏幕展示和用户交互。严格遵循 Material 3 设计规范。

## 核心页面

| 文件 | 说明 |
|------|------|
| `home_page.dart` | 应用主页（89k+ 行），底部导航、笔记列表、每日一言、搜索 |
| `note_full_editor_page.dart` | 富文本编辑器入口，通过 `note_editor/` 拆分 |
| `insights_page.dart` | AI 洞察与统计分析（45k+ 行） |
| `settings_page.dart` | 设置中心（57k+ 行） |
| `ai_settings_page.dart` | AI 服务商配置（35k+ 行） |
| `smart_push_settings_page.dart` | 智能推送设置（58k+ 行） |
| `category_settings_page.dart` | 分类管理（44k+ 行） |
| `tag_settings_page.dart` | 标签管理（48k+ 行） |
| `backup_restore_page.dart` | 备份与恢复 |
| `note_sync_page.dart` | 设备同步（54k+ 行） |
| `note_qa_chat_page.dart` | AI 问答对话 |
| `ai_periodic_report_page.dart` | AI 周期性报告，通过 `ai_report/` 拆分 |
| `annual_report_page.dart` | 年度报告页面（56k+ 行） |
| `ai_analysis_history_page.dart` | AI 分析历史 |
| `theme_settings_page.dart` | 主题与颜色设置 |
| `onboarding_page.dart` | 首次引导流程 |
| `hitokoto_settings_page.dart` | 一言设置 |
| `media_management_page.dart` | 媒体文件管理 |
| `trash_page.dart` | 回收站 |
| `logs_page.dart` | 日志查看（开发者模式） |
| `local_ai_settings_page.dart` | 本地 AI 设置（开发者模式） |
| `storage_management_page.dart` | 存储管理（开发者模式） |
| `license_page.dart` | 开源许可 |
| `user_guide_page.dart` | 用户指南 |
| `feedback_contact_page.dart` | 反馈与联系 |
| `preferences_detail_page.dart` | 偏好设置详情 |
| `api_key_diagnostics_page.dart` | API 密钥诊断 |

## 拆分子目录

| 子目录 | 父页面 | 说明 |
|--------|--------|------|
| `note_editor/` | `note_full_editor_page.dart` | ai_features / build / color_and_media / document_init / location_dialogs / location_fetch / metadata_ai_section / metadata_dialog / metadata_location_section / save_and_draft (10 个) |
| `ai_report/` | `ai_periodic_report_page.dart` | card_actions / data_loading / featured_cards / overview / stats / time_selector (6 个) |

## 规范

### Material 3
- 颜色使用 `Theme.of(context).colorScheme`，禁止硬编码颜色值
- 间距/圆角使用 `Theme.of(context).xxx` 或 `AppTheme` 常量
- 图标优先使用 `Icons.*`，自定义图标走 `IconUtils`

### 国际化 (严格)
```dart
// 正确
Text(AppLocalizations.of(context)!.saveButton)
ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(content: Text(AppLocalizations.of(context)!.saveSuccess)),
);

// 错误（禁止）
Text('保存')
Text('Save')
```

### 性能
- 长列表使用 `ListView.builder` 或 `NoteListView`（已实现分页）
- 避免在 `build()` 中进行重计算，提取到 `initState` 或 Controller
- 图片使用 `OptimizedImageLoader`

### 异常处理
```dart
Future<void> _saveNote() async {
  try {
    await context.read<DatabaseService>().saveQuote(note);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(...);
    }
  } catch (e, stack) {
    logError('NotePage._saveNote', e, stack);
    if (mounted) {
      // 用国际化文案提示用户
    }
  }
}
```

### mounted 检查
- 所有 `async` 操作完成后访问 `context` 前必须检查 `mounted`
- `dispose` 后不得调用 `setState` 或 `notifyListeners`

## 复杂度警告
- `home_page.dart` 是最大页面文件，包含大量交互逻辑
- `note_full_editor_page.dart` 修改前必须阅读 `note_editor/` 子目录各文件
- `ai_periodic_report_page.dart` 修改前阅读 `ai_report/` 子目录
- 两个文件都已通过 `part`/`part of` 拆分，新增功能优先放入对应子目录文件

## 开发者模式页面
以下页面仅在开发者模式（连续点击关于页应用图标 3 次）下可见：
- `LogsPage` / `logs_settings_page.dart`（日志中心）
- `LocalAISettingsPage`（本地 AI 实验）
- `StorageManagementPage`（存储管理）
- 禁止在普通用户 UI 中直接暴露调试功能
