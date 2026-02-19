# PAGES MODULE

## OVERVIEW
页面组件层 (33+ files)，负责完整的屏幕展示和用户交互。

## CORE PAGES
- `home_page.dart`: 应用主页，包含底部导航和核心功能入口。
- `note_full_editor_page.dart`: 富文本编辑器 (3083 lines)，处理 Quill 编辑、多媒体附件。
- `note_qa_chat_page.dart`: AI 问答对话界面。
- `ai_periodic_report_page.dart`: AI 周期性分析报告。
- `insights_page.dart`: 洞察与统计页面。
- `settings_page.dart`: 设置中心。
- `backup_restore_page.dart`: 备份与恢复管理。

## CONVENTIONS
- **Material 3**: 严格遵循 M3 设计规范，使用 `Theme.of(context).colorScheme`。
- **国际化 (i18n)**: 严禁硬编码文案，使用 `AppLocalizations.of(context)`。
- **性能**: 对于长列表页面（如 `NoteListView`），确保使用分页或流式加载。
- **异常捕获**: 页面级操作应包裹 try-catch，并使用 `UnifiedLogService` 记录。

## COMPLEXITY WARNING
- `note_full_editor_page.dart` 和 `ai_periodic_report_page.dart` 逻辑极为复杂，修改前请务必阅读相关注释并理解数据流。
