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

