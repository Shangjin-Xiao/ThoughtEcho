# 记录页仍然卡顿 —— 日志诊断（2026-08-13）

接着 `docs/note-list-perf-handoff-2026-08-12.md`（阶段 D，折叠卡片彻底不跑 Quill）。
这份只做一件事：**用 2026-08-13 那轮 `NoteListView.Perf` 日志回答「Quill 都拿掉了，
为什么还卡」**。结论先行，证据在后，最后是按性价比排序的下一步。

---

## 一句话结论

阶段 D 优化的是**稳态**成本，而稳态从来就不是卡顿的来源。日志里所有掉帧都集中在
两类帧上，这两类阶段 D 一个都没碰：

1. **某张卡第一次被建出来 / 第一次布局**（`h=none→…`）；
2. **整个列表被 `setState` 重建一遍**（分页数据到达、`_isLoading` 翻转……）。

滑过**已经建好**的卡片时，帧时间是 `avgFrame=3.1ms / frameJank=0`——完美。
所以主观上「没减轻很多」是准确的：均值确实降了（`avgBuild` 从上一份基线的
15.6ms 降到 1.2~6.1ms），但用户感知的是那几个 **117.8ms / 123.9ms 的建帧**，
而它们和上一份基线的 157.6ms 是同一个量级。

---

## 证据：把 14 个 session 按「有没有新卡片」分两堆

| session | 场景 | frames | frameJank | avgFrame | worstFrame | worstBuild | built |
|---|---|---|---|---|---|---|---|
| scroll-10 | 往回滑，全是老卡片 | 100 | **0** | **3.1ms** | 6.2ms | 3.5ms | **0** |
| scroll-13 | 往回滑，全是老卡片 | 102 | **0** | **3.8ms** | 14.6ms | 7.9ms | **0** |
| scroll-11 | 往回滑，全是老卡片 | 8 | 0 | 3.8ms | 6.9ms | 1.9ms | 0 |
| scroll-9 | 下滑，11 张新卡 | 99 | 1 | 4.5ms | 16.8ms | 13.5ms | 11 |
| scroll-8 | 下滑，16 张新卡 | 80 | 4 | 6.8ms | 31.7ms | 28.9ms | 16 |
| scroll-5 | 下滑，23 张新卡 | 65 | 6 | 7.4ms | 25.3ms | 21.7ms | 23 |
| scroll-3 | 下滑 + loadMore | 55 | **11** | 9.7ms | 22.7ms | 21.2ms | **104** |
| scroll-4 | 几乎没动 + 分页落地 | 31 | **10** | **18.5ms** | **122.9ms** | **117.8ms** | 30 |
| scroll-14 | 往回滑 + loadMore | 231 | 4 | 5.0ms | **143.5ms** | **123.9ms** | **297** |

分界线干净得不像话：**`built=0` 的 session 一帧都不掉；`built` 大的 session 出现
三位数毫秒的建帧。** 卡顿 100% 是「第一次」的成本，稳态成本已经不是矛盾了。

顺带两个读日志时容易被骗的地方：

- **scroll-1 / scroll-2 的 `frames=0` 是仪表盲区，不是「没掉帧」。** `FrameTiming`
  是批量回调，短 session 被下一个 session 的 `_startScrollSessionPerfCapture`
  强制收尾（`note_list_scroll.dart:118`），回调还没送到。**首屏那两段——恰恰是最贵的
  两段——完全没有帧数据。** 它俩的 `eventJank=12/16` 和 `eventAvg=22.4ms` 才是真相。
- **`quoteContent={…}` 里贵的那两项没被统计。** `height=` 统计的是
  `_QuoteHeightEstimateCache`（廉价估算），真正做 `TextPainter` 实测的
  `_QuotePlainTextLayoutExpansionCache` 和 `CollapsedRichTextMetrics.plan()`
  **一个计数器都没有**。日志显示 `docWorstUs=0`、`irWorstUs=415`，看着一片绿，
  是因为它只盯着已经被优化掉的那条路。

---

## 根因一：纯文本卡片仍然排版**整篇**正文

阶段 D 给富文本上了行数预算，**纯文本一行没改**：

```dart
// lib/widgets/quote_content_widget.dart:769
Widget _buildPlainTextContent({required bool needsExpansion}) {
  Widget plainText = Text(
    quote.content,          // ← 没有 maxLines
    style: style,
    softWrap: true,
    overflow: TextOverflow.visible,
  );
  if (!showFullContent && needsExpansion) {
    plainText = _CollapsedContentWrapper(maxHeight: 160, child: plainText);
  }
  return plainText;
}
```

`_CollapsedContentWrapper` 是 `ClipRect(SizedBox(height: 160, …))`。
`RenderParagraph` **不看高度约束**——它按 `maxWidth` 把整篇正文断行、整形完，
算出自然高度，然后才被裁掉只剩 160px。一条 3000 字的笔记，折叠卡片只显示 5 行，
却付了 3000 字的排版钱。

折叠判定那一路是同一个毛病（`quote_content_widget.dart:472`）：

```dart
final painter = TextPainter(text: TextSpan(text: quote.content, style: style), …)
  ..layout(maxWidth: maxWidth);          // ← 也没有 maxLines
return painter.height > collapsedContentMaxHeight + 0.5;
```

这一路有缓存兜着（`_QuotePlainTextLayoutExpansionCache`），渲染那一路没有。

**日志对得上**：`slowLayouts` 里最慢的清一色是 `plain`——
`11.1ms / 11.6ms / 10.6ms / 9.5ms / 9.3ms`，全部 `h=none→…`（首次布局）。
而 119 条笔记里 `rich=40`，剩下 **79 条是纯文本**，`builtKind=p143/r26/m128`
也说明构建量的大头是 plain。**阶段 D 优化的是少数派。**

> 修法：判定侧用 `TextPainter(maxLines: n)` + `didExceedMaxLines`；渲染侧给
> `Text` 传 `maxLines` + `TextOverflow.clip`，`n` 由 `160 / 行高` 推出。
> 保真度不变（本来就要裁掉），成本从 O(全文) 降到 O(可见行)。

---

## 根因二：富文本卡片**每次重建**都重新量一遍，而且量两遍

`CollapsedRichTextMetrics.plan()` 在 `QuoteContent.build` 的 `LayoutBuilder` 里
直接调用（`quote_content_widget.dart:676`），**没有任何缓存**。每次重建：

- 每个可见块跑一次 `buildCollapsedBlockLayout()` + 一次 `TextPainter.layout()`（测量）；
- 然后 `_CollapsedRichTextBlock.build` 里**又**跑一次 `buildCollapsedBlockLayout()`（渲染）；
- 再由 `RenderParagraph` 做真正的排版。

也就是说同一段文字的 span 构造做了两遍，排版做了两遍。IR 解析确实很便宜
（`irWorstUs=415`，阶段 D 的功劳），但**贵的是 IR 之后的排版，那部分完全没缓存**。

---

## 根因三：37 张最贵的卡片被永久钉在树上，每次 `setState` 全部重建

```dart
// lib/widgets/note_list_view.dart:111
static bool shouldKeepAliveQuoteItem(Quote quote) {
  …
  if (deltaContent.contains('"image"') || …) return true;   // 有媒体 → 永久 keepAlive
  return QuoteItemWidget.needsExpansionFor(quote);
}
```

日志里 `pinnedKeepAlive=37`、`keepAlive=53~66`。这些 element 永远不脱离树；
而 `ListView.builder` 每次 build 都换一个新的 `SliverChildBuilderDelegate`
（`shouldRebuild` 恒为 true），所以 **`NoteListViewState` 每 `setState` 一次，
就有 55~100 张卡片重建一次**——其中 37 张正是根因二里最贵的那类。

`built=297@10-118`（scroll-14，`stateΔ=4`）、`built=104@0-46`（scroll-3）就是这么来的。
`worstBuild=123.9ms` 也是。

触发 `setState` 的源头至少有：

- **分页数据事件**：`_quotes..clear()..addAll(list)`
  （`note_list_data_stream.dart:112`、`:396`）。注意 `watchQuotes` 每次都重发
  **整个累积列表**，第 3 页到达 = 119 个**全新** `Quote` 对象替换 119 个旧对象。
  `AppConstants.scrollPreloadThreshold = 0.35` 意味着只要滑过全长的 1/3 就会触发，
  几乎每次下滑都要吃一次。
- `_scheduleExpandableQuoteCheck` 的回填（`note_list_data_stream.dart:28`）；
- `_isLoading` 收尾、`_hasMore` 同步、锚点修正……

`_scheduleIdlePrefetch` 的注释（`note_list_scroll.dart:823`）其实已经点破了这件事，
但它只是把**预取**挪到静止期；用户滑到 35% 触发的那次 `_loadMore` 仍然落在滚动帧内。

---

## 根因四：热路径上有几个 O(正文长度) 的字符串扫描（release 也在跑）

`_shouldKeepAliveNoteListItem` → `shouldKeepAliveQuoteItem` 会对**每一次 itemBuilder
调用**做 3 次 `deltaContent.contains(…)`，全量扫描整个 delta JSON，无缓存。
`delta_media_extractor.dart` 明确说明 source 可能是整段 base64 `data:` URL，
那种笔记上这一步就是每次构建扫几 MB。

`DeltaMediaCache` / `DeltaRichTextCache` 已经把这类判断缓存好了
（`readDeltaMediaEmbed` 是唯一真源），`shouldKeepAliveQuoteItem` 应该走缓存，
而不是自己再 `contains` 一遍。

另外几个每卡每帧的固定开销：`QuoteItemWidget.build` 里 7 个
`context.select<SettingsService, …>` + `QuoteContent.build` 里 2 个、
`DateTime.parse(quote.date)` + `DateFormat` 格式化、两层嵌套 `LayoutBuilder`、
每张卡一个带 `BouncingScrollPhysics` 的 `SingleChildScrollView`（=每张卡一个
独立 `ScrollPosition`）、`PopupMenuButton` + `Tooltip` + `Material/InkWell`。
单看都不贵，乘以 100 张卡的重建就是几十毫秒。

---

## 还有一个测量本身的问题

开发者模式的「首屏滚动性能监控」打开时，`_recordNoteListItemBuild` 和
`_wrapNoteListItemPerfProbe` 各调一次 `_noteListPerfKindFor(quote)`，
里面又是 3 次全量 `contains`；`_quoteMixStatsText()` 每次收尾再对 119 条各扫 3 次。
**开着监控测出来的绝对值是偏高的**，而如果你是开着它在体感流畅度，那你摸到的
有一部分就是探针自己。

这轮日志本身**已经是 release 的**（上一份交接的「下一步第 1 条」做了），
所以上面那些绝对值就是用户真实感受到的量级，只是还含着探针自己的开销。
本轮已经把探针改走缓存，下一轮的绝对值会更干净一些。

---

## 已修（本轮）

根因一、二、四**已经改掉**，都不改视觉、不改用户可见行为：

| | 改法 | 落点 |
|---|---|---|
| 纯文本排版整篇正文 | 判定与渲染各加一处 `maxLines`，行数由 `QuoteContent.collapsedPlainTextMaxLines` 按「折叠盒高 ÷ 行高下界 + 1」算 | `quote_content_widget.dart` |
| `plan()` 每次重建重量 | 加 `CollapsedRichTextPlanCache`（LRU 300，键只存内容指纹），两个调用点都带上键 | `collapsed_rich_text.dart` |
| 热路径全量 `contains` | `shouldKeepAliveQuoteItem` 改走新的 `DeltaMediaCache.hasMediaOf`（只存 bool，`data:` 笔记也能缓存） | `note_list_view.dart` / `delta_media_extractor.dart` |
| 探针自己也在扫 | `_noteListPerfKindFor`、`_quoteMixStatsText` 一并改走缓存 | `note_list/*.dart` |

行数预算**只能偏大**：多排的行落在 160px 盒子外面被 `ClipRect` 裁掉，看不见；
少排的内容是静悄悄消失的。所以行高取 `fontSize * (height ?? 1.0)` 这个下界，再 +1 行。
渲染侧还要按 `DefaultTextStyle.merge` 之后的**实际**样式算——`Text` 的字号可能整个
来自环境，照着一个 `fontSize` 为 null 的样式估就会低估行数。
`test/unit/widgets/collapsed_plain_text_budget_test.dart` 用真的 `TextPainter`
钉住了这条不变量。

顺带把测量盲区补上了：性能日志新增 `plan=`、`planMiss+`、`planWorkUs+`、`planWorstUs=`。
折叠富文本真正的排版成本一直在 `plan()` 里，而日志此前只统计便宜的 IR 解析
（`irWorstUs=415`），看着一片绿。

**根因三（37 张媒体卡永久 keepAlive + 数据事件整表替换）没动**，它是结构性的，
需要单独一轮并配基准，见下。

## 下一步（按性价比排序）

1. **切断「数据事件 → 全列表重建」**（根因三）。两个方向，选一个：
   - `watchQuotes` 分页事件改成**追加**而不是整表替换，并给 `Quote` 加值相等，
     让没变的卡片 `didUpdateWidget` 直接短路；
   - 或者把 `keepAlive` 收窄——媒体卡片永久钉住是为了防图片闪烁，但
     `imageCache` 本来就兜得住（`CollapsedMediaImage` 的注释里已经论证过一次了），
     值得重新验证「永久 keepAlive」这个前提还成不成立。
2. **`scrollPreloadThreshold` 0.35 太早**。整表替换的代价这么大，应该等到接近底部
   （0.8 左右）再触发，把它推进静止期。**会改变分页时机**，要先确认。
3. **让测量和渲染共用一份 `buildCollapsedBlockLayout`**。现在同一段文字的 span
   构造做两遍（测量一遍用 `measurement` palette、渲染一遍用主题 palette）。
   `plan()` 有缓存之后测量那遍已经不在热路径上了，收益变小，但仍然是浪费。
4. **冷启动首次滑过仍然要重解全部图片**（上一份就记着的第 3 条，与本轮正交）。
   `imageCache` 是纯内存的，重启即失。要消除首次等待需要保存时生成缩略图文件存盘。

---

## 复测口径（别再换了）

release 模式，115~119 条笔记 / `media≈32`，下滑约 28000px 后原路滑回。
只看这三个数，别看均值：

- `worstBuild` —— 改前 117.8ms / 123.9ms，这是用户唯一能感觉到的东西；
- `built=` 的峰值 —— 改前单 session 297，衡量根因三（**本轮没动，应该基本不变**）；
- `slowLayouts` 里 `plain` 的占比和耗时 —— 改前包揽前几名（11.1 / 11.6 / 10.6ms），
  衡量根因一，**本轮主要看这一项**；
- 新增的 `planMiss+` / `planWorkUs+` —— 稳态滑动里 `planMiss` 应该接近 0，
  不是 0 就说明缓存键漏了什么维度，每帧都在重量。
