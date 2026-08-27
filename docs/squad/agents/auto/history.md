# AUTO 的项目记忆

## 核心背景

- 项目: ThoughtEcho (心迹)
- 负责人: 上晋
- 我的角色: 技术主管
- 技术栈: Flutter + Dart + SQLite + Provider

## 关键代码位置

- 入口: lib/main.dart
- 数据库: lib/services/database_service.dart
- AI 服务: lib/services/ai_service.dart
- 测试入口: test/all_tests.dart

## Learnings

<!-- 在此追加学到的项目知识 -->
- 2026-04-06: 设置页关于弹窗可通过与用户指南同款 `ElevatedButton.icon` 快速扩展外链操作，使用 `_launchUrl` 统一处理外部链接打开与失败提示。
- 2026-04-10: Daily Quote provider 切换到 API Ninjas 时需要即时刷新 API Key 状态，建议在 provider 变更入口主动触发状态加载以避免 UI 显示陈旧状态。
- 2026-04-11: 设置持久化来自存储的字段需做类型安全反序列化（尤其 String/List），避免历史脏数据触发运行时类型异常并在请求层再次过滤非法枚举值。
- 2026-08-23: 性能日志里「进度」和「产出」必须是两个指标。预热的 `items=121` 一直很好看，
  而缓存里一条都没有 —— 循环转空圈时进度计数照样涨。后来补的 `expand=`/`plan=`（预热自己
  做掉的未命中增量）才是证据。同理，`frameJank` 只统计 build+raster，整帧被跳过不会留下
  任何 FrameTiming，得靠相邻两帧的 vsync 间隔去数（`dropped=`）。
- 2026-08-23: 帧预算不要写常量。三处写死的 `16600` 是 60Hz 的一帧，在 120Hz 屏上等于
  「连丢两帧才算一次」，`frameJank=0` 和「明显觉得卡」可以同时成立。统一走
  `frameBudgetMicrosForRefreshRate(display.refreshRate)`。
- 2026-08-23: `Quote.operator ==` 只比 `id`，**不能**拿来判断「这一行变了没有」。列表侧要
  沿用旧实例（卡片记忆化按 `identical` 判断）时用 `Quote.hasSameContentAs`（`toJson()` +
  `tagIds`）；用 `==` 会让改过内容的笔记永远停在旧内容上。
- 2026-08-23: 进后台清缓存（`AppLifecycleState.paused` → `resetCaches()`）是笔亏本买卖，
  已改挂 `didHaveMemoryPressure`。折叠列表跑起来时真正占地方的 doc/controller 缓存本来就是
  空的，清掉的都是小对象，代价却是每次回前台第一次滑动必然重算一遍。
- 2026-08-23: 本地跑测试前先执行 `scripts/patch_flutter_quill.sh`：Flutter 3.47.x 给
  `TextInputClient` 加了 `onFocusReceived`，锁定的 flutter_quill 11.5.0 没实现，不打补丁
  任何 widget 测试都编译不过。
- 2026-08-25: 记录页有了一条干净基线 —— 全是老卡片的回滑（`built=0`）现在是
  `frameJank=0`、`avgFrame=2.4ms`、`worstVsync=1.5ms`。再有人报「记录页卡」，先看这一段：
  它干净就说明问题不在卡片本身，而在「第一次」（挂载/测量/首屏光栅）或分页。
- 2026-08-25: 「先量再改」在这条线上连着对了三次。分页那 77ms 落在帧之外的 UI 线程，
  但 SQL 等待 / 标签批查 / 反序列化 / widget 侧复用四种改法完全不同，没有证据就别挑。
- 2026-08-25: 性能日志里凡是 `setState` 相关的计时都要小心命名 —— 它只是排一帧，
  真正的重建成本在下一帧。落库那段叫 `apply=` 不叫 `state=`，就是为了不让人误读。
- 2026-08-26: 分页那 77ms 的推断被自己加的分段计时证伪了（实测 service=13.6ms）。这条线上
  第四次证明「先花小代价加指标，再决定改哪」比「照着合理的推断直接改」省时间 —— 那个推断
  当时看起来无懈可击。
- 2026-08-26: 性能指标要防的不只是「测不准」，还有「在边界情况下给出看起来合理、其实会被
  误读的数」。`dropped` 在列表不动时虚高（引擎本来就不出帧）、采样窗口不关导致 `sql` 比
  `service` 还大、门控太严把要量的那次漏掉 —— 三条都属于后者。
- 2026-08-26: `FrameTiming` 的时间戳走引擎时钟，和 `DateTime.now()`（滚动通知用的）不是同
  一条时间轴，不能直接对齐。要把帧和滚动状态关联，走 `FrameTiming.frameNumber` 和
  `PlatformDispatcher.instance.frameData.frameNumber`（同一个计数器）。

- 2026-08-27: **Android 每次切后台都会发 `memoryPressure`**（`onTrimMemory` 带
  `TRIM_MEMORY_UI_HIDDEN`），Flutter 把它和真正的低内存警告转成同一条消息，Dart 侧分不
  出来；框架默认反应是清空 `imageCache` 并广播 `didHaveMemoryPressure()`。所以 08-23 那条
  「改挂 `didHaveMemoryPressure` 就不会被后台触发」是**错的**，日志里 `gen=2, rewarm=1`
  就是证据。现在靠 `AppWidgetsBinding` 按生命周期状态分流（例行 trim 只把图片缓存淘汰到
  8MB，不清测量缓存）。用户报的「切后台回来图片变灰」和「回前台第一次滑动卡」是同一件事。
- 2026-08-27: 记录页热态滚动已经打平（连着三段 `frameJank=0`）。再收到「记录页卡」的反馈，
  先分清是冷启动首滑、回前台首滑，还是整列表重建（`depsΔ`/`built=全部`）—— 这三条现在是
  互相独立的线，别再当成一个问题一起查。
- 2026-08-27: `dropped` 在可变刷新率（LTPO）屏幕上仍然可能虚高：固定的 8.3ms 预算做除数，
  面板降到 60Hz 时每一帧都会被记成「跳了一帧」。scroll-24 `frames=265 / elapsed=2199ms`
  已经是满帧率，却报 `dropped=54`，算术上说不通。没有证据前不动它，但**任何筛选、判据都
  不要用这个数**。
