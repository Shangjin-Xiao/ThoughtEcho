# UI 清理工作交接（2026-07-31）

> 承接 2026-07-30 的全项目 UI 审查。本文档记录已完成、未完成、以及接手时必须知道的坑。
> 主分支：`main`（所有已完成工作都已推送到 `origin/main`）。

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

### 1. 圆角收敛（零进度，优先级最高）

**状态：完全没有开始**，五个批次的子代理都在写入文件前撞上 session limit。

问题：`lib/theme/app_theme.dart:138-141` 定义了 `cardRadius=18` / `dialogRadius=24` /
`buttonRadius=12` / `inputRadius=12`，但页面里手写了 13 种 `BorderRadius.circular(N)`
（2/4/6/7/8/10/12/14/16/18/20/21/24/28/30/999），最常用的是 12 和 16，**几乎没有一处用
主题值**。记录页一屏内就有 10/12/14/16/20/24 六种圆角。

改的边界（这条很重要，放宽了会把小徽章也改成 18 圆角）：

- **改**：`Card` 的 `shape`（优先直接删掉让它继承 `cardTheme`）、作为卡片用的
  `Container`+`BoxDecoration`（判据：有 `boxShadow` 或 `border` 且内含整块内容）、
  `Dialog`/`BottomSheet` 形状、输入框 border、按钮 `styleFrom(shape:)`、包裹整张卡片的
  `InkWell`/`ClipRRect`
- **不改**：Chip / 标签 / 徽章（padding 水平 ≤10、垂直 ≤6）、进度条和分段条、头像和
  缩略图、图标背景小圆、任何宽高 < 40 的装饰容器
- `circular(999)` / `circular(30)` 想做胶囊的 → 按钮/Chip 换 `const StadiumBorder()`

**不要动** `annual_report_page.dart`、`ai_annual_report_webview.dart`、`lib/pages/ai_report/`
（年度报告已废弃，见下）。

### 2. 第二批死代码（已核实零引用，未删）

| 类 | 文件 | 行数 |
| --- | --- | --- |
| `InsightsPage` | `lib/pages/insights_page.dart` | 1239 |
| `TagSettingsPage` | `lib/pages/tag_settings_page.dart` | 995 |
| `MediaManagementPage` | `lib/pages/media_management_page.dart` | 390 |

共 2624 行。核实方式：全项目（含 `test/`）grep 类名和文件名，零引用点。

- `InsightsPage`：无人 `import 'insights_page.dart'`。洞察功能现在走
  `home_page.dart:978` 的 `AIFeaturesPage` → `AIPeriodicReportPage`，这个页面是被替换后
  的遗留。注意 `annual_report_page.dart` 里有个**恰好同名**的方法 `_buildInsightsPage()`，
  搜索时容易误判为引用。
- `TagSettingsPage`：设置页那个「标签」入口（`settings_page.dart:660`，标题是
  `l10n.settingsTags`）打开的其实是 `CategorySettingsPage` —— UI 上早就改叫标签，代码里
  还是 category 的旧命名。`TagSettingsPage` 是更早的遗留。
- `MediaManagementPage`：零入口。

**删之前务必重新 grep 确认**，不要直接信本文档——距离写下这些已经过了一段时间。

### 3. 空态（结论已修正，优先级低）

**之前的判断是错的，不要照做。** 曾认为「标签页/分类页/媒体页缺空态」，实际上：

- 数据库有 6 个系统默认标签（`database_service.dart:61-66` 的
  `defaultCategoryIdHitokoto/Anime/Comic/Game/Novel/Original`），标签页不会空
- 媒体页是死代码，不用管

真正值得做的空态还需要重新调研，不要基于旧结论动手。

### 4. 加载态统一（已降级，不建议做）

曾把「51 处裸 `CircularProgressIndicator`」当成待修复量报告，**这个数字是误导性的**：
其中 36 处带 `strokeWidth`，是按钮内/图标内的小 spinner，属于正确用法。真正的整页加载态
只有约 15 处，去掉年度报告相关的还剩 12 处左右。

而且 `AppLoadingView` 默认是 80px 的 Lottie 动画，页面若加载很快（本地 SQLite 通常几十
毫秒），大动画闪一下就消失，比朴素 spinner 更晃眼。**收益可疑，建议不做。**

## 三、主题工作的决策状态

详见 `docs/paper-ink-theme-plan-2026-07-30.md`。

- **已选定方案 02「纸与墨（暖）」**：色板从官网 `res/style.css` 的 `--paper-*` /
  `--ink-*` / `--line-color` / `--accent-*` 移植。方案对比页曾发布为 Artifact 供选择。
- **待决策一：字体。** 调研实测（拉 `google/fonts` 仓库真实文件大小）：
  Noto Serif SC 可变字重 **24.0 MiB**、ZCOOL XiaoWei **6.0 MiB**、Long Cang **4.9 MiB**，
  全量约 35MB。子集化到 3500 常用字后 Noto Serif SC 约 2.5MB。Flutter 的
  `--tree-shake-icons` 对正文字体无效，只能用 `fonttools pyftsubset` 做外部构建步骤，
  产物二进制签入仓库——意味着**文案一改就要重跑并重新提交**。
  **当前建议：第一版只做颜色，不动字体。**
- **待决策二：纸墨是默认还是可选。** 倾向默认纸墨、设置里可切回 Material。未定。

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
  中断。`test/widget/` 全量基线是 **143 个用例全部通过**，`flutter analyze` 基线是
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
