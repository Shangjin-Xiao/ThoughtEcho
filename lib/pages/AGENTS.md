# PAGES 模块

页面组件层，Material 3 设计。拆分子目录：
- `note_editor/` — 富文本编辑器（10 个 part 文件，见子目录 AGENTS.md）
- `ai_report/` — AI 周期报告（6 个 part 文件）

## 复杂度警告
多个页面超 40k 行（`home_page`、`smart_push_settings`、`tag_settings`、`category_settings`、`annual_report`、`note_sync`、`settings`、`add_note_dialog`），修改前务必确认影响范围。

## 规范
- **国际化（严格）**：禁止硬编码任何用户可见文本，必须 `AppLocalizations.of(context)!.xxx`
- **颜色/间距**：用 `Theme.of(context).colorScheme`，禁止硬编码 `Color(0x...)`
- **长列表**：必须 `ListView.builder`，禁止 `Column(children: items.map(...)`
- **mounted 检查**：所有 async 操作后访问 context 前必须 `if (mounted)`
- **try-catch**：页面级操作必须包裹，异常 `logError` 后用国际化文案提示用户

## 开发者模式页面
仅开发者模式可见：`LogsSettingsPage`、`LocalAISettingsPage`、`StorageManagementPage`。禁止在普通 UI 暴露。
