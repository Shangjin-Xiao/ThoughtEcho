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

## 列表卡片的 element 预算

`quote_item_widget.dart` 是记录页首滑掉帧的直接来源：卡片第一次建出来的成本几乎与
内容无关，只与这棵树有多大有关，而首滑一次要新建三十多张。往卡片上随手加一层
`Tooltip`、一个 `IconButton`、一个 `SingleChildScrollView`，代价都要乘以那个张数 ——
实测曾经一张**最小**卡片 146 个 element，其中两个动作按钮占 99，正文只占 3 个。

- 上限由 `test/widget/widgets/quote_item_element_budget_test.dart` 钉住，
  要涨就连同「为什么值得」一起改那里。
- 只在折叠态可能变化的卡片上挂动画机件（`AnimatedSize` / `AnimatedSwitcher` /
  `AnimationController`）；静态卡片一律不挂。
- 触摸端不给卡片内的图标按钮挂 `Tooltip`（长按弹不出来或位子被占），
  无障碍名称用 `Semantics(button: true, label: ...)` 单独给。
- 折叠测量（判定、排版、图片解码）有空闲预热，见
  `lib/widgets/note_list/note_list_warmup.dart`。**改任何一处测量入参前先想一下预热那边**，
  两边的缓存键必须逐字节相同，回归测试在 `collapsed_layout_warmup_test.dart`。

复杂 Widget 改动优先补 `test/widget/` 或 `test/unit/widgets/` 的交互回归测试，并使用已有测试
helper，不依赖真实网络、文件选择器或用户数据。
