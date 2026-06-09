# AddNoteDialog Firebase 性能定位交接

## 背景

用户反馈：非全屏编辑器 `AddNoteDialog` 打开会卡。当前依据为
Firebase Test Lab / GitHub Actions 产物：

- `temp_firebase_perf/firebase-test-run.log`
- `temp_firebase_perf/build/firebase-test-lab/thoughtecho-performance-summary.json`
- 原始 logcat：
  `temp_firebase_perf/build/firebase-test-lab/2026-06-08_08_17_25.089828_JnOi/MediumPhone.arm-35-zh_CN-portrait/logcat`

测试矩阵：

- 时间：2026-06-08 08:17 UTC 左右
- 设备：`MediumPhone.arm-35-zh_CN-portrait`
- 结果：Instrumentation test passed

## 已确认事实

### 1. 测试通过但 AddNoteDialog 打开阶段有明显掉帧

`thoughtecho-performance-summary.json` 中 AddNoteDialog 数据：

| 场景 | frame_count | worst build | missed build | worst raster | missed raster | GC |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| `add_note_dialog_cold_open` | 5 | 74.415ms | 3 | 159.737ms | 3 | new 2 / old 6 |
| `add_note_dialog_warm_open` | 6 | 65.875ms | 3 | 44.277ms | 2 | new 2 / old 0 |

结论：

- 卡顿不是测试失败，而是打开路径存在 16.6ms 帧预算外的 jank。
- 冷启动尤其重，raster worst 159.737ms，且 old GC 6 次，说明冷路径有较强渲染/内存压力。
- 热启动 build 仍高达 65.875ms，说明问题不只是冷缓存。

### 2. Action 测的是默认“自动聚焦并拉起键盘”的路径

`integration_test/note_list_performance_test.dart` 的 `_PerformanceSettingsService`
使用：

- `addNoteDialogAutoFocus == true`
- `addNoteDialogDeferAutoMetadata == false`
- `developerMode == true`
- `enableFirstOpenScrollPerfMonitor == true`

因此 Firebase 结果覆盖的是默认路径：BottomSheet 打开后自动请求内容输入框焦点，
随后系统键盘弹出，300ms 后启动延迟元数据初始化。

### 3. 自定义 timeline 标记显示键盘参与打开路径

AddNoteDialog 两个场景都出现了：

- `ThoughtEcho.AddNoteDialog.routeAnimation.complete`
- `ThoughtEcho.AddNoteDialog.focus.requested`
- `ThoughtEcho.AddNoteDialog.focus.acquired`
- `ThoughtEcho.AddNoteDialog.keyboardInset.started`
- `ThoughtEcho.AddNoteDialog.deferredMetadata.start`
- `ThoughtEcho.AddNoteDialog.deferredMetadata.complete`

没有出现：

- `ThoughtEcho.AddNoteDialog.keyboardInset.settled`

结论：

- 自动聚焦确实发生，键盘 inset 变化确实进入 trace。
- 当前 trace 窗口/日志没有记录到键盘稳定点，无法精确量化键盘动画持续时间。

### 4. logcat 证实输入法在同一时间段重算并展示键盘

原始 logcat 在 AddNoteDialog 打开附近有大量 `GoogleInputMethodService`
和 `KeyboardHeightUtil` 记录，例如：

- `isFullscreenMode:false`
- `leave 281 height for app ... max keyboard body height ...`
- `onKeyboardViewShown: keyboardType=prime`

结论：

- “非全屏编辑器打开会卡”的 Action 结果与 Android 非全屏键盘动画/inset
  调整高度强相关。
- 这不是全屏编辑器路径；全屏编辑器不会走同一个 BottomSheet + keyboard inset
  组合。

### 5. 当前 Action 产物没有 detailed AddNoteDialog slice

本次产物只有以下 chunk：

- `add_note_dialog_cold_open`
- `add_note_dialog_warm_open`
- `note_list_plainText`
- `note_list_richText`
- `note_list_images_cold`
- `note_list_images_warm`

没有：

- `add_note_dialog_cold_diagnostic_open`
- `add_note_dialog_warm_diagnostic_open`
- detailed build/layout slice

重要时间点：

- Firebase run：2026-06-08 08:17 UTC
- 后续提交 `79ded6e0 test: expose detailed Firebase timeline slices`：
  2026-06-08 10:27 UTC

结论：

- 这次 Action 结果不足以精确定位到某个 widget build/layout slice。
- 需要在包含 detailed diagnostic 的最新提交上重跑 Firebase workflow，才能把
  jank 归因到具体 Widget/RenderObject。

## 当前代码中的相关机制

文件：`lib/widgets/add_note_dialog.dart`

已存在优化：

- 等 BottomSheet route animation 完成后再 `_requestContentFocus()`。
- `didChangeMetrics()` 中检测键盘 inset 变化。
- `_beginKeyboardRebuildDeferral()` 在键盘变化期间启用 body 复用。
- `_buildKeyboardDeferredDialogBody()` 通过 `_cachedDialogBody` 复用完整表单子树。
- `_startDialogPerfCapture()` 在开发者模式下记录帧、build、raster、inset、
  focus、state change。

外层结构：

- `showModalBottomSheet(isScrollControlled: true)`
- `AddNoteDialog.build()`
- `KeyboardInsetPadding` 读取 `MediaQuery.viewInsetsOf(context).bottom`
- `SingleChildScrollView + Column + TextField + chips + tags + buttons`

风险点：

- `KeyboardInsetPadding` 只把 `viewInsets` 影响限制在 padding 层；
  但 BottomSheet route 本身仍会随 inset / route animation 布局和重绘。
- `_cachedDialogBody` 能减少 Dart widget build，不一定能减少外层 sheet、
  scroll view、clip/shadow、keyboard resize 触发的 raster 成本。

## 暂定根因判断

最可能根因：

1. 默认自动聚焦导致 BottomSheet 入场动画刚结束后立刻拉起软键盘。
2. 软键盘以非全屏模式展示，`viewInsets` 连续变化。
3. BottomSheet + `KeyboardInsetPadding` + `SingleChildScrollView` + 大表单在
   inset 动画期间触发布局/光栅。
4. 冷路径还叠加首次渲染、Impeller 光栅、GC 和表单资源初始化，因此 cold
   raster 达到 159.737ms。

这解释了：

- 为什么用户感知是“打开 AddNoteDialog 会卡”。
- 为什么 timeline 中 `focus`、`keyboardInset.started` 都出现。
- 为什么 cold/warm 都卡，但 cold 更重。

尚未被当前 Action 直接证明：

- 哪个具体 widget/layout slice 最慢。
- 关闭自动聚焦后 jank 会下降多少。
- 将元数据延迟到键盘动画后是否有明显收益。
- 是否需要从 BottomSheet 改为固定高度/全屏路由/DraggableScrollableSheet。

## 建议下一步

1. 在最新代码上重跑 `firebase-note-list-performance.yml`，确保产物包含
   `add_note_dialog_*_diagnostic_open`。
2. 增加或临时参数化三个 AddNoteDialog 场景：
   - 默认：`autoFocus=true, deferMetadata=false`
   - 无自动键盘：`autoFocus=false, deferMetadata=false`
   - 键盘后元数据：`autoFocus=true, deferMetadata=true`
3. 对比三个场景的：
   - worst build/raster
   - missed frame count
   - `keyboardInset.started/settled`
   - detailed slow slices
4. 若 `autoFocus=false` 明显改善，优先考虑默认不自动拉起键盘，或给用户设置默认关闭。
5. 若 detailed slice 指向 raster 而不是 Dart build，继续减少 BottomSheet
   打开期间的重绘面积，而不是只优化子 Widget build。

## 当前不建议直接做的改动

- 不建议仅继续缓存 `_cachedDialogBody`。现有数据已经显示 warm build 仍有
  65.875ms，cold raster 仍有 159.737ms，说明问题不只在表单子树重复 build。
- 不建议直接把 metadata 延迟开关默认改为 true。当前 Action 没有对照组。
- 不建议只修改 tag 列表。测试场景标签 100 个但未展开，且 TagSelectionSection
  已延迟构建展开内容。

## 2026-06-09 追加定位

已下载并分析成功 run：

- GitHub Actions run：`27192007949`
- Firebase 产物目录：
  `temp_firebase_perf_prior/firebase-performance-27192007949/`
- 该 run 已包含 detailed AddNoteDialog 场景。

AddNoteDialog 摘要：

| 场景 | worst build | missed build | worst raster | missed raster | 关键 marker |
| --- | ---: | ---: | ---: | ---: | --- |
| `add_note_dialog_cold_open` | 104.065ms | 4 | 66.019ms | 2 | focus + keyboardInset |
| `add_note_dialog_cold_diagnostic_open` | 72.922ms | 2 | 29.569ms | 1 | focus + keyboardInset |
| `add_note_dialog_warm_open` | 29.155ms | 2 | 23.007ms | 1 | focus + keyboardInset |
| `add_note_dialog_warm_diagnostic_open` | 69.561ms | 3 | 1.476ms | 0 | focus + keyboardInset |

Detailed 证据：

- `add_note_dialog_cold_diagnostic_open` 的慢 build slice 明确出现：
  `_MediaQueryFromView(dirty)`，最近 marker 是
  `ThoughtEcho.AddNoteDialog.keyboardInset.started`。
- 同一场景的路由链路慢 slice 包括：
  `_ModalBottomSheet<void>`、`BottomSheet`、`_BottomSheetLayoutWithSizeListener`、
  `PhysicalShape`、`ClipRect`、`MediaQuery`、`Padding`。
- `add_note_dialog_cold_open` 中 `GPURasterizer::Draw` 66.02ms，最近 marker 是
  `ThoughtEcho.AddNoteDialog.focus.acquired`。
- logcat 同时显示 Gboard/Google 输入法以 `isFullscreenMode:false` 展示键盘。

修复方向已由证据收敛：

- 默认不要在 AddNoteDialog 打开时自动请求焦点。
- 保留开发者设置 `addNoteDialogAutoFocus`，需要旧体验的用户仍可手动开启。
- 不把 `addNoteDialogDeferAutoMetadata` 默认改为 true；当前主要 jank 证据来自
  keyboard inset/BottomSheet，而不是元数据服务。

本地已实施修复：

- `AppSettings.addNoteDialogAutoFocus` 默认改为 `false`。
- `AppSettings.fromJson({})` 缺省值改为 `false`。
- `AddNoteDialog` 在找不到 `SettingsService` 时 fallback 为不自动聚焦。
- 开发者设置页文案改为国际化，并标明“默认关”。

本地验证：

- 先写测试并确认红灯：
  `test/unit/models/app_settings_test.dart --name "defaultSettings should have expected default values"`
  在实现前失败，实际值为 `true`。
- 实现后通过：
  `timeout 120s flutter test --reporter compact test/unit/models/app_settings_test.dart --name "defaultSettings should have expected default values"`

## 2026-06-09 Firebase 重跑结果

已重跑 main 基线：

- GitHub Actions run：`27196077326`
- Firebase 产物目录：`temp_firebase_perf_main_current/`

main 基线结果：

| 场景 | worst build | missed build | worst raster | missed raster | 关键 marker |
| --- | ---: | ---: | ---: | ---: | --- |
| `add_note_dialog_cold_open` | 101.981ms | 3 | 60.936ms | 2 | focus + keyboardInset |
| `add_note_dialog_cold_diagnostic_open` | 71.274ms | 2 | 20.428ms | 2 | focus + keyboardInset |
| `add_note_dialog_warm_open` | 36.083ms | 3 | 27.405ms | 1 | focus + keyboardInset |
| `add_note_dialog_warm_diagnostic_open` | 74.661ms | 4 | 1.859ms | 0 | focus + keyboardInset |

已重跑第一版修复分支：

- GitHub Actions run：`27196624573`
- Firebase 产物目录：`temp_firebase_perf_fix/`

第一版修复结果：

| 场景 | worst build | missed build | worst raster | missed raster | 关键 marker |
| --- | ---: | ---: | ---: | ---: | --- |
| `add_note_dialog_cold_open` | 124.855ms | 2 | 71.232ms | 3 | no focus/keyboardInset |
| `add_note_dialog_cold_diagnostic_open` | 87.577ms | 2 | 15.946ms | 0 | no focus/keyboardInset |
| `add_note_dialog_warm_open` | 52.479ms | 1 | 30.427ms | 2 | no focus/keyboardInset |
| `add_note_dialog_warm_diagnostic_open` | 87.275ms | 2 | 1.403ms | 0 | no focus/keyboardInset |

结论：

- 默认关闭 AddNoteDialog 自动聚焦已经移除了 `focus.requested`、
  `focus.acquired`、`keyboardInset.started`，键盘/inset 卡顿链路被切断。
- 但打开阶段仍有大帧，说明第二层问题是 modal bottom sheet route 打开本身：
  detailed slice 中仍可见 `Navigator`、`ModalRoute`、`Overlay`、`BottomSheet`、
  `FocusTraversalGroup` 等 route/动画/焦点链路。
- 因此需要继续减少 AddNoteDialog 打开时的 route 动画和 route 级焦点工作。

第二版本地修复方向：

- 在 `AddNoteDialog` 旁统一定义 `bottomSheetAnimationStyle =
  AnimationStyle.noAnimation`。
- 生产入口使用 `sheetAnimationStyle` 禁用非全屏编辑器 bottom sheet 动画。
- 生产入口同时设置 `requestFocus: false`，避免 route 打开时额外请求焦点。
- Firebase 性能 harness 使用同一策略，确保 CI 测到真实修复路径。
- 通过：
  `timeout 120s flutter test --reporter compact test/unit/services/settings_service_test.dart`
- 通过：
  `timeout 120s flutter test --reporter compact test/widget/add_note_dialog_focus_timing_test.dart`
- 通过：
  `timeout 120s flutter test --reporter compact test/unit/l10n/app_arb_consistency_test.dart`
- 通过：
  `flutter analyze --no-fatal-infos`，仅有既有 info 级提示。

待完成：

- 将修复分支推到 GitHub 后，用 Firebase workflow 在修复后 commit 上重跑。
- 预期修复后 AddNoteDialog 默认场景不再出现：
  `ThoughtEcho.AddNoteDialog.focus.requested`、
  `ThoughtEcho.AddNoteDialog.focus.acquired`、
  `ThoughtEcho.AddNoteDialog.keyboardInset.started`。
