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

