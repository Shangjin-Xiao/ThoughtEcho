# NOTE EDITOR 子模块

`note_full_editor_page.dart` 的 `part` 拆分，共 10 个文件。

## 职责划分

| 文件 | 职责 |
|------|------|
| `editor_build.dart` | build 方法、UI 结构搭建 |
| `editor_document_init.dart` | Quill 文档初始化、控制器创建 |
| `editor_ai_features.dart` | AI 续写/润色/分析等编辑器内 AI 功能 |
| `editor_color_and_media.dart` | 颜色选择器、媒体附件（图片/视频）插入 |
| `editor_metadata_dialog.dart` | 元数据编辑弹窗（来源/作者/分类/标签） |
| `editor_metadata_ai_section.dart` | 元数据弹窗中的 AI 分析区域 |
| `editor_metadata_location_section.dart` | 元数据弹窗中的位置信息区域 |
| `editor_location_dialogs.dart` | 位置选择/天气获取弹窗 |
| `editor_location_fetch.dart` | 位置/天气数据获取逻辑 |
| `editor_save_and_draft.dart` | 保存、草稿箱、自动保存逻辑 |

## 规范

- 所有文件都是 `part of '../note_full_editor_page.dart'`，不独立 import
- 修改前**必须**阅读父文件 `_NoteFullEditorPageState` 的状态变量和生命周期方法
- 新增编辑器功能优先放入对应 part 文件，不要在父文件中堆砌
- AI 功能调用走 `AIService` 流式接口，结果回写到 Quill Controller
- 保存时必须同步更新 `content`（纯文本）和 `deltaContent`（Quill Delta JSON）
- 异步操作后访问 `context` 前必须检查 `mounted`
