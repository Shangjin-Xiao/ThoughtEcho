# Note Editor 子模块

本目录是 `note_full_editor_page.dart` 的 10 个流程/UI `part` 文件。页面 State 只组合
`NoteEditorState`、`NoteEditorMetadataState` 和 `NoteEditorMediaState`；part 必须通过对应状态模块
读写数据，禁止重新向 `_NoteFullEditorPageState` 增加跨 part 的私有状态别名。

## 职责划分

| 文件 | 职责 |
|---|---|
| `editor_build.dart` | 页面结构和编辑器 UI |
| `editor_document_init.dart` | Quill 文档、Controller 和初始内容 |
| `editor_ai_features.dart` | 编辑器内 AI 续写、润色和分析 |
| `editor_color_and_media.dart` | 颜色和媒体附件插入 |
| `editor_metadata_dialog.dart` | 来源、作者、分类、标签等元数据弹窗 |
| `editor_metadata_ai_section.dart` | 元数据弹窗 AI 区域 |
| `editor_metadata_location_section.dart` | 元数据弹窗位置区域 |
| `editor_location_dialogs.dart` | 位置选择与天气弹窗 |
| `editor_location_fetch.dart` | 位置和天气数据获取 |
| `editor_save_and_draft.dart` | 保存、草稿和自动保存 |

## 修改规则

- 文件目前保持 `part of '../note_full_editor_page.dart'`，不能自行添加 import；依赖在父文件集中
  声明。这里的 part 只拆流程和 UI，不拥有共享状态。
- 修改前阅读三个 editor 状态模块、父页面的组合生命周期和保存路径；新增可观察状态及其不变量
  放入职责对应的状态模块，父页面只做初始化、组合和页面级编排。
- 保存、自动保存、草稿恢复和 AI 回写必须同步维护纯文本 `content` 与 Delta JSON
  `deltaContent`，并保留光标/selection 的合理状态。
- 调用 AI 时沿用当前流式接口和取消/错误处理，不在 UI part 中新增 Provider 协议分支。
- 媒体插入同时检查临时文件转正、引用记录、失败清理和恢复流程，避免孤儿文件。
- 异步间隔后访问 `context`、Navigator、QuillController 或 `setState` 前检查 State 是否仍挂载，
  并避免已释放 Controller 被回调使用。
- 用户文案必须更新中英文 ARB 并生成 l10n；修改 Quill API 前按根指令查询当前官方文档。

优先运行 `test/widget/pages/note_editor_draft_behavior_test.dart` 及与改动直接相关的 Widget/Unit
测试，不主动运行全量套件。
