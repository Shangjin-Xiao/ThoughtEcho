# 记录页性能 —— 交接（2026-08-08）

接手「记录页滚动卡顿」的人看这份。#455 / #459 已合并，它们修的是**图片加载时序和
卡片版式**；**卡顿本身基本没动**，那是下一步。

---

## 一句话结论

**卡顿的大头在 build，不在 raster，也不在内存。** 下面所有取舍都基于这条。

## 实测（release 模式，115 条笔记 / media=32 / 下滑 28066px）

```
avgBuild=15.6ms   worstBuild=157.6ms(首屏)
avgRaster=7.4ms
docWorstUs=14506  ← 单次折叠文档构建最坏 14.5ms，在滚动帧内
imageCache bytes=15.4MB/100.0MB  ← 内存离淘汰门槛很远，从来不是瓶颈
```

日志开关：开发者模式 →「首屏滚动性能监控」，tag `NoteListView.Perf`，
找 `滚动性能摘要(复制此行)`。

## 卡顿的两个已定位来源（都还没修）

| 来源 | 位置 | 成本 |
|---|---|---|
| 折叠截断的 O(n²) 测量 | `quote_content_widget.dart` 的 `_truncateDeltaOpsForCollapsedDocument`：每加一个 op 就把已累积的全部 span 重新 `TextPainter.layout` 一次 | 单次最坏 14.5ms |
| 冷 Quill 首布局 + 占位→Quill 切换 | `quote_content_deferred.dart` | 20~48ms/张；静止 475ms 内建 14 个 document |

---

## 已做的（背景，不用细看）

三个现象（图片三段式、滑回来变灰、停下闪一下）来自**三层独立的「延迟物化」叠加**，
每个阶段对应一层门控放行。决定性证据：日志 `defer=0` —— 图片的延迟分支一次都没执行过，
因为 `_DeferredRichTextContent` 挡在上游，滚动时 Quill 不物化，图片 widget 不进树。

- #455：媒体移出 Quill 交给独立 widget；删掉 `_LazyQuillImage` 的自建门控
  （`Image` 内部的 `ScrollAwareImageProvider` 本来就做对了「快滚延迟、命中不延迟」）；
  `imageCache` 上限显式化；`ImageCacheService` → `SvgRasterCacheService`
- #459：折叠卡片媒体版式三选一（`NoteCardMediaStyle`：thumbnail / inline / banner，
  开发者模式切换）；折叠盒改为按剥离后估算的固定高度；媒体可点击预览

---

## 下一步：阶段 D —— 折叠卡片彻底不跑 QuillEditor

一步消除上面两个来源：没有 Quill 就没有冷布局；摘要在别处算好就没有运行时截断。

### 先做 D1

| | 做法 | 代价 |
|---|---|---|
| **D1（先做）** | 运行时 Delta → `InlineSpan`，按内容签名缓存，卡片用 `Text.rich` | 不动 DB。纯数据变换（O(ops)，无布局无 RenderObject），比建整棵编辑器树便宜两个数量级 |
| D2（不够再上） | 保存时把前 N 行压成 runs 存 DB 新字段 | 要加字段 + migration + 老笔记回填 |

### 转换器不用从零写

`lib/services/delta_to_pdf_parser.dart` **已经是在跑的 Delta 遍历器**（bold/italic/
underline/color/list/header/blockquote/code 都处理了），只是输出 `pw.TextSpan`。
新代码换输出类型即可。

### 范围（已与用户确认）

- **要 1:1**：粗体、斜体、下划线、删除线、字色、背景色、字号、行高、列表符号、
  引用左线、行内代码
- **不投入**：块级间距细节（`VerticalSpacing`）、多级嵌套列表缩进、表格、代码块内边距。
  折叠卡片只显示 160px ≈ 5~6 行，这些本来就看不全
- **动手前先建 golden 基线**（典型笔记各格式各截一张），这是现架构给不了的验证手段

### D 之后删什么

删：`quote_content_deferred.dart` 整个文件、`_QuoteContentControllerCache`、
全局信号 `isListScrolling` / `isListDragActive`、折叠截断整套。

留：`DeltaMediaSummary` / `parseDeltaMedia`、三个 `CollapsedMedia*` 组件、
**展开态与全屏编辑器的 Quill 路径完全不动**。

### 三选一保留，且 D 之后 inline 会变好

用户决定：**先保留三选一，D 做完再决定要不要收敛到小图。**

保留的成本接近零 —— 转换器天然输出 `[文字段, 媒体, 文字段...]` 序列，`Column` 一排
就是原位交错。D 之后 inline 反而比现在强：滚动时媒体能加载、不在列表里建播放器、
位置完全保真。

---

## 必须知道的代码陷阱

- **音频嵌入在 `insert.custom.audio`，不在顶层**（图片/视频才是顶层）。可对照
  `draft_service.dart:202`、`media_reference_service.dart:1001`、
  `editor_color_and_media.dart:262`。只认顶层会让折叠态漏掉音频，播放器照旧被实例化。
- **`deltaContent != null` ⟺ `editSource == 'fullscreen'`** 是全项目不变量，
  所有写入路径成对设置。别以为是漏判。
- **`_CollapsedContentWrapper` 必须定高**。滚动期间显示 `Text(quote.content)` 占位，
  停下才换 Quill 文档，两者自然高度不同 —— 盒子跟着内容走，物化那一刻卡片就跳。
- **`imageCache` 是纯内存的，重启即失**。冷启动第一次滑过必然全部重解。要消除首次
  等待需要**保存时生成缩略图文件存盘**（目前完全没有磁盘缩略图）。
- **`errorBuilder` 的 postFrame 回调要同时校验 source 和 provider 身份**；
  `didUpdateWidget` 的重置条件要包含 cacheWidth/cacheHeight，否则 `_hasError` 挂着、
  `build` 第一行提前返回，新 provider 永远没机会被试。
- **`trash_page_test.dart` 的 `_FakeSettingsService.noSuchMethod` 是显式抛异常的**：
  新增任何 `SettingsService` getter 都要同步补这个 fake（CI 上就是这么红的）。
- **`flutter_quill` 必须 ≥ 11.5.1**：Flutter 全部 3.44.x 都给 `TextInputClient` 加了
  `onFocusReceived`，11.5.0 没实现，任何引入 quill 的测试都编译失败。别回退。
- **`SettingsService` 的 MMKV 写入是否检查返回值，约定正在变**：旧 setter 普遍忽略，
  但 #460 的 `setAgentMemoryEnabled` 已检查并抛 `StateError`。新写 setter 按
  「静默回退会不会误导用户」判断。

## 已知待办（用户决定放到 D 之后再看）

1. 短文本下方留白 —— Row 用 `crossAxisAlignment: start`，文字 24px、缩略图 72px。
   按 `boxHeight <= 缩略图边长 ? center : start` 判断即可，1 行
2. 展开遮罩挡住小图 —— `_buildCollapseHintOverlay` 的 `Positioned` 横跨整个内容区，
   加 `right: CollapsedMediaThumbnail.reservedWidth()` 内缩即可
3. 视频不能点击播放 —— 项目里**没有独立的全屏视频页**，`MediaPlayerWidget` 只活在
   Quill 嵌入里。最便宜：点视频缩略图 = 展开卡片
4. 非方形图片裁切 —— 改 `Alignment.topCenter`（长截图保住顶部），1 行。
   ⚠️ **不要**改成按原图比例的非方形缩略图：方形是唯一能让 `cover` 解码尺寸有上界的
   形状，改了会把已解决的问题重新引进来

## 验证

- Delta→InlineSpan 转换器：纯函数单测，参考 `test/unit/utils/delta_media_extractor_test.dart`
- Golden test：折叠卡片各格式组合（**先建基线再动手**）
- Widget test：`QuoteContent` 的 Document / Controller 缓存是**静态**的，用例之间会耦合，
  在 `setUp` 里统一 `QuoteContent.clearCacheForTesting()`
- 实机：release 模式跑同样的滚动会话，主看 `avgBuild` 和 `docWorstUs`
- ⚠️ `test/performance/` 下 4 个用例在容器/CI 里因墙钟断言和离屏渲染超时而失败，
  **main 基线上同样失败**，与改动无关；CI 中该组是 manual 触发

## 工作方法上的教训（这条线上真实发生过）

- 优先级排错：用户要的是「不卡」，却按技术依赖顺序先做了解决观感的部分
- 用错理由做决定：「换小图省内存」——但日志明明写着内存不是瓶颈
- 明知有问题却搪塞：折叠盒空白在规划时就想到了，用「和其他卡片一致」糊弄过去（错的）
- 验证不严：全量测试 `-11` 只列 4 个文件名，尾部 `... and N more` 被 grep 吃掉，
  注意到数字对不上却自行解释掉，没核实 —— CI 抓出来是 7 条
