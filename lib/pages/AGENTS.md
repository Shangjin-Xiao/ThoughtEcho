# PAGES 模块

## 概览
页面组件层（35+ 文件），负责完整屏幕展示和用户交互。严格遵循 Material 3 设计规范。

## 核心页面

| 文件 | 说明 |
|------|------|
| `home_page.dart` | 应用主页，底部导航，笔记列表入口 |
| `note_full_editor_page.dart` | **富文本编辑器（3083+ 行）**，FlutterQuill + 媒体附件 + 位置天气 |
| `note_qa_chat_page.dart` | AI 问答对话界面 |
| `ai_periodic_report_page.dart` | **AI 周期性分析报告（2680+ 行）** |
| `insights_page.dart` | 洞察与统计 |
| `settings_page.dart` | 设置中心 |
| `backup_restore_page.dart` | 备份与恢复管理 |
| `note_sync_page.dart` | 设备同步 |
| `ai_settings_page.dart` | AI 服务商配置 |
| `onboarding_page.dart` | 引导流程 |

## 拆分子目录

| 子目录 | 父页面 | 说明 |
|--------|--------|------|
| `note_editor/` | `note_full_editor_page.dart` | ai_features / build / color_and_media / document_init / location_dialogs / save_and_draft 等 9 个文件 |
| `ai_report/` | `ai_periodic_report_page.dart` | card_actions / data_loading / featured_cards / overview / stats / time_selector 等 6 个文件 |

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
// 页面级操作必须包裹 try-catch
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
- `note_full_editor_page.dart` 极度复杂，修改前必须阅读 `note_editor/` 子目录各文件
- `ai_periodic_report_page.dart` 涉及多种图表和数据加载，修改前阅读 `ai_report/` 子目录
- 两个文件都已通过 `part`/`part of` 拆分，新增功能优先放入对应子目录文件

## 开发者模式页面
以下页面仅在开发者模式（连续点击关于页应用图标 3 次）下可见：
- `LogsSettingsPage`（日志中心）
- `LocalAISettingsPage`（本地 AI 实验）
- `StorageManagementPage`（存储管理）
- 禁止在普通用户 UI 中直接暴露调试功能
