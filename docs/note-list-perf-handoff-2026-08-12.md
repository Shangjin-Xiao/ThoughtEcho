# 记录页性能 —— 交接（2026-08-12）

接着 2026-08-08 那份交接往下写。上一份定位了卡顿的两个来源并规划了「阶段 D」，
这份记录 **D 做完了什么、行为变了哪些、下一步测什么**。

---

## 一句话结论

**折叠卡片已经完全不跑 `QuillEditor` 了。** 上一份点名的两个卡顿来源
（O(n²) 折叠截断、冷 Quill 首布局）连同它们的整套时序补丁一起删掉了。

## 做了什么

| | 旧 | 新 |
|---|---|---|
| 折叠正文 | `QuillEditor` + 截断过的 `Document` | `Text.rich`（`CollapsedRichText`） |
| 截断 | `_truncateDeltaOpsForCollapsedDocument`，每加一个 op 重排全部已累积 span（O(n²)，单次最坏 14.5ms，在滚动帧内） | 行数预算封顶，工作量与正文长度无关 |
| 滚动期间 | 显示 `Text(quote.content)` 占位，停下才换 Quill | 第一帧就是最终形态，没有占位 |
| 折叠判定 | 富文本走「28 字符算一行」静态估算 | `TextPainter` 实测，与纯文本同一口径 |
| 短富文本卡片 | 走 Quill（`showFullContent` 为 true） | 也走 `Text.rich` |

新增两个文件：

- `lib/utils/delta_rich_text_parser.dart` —— Delta → 块/段 IR，纯函数。
  **IR 不含任何主题信息**，所以缓存键只是内容指纹，换主题不作废。
- `lib/widgets/note_list/collapsed_rich_text.dart` —— 按 IR 排 `Text.rich`，
  外加 `CollapsedRichTextMetrics.plan()`。

删除：`quote_content_deferred.dart` 整个文件（占位、每帧额度、恢复队列）、
折叠截断整套、无人调用的 `prewarmDocumentCache`。

**没删**（上一份的删除清单在这两处过宽）：

- `isListScrolling` / `isListDragActive` —— 富文本物化只是它们五个消费者之一。
  图片解码门控、空闲预取、`loadMore` 收尾、滚动锚点仍在用。
- `_QuoteContentControllerCache` / `_QuoteDocumentCache` —— 展开态和全屏预览仍然
  是真 Quill，没有缓存的话每次 rebuild 都要重建 controller。

## 关键设计：测量与渲染同源

`CollapsedRichTextMetrics.plan()` **一次**算出「画哪些块、每块几行、一共多高」，
盒子的高度和要画的内容都从这一次的结果来。

这不是洁癖。中间版本里两者是分开算的，行数预算按「每块扣 1 行」估——于是一个填满
整屏的长段落只扣掉 1 行，**它后面的媒体照样被建出来、照样解码**。预算必须按
`painter.computeLineMetrics().length` 实际用掉的行数扣。改这块时留意这个坑。

## 行为变化（用户可见）

1. **带媒体的笔记一律可展开**。以前靠高度阈值猜，「一张图配一句话」会因为算出来
   不到 160px 而失去展开入口，图片再也放不大。现在只要有媒体就给展开入口——折叠态
   无论哪种版式都不会把媒体按原尺寸画出来，「还有没有更多可看」的答案恒为是。
2. **折叠盒高度是实测的**，媒体摘走后正文只剩一两行就取那几行的高度，不再留空白。
3. **inline 版式不再实例化播放器**：视频/音频在折叠态只画占位，播放入口在展开态。
4. **加粗内容优先**改成块（行）粒度。以前在 op 粒度上把加粗片段拼到前面，一行里
   只加粗了半句时会把那半句单独拽出来，读起来是断的。
5. 缩略图改 `Alignment.topCenter`（长截图保住顶部）；展开遮罩给缩略图让位；
   正文比缩略图矮时改居中对齐。

## 保真范围

**逐项还原**：粗体、斜体、下划线、删除线、字色、背景色、字号、字体族、行内代码、
列表符号、引用左线、标题层级。字号 token 和标题字号取 `flutter_quill` 的
`DefaultStyles` 默认值（small=10 / large=18 / huge=22，h1=34 / h2=30 / h3=24），
折叠态和展开态同屏出现在一个列表里，差一号很显眼。

**刻意不还原**：块级间距细节（`VerticalSpacing`）、多级嵌套列表缩进、表格、
代码块内边距——折叠卡片只有 5~6 行，这些本来就看不全。

**刻意不同**：quill 的引用左线（`grey.shade300`）、行内代码底（`grey.shade100`）、
代码块字色（`blue.shade900`）都是固定浅色，暗色模式下会变成刺眼白块或对比度不足。
折叠卡片改用 surface / outline 令牌。**用户自己标的颜色仍然逐位还原**，换掉的只有
quill 自己的装饰色。

## 验证

- `test/unit/utils/delta_rich_text_parser_test.dart` —— 属性映射逐项断言 `TextStyle`
- `test/widget/widgets/collapsed_rich_text_golden_test.dart` —— golden 基线
- ⚠️ **golden 管几何和颜色，不管字重**。`flutter_test` 的默认字体把每个字形都画成
  同样的方块，粗体 / 斜体 / 字体族在图里看不出差别——恰好是「要 1:1」清单上最要紧的
  几项。那几项靠上面的单测，比截图更严格，也不会随字体版本漂。两者合起来才是完整
  防线，别以为有 golden 就够了。
- 重录基线：`flutter test --update-goldens test/widget/widgets/collapsed_rich_text_golden_test.dart`。
  图变了先看清是修好了还是弄坏了，别顺手重录。

全量 `test/unit`、`test/widget`、`test/bug_fixes` 与根目录用例通过（1724 + 203）。
`test/performance/` 下 4 个用例在容器/CI 里因墙钟断言和离屏渲染超时失败，
**main 基线上同样失败**，与改动无关。

## 下一步

1. **实机复测，这是最重要的一条。** release 模式跑和上一份同样的滚动会话
   （115 条笔记 / media=32 / 下滑 28066px），对比 `avgBuild` / `worstBuild`。
   上一份的基线是 `avgBuild=15.6ms  worstBuild=157.6ms(首屏)`。
   日志开关：开发者模式 →「首屏滚动性能监控」，tag `NoteListView.Perf`，
   找 `滚动性能摘要(复制此行)`。
   注意 `docWorstUs` 这个指标现在只反映展开态的 Document 构建，折叠态已经不建
   Document——想看折叠态的成本要读 `DeltaRichTextCache.stats` 的 `worstWorkMicros`。
2. **三选一版式要不要收敛。** 上一份记的用户决定是「先保留，D 做完再定」。现在
   inline 确实变好了：滚动时媒体能加载、不建播放器、位置完全保真。可以实机比一比
   再决定。
3. **冷启动首次滑过仍然要重解全部图片。** `imageCache` 是纯内存的，重启即失。
   要消除首次等待需要**保存时生成缩略图文件存盘**，目前完全没有磁盘缩略图。
   这是剩下的最大一块，且与本轮改动正交。
4. **待办：点视频缩略图播放。** 项目里没有独立的全屏视频页，`MediaPlayerWidget`
   只活在 Quill 嵌入里。最便宜的做法仍然是「点视频缩略图 = 展开卡片」。

## 仍然有效的代码陷阱

上一份那节基本还成立，其中这几条这轮又被踩到或变得更要紧：

- **音频嵌在 `insert.custom.audio`，不在顶层。** 现在这三种形状的判断**只在
  `delta_media_extractor.dart` 的 `readDeltaMediaEmbed` 里有一份**，
  `isDeltaMediaInsert`、`parseDeltaMedia` 和 IR 解析都从那里取。改媒体序列化只改
  那一处。
- **`SettingsService` 的 fake 要跟着补。** 折叠卡片每次 build 都要问
  `noteCardMediaStyle`，这轮因此让三个笔记列表测试的 `_FakeSettingsService` 炸了
  （它们的 `noSuchMethod` 是显式抛异常的）。新增任何 `SettingsService` getter 之前
  先 `grep -rln "implements SettingsService" test/`。
- **`deltaContent != null` ⟺ `editSource == 'fullscreen'`** 仍是全项目不变量。
- **`flutter_quill` 必须 ≥ 11.5.1**，别回退。
- 上一份「`_CollapsedContentWrapper` 必须定高」的**理由已经失效**（没有占位了，
  不会在物化那一刻跳），但盒子仍然定高：高度只由内容和宽度决定，同一次布局里每帧
  同值。定高裁剪只给真正需要折叠的卡片，短卡片让 `Text.rich` 自然定高——测量与渲染
  差半个像素，套在短卡片上就会啃掉一截下伸部。
