# 记录页：预热在空转，日志用的是别人家屏幕的尺子（2026-08-22）

接着 `docs/note-list-first-paint-cost-2026-08-19.md` 和 489c0fc（空闲预热 + 缓存区预建）。
这一份回答的问题是：预热和预建都上了，**为什么「不是冷启动也卡」**。

---

## 一句话结论

两件事同时成立：

1. **空闲预热在空转。** App 进后台会把测量缓存整排清空，而预热的游标停在列表末尾，
   没有任何东西把它拨回去 —— 回到前台后缓存是空的、游标是满的，每张卡片滑进来
   都要重新算一遍折叠判定和折叠排版。
2. **日志看不见这件事。** 帧的 jank 阈值写死 16.6ms（60Hz 的一帧），用户的屏是
   120Hz（一帧 8.3ms）。`frameJank=0` 和「明显觉得卡」可以同时成立。

---

## 证据：用户 2026-08-22 那四段 log

`warmup=` 说预热跑完了 121 条、发了 31 次 precache。可同一行里的缓存尺寸全部对不上：

| 指标 | 日志值 | 预热真跑过的话 |
|---|---|---|
| `expand`（折叠判定缓存） | 59 | ≥121 |
| `ir`（DeltaRichTextCache） | 20 | 40（`rich=40`） |
| `plan`（折叠排版缓存） | 36 | ≥40 |
| `imageCache.img` | 15 | ~31 |

`expand=59` 恰好等于 `tracked=59`（`_expandedItems.length`，「一共建出来过几张卡」），
scroll-5 那段则是 `expand=44 / tracked=44`。**缓存里没有一条是预热的份，全是卡片
自己现算的。** 三个缓存的上限分别是 300/200/300，都远没到，不是被挤掉的。

清空的地方在 `lib/main.dart` 的 `didChangeAppLifecycleState`：`paused` 时
`QuoteContent.resetCaches()` 把 document / heightEstimate / expansion / controller /
media / richText / plan 七个缓存一起清掉（Android 侧后台还会清 Flutter 自己的
imageCache，正好解释 31 → 15）。而 `_resetIdleLayoutWarmup()` 只在**列表内容变化**时
被调用，宽度和版式都没变，游标就一直停在 `121/121`：下一轮 tick 进来直接判定
「暖完了」，转头去撑缓存区。

## 剩下那一半：尺子不对

| session | eventJank | eventWorst | frameJank | avgFrame | 说明 |
|---|---|---|---|---|---|
| scroll-8 | 15/106 | 25.2ms | **0** | 3.0ms | build+raster 很小，帧却在丢 |
| scroll-6 | 14/141 | 82.8ms | 2 | 4.4ms | 这段撞上了分页 |

`frameJank` 只统计 `buildDuration + rasterDuration`，阈值 16600 —— 120Hz 上那是
两帧。而 vsync 到 build 之间的等待不进账，**整帧被跳过更不会留下任何 FrameTiming**。
`eventAvg=12.2ms`（120Hz 期望 8.33ms）说明确实在丢帧，但那是滚动事件的间隔，
拖拽期混着触摸采样率，不能当帧率用。

---

## 这一轮做了什么

- `QuoteContent.cacheGeneration`：`resetCaches()` 每清一次自增一次。预热 tick 拿它
  和宽度、版式一起比对，代号变了就把游标拨回 0 并清掉 precache 去重集合。
  这样任何清缓存的路径都会自动触发重暖，不用让 NoteListView 去认识 App 生命周期。
- `NoteListViewState` 监听 `AppLifecycleState.resumed`，回前台排一轮预热。
  没被清过的话那一轮全是查表命中，几乎不花时间。
- `lib/utils/frame_timing_stats.dart`：一帧的预算按 `display.refreshRate` 算
  （120Hz → 8333µs），首滑 / 加载更多 / 滚动会话三处共用同一份换算，`16600` 从此
  只此一处、且不再是常量。`JankDetector` 的 32ms 同样改成「两帧」。
- 日志新增 `dropped=`（按相邻两帧 vsync 间隔折算出的、根本没产出的帧数）、
  `worstGap=`、`avgSpan=` / `worstSpan=`（`totalSpan`，含 build 之前的等待）、
  `worstVsync=`（`vsyncOverhead`）。
- `warmup={}` 新增 `expand=` / `plan=`（预热**自己**做掉的测量量）、`gen=`、
  `rewarm=`。`items` 只数循环转了几圈，转空圈时它照样很好看；这两个增量才是
  「预热真的落地了」的证据。

---

## 2026-08-23 复验：修的两处都生效，露出了下一层

用户在 120Hz 机器上跑了两组：(a) 冷启动直接滑，(b) 切后台再回来滑。

**(a) 冷启动**：`warmup={...,expand=114,plan=68,gen=0,rewarm=0}`，滑动全程
`planMiss+0 / expandMiss+0`，`expand=121/300`、`ir=40/200` —— 预热确实把整张列表
暖好了，卡片滑进来一次测量都不用做。（也反过来确认了 08-22 那份日志是切过后台的：
同样的位置那时是 `expand=59`。）

**(b) 切后台回来**：`gen=3, rewarm=3` —— 重暖机制按设计触发了。但同一段里仍然
`planMiss+33 / expandMiss+28`，因为 `cursor=23/121`：**重暖是从第 0 条开始的，
而用户停在第 45~72 条**。功夫全花在屏幕外面，滑到的每一张还是现算。
用户同时看到「原本加载过的图片又变灰重新加载」（`imageCache img=18, Δimg+18`）。

新指标把「卡在哪」也指出来了：

| session | dataΔ | worstVsync | worstSpan | frameJank | avgBuild | dropped |
|---|---|---|---|---|---|---|
| scroll-1 | 1 | 52.5ms | 55.5ms | 12 | 1.2ms | 119 |
| scroll-2 | 1 | 110.5ms | 118.8ms | 15 | 1.4ms | 96 |
| scroll-3 | **0** | **1.4ms** | 16.1ms | 11 | 1.2ms | 61 |

`avgBuild` 一直只有 1.2ms，掉帧却成片 —— **成本不在 build/raster，在 vsync 到
build 之间那段**，而它和 `dataΔ` 高度相关：有数据事件的两段 worstVsync 是
52ms / 110ms，没有的那段是 1.4ms。

### 这一轮又改了什么

- **进后台不再清测量缓存**，改挂 `didHaveMemoryPressure`。日志证明 pause 清掉的
  几乎全是小对象（`doc=0/120`、`ctrl=0/50` 本来就是空的），换来的却是每次回前台
  第一次滑动必然重算。系统真缺内存时（含后台 trim）照样会清。
- **预热改成从视口向两边扩散**（`lib/utils/spread_from_anchor_cursor.dart`），
  锚点在「这一轮第一条都还没暖」的时候取 `_estimatedScrollCenterIndex()`。
  日志里的 `cursor=` 后面跟上了 `@anchor`。
- **回前台重走一轮预热并清掉 precache 去重集合**：Flutter 自己的 imageCache 会被
  引擎清空（那是「图片变灰」的来源，和 App 的缓存无关），测量这时全是命中，
  这一轮基本只花 precache 的钱，而且视口里的图先回来。

### 再一轮：一次数据事件重建 113 张卡

复验日志的 scroll-14：`itemMemo={size=121,hit+0,miss+113}`、`worstBuild=74.9ms`
—— 一个滚动帧里把 113 张卡片全部重建，而内容一条都没变。

`_QuoteItemMemo.matches` 和 `_isSameQuoteInstances` 都按 `identical` 判断。那本身
是对的（`Quote` 全字段 final，同一实例就意味着内容没变），问题出在上游：数据库
一旦重新查询（回前台刷新、换页、重新订阅），就会造出一批全新的 `Quote` 对象 ——
内容一个字没改，身份却全变了，这道防线整条失效。

改法是让数据事件里内容没变的行**沿用旧实例**（`_reuseUnchangedQuoteInstances`），
判据是新加的 `Quote.hasSameContentAs`：`toJson()`（quotes 表那一行）+ `tagIds`
（走关联表、不在 toJson 里）。

**不能用 `==`**：那个只比 `id`，会把「同一条笔记被改过内容」也判成没变，卡片就
永远停在旧内容上。用 `toJson()` 而不是手写一份字段清单，是为了让「新增持久化
字段」按 AGENTS.md 同步 toJson 时自动纳入判据。

日志的 `activity={}` 里新增 `reuseΔ=`：这一段滑动中有多少行是沿用旧实例的。

## 下一轮该看什么

拿到新日志先看三个数：

- `warmup` 里的 `expand=` / `plan=` 有没有涨。是 0 就说明预热仍然没落地，
  别再往下猜。
- `rewarm=` 有没有随着切后台次数增加。
- `dropped=` 和 `frameJank=`。如果 `frameJank` 仍然接近 0 而 `dropped` 很大，
  说明成本不在 build/raster 里，要往 UI 线程的非帧工作（定时器、平台通道、GC）
  和光栅线程排队去找。
- `itemMemo` 的 `hit+`/`miss+` 和 `activity` 里的 `reuseΔ=`。有 `dataΔ=1` 的
  会话里 `miss+` 应该塌下去、`reuseΔ` 顶上来；`worstVsync` 是不是跟着 `dataΔ`
  一起消失，是判断「52ms/110ms 到底是不是整列表重建造成的」的关键一眼。

还没做、按优先级排：

1. **排版量封顶。** `planWorstUs=15486`（单条笔记一次 plan 15.5ms）、首个
   rich-image 卡片 `itemLayout 18.3ms`。`_computePlan` 和渲染侧的 `Text.rich`
   都把**整块正文**交给引擎，`maxLines` 只限制保留几行，断行仍然要跑全文 ——
   折叠盒只有 160px，成本却随笔记长度线性增长。两侧用同一个字符上限截一刀。
2. **分页别落在惯性里。** scroll-6 是唯一真掉帧的一段，也正是
   `loadMoreStartΔ=1` 那段（15 次挂载、9 次解码）。新页到达即刻预热，
   并把预热的「在滚就整轮放弃」改成按帧余量切片。
3. **iOS 的 Sentry profiling。** `profilesSampleRate` 目前是 null（仅 iOS/macOS
   支持）。打开它并把滚动会话包成一个 transaction，才能拿到函数级的火焰图 ——
   profiling 只在有活跃 transaction 时采样，而滑动本身不产生 transaction。

---

## 2026-08-25 复验：列表本身已经基本没成本了

用户在同一台 120Hz 机器上跑了冷启动滑 + 滑到底再来回滑两组。

**上一轮（#510）的改动全部生效**：

- 实例复用：唯一带 `dataΔ=1` 的 scroll-3 是 `reuseΔ=121`、`itemMemo hit+58/miss+31`、
  `worstBuild=13.3ms`。上一版同类会话是 `hit+0/miss+113`、`worstBuild=74.9ms`。
- 重暖锚点：回滑那组 `gen=2, rewarm=1`（系统真报过一次内存压力，现在只有这条路会清
  缓存），重暖从 `@37` 开始，正是视口位置。
- **最干净的一段 scroll-10（`built=0`，全是老卡片）**：`frameJank=0`、
  `avgFrame=2.4ms`、`worstVsync=1.5ms`、`itemMount=0`。列表本身已经几乎不花钱了。

剩下的成本全部集中在「第一次」和「分页」：

| 来源 | 证据 |
|---|---|
| 分页 | scroll-3 `loadMoreStartΔ=1` + `worstVsync=77.1ms`、`worstGap=357.5ms`、`dropped=90`，而 `avgBuild` 只有 1.3ms |
| 冷启动首屏光栅 | scroll-1 只滑了 331px、`built=2`，却 `frameJank=26/45`、`worstRaster=36.0ms`、`avgRaster=5.5ms`（后面几段只有 1.9–2.5ms） |
| 头部测宽 | scroll-2 `headerMiss+48 / 13.1ms`、scroll-3 `+62 / 16.8ms` |

**折叠排版封顶降级**：scroll-2/3 `planMiss+0`，预热已经全吃掉了；只有冷启动
scroll-1 有 `+5 / 5.6ms`。`planWorstUs=18913` 只是历史最坏值，不是这几段产生的。

### 这一轮做了什么

1. **给分页加分段计时**（`lib/utils/note_list_load_more_profile.dart`）。77ms 落在
   vsync 到 build 之间，也就是帧之外的 UI 线程；查过不是 N+1（标签查询已经 batch），
   所以嫌疑在「SQL 等待 / 标签批查 / 一页 50 条 `Quote.fromJson` / 送到列表之后的
   复用比较和落库」这四段里。日志新增
   `loadMore={n=,rows=,service=,sql=,tags=,parse=,reuse=,apply=}`，记的是**最近一次**
   分页而不是增量 —— 要看的是「那一下 77ms 花在哪」，平均掉就看不见了。
   `apply=` 只包含把新列表落进 state 的那一下，**不含随后的重建**（`setState` 只是
   排一帧），名字特意不叫 `state`。
2. **头部测宽进预热**。日期逐条不同、按文本做键，必然是每张新卡片一次未命中。
   把头部三段文字和样式抽成 `QuoteItemWidget.resolveHeaderTexts`，`build` 和
   `warmCollapsedMeasurements` 共用同一处 —— 和折叠排版当初同一个理由：两边各写一份
   格式化逻辑的话，预热会变成静悄悄的空转。

### 下一轮该看什么

先看 `loadMore={}` 那一行，77ms 落在哪一段：

- `parse=` 占大头 → 反序列化在 UI 线程，改时机（滑动期间不发起分页，靠空闲预取提前
  备好）或者分片解析。
- `sql=`/`tags=` 占大头 → 是数据库/通道往返，减小页大小或提前取。
- `reuse=`/`apply=` 占大头 → 是我们自己在 widget 侧的开销，那就直接优化那两处。

还没做：冷启动首屏光栅（scroll-1 的 `worstRaster=36ms`，只建了两张卡，成本在着色器
编译 / 首批纹理上传 / 首次图层合成，和卡片优化无关）。

---

## 2026-08-26 复验：分页被证伪，成本跟着「建卡片」走

PR #520 的分段计时到手，结论和之前的推断**相反**。

### 分页不是瓶颈

scroll-2 是唯一真发生分页的会话（`loadMoreStartΔ=1`）：

```
loadMore={seq=3,q=1,ev=0,rows=0,service=13.6ms,sql=13.3ms,tags=0.0ms,parse=0.0ms}
```

`q=1` 说明这份拆分干净，而 `service` 只有 **13.6ms**，`rows=0`（那次查到「没有更多了」）。
之前推测的「一页 50 条 `Quote.fromJson` 占掉 77ms」完全不成立 —— 同一段的
`worstVsync` 是 **185.0ms**。**先量再改这一步省掉了一整轮走错方向的优化。**

### 成本和「建了几张卡」完美相关

| session | built | worstVsync |
|---|---|---|
| scroll-1 | 32 | 41.2ms |
| scroll-2 | 89 | **185.0ms** |
| scroll-13 | 23 | 49.4ms |
| scroll-40 | **0** | 7.2ms |
| scroll-44 | **0** | 1.5ms |
| scroll-47 | **0** | 1.2ms |

`built=0` 的三段 `worstVsync` 都在 1~7ms，`built>0` 的三段是 41~185ms。**帧外那段
UI 线程开销跟着新卡片走**，而卡片自己的 build/layout 都在预算内（`avgBuild` 1.1ms、
`itemLayout worst` 5.7ms）—— 所以它不在 build 阶段里，而在建卡片**引出的**异步工作上
（图片文件读取、解码完成回调这一类落在帧与帧之间的东西）。

再猜就是重蹈覆辙。下一步该上函数级采样：Sentry profiling（`profilesSampleRate`，
仅 iOS/macOS，上晋有侧载包），把滚动会话包成一个 transaction —— 起止钩子
（`_startScrollSessionPerfCapture` / `_finalizeScrollSessionPerfCapture`）现成。

### 这一轮修的三个指标缺陷

日志本身有三处会把下一轮带偏，先修掉：

1. **`dropped` 在列表不动时虚高。** scroll-40 `dist=-53`（手指按着几乎没挪）却报
   `dropped=179`。列表停着时 Flutter 本来就不产出帧，那是省电不是卡顿。改成逐帧记
   偏移（帧号 → `position.pixels`，靠 `FrameTiming.frameNumber` 对齐，因为帧时间戳
   走引擎时钟、和滚动通知的 `DateTime.now()` 不是同一条时间轴），只有相邻两帧之间
   真的挪过才折算丢帧；没挪的那部分单独记进新的 `idle=`。`eventJank` 同理。
2. **采样窗口一直开着。** 冷启动那段 `q=4,rows=410,sql=131.5ms` 而 `service=127.4ms`
   —— `sql` 比包着它的 `service` 还大。改成 `loadMoreQuotes` 一返回就关查询窗口、
   分页数据事件处理完就关事件窗口。
3. **门控太严，把要量的那一次漏掉了。** scroll-2 `reuseΔ=117` 明明做了 117 行内容
   比较，`loadMore` 里却是 `ev=0`、`reuse=0.0ms`：分页查到「没有更多」时列表不变长、
   长度也不小于一页，`isLoadMorePage` 为假。分段计时的门控改用
   `_loadMoreAwaitingPage`（「正在等分页的数据事件」），`isLoadMorePage` 继续管它自己
   那件事（`_isLoading` 何时归位）。

### 顺带记下

- `headerWorstUs=14004` —— 头部测宽的历史最坏值是 14ms（预热期间的第一次，字体
  shaping 冷启动）。所有会话 `headerMiss+0`，预热在正常工作。
- 冷启动首屏光栅那条（scroll-1 `worstRaster=19.2ms`）仍然挂着，未动。


---

## 2026-08-27 复验：热态已经打平，剩下的两条线是「回前台」和「整列表重建」

PR #526 的指标修正到手后的第一份日志。这一轮**不是**又一轮指标返工 —— 热态滚动
已经达标，可以开始处理用户直接看得见的那件事了。

### 热态滚动打平了

滑到底之后来回滑的四段（scroll-24~27）：

| session | frames | frameJank | avgFrame | worstFrame | built |
|---|---|---|---|---|---|
| scroll-24 | 265 | **0** | 2.4ms | 5.5ms | 0 |
| scroll-25 | 209 | **0** | 2.4ms | 6.5ms | 0 |
| scroll-26 | 184 | **0** | 2.2ms | 4.8ms | 0 |
| scroll-27 | 269 | 2 | 2.7ms | 35.8ms | **121** |

前三段一帧都没超预算。第四段那两次 jank 是下面第三节的事。

冷启动首滑仍然掉帧（scroll-1~3 的 `frameJank` 是 11/9/10），但也在收敛：scroll-4
（当轮第四段，缓存都暖上了）只剩 `frameJank=4`、`worstVsync=0.9ms`。

### 「切后台回来图片变灰」的根因：切后台被当成缺内存

用户第二次反馈这件事了。根因不在预热，在生命周期：

- **Android 每次切后台都会发 `memoryPressure`。** 系统的 `onTrimMemory` 在应用退到
  后台时就会带着 `TRIM_MEMORY_UI_HIDDEN` 打过来，Flutter 引擎把它和真正的低内存
  警告转成同一条消息，Dart 侧完全分不出来。
- 框架对这条消息的默认反应是**当成缺内存**：`PaintingBinding.handleMemoryPressure`
  直接 `imageCache.clear()`，`WidgetsBinding` 再把 `didHaveMemoryPressure()` 广播给
  所有观察者 —— 本仓库那个观察者会 `QuoteContent.resetCaches()`。

日志对上了：scroll-4（14:18:34）时 `warmup gen=0`，两分钟后的 scroll-24 是
`gen=2, rewarm=1`。中间用户只是把应用切出去又切回来，测量缓存却被整排清了两次。
于是「之前显示过的图片变灰重新加载」和「回前台第一次滑动要重算折叠排版」是同一个
原因的两个症状。

**修法**：`AppWidgetsBinding`（`lib/utils/app_widgets_binding.dart`）按生命周期状态
分流这条消息。判据对齐例行 trim 实际送达的时机 —— `TRIM_MEMORY_UI_HIDDEN` 是
`onStop` 之后、界面完全不可见时才发的，对应 `hidden` / `paused` / `detached`。

- 前台真缺内存（`resumed`、`inactive`）：照旧走 `super`，全清。
- 后台例行 trim（`hidden`、`paused`、`detached`）：卸掉 asset bundle，把 `imageCache`
  **淘汰**到 8MB 而不是清空（`maximumSizeBytes` 的 setter 会立刻按 LRU 淘汰到新额度，
  调低再调回去即可），测量缓存一个不动 —— 它装的是折叠判定和折叠排版这类小对象，
  省不下多少内存，重算却整整落在回到前台的第一次滑动里。

`inactive` 归在前台一侧是有意的：它是「还在屏幕上但没有输入焦点」（权限弹窗、系统
浮层、下拉通知栏、来电横幅、任务切换器），这时进程完全在前台，例行 trim 还没发生，
收到的压力是真缺内存。拿不到状态时同样按「真缺内存」处理：宁可多释放一次，也不要在
真缺内存时装看不见。

回前台那条重走预热的路（`didChangeAppLifecycleState`）保留：8MB 额度之外的图还是掉了，
用户往回滑越过那条线仍然会看到一次重解。

### Sentry profiling 开了，只留真卡过的那几段

上一轮的结论是「再猜就是重蹈覆辙，该上函数级采样」。这一轮把它接上：

- `profilesSampleRate = 1.0`。它是架在 `tracesSampleRate` 之上的第二层，配合现有的
  1.0 等于「每条上报的事务都带一份采样式 CPU profile」。SDK 自己判平台（见
  `SentryNativeProfilerFactory.attachTo`），只有 iOS/macOS 真正启动 profiler，
  所以这里没再重复写一层平台分支 —— 上晋有 iOS 侧载包。
- 滚动会话的 transaction 本来就有（`AppTracer.start(scrollSessionTraceName)`，起止
  钩子就是 `_startScrollSessionPerfCapture` / `_finalizeScrollSessionPerfCapture`），
  这次只是把收尾地标里的帧统计**保持成数值类型**，并在 `beforeSendTransaction` 里
  按它筛：只留 `frameJank > 0`，或者最坏一帧到了两帧预算的会话。

  随手翻一分钟就是几十个滚动事务，全量上报既淹没面板也白烧流量，在 iOS 上还每条都
  附一份 profile。按这一轮的数据，scroll-24~26 会被丢掉，scroll-1~4 和 scroll-27
  留下 —— 正好是想看的那几段。拿不到收尾地标的一律保留：那说明会话没走到正常收尾，
  异常路径最不该被筛选悄悄吃掉。

  判据里**故意没有 `dropped`**，理由见下一节。

- 滚动会话要用 `AppTracer.start(..., forceRootTransaction: true)`。CPU profile 和
  `beforeSendTransaction` 都只认根事务，而冷启动进页面时路由事务还绑在作用域上 ——
  不强制的话，「冷启动几秒后的第一次滑动」这一段会挂成路由事务的子 span，profile
  和筛选两样都拿不到。强开时只在作用域没人绑的时候才绑，免得把路由事务顶掉。

- 采样开销要说清：SDK 没有按事务名开关 profiler 的钩子，iOS/macOS 上每条事务都会被
  采样，筛选省的是上传不是采样。这个问题排完应当把 `profilesSampleRate` 调回 `null`。

### 挂起来的两个疑点

**一、`dropped` 在可变刷新率屏幕上可能仍然虚高。** scroll-24 是
`frames=265, elapsed=2199ms, budget=8.3ms`：2199 / 8.3 ≈ 264，等于每个 vsync 都出了
帧，`dropped` 该接近 0，日志却报 **54**。算术上说不通，最像的解释是 LTPO 面板在静止
期把刷新率降到 60Hz，那时的 vsync 间隔是 16.7ms，除以 8.3ms 的固定预算每一帧都会被
记成「跳了一帧」。这一轮**没有动它** —— 前三轮的教训是不要在没有证据的时候改指标，
而且 `frameJank`（不依赖间隔）已经足够判断这几段。下一轮要么拿到刷新率随时间变化的
证据，要么改用会话内观测到的 vsync 间隔中位数做除数。

**二、一次依赖变化重建整个列表。** scroll-27 是唯一有 jank 的热态会话：
`depsΔ=1, widgetΔ=1, buildΔ=1` 带出 `built=121@0-120`，`worstBuild=31.6ms`。
`itemMemo hit+119/miss+2` 说明记忆化基本全中（真正重建的只有 2 张），那 31.6ms 是
`SliverChildBuilderDelegate` 把 121 个 builder 跑一遍加 `Element.updateChild` 的钱。
先得知道那次 `didChangeDependencies` 是被什么触发的，才谈得上收窄。

### 顺带记下

- `loadMore` 出现过第二次 `rows=0` 的空查询（scroll-24 的 `seq=4`），`sql=13.8ms`。
  已经翻到底之后还会再查一次空页，说明 `_watchHasMore` 在中途被复位过。没查根因。
- 冷启动首屏光栅那条（scroll-1 `worstRaster=7.0ms`，比上一轮的 19.2ms 又降了）
  仍然挂着，未动。

---

## 2026-08-28 iOS 复验：profile 拿到了，但符号没传，等于白拿

上晋在 iPad Air 4（`iPad13,1`，60Hz 面板）上装了含 PR #531 的包
（release `4.0.0+56`），并接了 Sentry MCP。直接查了线上数据。

### iPad 不卡，但同一个缺陷在

`budget=16.7ms`（真 60Hz，不是取不到刷新率的回退：`CADisableMinimumFrameDurationOnPhone`
是 true，ProMotion 没被挡，这台机器本来就没有）。

scroll-45：274 帧里 `frameJank=2`、`dropped=5`、`avgFrame=2.5ms`、`worstVsync=3.2ms`
—— 流畅是真的。但同一段里 `dataΔ=2 → built=234@13-120`、`worstBuild=36.2ms`、
`worstFrame=49.7ms`，而 `itemMemo hit+234 / miss+0`，记忆化一条没漏。

**36ms 在 60Hz 上掉 2 帧（看不出），在 120Hz 上掉 4~5 帧（就是用户说的卡）。**
不是代码路径的设备差异，是预算的设备差异。

### 这份日志把两条线拆开了

| | built | itemMount | worstVsync |
|---|---|---|---|
| iPad scroll-45 | 234 | **0** | 3.2ms |
| Android scroll-27 | 121 | **0** | 2.8ms |
| Android scroll-1/2/3 | 33/178/30 | **33/31/30** | 44.6 / **143.6** / 27.3ms |

**帧与帧之间那笔开销跟着「挂载新卡片」走，不跟着「重建」走。** 重建的钱全在 build
阶段。所以之前混在一起的那条线索现在是两条：

1. 挂载引出的帧外异步工作 —— 需要函数级证据
2. 整列表重建的 36ms —— 已定位在 sliver 层，不需要 profile

### profile 是空的：符号没传

查了三个 profile（`root /` 13.1s / scrollSession 454ms / 冷启动那次 349ms）：

- 采样完全正常：13.1s 那个 7629 个样本、17 条线程，`io.flutter.1.raster`、
  `DartWorker`、`dart:io EventHandler` 都在，3587 个栈帧。
- Apple 系统库的帧**有名字**（`_CFRunLoopRunSpecificWithOptions`、
  `__CFRunLoopDoTimers`、`start_wqthread`）。
- **我们自己二进制的帧全是 `unknown`。**

原因：仓库里**没有任何地方上传调试符号**（`sentry-cli` / `debug-files` /
`sentry_dart_plugin` / `upload-dif` 在 `.github/workflows/`、`scripts/`、
`pubspec.yaml`、`ios/` 里一个都没有）。

这是上一轮的疏漏：只开了 `profilesSampleRate`，没把符号上传一起做掉，结果拿到一堆
有形状没名字的栈。已在 `ios-build.yml` 里补上（见下）。

**但要说清这条路的上限**：补符号之后能读出来的是 Flutter 引擎（C++）和 Runner
（ObjC）两层；**Dart 代码的帧大概率仍然打不开** —— AOT 机器码不是靠 DWARF 描述的，
原生 profiler 一般只能把它看成一整块。对「图片文件读取 / 解码完成回调落在帧与帧
之间」这个假设来说引擎帧就够用，但别指望看到 `QuoteItemWidget.build`。

### 还有一个更硬的约束

刚才那次冷启动，整条 trace 里**只有一个滚动会话通过了筛选**（382ms）。也就是说
iPad Air 4 上连冷启动首滑都不卡。

**能 profile 的设备不卡，卡的设备（120Hz LTPO Android）不能 profile。**
所以 iOS 符号上传是「让这个工具将来能用」，不是「这次就能定位」。

### 这一轮做了什么

1. **`collapsedImage={}` 分段计时**（`NoteListImageProfile`）。不靠 profiler，两个
   平台都能用，直接冲着上面第 1 条线索去：记录每段滚动里图片的
   `resolve/sync/async/pending` 和 `avgWait`/`worstWait`。判据写在类注释里 ——
   `async` 跟着 `built` 涨且 `worstWait` 和 `worstVsync` 一个量级就是坐实；
   `async=0` 而 `worstVsync` 照样一两百毫秒就是**证伪**，省掉一整轮错方向的优化。
   挂在 `CollapsedMediaImage` 的 `frameBuilder` 上（`wasSynchronouslyLoaded` 天然
   就是「imageCache 命中、零异步工作」的信号），**没有包装 provider** —— `imageCache`
   按 provider 相等性做键，包一层会把缓存键改掉。
2. **iOS 符号上传**（`ios-build.yml` + `release.yml`）。开关是
   `SENTRY_AUTH_TOKEN` 这个 secret 在不在，`workflow_dispatch` 上另有一个默认勾上的
   `upload_symbols`。刻意**不加** `--split-debug-info`：它会把 Dart 调试信息剥离，
   应用内日志里的异常堆栈退化成裸地址，而整个排查流程靠的就是用户直接贴可读日志。
3. **`excerpt_intent` 按平台守卫**。channel 只在 `MainActivity.kt` 注册，iOS 每次进
   主页撞一次 `MissingPluginException` 并按 ERROR 记录、上报 Sentry（一条 trace 里
   6 条）。平台判断做成可注入，两条分支都有测试。

### 没做的：翻到底后的空查询

查清楚了，但**决定不动**。

根因在 `_refillAfterRefresh`：刷新会把 `_watchHasMore` 置回 true 再分块回填原有条数，
最后一块的 `requestLimit` 是个余数，而 `_watchHasMore = quotes.length >= requestLimit`
对余数来说**说明不了后面还有没有** —— 于是刷新后总是 true，用户滑到底再查一次空页。

不修的理由：任何「刷新后沿用旧的 `hasMore`」的写法都会在**刷新期间真的新增了笔记**时
把末尾的笔记藏掉（新笔记排在最前，回填同样条数会把最老的挤出去，那时 `true` 是对的）。
要精确判定得在最后一块多取一条，而这会改动回填目标的语义，进而扰动滚动位置 ——
这个文件的注释里记着这块为「列表突然飞走」返过好几次工。

代价是一次 5~20ms 的 SQL，还在后台线程上。**为它冒动回填机制的风险不划算**，
现在这个偏保守的行为（宁可多查一次，也不藏笔记）是两害相权的那个轻的。
