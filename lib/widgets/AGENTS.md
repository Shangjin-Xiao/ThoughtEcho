# Widgets 模块

本目录存放可复用 UI 组件。主要子目录包括 `ai/`、`note_list/`、`common/`、`local_ai/` 和
`onboarding/`。`add_note_dialog.dart`、`quote_item_widget.dart` 与 `note_list_view.dart` 是复杂热点。

## 组件规则

- Widget 聚焦展示和局部交互，可复用业务规则与 I/O 放到 Controller/Service。不要在 `build()`
  中发网络请求、写数据库或创建每次重建都会泄漏的 Controller。
- 能保持无状态时使用 `StatelessWidget`；需要生命周期、动画或局部瞬态状态时合理使用
  `StatefulWidget`，不为追求形式强行转换。
- 拆分长 `build()` 时按语义提取私有 Widget/独立组件，避免仅为了行数拆成难导航的小方法。
- 用户可见文本、Tooltip 和 Semantics 文案全部国际化；颜色和文本样式优先来自 Theme。
- 大列表惰性构建并使用稳定 key；少量固定 children 无需机械改成 builder。
- 异步间隔后操作 context/State 前检查 mounted。`AnimationController`、文本/滚动控制器、
  `FocusNode`、订阅和 Timer 必须释放。
- 读取一次状态使用 `context.read`，需要重建时优先 `select`、`watch` 或 `Consumer`，缩小监听范围。
- 图片、视频和富文本组件要考虑加载失败、占位、内存占用、无障碍和资源释放。

复杂 Widget 改动优先补 `test/widget/` 或 `test/unit/widgets/` 的交互回归测试，并使用已有测试
helper，不依赖真实网络、文件选择器或用户数据。
