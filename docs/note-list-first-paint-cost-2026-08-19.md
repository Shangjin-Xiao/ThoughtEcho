# 记录页首滑：成本不在测量，在**挂载**（2026-08-19）

接着 `docs/note-list-perf-analysis-2026-08-13.md` 和 dd3674c（卡片按入参记忆化）。
这一份回答的问题是：整列表重建挡住了、折叠判定和排版都加了缓存，**为什么首滑还是卡**。

---

## 一句话结论

首滑的成本主要不在「量」，在「建」。实测一张**最小**卡片（短纯文本、无标签、无媒体、
不可展开）有 **146 个 element**，其中：

| 子树 | element 数 | 占比 |
|---|---|---|
| `PopupMenuButton`（更多按钮） | 59 | 40% |
| 心形按钮外面那层 `Tooltip`（含按钮本体） | 40 | 27% |
| **正文（`QuoteContent`）** | **3** | 2% |

首滑一次要新建三十多张这样的卡片，而卡片的 element 树有 2/3 是两个动作按钮。
这一项此前**从来没有被计量过**：`itemLayout` 探针只盖到布局，`built=` 只数次数。

---

## 证据：把用户 2026-08-19 那四段 log 按「有没有新卡片」分开

| session | 方向 | 新建卡片 | frameJank | avgFrame | avgBuild | avgRaster |
|---|---|---|---|---|---|---|
| scroll-1 | 下 | 32 | 6 | 5.5ms | 2.1ms | 3.4ms |
| scroll-2 | 下 | 32 | 4 | 4.9ms | 1.6ms | 3.4ms |
| scroll-3 | 上 | **0** | **0** | 3.4ms | 0.6ms | 2.8ms |
| scroll-4 | 上 | 0（72 次重建全被记忆化命中） | **0** | 2.8ms | 0.5ms | 2.3ms |

分界线和 08-13 那份完全一致：**`built` 里有新卡片就掉帧，全是老卡片就一帧不掉。**
dd3674c 的记忆化确实生效了 —— scroll-4 那次整列表重建 `itemMemo hit+72 / miss+0`，
`itemLayout avg=0.0ms`，一帧没掉。剩下的就只有「第一次」。

把 scroll-1 和 scroll-4 相减，摊到 32 张新卡片上：

```
UI 线程：(2.1ms × 169 帧) − (0.5ms × 174 帧) ≈ 268ms  → 每张新卡片 ~8.4ms
光栅：  (3.4ms × 169 帧) − (2.3ms × 174 帧) ≈ 175ms  → 每张新卡片 ~5.5ms
```

再把 UI 线程那 8.4ms 拆开（这些计数器是 dd3674c 那轮补上的）：

```
itemLayout 总计   107 次 × 0.9ms          ≈ 96ms   → 3.0ms/卡
  其中 expandWorkUs+15426                 = 15.4ms → 0.5ms/卡（折叠判定）
       planWorkUs  +11910                 = 11.9ms → 0.4ms/卡（折叠排版）
       headerWorkUs+14485                 = 14.5ms → 0.5ms/卡（头部测宽）
       剩下的真正布局                      ≈ 54ms   → 1.7ms/卡
差额（构造 widget + 建 element/RenderObject + 绘制）≈ 5.4ms/卡
```

**那 5.4ms 才是首滑的大头，而它一直没有名字。** 于是本轮做两件事：给它一个计数器，
然后把它砍下来。

---

## 本轮改了什么

### 1. 卡片瘦身（主要收益）

一律不改像素：两个按钮的触控尺寸（心形 36、更多 48）由测试钉住。

| 改动 | 为什么它是白付的 |
|---|---|
| `PopupMenuButton` → 轻量按钮 + `showMenu` | `IconButton` 的整套 `ButtonStyle` 逐属性解析、48dp 触控内衬、焦点/快捷键节点，这个位置一样都用不上 |
| 触摸端不挂 `Tooltip` | 触摸端 Tooltip 只能长按弹出，而心形的长按位已被「清除收藏」占着；无障碍名称改由 `Semantics` 单独给。桌面端（有指针悬浮）照旧挂 |
| 两个按钮共用一层 `Material` | 墨水层是按 `Material` 挂的，一张卡片不需要两层 |
| 双击反馈的 `AnimationController` + 两条 `TweenSequence` 改懒建 | 绝大多数卡片从挂载到销毁不会被双击一次 |
| 不可展开的卡片不挂 `AnimatedSize` / 两层 `AnimatedSwitcher` / 折叠遮罩 | 它的正文高度是静的，没有任何东西需要补间 |
| 标签放得下时不挂 `SingleChildScrollView` | 一层 `Scrollable` 要带 `ScrollPosition`、两个手势识别器、`Viewport` 和语义节点；多数笔记的标签一行就放得下，那层滚动视图从挂载到销毁不会被滑动一次 |

实测（`test/widget/widgets/quote_item_element_budget_test.dart` 钉住上限）：

| 卡片 | 改前 | 改后 |
|---|---|---|
| 最小（短纯文本、无标签） | 146 | **90**（−38%） |
| 可展开（长纯文本） | 164 | **122**（−26%） |
| 可展开 + 3 个标签 | 216 | **155**（−28%） |

### 2. 空闲预热（次要收益，但顺手把图片解码也挪走了）

列表静止时按小片（每轮 3ms 预算）把后面卡片的**折叠判定、折叠排版、缩略图解码**
提前算好，滑动/按住屏幕时立刻让路。预热不建任何 widget、不碰 element 树，
只是把几张按内容指纹做键的 LRU 缓存填热。

关键约束：**预热用的键必须和渲染时问的键逐字节相同**，否则就是静悄悄的空转。
两处保障：

- 布局宽度由真实卡片回填到 `QuoteItemWidget.lastCollapsedContentWidth`，
  不按「外边距 + 边框 + 两层内边距」反推 —— 那个算式散在四个 widget 里；
- plan 的入参由 `QuoteContent._resolveCollapsedLayout` 一处产出，
  渲染和预热共用；解码尺寸由两种媒体版式各自的 `imageProviderFor` 一处产出。
- `test/widget/widgets/collapsed_layout_warmup_test.dart` 钉死：先暖再建，
  未命中数一次都不许涨。这个项目已经吃过一次「缓存一次都没命中」的亏（beab8ca）。

### 3. 把挂载成本接进性能日志

新增两栏：

- `itemMount={count=,workUs=,worstUs=}` —— 卡片子树的挂载耗时。
  `mount` 只在真正新建时走一次：被 keepAlive 留住、被记忆化短路的重建都不进来，
  正好就是「第一次」的定义。
- `warmup={items=,cursor=n/m,img=}` —— 预热跑到哪了。
  滑动时 `expandMiss+`/`planMiss+`/`Δimg+` 还高的话，先看这一行是不是根本没跑起来。

---

## 下一轮怎么复测

release 模式，同样 115~120 条笔记，冷启动后下滑到底再滑回来。只看这几个数：

1. `itemMount` 的 `workUs / count` —— 每张新卡片的挂载均值。这是本轮的主指标，
   按 element 数推算应当降到改前的六成左右；
2. `expandMiss+` / `planMiss+` / `imageCache` 的 `Δimg+` —— 预热生效的话，
   下滑 session 里这三项应当接近 0。**不为 0 就先看 `warmup=` 那一栏**：
   `cursor` 没走完说明预热一直在让路或宽度取不到，不是键对不上；
   `cursor` 走完了而 miss 还在，才是键对不上（那就是上面那条不变量破了）;
3. `avgBuild` / `worstBuild` —— 改前 2.1ms / 23.0ms；
4. `avgRaster` —— 预热把图片解码挪走之后应当略降，但**首次光栅化本身挪不走**
   （新卡片的字形要进图集、纹理要上传），见下。

---

## 还没做的（按性价比排序）

1. **光栅侧的 ~5.5ms/新卡片没有动过。** 新卡片第一次绘制要把 CJK 字形栅格化进图集、
   把图片纹理传上 GPU，这部分随卡片进场是必然的。能省的只有「画得更简单」：
   折叠遮罩上那层 `BackdropFilter`（σ=1.2 的背景模糊）是同屏可展开卡片数量倍数的
   `saveLayer`，而它盖的只是一条 30px 高的渐变 + 一个文字胶囊。
   设置里已有 `noteListDisableBackdropBlur` 开关，**要不要把默认值翻过来是个视觉决定，
   得先问用户**，所以本轮没动。
2. **空闲期把 `scrollCacheExtent` 逐级爬升**，让下一屏的卡片在静止期就建好。
   收益上限很高（挂载彻底离开滚动帧），但有两个真风险：一是 120 张卡片全挂在树上的
   内存（本项目还要照顾 32 位 ARM 回退设备），二是已建条目变多会改变
   `_extrapolateMaxScrollOffset` 的估算，而「maxScrollExtent 变化 → 偏移被夹紧 →
   列表回弹」是这块代码反复踩过的坑。要做必须配基准和回归。
3. **头部测宽（`headerWorkUs`，0.5ms/卡）还没进预热。** 它要把日期/位置/天气的
   格式化和样式推导也搬出来，plumbing 比收益多，留到下一轮顺手。
4. **标签胶囊本身还能再薄**（现在 3 个标签 33 个 element）。
5. **遗留 bug（改前就有）**：超长富文本的折叠盒会溢出 4px 再被 `ClipRect` 裁掉，
   debug 下有 `RenderFlex overflowed by 4.0 pixels` 告警。像素上看不出来
   （本来就要裁），但它会污染 widget 测试的异常检查。修它要动
   `plan.height` 与盒高的口径，本轮没碰。
