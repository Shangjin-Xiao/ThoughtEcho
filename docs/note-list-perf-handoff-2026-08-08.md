# 记录页性能与折叠卡片版式 —— 交接文档（2026-08-08）

## 这份文档是给谁的

接手「记录页滚动卡顿」这条线的下一个人。前面已经合并了两个 PR（#455、#459），
它们解决的是**图片加载时序和卡片版式**；**卡顿本身基本没动**，那是接下来的工作。

读之前请先接受一个结论：**记录页卡顿的大头在 build，不在 raster，也不在内存。**
下面所有取舍都建立在这条之上，证据在第二节。

---

## 一、已经做完的（#455 + #459，均已合并）

### 起因

用户报三个现象：

1. 图片三段式出现：滚动时先什么都没有 → 灰色占位 → 才加载出图片
2. 滑回来时已加载过的图又变回灰色重新加载
3. 滚动停下瞬间富文本闪一下

### 诊断（关键，别重新推一遍）

这三个现象来自**三层各自独立的「延迟物化」叠加**，用户看到的每个阶段恰好对应
一层门控放行：

| 用户看到 | 代码 |
|---|---|
| ① 什么都没有 | `_DeferredRichTextContent`（`quote_content_deferred.dart`）滚动/拖拽期间只渲染 `Text(预览文字)`，**图片根本不在 widget 树里** |
| ② 灰色占位 | `_LazyQuillImage` 的 `_shouldLoad` 初始为 false |
| ③ 图出来 | postFrame + `Timer(80~120ms)` 之后才**创建** `Image` widget |
| 停下闪一下 | `_DeferredRichTextContent` 把 `Text` 换成 `QuillEditor` |

**决定性证据**：日志里 `imageEmbed={start=1, defer=0, ... Δstart+0}`。`defer=0` 说明
`_LazyQuillImage` 的两个延迟分支**一次都没被走到** —— 因为上游 Quill 压根没物化，
图片 widget 不存在。所以「先删图片自建门控」是无效的，必须先把媒体移出 Quill。

### 改了什么

**#455**
- 新增 `lib/utils/delta_media_extractor.dart`：`DeltaMediaSummary` / `parseDeltaMedia`
  / `DeltaMediaCache`（纯函数 + LRU，不做 IO）
- 折叠态从 Quill 文档剥离媒体（`_stripMediaOps`），改由独立 widget 渲染
- **删掉 `_LazyQuillImage` 的自建加载门控**。`Image` 内部的 `ScrollAwareImageProvider`
  本来就实现了「快滚时延迟解码、但缓存命中永不延迟」，自建门控跑在 `Image` 被创建
  **之前**，对命中和未命中一视同仁地砍掉一帧加 80~120ms
- `main.dart` 显式设定 `imageCache` 上限（64MB / 1000 条）
- `ImageCacheService` → `SvgRasterCacheService`（它只缓存 SVG 光栅字节，与
  `PaintingBinding.imageCache` 无关，旧名字会把排查带偏）
- `pubspec.lock` 升 `flutter_quill` 11.5.0 → 11.5.1：**Flutter 全部 3.44.x 都给
  `TextInputClient` 加了 `onFocusReceived`，11.5.0 没实现，任何引入 quill 的测试
  都编译失败**。这条别回退。

**#459**
- 折叠卡片媒体版式三选一（`NoteCardMediaStyle`，开发者模式可切换）：
  `thumbnail`（右侧 72×72 方图）/ `inline`（原位，旧版式）/ `banner`（顶部通栏）
- 折叠盒高度改为按「剥离媒体后的估算」算出的**固定值**（`collapsedBoxHeightFor`）
- 媒体可点击打开大图预览

---

## 二、当前的性能画像（**release 模式**实测）

数据来自 115 条笔记 / rich=40 / media=32、连续下滑 28066px 的滚动会话日志。
开启方式：开发者模式 → 「首屏滚动性能监控」，日志 tag `NoteListView.Perf`，
找 `滚动性能摘要(复制此行)`。

```
avgBuild=15.6ms   worstBuild=157.6ms(首屏)
avgRaster=7.4ms   worstRaster=70.2ms
docWorstUs=14506  ← 单次折叠文档构建最坏 14.5ms，发生在滚动帧内
imageCache bytes=15.4MB/100.0MB  ← 内存从来不是瓶颈
```

### 三条必须记住的结论

1. **build 是瓶颈，raster 不是。** `avgBuild` 是 `avgRaster` 的两倍。
2. **内存不是瓶颈。** 15.4MB / 100MB，离淘汰门槛很远。
   → 因此「换小图省内存」这个理由**不成立**（#455 里我用错了这个理由，见第五节）。
3. **这些是 release 数据**，没有 debug 放大。

### 卡顿的两个已定位来源（都还没修）

| 来源 | 位置 | 成本 |
|---|---|---|
| 折叠截断的 O(n²) 测量 | `quote_content_widget.dart` 的 `_truncateDeltaOpsForCollapsedDocument` | 单次最坏 **14.5ms**，滚动帧内 |
| 冷 Quill 首布局 + 占位→Quill 切换 | `quote_content_deferred.dart` | 20~48ms/张；静止 475ms 内建了 14 个 document |

O(n²) 的具体形状：循环里每加一个 op 就调 `_estimateCollapsedPrefixHeight(candidateOps)`，
而后者把**已累积的全部 span** 重新塞进新 `TextPainter` 再 layout 一次。

---

## 三、接下来要做的：阶段 D

### 目标

让折叠卡片**彻底不跑 `QuillEditor`**。这一步同时消除上面两个来源：截断逻辑不再存在
（摘要在别处算好），冷 Quill 首布局不再存在（没有 Quill）。

### 两个档次，先做 D1

| | 做法 | 代价 |
|---|---|---|
| **D1（先做这个）** | 运行时把 Delta 转成 `InlineSpan`，结果按内容签名缓存；卡片用 `Text.rich` 渲染 | 不动 DB、不用迁移。转换是纯数据变换（O(ops)，无布局、无 RenderObject），比 Quill 建整棵编辑器树便宜两个数量级 |
| **D2（D1 不够再上）** | 保存笔记时把前 N 行压成 runs JSON 存进 DB 新字段，卡片直接映射 | 更快，但要加字段 + migration + 老笔记回填 |

### 转换器不用从零写

`lib/services/delta_to_pdf_parser.dart` **已经是一个在跑的 Delta 遍历器**：
bold / italic / underline / color / list(ordered+bullet) / header / blockquote /
code-block 都处理了，只是输出 `pw.TextSpan` 给 PDF 导出。新代码是**换输出类型**，
不是重写遍历。

### 范围（已与用户确认）

**要求 1:1 还原的**：粗体、斜体、下划线、删除线、字色、背景色、字号、行高、
列表符号、引用左线、行内代码。

**不用费力气对齐的**（用户明确表态）：Quill 的块级间距细节（`VerticalSpacing`）、
多级嵌套列表缩进、表格、代码块的内边距背景。折叠卡片只显示 160px ≈ 5~6 行，
这些在窗口里本来就看不全。

**验证手段**：加 golden test —— 改动前对典型笔记（粗体/标题/列表/引用/代码/带图）
截一组基线图，改完逐张比对。这是当前架构给不了的验证方式，务必先建基线再动手。

### D 之后删什么、留什么

| 会删 | 会留 |
|---|---|
| `quote_content_deferred.dart` 整个文件（`_DeferredRichTextContent`、`_DeferredRichTextMaterializationQueue`、`_ColdCollapsedQuillFrameBudget`） | `DeltaMediaSummary` / `parseDeltaMedia` / `DeltaMediaCache` |
| `_QuoteContentControllerCache`（卡片不再需要 `QuillController` / `FocusNode` / `ScrollController`） | `CollapsedMediaImage` / `CollapsedMediaThumbnail` / `CollapsedMediaBanner` |
| 全局信号 `isListScrolling` / `isListDragActive` | `NoteCardMediaStyle` 三种版式（用户要求保留切换） |
| 折叠截断整套 + `collapsedBoxHeightFor` / `_estimateDeltaHeight` 的折叠用途 | **展开态与全屏编辑器的 Quill 路径，完全不动** |

### inline 版式在 D 之后会变好，不是变差

转换器天然输出的就是 `[文字段, 媒体, 文字段, ...]` 序列，`Column` 一排就是原位交错。
没有 Quill 就没有物化时序问题，所以 D 之后 inline：
- 滚动时媒体正常加载（现在不行）
- 音视频不再在列表里实例化 `MediaPlayerWidget`（现在会）
- 位置完全保真

**保留三种版式切换的成本因此接近零。**

---

## 四、还没做的小修补（与 D 无关，做了就有）

用户反馈的 4 个收尾问题：

1. **短文本下方留白**：Row 是 `crossAxisAlignment: start`，文字一行 24px、缩略图 72px，
   行高取 max，文字下面空 48px。
   → 按文本高度选对齐：`boxHeight <= 缩略图边长 ? center : start`。**1 行**。
2. **展开遮罩挡住小图**：`quote_item_widget` 的 `_buildCollapseHintOverlay` 是
   `Positioned(left:0, right:0, bottom:0, height:30)`，横跨整个内容区，包括缩略图。
   → 给 `Positioned` 加 `right: CollapsedMediaThumbnail.reservedWidth()` 内缩。
   （曾担心这会把版式决策复制到第二处而漂移，但这段代码 D 之后要重构，
   **短命的代码用便宜的修法是对的**。）
3. **视频不能点击播放**：查证过，**项目里没有独立的全屏视频播放页**，`MediaPlayerWidget`
   只活在 Quill 嵌入里（即展开态）。
   → 最便宜：点视频缩略图 = 展开卡片，复用展开态里已有的播放器，零新页面。
4. **非正方形图片裁切**：现在 `BoxFit.cover` 居中裁切，长截图只剩中间一段。
   → 改 `Alignment.topCenter`，截图/文档保住信息密度最高的顶部。**1 行**。
   ⚠️ **不要**改成按原图比例的非方形缩略图：方形是唯一能让 `cover` 解码尺寸有上界的
   形状（宽扁条带要同时满足宽和高，会解到比整宽渲染还大），改了会把已解决的问题
   重新引进来。

---

## 五、这条线上踩过的坑（务必读，都是真实教训）

### 关于代码本身

- **本项目三种媒体的序列化形状并不统一**：
  - 图片 `{'insert': {'image': ...}}`
  - 视频 `{'insert': {'video': ...}}`
  - **音频 `{'insert': {'custom': {'audio': ...}}}`** —— 走 `CustomBlockEmbed`，**不在顶层**

  可对照 `draft_service.dart:202`、`media_reference_service.dart:1001`、
  `editor_color_and_media.dart:262` 三处同样的判断。只认顶层 `audio` 会让折叠态漏掉
  音频：既不计角标，也不会被剥离，滚动列表里照旧实例化播放器。

- **`deltaContent != null` ⟺ `editSource == 'fullscreen'`** 是全项目不变量，所有写入
  路径成对设置（`note_proposal_applier.dart` 还有「plain 提案不得带 Delta」的显式校验）。
  渲染入口 `quote_content_widget.dart` 用的就是这个条件。**不要以为这是漏判。**

- **`_CollapsedContentWrapper` 必须定高，不能跟着内容走**。滚动期间折叠卡片显示的是
  `Text(_deferredPreviewText(quote.content))` 轻量占位，停下后才换成 Quill 文档，
  两者自然高度不同 —— 盒子一旦跟着内容走，物化那一刻卡片就跳。
  高度该取多少由 `collapsedBoxHeightFor` 按版式算好后传进来。

- **`imageCache` 是纯内存的，重启 App 就没了。** 所以每次冷启动第一次滑过，所有图都要
  从原图重新解码。要彻底消除首次等待，需要**保存时生成缩略图文件存盘**（目前没有任何
  磁盘缩略图缓存，`media_file_service.dart` 里没有相关逻辑）。

- **`errorBuilder` 的 postFrame 回调必须同时校验 `source` 和 `provider` 身份**。只比
  source 的话，尺寸/dpr 变化时 source 不变但 provider 换了，旧请求的失败会把新图永久
  钉在 broken-image 上。`didUpdateWidget` 的重置条件也要包含 cacheWidth/cacheHeight，
  否则 `_hasError` 挂着、`build` 第一行就提前返回，新 provider 永远没机会被试。

- **`SettingsService` 里 MMKV 写入是否检查返回值，约定正在变。** review 时我以
  「该文件 40 处 `setString` 全部忽略返回值」为由，驳回了「`setNoteCardMediaStyle`
  应在持久化失败时不提交内存状态」的建议。**这个前提现在不成立了**：#460 加入的
  `setAgentMemoryEnabled` / `setAgentMemoryNoticeShown` 都检查了返回值并抛
  `StateError`（理由写在注释里：隐私开关静默失败会误导用户）。
  → 新写 setter 时按「这个设置静默回退会不会误导用户」判断，别再拿旧约定当挡箭牌；
  旧的那批值不值得统一收紧，可以单开一个 issue。

### 关于工作方法（我犯的错，别重蹈）

- **优先级排错了。** 用户要的是「不卡」，我按技术依赖顺序推进，先做了解决观感的部分。
  应该开工前就问「三段式和卡顿哪个更烦」。
- **用错理由做决定。** 换小图我说是为了省内存，但日志明明写着内存不是瓶颈。真正有意义的
  只有「把媒体移出 Quill」，那一步不要求必须是小图。
- **明知有问题却搪塞。** 折叠盒空白在规划时就想到了，用「留白和其他卡片一致」糊弄过去 ——
  那理由是错的（其他卡片天然填满，带图笔记是唯一必然填不满的）。
- **验证不严。** 全量测试输出 `-11` 但只列了 4 个文件名，尾部 `... and N more` 被 grep
  吃掉；注意到 11 与 4 对不上却用「svg 重复计数」解释掉，没核实。CI 抓出是
  `trash_page_test` 的 7 条 —— 它的 `_FakeSettingsService.noSuchMethod` 是**显式抛异常**的，
  新增任何 `SettingsService` getter 都要同步补这个 fake。
- **对不确定的事说得太满。** 在拿到 release 日志之前就对「D 能带来多少」下判断。

---

## 六、怎么验证

1. **单元测试**：Delta → InlineSpan 转换器，纯函数，覆盖各属性组合、截断边界、
   空/畸形 Delta。参考 `test/unit/utils/delta_media_extractor_test.dart` 的写法。
2. **Golden test**：折叠卡片各格式组合。**动手前先建基线。**
3. **Widget test**：注意 `QuoteContent` 的 Document / Controller 缓存是**静态**的，
   用例之间会耦合 —— 在 `setUp` 里统一 `QuoteContent.clearCacheForTesting()`。
4. **实机对比**（release 模式，与本文档第二节的数字对照）：
   - `docWorstUs` 应大幅下降或消失
   - `dir=still` 会话里的 `ΔdocMiss` 应大幅下降
   - `avgBuild` 是主指标
5. `flutter analyze` + `dart format` + 全量 `flutter test`。
   ⚠️ `test/performance/` 下有 4 个用例在容器/CI 里会因墙钟断言和离屏渲染超时而失败，
   **在 main 基线上同样失败**，与改动无关；CI 中该组是 manual 触发，不挡合并。

## 七、环境备注

- CI 的 `FLUTTER_VERSION` 是 `3.44.x`；本地务必用同版本，`flutter_quill` 必须 ≥ 11.5.1。
- 性能日志开关：`SettingsService.enableFirstOpenScrollPerfMonitor`（需开发者模式）。
