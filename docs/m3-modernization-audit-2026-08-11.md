# Material 3 现代化审计（2026-08-11）

这份审计的由来：改 Thoughter 对话页时发现顶栏没有任何"内容滚到底下"的反馈，
往下追发现是主题里把 M3 的一整套机制关掉了。顺手把全项目扫了一遍，记在这里，
留给专门的一轮 UI 翻新用。**本文只记录现状和建议，不代表已经改了。**

先说结论：**代码本身比"看起来旧"要新得多。** 核心组件基本都迁到 M3 了——

| 用了 M3 | 处数 | 对应的 M2 老组件 | 处数 |
| --- | ---: | --- | ---: |
| `FilledButton` | 81 | `ElevatedButton` | 32 |
| `NavigationBar` | 10 | `BottomNavigationBar` | 0 |
| `DropdownMenu` | 12 | `DropdownButton` | 7 |
| `SegmentedButton` | 3 | `ToggleButtons` | 0 |
| `Badge` | 14 | — | — |

`RaisedButton` / `FlatButton` 这类 M2 遗物一个都没有，动态取色默认开，
SnackBar 已经是 floating。**"陈旧感"主要来自下面这些系统级的动效和细节没接上，
不是组件本身。**

统计口径：`grep -rn <名字> lib --include=*.dart | wc -l`，2026-08-11 于
`claude/thoughter-dialog-spacing-ui-fk77q4` 分支上跑的。数字是"出现次数"不是
"调用点数"，看量级即可。

---

## 一、AppBar 的 scrolledUnder 在全 app 失效

### 现象

`lib/theme/app_theme.dart` 浅色 773-774 行、深色对应位置：

```dart
appBarTheme: baseTheme.appBarTheme.copyWith(
  backgroundColor: colorScheme.surfaceContainerLow,
  elevation: 0,
  surfaceTintColor: Colors.transparent,   // ← 这一行
),
```

M3 规定内容滚到顶栏底下时顶栏要变一下。Flutter 的实现是
`scrolledUnderElevation`（M3 默认 3）配合
`ElevationOverlay.applySurfaceTint(backgroundColor, surfaceTintColor, elevation)`
——**M3 里的"高度"不再画阴影，而是往背景色里掺 `surfaceTintColor`**。

染色设成透明，`applySurfaceTint` 掺多少都返回原色；而 M3 的 `AppBar` 默认
`shadowColor` 本来就是透明的（画阴影是 M2 的做法）。两条路都堵上，
`scrolledUnderElevation` 还是 3，但它什么也做不出来。

**影响范围是全 app 每一个可滚动页面**，不只 Thoughter。

### 为什么当初这么写

查不到。`git log -S "surfaceTintColor: Colors.transparent"` 只指向
`479daa8`，那是一个把 `.agents/skills` 整个塞进来的巨型导入 commit，
历史被压过了，看不到原始意图。

**以下是推测**：`elevation: 0` + `surfaceTintColor: Colors.transparent`
是 M2→M3 迁移时最常被复制的两行。M3 一开，很多人发现顶栏莫名其妙泛紫
（就是这个 surface tint），搜出来的第一个答案就是这么关掉。

### 三条路

1. **恢复染色**：删掉 `surfaceTintColor: Colors.transparent`，让 M3 的机制跑起来。
   代价是顶栏在滚动时会泛一层主题色，也就是当初被关掉的那个效果。
2. **顶栏融进页面**：`backgroundColor` 改成 `colorScheme.surface`，
   边界交给内容区上缘的渐隐。ChatGPT / Gemini 都是这个路子。
   **Thoughter 页已经按这条改了**（页面级，没动全局主题）。
3. **保持现状**，接受没有滚动反馈。

选 2 的话建议连 `surfaceContainerLow` 一起从全局主题里去掉，否则每个页面
都要自己覆盖一次。

---

## 二、预测式返回（Predictive Back）没启用

**这是"旧"得最明显的一条，也是改动最小的一条。**

Android 13+ 的手势返回本该是"当前页缩小、露出后面那页"，跟着手指走、
松手前可以反悔。要开需要两处，目前**一处都没有**：

- `android/app/src/main/AndroidManifest.xml` 的 `<application>` 上加
  `android:enableOnBackInvokedCallback="true"`
- 主题里配 `pageTransitionsTheme`，Android 平台用
  `PredictiveBackPageTransitionsBuilder`

全项目 `PredictiveBack` 0 处，`pageTransitionsTheme` 0 处——现在走的是
Flutter 默认的 `ZoomPageTransitionsBuilder`。**它本身是有转场动画的**（Android 10
那套缩放），只是不支持预测式返回手势：返回不跟手、松手前看不到目标页、也没法反悔。
`PredictiveBackPageTransitionsBuilder` 只负责这段视觉转场，手势能力由 Manifest
那个系统回调开关决定，两者要一起配才完整。

`targetSdkVersion 35`，版本条件早就满足了。

**返回逻辑本身不用动。** 仓库里没有 `WillPopScope`，已有 9 处 `PopScope`；
`note_sync_page.dart:607` 的 `_onWillPop()` 是自定义的异步确认逻辑，外面由
`PopScope(canPop: _allowPagePop, onPopInvokedWithResult: ...)` 承载——
`_allowPagePop` 初值 false，确认通过后置成 true 再真的 pop（同文件 148 / 613 行），
正是 Flutter 文档给的异步确认写法。这一条只涉及 Manifest 开关和转场 builder 两处，
不需要迁移任何返回处理代码。

---

## 三、分隔线：浅色和深色不一致（大概率是手滑）

`lib/theme/app_theme.dart`：

- 第 712 行（浅色）：`useM2StyleDividerInM3: true`
- 第 848 行（深色）：`useM2StyleDividerInM3: false`

浅色主题下用的是 **M2 的黑色半透明分隔线**，深色下用 M3 的 `outlineVariant`。
全项目 74 处 `Divider(`。

两处应该一致。没找到任何注释解释为什么要分开，看着像复制粘贴时漏改。

---

## 四、系统栏 / edge-to-edge 只覆盖了两个页面

系统栏样式**不是没人管，是只管了两处**：

- `lib/pages/home_page.dart:788` —— `AnnotatedRegion<SystemUiOverlayStyle>`，
  样式由 `_buildSystemUiOverlayStyle()`（同文件 1088 行）按主题算出来
- `lib/widgets/anniversary_animation_overlay.dart:159` —— 沉浸式覆盖层，
  用的是写死的 `_immersiveOverlayStyle`

其余页面没有任何 `AnnotatedRegion` / `SystemUiOverlayStyle`，靠 `AppBar` 自己按
背景亮度推的 `systemOverlayStyle` 兜着——**底部导航栏那条它管不到**。
`SystemChrome.setEnabledSystemUIMode` 只出现在测试里
（`test/widget/widgets/anniversary_animation_overlay_test.dart:113`），生产代码 0 处。

版本这块要说准：`targetSdkVersion 35` 意味着**在 Android 15（API 35）上受
edge-to-edge 强制约束**；`compileSdk 36` 只决定编译时能用哪些 API，不等于
target 了 Android 16。退出开关 `windowOptOutEdgeToEdgeEnforcement` 在
Android 15 上仍然可用，只有 target 36 的应用在 Android 16 设备上才被禁用。
而 `android/app/src/main/res/values/styles.xml` 和 `values-night/styles.xml`
两处都没有配这个属性——**也就是没有退出，应用确实在 edge-to-edge 下跑。**

Flutter 的 `SafeArea` 挡住了大部分问题，但状态栏 / 导航栏的图标颜色
（`SystemUiOverlayStyle`）在主题切换时是否跟着走，需要真机验一下——
`AppBar` 会按自己的背景亮度自动设 `systemOverlayStyle`，但底部导航栏那条不会。

---

## 五、其余（按值不值得做排）

| 项 | 现状 | 说明 |
| --- | --- | --- |
| 底部表单缺拖拽手柄 | 20 处 `showModalBottomSheet`，仅 3 处带 `showDragHandle: true` | M3 的 sheet 顶部那条小横杠，既是样式也是"这个拖得动"的提示 |
| 搜索框还是 `TextField` | 0 处 `SearchAnchor`，1 处 `SearchBar` | 典型代表：`lib/pages/thoughter/session_history_page.dart:196`。M3 的 `SearchAnchor` 点开展开成全屏搜索带建议列表，是"一眼就旧"的控件之一 |
| 进度指示器 | 59 处 `CircularProgressIndicator` + 10 处 `LinearProgressIndicator`，0 处 `year2023` | Flutter 3.27 之后给进度条加了新 M3 造型（带缺口、圆头），用 `ProgressIndicatorThemeData(year2023: false)` 开。**要在项目锁定的 Flutter 版本上先验一下**——版本够新的话默认可能已经翻过去了，那就不用动 |
| 弹出菜单 | 5 处 `PopupMenuButton`，0 处 `MenuAnchor` | M3 用 `MenuAnchor` 取代 `PopupMenuButton`。数量少，收益也小 |
| `Card` 变体 | 177 处 `Card(`，0 处 `Card.filled` / `Card.outlined` | **基本可以不管**：`_styleCardTheme` 已经统一压成 elevation 0 + 描边，视觉上已经是 outlined 的效果，只是没用新 API |
| `ElevatedButton` | 32 处，与 81 处 `FilledButton` 混用 | M3 里 `ElevatedButton` 是"低强调但需要和背景分离"的特殊场景。32 : 81 这个比例更像是没统一，而不是有意区分。值得逐个看一眼该不该换成 `FilledButton` / `FilledButton.tonal` |
| `chat_input_suggestions.dart` | `lib/` 里没有任何地方 import 它 | 一个横向滚动的 `ActionChip` 列表，看着像当初为 Thoughter 空状态写的、写完忘了接上。**先别删**：PR #463 正在给它加 `generateSuggestions()` 和单元测试，删掉会和那个 PR 硬冲突。等 #463 落地后再决定是接上（比如首条回答之后给两三个追问）还是删掉 |

---

## 建议的推进顺序

1. **预测式返回**（两行配置，体感提升最大）
2. **分隔线那个不一致**（大概率是 bug，一行）
3. **AppBar scrolledUnder** 三选一，定下来后全局统一
4. 系统栏 / edge-to-edge 真机验一遍
5. 底部表单补手柄（20 处，机械劳动）
6. 其余按需

前三条加起来改动量很小，但覆盖了"陈旧感"的绝大部分来源。

---

## 附：这一轮（PR #467）已经在 Thoughter 页做掉的

页面级改动，**没有动全局主题**，方便将来整体翻新时统一收回去：

- 顶栏 `backgroundColor` 改成 `surface`，配合对话区上下缘的渐隐
- 渐隐用同色渐变而不是 `ShaderMask`（省掉每帧一次 saveLayer；页面背景是
  纯色 `surface`，两者视觉上等价）
- 渐变终点写 `surface.withValues(alpha: 0)` 而不是 `Colors.transparent`
  ——后者是"透明的黑"，`LinearGradient` 做的是直接 RGBA 插值，
  白→透明黑中间会经过灰，浅色主题下边缘会脏一道
- 渐隐只在那个方向真的藏着内容时才出现（`extentBefore` / `extentAfter`），
  等于用别的方式表达了 scrolledUnder 想说的意思
