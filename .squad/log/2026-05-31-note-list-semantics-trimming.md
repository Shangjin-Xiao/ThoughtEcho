# 2026-05-31 记录列表语义裁剪性能修复

## 背景

用户在 Profile 模式下采集了约 100 条含媒体笔记的记录页滚动数据，并提供了 Gemini 对
`PipelineOwner.flushSemantics` 的判断。接手时先核对 `.squad/decisions.md`、5 月 24 日
旧交接记录，以及本次两个 DevTools 导出文件。

## 定位证据

`dart_devtools_2026-05-31_12_08_07.627.json` 的 CPU profiler 显示：

- `PipelineOwner.flushSemantics` inclusive 占 `31.6%`，是当前采样窗口第一梯队热点。
- `SemanticsOwner.sendSemanticsUpdate` 占 `19.3%`。
- `FlutterView.updateSemantics` native leaf 占 `14.1%`。
- 同一窗口还存在其他热点：`flushLayout 26.1%`、`BuildOwner.buildScope 21.3%`、
  `TextPainter.layout 10.0%`、图片 `ImmutableBuffer.fromUint8List 9.4%`、
  FlutterQuill layout 约 `7%`。

结论：Gemini 对 semantics 热点的判断有数据支撑，但“彻底消除卡顿”的表述过强；
语义裁剪只能解决一个主要热点，不能覆盖全部滚动成本。

## 修改内容

- `lib/widgets/note_list/note_list_items.dart`
  - 在 `ListView.builder` 增加 `addSemanticIndexes: false`，关闭自动列表语义索引。
  - 同步设置 `semanticChildCount`，保留列表总数语义信息，减少无障碍回归风险。
- `lib/widgets/quote_item_widget.dart`
  - 对纯装饰图标、折叠底部毛玻璃/渐变遮罩、双击高亮覆盖层增加 `ExcludeSemantics`。
  - 保留折叠提示文字（`doubleTapToViewFull`）的语义，避免屏幕阅读器丢失展开提示。
  - 没有包裹卡片最外层渐变容器，因为那会连同正文、日期、标签和按钮一起从语义树移除。
- `test/widget/note_list_view_filter_test.dart`
  - 增加列表语义索引关闭的回归测试。
  - 修正过期的 `cacheExtent == 250` 断言，当前架构已采用 `400~900` 大缓存区。
- `test/widgets/quote_item_widget_test.dart`
  - 增加折叠遮罩被 `ExcludeSemantics` 包裹的回归测试。

## 视觉影响

本次修改只增加语义树裁剪 widget，不改变布局、颜色、动画、尺寸、边距或绘制参数。
预期视觉效果保持不变。

## 无障碍说明

`addSemanticIndexes: false` 会关闭所有列表项的自动顺序语义索引，而不只影响屏外缓存项。
这意味着屏幕阅读器可能不再播报类似“第 N 项，共 M 项”的列表位置信息。当前选择该权衡是为了
降低大缓存区记录列表的 `flushSemantics` 成本；后续如果做专项无障碍优化，可评估是否以更轻量的
手动 `Semantics` 节点补回必要的位置信息。

## 验证

已执行：

```bash
dart format --set-exit-if-changed lib/widgets/note_list/note_list_items.dart lib/widgets/quote_item_widget.dart test/widget/note_list_view_filter_test.dart test/widgets/quote_item_widget_test.dart
timeout 60s flutter test --reporter compact test/widget/note_list_view_filter_test.dart
timeout 60s flutter test --reporter compact test/widgets/quote_item_widget_test.dart
timeout 60s flutter analyze --no-fatal-infos lib/widgets/note_list/note_list_items.dart lib/widgets/quote_item_widget.dart test/widget/note_list_view_filter_test.dart test/widgets/quote_item_widget_test.dart
```

结果：相关测试通过，静态分析无 issues。

## 后续建议

用同样的 Profile 滚动流程复测，重点看 `PipelineOwner.flushSemantics` 是否下降。
如果卡顿仍明显，下一优先级应分析：

1. `quote_item_widget.dart` 中头部 `_measureSingleLineTextWidth` / `TextPainter` 测量。
2. 富文本和媒体导致的 FlutterQuill layout / 图片解码成本。
3. `NoteListView` item `GlobalKey` 在长列表中的 element 管理成本。
