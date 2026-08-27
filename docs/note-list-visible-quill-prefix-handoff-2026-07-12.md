# 记录页折叠 Quill 可见前缀交接（2026-07-12）

## 问题

真机持续下滑时，连续图文记录首次进入布局会形成明显停顿。最新可信 session 中没有分页、
数据流或状态更新，UI build 峰值为 152.8ms；7 个首次 `rich`/`rich-image` layout 合计约
144ms。图片解码已被现有占位延迟，瓶颈是 Quill/embed 的首次 Widget/RenderObject 布局。

## 根因细化

折叠区只显示 160px，但旧 `_collapsedDocumentHeightBudget` 为 640px。Flutter Quill 的
`RenderEditor.performLayout()` 会遍历 Document 的全部 child，外层 `ClipRect/SizedBox` 只会
裁掉绘制结果，不会跳过不可见 child 的 layout。因此被截掉的后续文字和图片占位仍消耗 UI
线程。

## 本次实现

- 折叠富文本进入 `LayoutBuilder`，以真实宽度生成可见 Delta 前缀；
- 连续文本使用 `TextPainter` 测量，并二分保留能覆盖 160px + 96px guard 的 Unicode 前缀；
- 图片采用当前占位最小高度的保守估计，边界相交 embed 始终保留；
- 最终仍由原 `QuillEditor`、原 custom styles 和原 embed builders 绘制；
- 展开态不截断；
- 缓存键加入宽度、style、文字方向、text scaler 和 locale；
- 移除无法复用的宽度无关 controller 预热。

## 自动化证据

新增/更新测试覆盖：

1. 旧实现保留 1 张不可见图片、修改后为 0（已完成 red → green）；
2. 前缀 Quill 与完整 Quill 裁剪后的前 160px 原始 RGBA 完全相同；
3. 280px 与 560px 宽度产生不同前缀，证明缓存不会串用；
4. 展开态仍包含全部图片和文本；
5. QuoteItemWidget 与 NoteListView 相关回归。

## 真机复测

发布后使用相同的 102 条数据从顶部持续滑到底，复制发生停顿的
`滚动性能摘要(复制此行)`。重点对比：

- `rich-image itemLayout.worst`（基线 19.0～27.2ms）；
- `worstBuild`（基线 152.8ms）；
- `frameJank`（基线 14）；
- `imageEmbed Δdefer` 与每个 session 的 `slowLayouts` 数量。

如果图文 item 仍稳定超过 16.7ms，下一步不是手写 renderer，而是只对高速滚动中新建的冷
Quill 延迟 materialize；已经显示的 item 不随滚动状态降级，停止后按可见优先分批恢复真实
Quill。
