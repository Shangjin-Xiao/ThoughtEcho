# PR143 后重构回归复盘

> 审查范围：`Merge pull request #143` 之后至 `main` 的重构提交  
> 审查时间：2026-03-08  
> 审查目标：确认拆分式重构未破坏行为，并记录已发现/已修复的问题

---

## 1. 本轮重构原本会导致什么问题

### 1.1 DatabaseService 拆分后公共 API 实际丢失

`DatabaseService` 在拆分为多个 part/mixin 文件后，出现了两个问题：

1. 部分拆分文件最初按 `extension`/错误约束方式组织，导致方法没有稳定并入 `DatabaseService` 类型。
2. `database_query_helpers_mixin.dart` 中 `getQuotesForSmartPush()` 缺少结束花括号，导致 `getQuotesCount()` 被错误嵌套到函数内部，外部调用全部失效。

### 直接影响

- 页面/服务编译失败：
  - `getQuotesCount()`
  - `getAllQuotes()`
  - `getUserQuotes()`
  - `getQuoteById()`
  - `addQuote()` / `updateQuote()` / `deleteQuote()`
  - `getCategories()` / `watchCategories()` / `deleteCategory()` 等
- 备份、洞察、首页、编辑页、同步、SmartPush 等模块会连锁报错。

### 1.2 拆分后的私有状态访问关系被破坏

数据库拆分文件大量依赖 `DatabaseService` 内部私有字段/方法，例如：

- `_memoryStore`
- `_categoryStore`
- `_database`
- `_clearAllCache()`
- `_refreshQuotesStream()`
- `_updateCategoriesStream()`

如果拆分方式不对，这些成员会在 analyzer 看来“不可见”，从而引发整条服务链失效。

### 1.3 UI 拆分后 `setState` / static 成员引用不再安全

`AIPeriodicReportPage`、`NoteFullEditorPage`、`NoteListView` 拆成 part 文件后，原本在 `State` 类内部直接可用的内容，被移动到 extension 后会出现：

- `setState()` 被 analyzer 视为非法调用
- `_cardsPerBatch`、`_pageSize`、`_maxScrollExtentChecks`
- `_parseJsonInIsolate()` / `_encodeJsonInIsolate()`

这些 static/private 成员如果不加限定名，会直接编译失败或留下隐性回归。

### 1.4 SmartPush 拆分后静态常量与通知缓存链路失效

`SmartPushService` 的拆分文件里，以下成员被直接引用：

- `_androidAlarmId`
- `_dailyQuoteAlarmId`
- `_notificationChannelId`
- `_notificationChannelName`
- `_scheduledTimesKey`
- `_lastDailyQuoteKey`
- `_lastDailyQuoteDateKey`
- `_pendingHomeDailyQuoteKey`
- `normalizeDailyQuoteData()`

在 extension 场景下，这些静态成员若未显式以 `SmartPushService.` 限定，会导致：

- Android Alarm/通知调度编译失败
- 每日一言缓存/消费逻辑失效
- 后台推送与前台展示链路断裂

---

## 2. 我是如何修复的

### 2.1 恢复 DatabaseService 的可见 API 和拆分结构

修复文件：

- `lib/services/database_service.dart`
- `lib/services/database/*.dart`

修复方式：

1. 重新整理 `DatabaseService` 与拆分文件的关系，让拆分实现真正成为 `DatabaseService` 的一部分。
2. 在基类中声明重构后仍需对外暴露的方法，恢复类型系统可见性。
3. 修复 `getQuotesForSmartPush()` 的缺失花括号问题，恢复 `getQuotesCount()` 的公共方法身份。
4. 恢复测试和业务仍依赖的静态入口/常量，例如：
   - 分类默认 ID
   - `hiddenTagId`
   - `setTestDatabase()` / `clearTestDatabase()`

### 2.2 恢复内部辅助方法的可调用性

数据库拆分后，一些 part 文件之间需要调用内部 helper。为了避免再次出现可见性断裂，我增加了明确的“part 间桥接调用”：

- 缓存清理桥接
- 分类流刷新桥接
- 笔记流刷新桥接
- 安全通知桥接

这样做的目标是：

- 保持原有内部封装
- 让拆分后的文件之间仍能安全协作
- 避免以后再因为 private 访问路径变化而大面积报错

### 2.3 修复拆分 UI 页面的状态更新方式

修复文件：

- `lib/pages/ai_periodic_report_page.dart`
- `lib/pages/ai_report/*.dart`
- `lib/pages/note_full_editor_page.dart`
- `lib/pages/note_editor/*.dart`
- `lib/widgets/note_list_view.dart`
- `lib/widgets/note_list/*.dart`

修复方式：

1. 在宿主 `State` 中增加 `_updateState()` 包装，统一处理 `mounted` 检查。
2. 将拆分 extension 中直接调用的 `setState()` 改为 `_updateState()`。
3. 对静态成员访问改为显式限定：
   - `_AIPeriodicReportPageState._cardsPerBatch`
   - `_NoteFullEditorPageState._parseJsonInIsolate`
   - `NoteListViewState._pageSize`
   - `NoteListViewState._maxScrollExtentChecks`
4. 同时把这些 extension 改为私有命名，减少“对私有 State 暴露 public extension”产生的噪音。

### 2.4 修复 SmartPush 拆分后的静态成员访问

修复文件：

- `lib/services/smart_push_service.dart`
- `lib/services/smart_push/smart_push_notification.dart`
- `lib/services/smart_push/smart_push_platform.dart`
- `lib/services/smart_push/smart_push_scheduling.dart`
- `lib/services/note_sync_service.dart`

修复方式：

1. 所有静态常量访问改为 `SmartPushService.xxx` 显式限定。
2. 对通知相关 `notifyListeners()` 增加宿主转发入口，避免拆分 extension 误用保护成员。
3. 补上 `note_sync_service.dart` 中缺失的 `http` 引用导入，修复同步流程编译问题。

---

## 3. 修复后的验证结果

### `flutter analyze`

- 已无 `error`
- 当前剩余主要为历史 `info/warning`，例如：
  - `withOpacity` 弃用提示
  - 若干 `@override` 建议
  - 少量未使用私有辅助方法

这些不是本轮重构破坏功能导致的错误。

### `flutter test test/all_tests.dart`

- 代码编译已恢复
- 当前失败点为测试环境问题，而不是本轮修复逻辑问题：
  - `sqflite_common_ffi` 运行时无法加载 `libsqlite3.so`
  - 失败测试：`test/performance/day_period_patch_test.dart`

即：测试阻塞点已经从“重构代码错误”变成“本机动态库环境缺失”。

---

## 4. 结论

这次 PR143 之后的重构，原本确实引入了真实回归，且主要集中在“拆分后类型可见性/私有成员访问/State 生命周期调用方式”三类问题上。

本轮已完成的修复结论：

- `DatabaseService` 拆分后的核心 API 已恢复
- AI 报告页、编辑页、笔记列表拆分后的状态更新链路已恢复
- SmartPush 拆分后的调度/通知/缓存关键链路已恢复
- 当前剩余问题主要是历史 lint 与测试机缺少 `libsqlite3.so`

---

## 5. 对后续重构的建议

1. 大型类拆分优先使用 `part + mixin on 宿主类型`，不要混用不稳定的 extension 方案承载核心业务 API。
2. 拆分后先做一次最小验证：
   - `flutter analyze`
   - 关键页面编译
   - 关键服务入口 smoke test
3. 对以下高风险信号设为必查项：
   - static/private 成员跨 part 调用
   - `setState()` 是否仍在 `State` 安全上下文内
   - 公共方法是否仍能被 `DatabaseService` / `SmartPushService` 类型看到
4. 对“机械式拆分”提交，建议单独增加一轮 CI 或 checklist，而不是只看 diff 是否“逻辑未改”。
