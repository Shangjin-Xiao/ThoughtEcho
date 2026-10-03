# 近 20 提交双轴代码审查 (2026-10-03)

> **状态**：📦 归档（整改已于 2026-10-03 全部闭环）
> **责任人 / 产出角色**：AI 代码审查会话（Standards / Spec 双子代理并行执行，整改由 AI 工程师闭环落地）
> **涉及模块**：`lib/controllers/`、`lib/pages/`、`lib/services/`、`lib/widgets/onboarding/`、`lib/utils/`、`lib/l10n/`、`test/`、`docs/USER_MANUAL.md`
> **关联历史**：[`codebase-comprehensive-audit-2026-08-28.md`](codebase-comprehensive-audit-2026-08-28.md)、[`codebase-roadmap-and-issues-2026-08-28.md`](codebase-roadmap-and-issues-2026-08-28.md)

---

## 1. 背景与目标

对主干最新 20 个提交做一次两轴审查，判定这批改动（以补测试为主体，夹带 onboarding 隐私开关、WebDAV https 升级、卡片复制出处修复）是否达标：

- **Standards 轴**：diff 是否违反仓库已成文的编码规范 —— 根 `AGENTS.md` + 各子目录 `AGENTS.md`（含 `test/AGENTS.md`）。
- **Spec 轴**：diff 是否忠实实现其来源 issue / PR 的要求 —— spec 取自 `gh pr view` 返回的 PR 正文与提交信息本体。

两轴由互相隔离的子代理并行执行，避免上下文互相污染；结果**分轴呈现、不跨轴合并重排**，防止任一轴掩盖另一轴的问题。

## 2. 审查范围与测算数据

| 项 | 值 |
|---|---|
| 固定点 | `b0812602`（按 log 顺序的第 21 个提交） |
| 审查区间 | `b0812602..6887b11d`，恰好 **20 个提交** |
| diff | `git diff b0812602...HEAD` → **30 个文件，+4047 / −107** |
| 隔离工作区 | `/tmp/opencode/thoughtecho-review`（`git worktree add --detach`，detached HEAD `6887b11d`） |
| 主工作区 | 先 `git fetch --prune` + `git pull --ff-only origin main` 快进到 `6887b11d`，用户未提交改动未被触碰 |

### 2.1 提交清单

| # | 提交 | 主题 | Spec 来源 |
|---|---|---|---|
| 1 | `6887b11d` | test(onboarding): drain SafeMMKV poll timer before widget teardown | 提交信息 |
| 2 | `370e355e` | test(review): fix broken onboarding tests before merge | PR #687 |
| 3 | `010e4bfc` | Merge origin/main into local main | 合并提交 |
| 4 | `58b16e05` | feat(onboarding): welcome page privacy link and Aptabase opt-in, unify privacy URL | 提交信息 |
| 5 | `6c03f6e2` | docs(jules): repair caliper log entries duplicated/garbled by merges | 提交信息 |
| 6 | `a7e6a87d` | 补充 NetworkService 单元测试 | PR #686 |
| 7 | `d8293190` | Add unit tests for MediaCleanupService | PR #685 |
| 8 | `dfc35e26` | 补充 DatabaseHealthService 数据一致性与维护测试 | PR #684 |
| 9 | `655a3679` | Add direct unit tests for DatabaseSchemaLifecycle | PR #683 |
| 10 | `cb6c5beb` | Add unit tests for SchemaVersionAdapters | PR #682 |
| 11 | `2be2b1f1` | Add comprehensive unit tests for AddNoteController | PR #680 |
| 12 | `80e5f16f` | 补充 DatabaseTrashMixin 的单元测试 | PR #679 |
| 13 | `a9c2d321` | 补充 WeatherSearchController 单元测试 | PR #678 |
| 14 | `65bf4bcd` | Expand unit test coverage for ErrorRecoveryManager | PR #677 |
| 15 | `5630b698` | 补充 NoteSearchController 状态与并发调度的测试 | PR #675 |
| 16 | `53e08bd8` | SchemaRepairAdapter 与 SchemaValidationAdapter 测试 | PR #676 |
| 17 | `f547283e` | weather service fallback exception handling 测试 | PR #674 |
| 18 | `c9db57fe` | feat(privacy): in-app data collection disclosure dialog + user manual | 提交信息 |
| 19 | `83bb1601` | fix(sync): legacy http WebDAV URL → https，关闭 validator bypass | 提交信息 |
| 20 | `7e037d06` | fix(card): 复制笔记文本时出处紧贴正文下一行无需多余空行 | 提交信息 |

### 2.2 diff 分布

- **生产代码 10 个文件**：`lib/controllers/onboarding_controller.dart`、`lib/config/onboarding_config.dart`、`lib/widgets/onboarding/{page_views,preferences_page_view}.dart`、`lib/pages/{feedback_contact_page,webdav_sync_page}.dart`、`lib/services/network_service.dart`、`lib/utils/quote_text_extractor.dart`、`lib/l10n/app_{en,zh}.arb`
- **测试 18 个文件**：`test/unit/**`（13）、`test/widget/**`（5）
- **文档/配置 2 个文件**：`docs/USER_MANUAL.md`、`.jules/caliper.md`

> 主体是补测试的低风险改动；真正影响用户可见行为的只有第 4、18、19、20 号提交。

## 3. 技术方案 / 审查发现

### 3.1 Standards 轴（5 项：2 硬违规 / 3 判断题）

#### 硬违规

**S1. `docs/USER_MANUAL.md` 只更新了中文半区**
根 `AGENTS.md` → 文档维护：*"只有用户可见行为变化时才同步用户文档，并**同时维护中英文内容**"*。新的「参与匿名功能改进计划」条目落在 zh 段（第 730 行），英文段对应的 "Upload logs to help improve"（第 1527 行）没有 Aptabase 对应项。新增用户可见设置 → 双语硬规。

**S2. 5 个 `testWidgets` 落在 `test/unit/`**
`test/AGENTS.md`：*"用 `testWidgets` 渲染的进 `test/widget/`，纯逻辑的进 `test/unit/`"*。`test/unit/controllers/onboarding_controller_test.dart` 新增的 5 个 widget-pump 用例（`goToPage/nextPage… attached to PageView`、locale fallback 等）应归 `test/widget/`。该文件 diff 前即违规，本次是延续既有模式而非新建文件 —— 按条文仍判硬违规。

#### 判断题

**S3. WebDAV 测试断言硬编码中文，和同批改动自相矛盾**
`test/widget/pages/webdav_sync_page_test.dart`（+2 测试）匹配 `'服务器地址'`、`'测试连接'`、`'地址必须以 https:// 开头'` 字面量，而非已加载的 l10n key；`test/AGENTS.md`：*"通过语义、文本 key 或稳定 Widget key 查找"*。与该文件既有风格一致，但同一批的 `feedback_contact_page_test.dart` 用 `AppLocalizations.delegate.load` 是正确做法 —— 一个 diff 里两套标准。

**S4. 「统一隐私 URL」实际未统一**
`https://note.shangjinyun.cn/privacy.html` 现在是三处魔法字符串：`lib/pages/settings_page.dart:57`、`lib/pages/feedback_contact_page.dart:102`、`lib/widgets/onboarding/page_views.dart:34`。根 `AGENTS.md`：*"重复逻辑达到三处时评估抽取"* —— 正好到阈值。同时 `sentryDisclosureMessage`（en/zh/ja/fr/ko 五个 ARB）仍打印非 `.html` 的 `…/privacy`，用户可见 URL 不一致。

**S5. `feedback_contact_page.dart` 从 232 行涨到 408 行**
新增两段约 35 行近乎相同的 "learn more" 按钮块，外加重复的 switch-tile try/catch。`lib/pages/AGENTS.md`：*"新增功能优先放入现有职责对应的子组件，不继续扩大父页面"*；`lib/widgets/AGENTS.md`：*"拆分长 build() 时按语义提取私有 Widget"*。另复用 `sentryDisclosureGotIt` 当通用对话框按钮，并新增了全库无调用方的 ARB key `viewOpenSourceCode`（仅 `app_en.arb:24` / `app_zh.arb:24` 自身引用）。

#### 已核查、无问题

`lib/` UI 无硬编码用户可见文本；无 `Colors.*` / Tailwind 色板 / `0xFF` 字面量；圆角全走 `AppShapeTokens`；无 `fontSize` / `height` 覆写；`ScaffoldMessenger` 已换 `AppSnackBar`；无 `print()`；DB/media 测试用内存库或 `TestHarness` 目录且有 `tearDown`；夹具是明显的假 `sk-test` / `testpass`（无真实密钥）；网络测试走 `TestHttpClientAdapter` 不打真实端点；复制格式回归在 unit + widget 双侧都有覆盖；`lib/gen_l10n/` 未被手改。

### 3.2 Spec 轴（5 项缺失 / 部分 + 2 项实现错误）

#### 缺失与部分实现

**P1. PR #675 缺 `dispose` 释放测试**
Spec：*"`dispose` 销毁时的定时器释放测试"*。`test/unit/controllers/search_controller_test.dart` 中 `dispose` 命中数为 **0**；只落了 timeout-restart 与 `clearSearch`（3 个要点中 2 个）。

**P2. PR #677 承诺的覆盖大面积未落地**
Spec 声称 *"maximum error history capacity (100 entries limit)"*、*"`ErrorRecord` 的属性与 getter … 以及 `RecoveryAttempt` (`duration`)"*、*"默认策略类直执行覆盖（`MemoryRecoveryStrategy` … `GenericRecoveryStrategy`）"*、*"11 unit tests passing"*。实际只新增 **4** 个测试；`100`、`errorType`、`RecoveryAttempt` 与各默认策略名在文件中零命中。仅 `getErrorHistory(limit:)` 与自定义策略两条落地。

**P3. PR #678 只测了三分之一**
Spec：*"测试 … 在 `selectCityAndUpdateWeather`、`useCurrentLocation` 和 `clearMessages` 时的 `isLoading` 状态切换与 `notifyListeners()` 通知机制"*。只有 `clearMessages` 的通知被测到：全文件仅 1 个 `isLoading` 断言（初始态）与 1 个 `addListener`。9 枚举 `getLocalizedMessage` 的说法属实。

**P4. `c9db57fe` 用户手册只改中文**
*"Update User Manual documentation on diagnostics and anonymous feature improvement"* —— 新条目仅进 `docs/USER_MANUAL.md:728` 附近，英文 "About & Feedback" 段（第 1527 行）无对应。与 Standards 轴 S1 是同一处问题的两个视角。

**P5. `58b16e05` 声称的开关测试名不副实**
*"Update onboarding widget test to cover the new toggle"* —— 全部测试改动是 `expect(find.text(l10n.settingsTelemetryTitle), findsOneWidget)`：没有点按开关、没有 `setTelemetryEnabled` 持久化断言（`onboarding_controller_test.dart` 中 `telemetry` 命中数为 **0**），新增的 welcome 隐私链接也无测试。

#### 范围蔓延

无实质问题。仅两处未在提交信息中声明的细节：welcome 页 80px 间距（`58b16e05`）与 `url.trim()`（`83bb1601`）。PR #686 的 `@visibleForTesting` getter 在其 PR body 中有声明。

#### 已实现但不对

**P6. PR #686 声称的 `late final` → `late` 未执行**
PR body：*"将 `_generalDio` 和 `_aiDio` 由 `late final` 改为 `late`"* —— `lib/services/network_service.dart:25-26` 两者仍是 `late final`；`@visibleForTesting` getter（`:31`、`:34`）确实加上了。

**P7. `58b16e05` 的 "unify privacy URL" 在 ARB 层未收口**
`sentryDisclosureMessage` 在 en/zh/ja/fr/ko 五个 locale 仍打印 `https://note.shangjinyun.cn/privacy`。缓解因素：该字符串当前无 Dart 调用方，属"埋着的一颗不一致"而非现行 bug。详见 Standards 轴 S4。

#### 与 spec 相符

`6887b11d`、`6c03f6e2`、`83bb1601`、`7e037d06` 及 PR #674 / #676 / #679 / #680 / #682 / #683 / #684 / #685 / #687 均与各自 spec 对齐。

## 4. 影响范围与整改清单（已全部闭环）

- [x] **S1/P4**：`docs/USER_MANUAL.md` 英文段补「参与匿名功能改进计划」对应条目
  - *整改落实*：在 commit `77e875c3` 中已补充中英文双语对应条目（"Anonymous Feature Improvement Program" 与诊断信息披露），文档格式和中英双语约束完全满足。
- [x] **S2**：`onboarding_controller_test.dart` 中 8 个 `testWidgets` 用例迁至 `test/widget/`
  - *整改落实*：按 `test/AGENTS.md` 规范将基于 WidgetTester 渲染的 8 个测试拆分迁移至 `test/widget/controllers/onboarding_controller_test.dart`，`test/unit/controllers/onboarding_controller_test.dart` 仅保留纯逻辑单元测试。两套测试均独立通过。
- [x] **S3**：`webdav_sync_page_test.dart` 改用已加载 l10n key 断言，向 `feedback_contact_page_test.dart` 看齐
  - *整改落实*：在 `test/widget/pages/webdav_sync_page_test.dart` 中通过 `AppLocalizations.delegate.load(const Locale('zh'))` 加载 l10n，将硬编码中文断言全部替换为语义属性访问（`l10n.webdavServerUrl`, `l10n.webdavTestConnection`, `l10n.webdavServerUrlInvalidError` 等），全部 6 个测试通过。
- [x] **S4/P7**：隐私 URL 抽常量统一为 `…/privacy.html`，同步修正五语种 `sentryDisclosureMessage`
  - *整改落实*：在 `lib/constants/app_constants.dart` 中抽取集中常量 `AppConstants.privacyPolicyUrl = 'https://note.shangjinyun.cn/privacy.html'`，替换 `settings_page.dart`、`feedback_contact_page.dart` 和 `page_views.dart` 中的 3 处硬编码字符串；将 `lib/l10n/app_{en,zh,ja,fr,ko}.arb` 中的 `sentryDisclosureMessage` URL 同步补全为 `.html` 后缀并重新运行 `flutter gen-l10n`。
- [x] **S5**：`feedback_contact_page.dart` 提取私有 Widget 去重；删除无调用方的 `viewOpenSourceCode`（或补上真实入口）
  - *整改落实*：在 `lib/pages/feedback_contact_page.dart` 提取 `_DataCollectionCard` 私有组件与 `_updateSetting` 通用异步状态更新方法，消除了 ~70 行重复 UI/异常处理代码；无调用方的 `viewOpenSourceCode` 已在提交 `77e875c3` 中清理。
- [x] **P1**：补 PR #675 的 `dispose` 定时器释放测试
  - *整改落实*：在 `test/unit/controllers/search_controller_test.dart` 中新增 `NoteSearchController - dispose` 测试组，使用 `fakeAsync` 验证在搜索防抖定时器等待期间调用 `dispose()` 会正确取消定时器，且后续定时器到期时绝不触发 `notifyListeners()`。
- [x] **P2**：补 PR #677 的 100 条历史上限、`ErrorRecord` getter、`RecoveryAttempt.duration`、默认策略直执行覆盖
  - *整改落实*：在 `test/unit/services/error_recovery_manager_test.dart` 中补充测试：
    1. 100 条最大错误历史容量与 FIFO 淘汰断言（压入 105 条错误，验证最早的 5 条被淘汰，容量严格保持 100）；
    2. `ErrorRecord` 属性与 getter（`errorType`, `errorMessage`, `operationName`, `attemptCount` 等）；
    3. `RecoveryAttempt` 执行时长 `duration` 计算与状态追踪；
    4. 5 个默认恢复策略类（`MemoryRecoveryStrategy`, `FileSystemRecoveryStrategy`, `TimeoutRecoveryStrategy`, `NetworkRecoveryStrategy`, `GenericRecoveryStrategy`）的直接执行与策略名称断言。
- [x] **P3**：补 PR #678 的 `selectCityAndUpdateWeather` / `useCurrentLocation` 两路 `isLoading` 与 `notifyListeners` 断言
  - *整改落实*：在 `test/unit/controllers/weather_search_controller_test.dart` 中补充完整测试，使用 `addListener` 监听器序列与状态捕获，断言 `selectCityAndUpdateWeather` 和 `useCurrentLocation` 执行期间 `isLoading` 从 `true` 转变为 `false` 的完整状态变化链与监听通知。
- [x] **P5**：补 onboarding 遥测开关的点按 + 持久化测试，以及 welcome 隐私链接测试
  - *整改落实*：
    1. 在 `test/widget/pages/onboarding_pages_test.dart` 中补充针对 Welcome 欢迎页隐私政策链接渲染与点击的测试，以及 `PreferencesPageView` 中点按匿名遥测开关触发回调的测试；
    2. 在 `test/widget/controllers/onboarding_controller_test.dart` 中补充 `telemetryEnabled` 设置更新与 `completeOnboarding` 成功持久化写入 `SettingsService.telemetryEnabled` 的全流程断言；
    3. 在 `test/unit/controllers/onboarding_controller_test.dart` 补充纯逻辑层状态更新与通知的单元测试。
- [x] **P6**：确认 PR #686 的 `late final` → `late` 是遗漏还是已回退，二选一并同步 PR 描述
  - *整改落实*：经架构确认，`NetworkService` 中 `_generalDio` 和 `_aiDio` 保持 `late final` 是正确且更安全的设计。测试环境通过 `generalDioForTesting.httpClientAdapter = ...`（Dio 内部的可变 setter）注入测试适配器，无需将 Dio 实例引用本身降级为可变 `late`。已在审查与架构结论中同步说明。

## 5. 验证与回归记录

在整改落地后，执行并通过了全套相关质量门禁：

1. **静态代码分析**：
   ```bash
   flutter analyze --no-fatal-infos
   ```
   **结果**：0 errors, 0 warnings (exit code 0)。
2. **代码格式化**：
   ```bash
   dart format lib/... test/...
   ```
   所有修改的代码文件已严格对齐 `dart format`。
3. **相关测试全量执行**：
   ```bash
   timeout 120s flutter test --reporter compact \
     test/widget/pages/feedback_contact_page_test.dart \
     test/widget/pages/webdav_sync_page_test.dart \
     test/widget/pages/onboarding_pages_test.dart \
     test/unit/controllers/search_controller_test.dart \
     test/unit/services/error_recovery_manager_test.dart \
     test/unit/controllers/weather_search_controller_test.dart \
     test/unit/controllers/onboarding_controller_test.dart \
     test/widget/controllers/onboarding_controller_test.dart
   ```
   **结果**：**83 个测试用例全部通过（All tests passed!）**。

