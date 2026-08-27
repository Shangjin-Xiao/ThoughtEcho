# 记录页冷 Quill 每帧额度交接（2026-07-30）

## 为什么 f2f2ca51 之后真机仍卡

2026-07-26 的真机日志（f2f2ca51 之后采集）显示滚动帧里仍在编译冷 Document：

```
scroll-2 : ΔdocMiss+15, docWorkUs+64054, docWorstUs=47884, worstBuild=88.8ms
scroll-12: ΔdocMiss+8,  docWorkUs+85670, docWorstUs=36272, worstBuild=88.7ms
scroll-1 : ΔdocMiss+13, docWorkUs+22472, ctrlCreate+13,   Δbytes+32.6MB  ← 首屏
```

`worstRaster` 全程 12~25ms、`avgRaster` 3~5ms，瓶颈仍在 UI/build 线程。

根因不是 f2f2ca51 的机制写错了，而是它的**触发条件覆盖不全**：占位路径要求
`isListScrolling || isListDragActive`。这两个信号只在"正在滚动"期间为真，而下面三种
场景都发生在信号为 false 时，一帧内可以同时挂载多张冷卡片：

1. **首屏首帧**——列表还没动过，所有闸门都是开的，13 份 Document + 13 个 controller
   一次性同步付清；
2. **惯性停止后的补建**——`_scheduleScrollEndSettledWork` 在 ScrollEnd 后 32ms 就把
   `isListScrolling` 置 false，此后新挂载的卡片不再受恢复队列的逐帧节流；
3. **`scrollCacheExtent` 屏幕外预构建**——缓存区最多 900px，静止时也会建新 item。

恢复队列只管"已经挂成占位"的卡片，对上述新建卡片完全不生效，所以一帧里凑出
2~5 次 20~48ms 的 Quill 首布局，累成 88~135ms 的 `worstBuild`。

## 本轮改动

新增 `_ColdCollapsedQuillFrameBudget`（`quote_content_deferred.dart`）：折叠态冷 Quill
的创建额度改为**每帧一次，与滚动状态无关**。

- 滚动/拖拽期间：行为不变，一律零创建；
- 列表静止时：本帧第一张冷卡片正常创建，其余退回同尺寸 160px 轻量占位并入队，
  由恢复队列逐帧补齐；
- 恢复队列自身也扣除额度，避免"队列补一张 + 列表新建一张"又凑成两次首布局；
- `_buildRichTextContent` 新增 `deferralResolved`，队列回调走这条路径时不再重新判定
  额度，否则已物化的卡片会被打回占位。

单卡片场景（只有一张冷卡片进入视口）行为完全不变，不引入额外占位闪动。

## 保真边界

占位仍是 f2f2ca51 那一套：固定 160px 高、最多 320 UTF-16 code units 的纯文本前缀，
不改变列表 extent。静止画面仍由原 Quill 绘制。相比上一轮，**首屏现在也会出现
短暂的占位**（首帧 1 张真 Quill + 其余占位，随后每帧补一张），这是本轮唯一的观感
变化，换取首帧不再一次付清全部首布局。

## 自动化证据

`test/quote_content_widget_test.dart` 新增「列表静止时一帧内也只创建一个冷 Quill」：
3 张冷富文本在 `isListScrolling=false` 下挂载，断言首帧只有 1 个 `QuillEditor`、
`controller.createCount == 1`，随后两帧逐个补齐。改动前该用例失败（首帧 3 个）。

该文件 17 项、`quote_item_widget_test.dart` 26 项、`quote_content_cache_test.dart` 与
`cache_fix_verification_test.dart` 全部通过；3 个改动文件 `flutter analyze` 无问题。

## 真机复测

用新包完全冷启动，一次连续下滑到底，复制卡顿位置的滚动性能摘要，重点对比：

- `ΔdocMiss` / `docWorkUs`——应显著低于 64054~85670；
- `docWorstUs`——单份文档不应再出现 36~48ms 与同帧扎堆；
- `worstBuild`——应显著低于 88.8ms；
- 首屏（`scroll-1`）的 `ctrlCreate` 增量应从 13 降到个位数。

若 `docWorkUs` 已接近 0 但仍有体感卡顿，则剩余成本在 Quill 单次首布局本身
（20~38ms/张），那才是"折叠态换轻量渲染器"值得投入的信号。

## 已知未覆盖（不在本轮）

- **`needsExpansion == false` 的富文本卡片仍不受额度约束**：占位依赖固定 160px 高度，
  非折叠卡片高度由内容决定，套占位会引起 extent 跳变。这类卡片按定义内容较短，
  暂不认为是主要成本来源，但它是这套机制的结构性缺口。
- ~~**`note_list_items.dart:520` 的 `EdgeInsets.only(top: -1)`**~~：已在同日后续提交修复，
  见下节。

## 附：ListView 负 padding 断言（2026-07-30 同日修复）

`89be17a8` 为收紧首条笔记与搜索框的间距，给 ListView 加了 `EdgeInsets.only(top: -2)`
（`7a465c6a` 回调为 `-1`）。ListView 的 padding 会被包成 `SliverPadding`，负值命中
`RenderSliverPadding` 的 `assert(padding.isNonNegative)`：

- release 关闭断言，真机看不出问题，1px 收紧视觉上是生效的；
- debug 与测试中 ListView 一挂载就抛异常，导致
  `note_list_view_filter_test.dart`（18 项）、`note_list_scroll_controller_test.dart` 与
  `note_list_search_transition_test.dart`（共 3 项）全部失败。

用户确认间距改回卡片自身的 6px（`quote_item_widget.dart` 的 `cardMargin`
`vertical: 6`），因此直接删除该 padding，负值随之消失。上述 24 项测试全部转绿。

**后续若还要调这个间距**：不要再用负 padding。改 `cardMargin` 的 vertical 值，或给
ListView 加**非负** padding，否则会再次踩到同一个断言。
