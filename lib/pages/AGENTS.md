# Pages 模块

页面层负责路由目标、页面级状态组合和用户反馈，遵循 Material 3。复杂页面已经通过子目录或
`part` 文件拆分：

- `note_editor/`：富文本编辑器，10 个 part，另见该目录 `AGENTS.md`
- `ai_report/`：AI 周期报告，4 个 part
- `ai_assistant/`：助手会话、工作流和 UI 拆分
- `home/`：主页局部面板

## UI 规则

- 所有用户可见文本使用 `AppLocalizations`，包括 Tooltip、SnackBar、Dialog、菜单、空状态和
  Semantics 文案。
- 颜色、排版和形状优先来自 `Theme.of(context)` / `ColorScheme`，不要在页面散落硬编码颜色。
- 大数据列表使用惰性构建（如 `ListView.builder`、sliver 或现有分页组件）；少量固定项无需为
  规则机械改写。
- 异步间隔后使用 `context`、`setState` 或导航前检查 `mounted` / `context.mounted`。
- 页面捕获用户操作异常，记录技术上下文，并展示国际化、可行动的反馈；不显示原始堆栈、SQL
  或密钥。
- 页面只编排 Service/Controller，不在 `build()` 中执行 I/O，不复制数据库和网络业务规则。

## 复杂页面

`home_page.dart`、`settings_page.dart`、`note_sync_page.dart`、`annual_report_page.dart`、
`smart_push_settings_page.dart`、`tag_settings_page.dart` 和 `category_settings_page.dart` 均有较多
状态或交互。修改前先搜索关联 Service、part/辅助文件、路由入口和 Widget 测试。新增功能优先
放入现有职责对应的子组件，不继续扩大父页面。

开发者页面（日志、本地 AI、存储管理、数据库/诊断工具）必须受现有开发者模式或 debug 条件
保护，不得出现在普通用户路径。
