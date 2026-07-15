# 记录页冷 Quill 延后物化交接（2026-07-15）

## 为什么上一轮仍卡

宽度感知的可见 Delta 前缀保持了 Quill 的视觉同源，但真机 `scroll-10`
显示它把新成本放在了滚动帧里：8 个冷 Document 累计计算 110.7ms，然后冷 Quill
仍有 23.3～38.3ms 的首布局。最坏 build 帧从旧基线 152.8ms 变为 175.7ms，
所以上一轮不能算性能修复成功。

## 本轮方案

- 保留原 Quill 作为静止态唯一视觉真源；
- 已缓存的 Quill 即使再次滚动也不降级；
- 仅在 `isListScrolling=true` 且对应折叠 controller 缓存未命中时，返回
  固定 160px 高、最多 320 UTF-16 code units 的轻量纯文本预览；
- 列表停止 32ms 后的现有全局信号触发恢复队列；
- 队列每帧只创建一个 Quill，使用 `RenderAbstractViewport.getOffsetToReveal`
  优先选择视口内卡片，其他保活/预构建卡片随后处理。

## 保真边界

这不是手写富文本 renderer。当用户停下、打开或展开记录时，界面仍是原
Flutter Quill 与原 embed builders，内容与像素不另做一套实现。为换取滚动顺滑，
只有“高速滚动中首次出现的折叠卡片”在停止前短暂显示纯文本前缀。
占用高度保持 160px，不引起列表 extent 跳变。

## 自动化证据

`test/quote_content_widget_test.dart` 新增三组 TDD 回归：

1. 高速滚动中新出现的折叠富文本不创建 Quill/controller；
2. 停止后三个冷 Quill 在三帧内逐个恢复，不集中到同一帧；
3. 当第三张卡片在视口内时，它先于队列中的第一张屏外卡片恢复。

## 真机复测

用新包完全冷启动，只做一次连续下滑。重点对比失败基线：

- `docWorkUs+110739`；
- `worstBuild=175.7ms`；
- `frameJank=22`；
- `slowLayouts` 中 7 个 23.3～38.3ms 的 `rich`/`rich-image`。

期望滚动 session 中新的 Document/controller 创建接近 0，`slowLayouts` 不再出现
多个冷 rich 连续扎堆。自动化无法代替真机 vsync 评估，因此在新日志回传前，
只能确认结构性热路已移出滚动帧，不声称真机卡顿已完全消失。
