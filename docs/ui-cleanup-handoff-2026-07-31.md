# UI 清理工作交接（2026-07-31）

> 承接 2026-07-30 的全项目 UI 审查。本文档记录已完成、未完成、以及接手时必须知道的坑。
> 主分支：`main`（所有已完成工作都已推送到 `origin/main`）。

## 给接手的 agent

**本文档是自足的**，按它执行不需要额外上下文。但如果遇到「为什么当初这么决定」这类
问题，产生这些结论的那次 Claude Code 会话记录里有完整的推导过程（包括被推翻的中间判断、
子代理的调研原文、以及用户对若干结论的质疑和纠正）。会话记录存放在 Claude Code 的项目
历史中，可以通过 `claude --resume` 查看该项目的历史会话列表。

需要特别注意的是：**那次会话里有多条后来被推翻的结论**（详见下文「已修正的错误判断」），
所以读会话记录时要以本文档为准，不要直接采信会话中途的说法。本文档记录的是最终结论。

配套文档：`docs/paper-ink-theme-plan-2026-07-30.md`（主题方案与色板，含 02 暖、03 冷两套
完整取值）。

## 一、已完成并推送（8 个 commit）

| commit | 内容 |
| --- | --- |
| `a56158ab` | `AppSemanticColors`（ThemeExtension，补 M3 缺失的 success/warning）+ 两套主题补 `snackBarTheme` + 修 `AppSnackBar` 内部硬编码色 + AGENTS.md 新增「UI 硬性约束」 |
| `2bacebea` | 设置页「实验室」：7 份重复的 `developerMode` 判断收成 1 份；修正滚动性能开关错误复用 `l10n.logDebugInfo` 的 bug；2 处硬编码中文入 l10n |
| `fdb958ac` | 删 1439 行死代码（6 个文件 + `license_page` 里的 `SystemLicensesPage`） |
| `f3ffa8cb` | 22 个文件 51 处手写 SnackBar 统一到 `AppSnackBar`，硬编码红色 46 → 0，净减 199 行 |
| `f34e1fc8` | 周年纪念卡改用 `tertiaryContainer`，清掉 11 处 Tailwind 硬编码色 |
| `099dacf9` | `docs/paper-ink-theme-plan-2026-07-30.md`（纸墨主题计划，待决策） |
| `7e0c8958` | 17 个文件清除 UI 装饰性中文斜体；存储页 `_storagePalette` 三处配色统一 |
| `617539c6` | README 删掉中英文首屏的质量道歉 |

## 二、未完成的工作

### 1. 圆角收敛（已完成，`19e033e5`）

40 个文件，硬编码 `BorderRadius.circular(N)` 从 238 处降到 154 处，剩余的是徽章、图标
背景、进度条、头像、胶囊形状等按设计本就不该统一的装饰件。年度报告相关页面未动。

采用的判定规则完整记录在下面「圆角收敛规则」一节，后续新增 UI 沿用同一套判据。

**这次踩到的坑（重要）**：`Card` / 按钮的 `shape` 覆盖可以直接删掉继承主题，但
**输入框不行**。项目从未设置 `inputDecoratorBorderType`，FlexColorScheme 该参数默认是
`FlexInputBorderType.underline`（见 `flex_sub_themes_input_decoration.dart:510`），
所以主题的 `inputDecorationTheme.border` 是下划线。删掉 `border: OutlineInputBorder()`
会让描边输入框变成下划线输入框。输入框必须**保留**显式 `OutlineInputBorder`，只把圆角
换成 `AppTheme.inputRadius`。

（若将来想让输入框也能安全继承，正解是在两套主题的 `subThemesData` 里显式加
`inputDecoratorBorderType: FlexInputBorderType.outline`，然后再统一删除覆盖。）

**留给后续判断的模糊项**（子代理标记，本次一律未改，保持原值）：

- `home_page.dart:988-1003` —— FAB 的阴影 `Container` + `FloatingActionButton.shape`，
  都是 `circular(16)`。这是刻意做的 squircle FAB，不确定是否要收敛。
- `anniversary_animation_overlay.dart:205/214/340` —— 周年彩蛋的玻璃拟态卡片，
  整套用 28/20/999 自定义值，收敛可能破坏其刻意的视觉层次。
- `ai_assistant_page_ui.dart:350/513`、`assistant_input_panel.dart:57/151` —— 聊天输入
  框外壳，有 border+shadow 但 TextField 自身是 `InputBorder.none`，介于 `inputRadius`
  和 `cardRadius` 之间。
- `tool_progress_panel.dart:174` —— 和 `thinking_widget` 同类的折叠面板，但没有
  border/shadow，按判据不算卡片；两者目前不一致。
- `PopupMenuButton` / `DropdownButton` 的 `shape` 与 `borderRadius`（多处）—— 不在四个
  令牌的语义范围内，全部保持原样。
- Markdown 的 `codeblockDecoration` / `blockquoteDecoration`（多处）—— 属于排版而非
  应用结构，全部保持原样。

### 2. 第二批死代码（已完成，`267e609f`）

删除 `InsightsPage` / `TagSettingsPage` / `MediaManagementPage` 共 2624 行。删除前
重新 grep 复核过：类名与文件名在 `lib/` 和 `test/` 均零引用，`InsightsPage` 唯一命中的是
`annual_report_page.dart` 里那个恰好同名的方法 `_buildInsightsPage()`。

### 3. 空态（已修正的错误判断，优先级低）

**之前的判断是错的，不要照做。** 曾认为「标签页/分类页/媒体页缺空态」，实际上：

- 数据库有 6 个系统默认标签（`database_service.dart:61-66` 的
  `defaultCategoryIdHitokoto/Anime/Comic/Game/Novel/Original`），标签页不会空
- 媒体页是死代码，不用管

真正值得做的空态还需要重新调研，不要基于旧结论动手。

### 4. 加载态统一（已修正的错误判断，不建议做）

曾把「51 处裸 `CircularProgressIndicator`」当成待修复量报告，**这个数字是误导性的**：
其中 36 处带 `strokeWidth`，是按钮内/图标内的小 spinner，属于正确用法。真正的整页加载态
只有约 15 处，去掉年度报告相关的还剩 12 处左右。

而且 `AppLoadingView` 默认是 80px 的 Lottie 动画，页面若加载很快（本地 SQLite 通常几十
毫秒），大动画闪一下就消失，比朴素 spinner 更晃眼。**收益可疑，建议不做。**

## 三、主题工作的决策状态

**完整色板和架构要求见 `docs/paper-ink-theme-plan-2026-07-30.md`**，那里有 02、03 两套
亮暗齐全的取值表，可直接落地。

- **已选定两套自有风格一起做**：02「纸与墨（暖）」（官网 `res/style.css` 色板移植）和
  03「素笺（冷）」。因为确定不止一套，**代码从一开始就要按 N 套设计**，任何
  `if (isPaper)` 式的二元判断都是错的——加第三套时应该只增加一组常量。
- 每套色板落地前要验证对比度（WCAG AA），手工色板没有 M3 tonal palette 那样的算法保证。
- **字体：已定，第一版不做。** 只做颜色。调研实测（拉 `google/fonts` 仓库真实文件
  大小）：Noto Serif SC 可变字重 **24.0 MiB**、ZCOOL XiaoWei **6.0 MiB**、Long Cang
  **4.9 MiB**，全量约 35MB；子集化到 3500 常用字后 Noto Serif SC 约 2.5MB，但
  `--tree-shake-icons` 对正文字体无效，只能用 `fonttools pyftsubset` 做外部构建步骤、
  产物二进制签入仓库，文案一改就要重跑并重新提交。收益不抵成本，推迟。
- **默认值：已定，默认纸墨、设置里可切回 Material。** 意味着需要处理一次老用户升级后
  外观变化的默认值迁移。

### 实施纪律（从 Komi Store 源码核实出来的教训）

参考项目 `github.com/kurikomi-labs/komi-store`（Kotlin/Compose）有 **90 处
`is MangaPersonality` 分支散布在 150 个文件**，组件内部双份渲染逻辑。

> **绝不在 widget 里写 `if (isPaperTheme) ... else ...`。** 品牌差异全部通过
> `ThemeData` / `ThemeExtension` 的令牌值表达。

两条技术硬约束：

1. `ThemeData.lerp` 只对**两侧都注册了的** ThemeExtension 类型做插值，只在一侧存在的会
   瞬间蹦出/消失。所以 paper 不能自己发明一批 material 没有的扩展类型，只能同类型不同取值。
2. `TextStyle.lerp` 里 `fontFamily` 是 `t < 0.5 ? a : b` 的离散切换，切换动画播到一半
   字体会瞬间跳变、文字重排。风格切换建议用 `Duration.zero` 瞬切。
3. 现有 `createLightThemeData()` / `createDarkThemeData()`（`app_theme.dart:488-848`）是
   FlexColorScheme 强绑定的，paper 分支需要在方法顶部做一次 if 分叉、绕开 FlexColorScheme
   直接手搭 `ThemeData`。

## 四、接手时必须知道的坑

- **年度报告已废弃**（用户 2026-07-30 确认）。`annual_report_page.dart` 等仍有 13 处
  Tailwind 硬编码色和模板化统计卡，**但不要改，产品上已放弃**。
- **测试极慢**：这台机器上 `flutter test` 编译阶段可能 5 分钟无任何输出。不要以为卡死就
  中断。`test/widget/` 全量基线是 **144 个用例全部通过**，`flutter analyze` 基线是
  **4 个 info**（`add_note_dialog_parts.dart` 的 cacheExtent、test/ 下 1 个 cacheExtent、
  test/ 下 2 个 doc comment）。
- **仓库是公开的**：commit message 只描述改动本身，不要写自我纠正的旁注或内部工作流噪音。
- **用户会并行提交**：多次出现用户在同一时间段自己 commit / 切分支的情况。提交前务必
  `git status` 确认，只用 `git commit --only <明确路径>`，禁止 `git add .`。
- **斜体有例外**：富文本斜体（`quote_content_widget.dart` 判断 `attributes['italic']`）和
  PDF 导出（`pdf_export_service.dart`、`delta_to_pdf_parser.dart`）必须保留，那是在忠实
  呈现用户内容。详见 AGENTS.md「UI 硬性约束」。
- **死代码扫描容易两头出错**：只查跨文件引用会漏掉同文件内使用（`ProgressiveSystemLicensesPage`
  就是这样被误判过）；只查 `ClassName(` 又会被同名方法干扰（`_buildInsightsPage()`）。
  两种都要查，并逐个人工确认。
- **`part of` 文件加不了 import**：`smart_push_settings_page_*_sections.dart`、
  `note_list/*.dart`、`note_editor/*.dart` 都是 part 文件，需要的 import 要加在库主文件
  （`smart_push_settings_page.dart` / `note_list_view.dart` / `note_full_editor_page.dart`）。

## 五、圆角判定规则（后续新增 UI 沿用）

主题令牌在 `lib/theme/app_theme.dart:138-141`，已通过 FlexColorScheme 的 `subThemesData`
接到 `cardTheme` / `dialogTheme` / `inputDecorationTheme` / 各 buttonTheme：

```dart
AppTheme.cardRadius   = 18
AppTheme.dialogRadius = 24
AppTheme.buttonRadius = 12
AppTheme.inputRadius  = 12
```

优先级：**能删就删**（`Card.shape`、`XxxButton.styleFrom(shape:)` 直接删掉继承主题）→
删不掉（有自定义 `side` / `borderSide`，或是裸 `BoxDecoration`）就写
`BorderRadius.circular(AppTheme.xxxRadius)`。**输入框例外，见上文，必须保留显式
`OutlineInputBorder`。**

**改**：`Card` 的 shape；作为卡片用的 `Container`+`BoxDecoration`（判据：**有 `boxShadow`
或 `border`，且内含整块内容**）；`Dialog`/`BottomSheet` 形状；输入框 border；按钮
`styleFrom(shape:)`；包裹整张卡片的 `InkWell`/`ClipRRect`（取和卡片相同的值）。

**不改**：Chip/标签/徽章（padding 水平 ≤10 或垂直 ≤6）；进度条、分段条、滑块轨道；
头像、缩略图、图片圆角；只裹一个 `Icon` 的背景容器；写死宽高 < 40 的装饰容器；
`circular(999)` 胶囊；分享卡片与 PDF/图片导出的构图代码（那是渲染产物不是应用 UI）；
`PopupMenuButton`/`DropdownButton`；Markdown 的 codeblock/blockquote 装饰。

拿不准就不改并记录下来——宁可漏改，不可错改。
