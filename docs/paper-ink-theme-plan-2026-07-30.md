# 纸墨主题（Paper & Ink）落地计划

> 状态：**待决策，尚未实现**。本文档描述的功能全部属于路线图，不代表当前行为。
> 创建于 2026-07-30。

## 为什么做这件事

2026-07-30 的全项目 UI 审查得出一个结论：心迹**不是没有视觉特色，而是特色没进 App**。

项目官网 `res/style.css` 里有一套完整、语义化命名、亮暗双档齐备的设计系统：

```css
--paper-white: #fefdfb    --ink-dark:   #2c2416
--paper-cream: #f9f6f0    --ink-medium: #5a4a3a
--paper-yellow:#fff9e6    --ink-light:  #8b7355
--paper-pink:  #fff0f5
--paper-blue:  #f0f8ff    --line-color: #d4c5b9   /* 笔记本横线的颜色 */
--paper-green: #f0fff4
--accent-brown:#a67c52  --accent-orange:#d4895b  --accent-blue:#5d94b8
--accent-green:#7ca982  --accent-red:   #c66b6b
```

字体：`ZCOOL XiaoWei`（站酷小薇）、`Long Cang`（龙藏手写）、`Noto Serif SC`、`Caveat`。

而 App 里是 `seedColor: Colors.blue`（`lib/theme/app_theme.dart:224`、`:249`）加系统默认字体，
没有任何自定义字体资源（`pubspec.yaml` 无 `fonts:` 段，`assets/` 下无 ttf/otf）。用户在官网
看到「纸与墨」的文人笔记本，下载打开看到的是 Flutter 教程蓝。

## 目标形态

加一个**主题风格维度**，两条路径平等设计（而不是「品牌主题是给标准主题打补丁」）：

| 风格 | 内容 |
| --- | --- |
| `ThemeStyle.material` | 现有逻辑**一行不改**：真动态取色（`dynamic_color` + `DynamicColorBuilder`）、自定义 seed、FlexColorScheme |
| `ThemeStyle.paper` | 纸墨：上表色板移植 + 中文书法字体，形状与字重也相应调整 |

## 参考对象与它的教训

参考 Komi Store（`github.com/kurikomi-labs/komi-store`，Kotlin Multiplatform + Compose）。
它用 `sealed interface Personality` 定义六个槽位（colors / type / shape / shadow / motion /
decor），两个独立 data class 各自填满，通过 CompositionLocal 下发。

**值得学**：把形状、阴影、字重、装饰开关都做成主题令牌，而不是散落在 widget 里的魔法数字。

**必须避开的坑**（已在其源码中核实）：
1. **组件级分叉**：它有 **90 处 `is MangaPersonality` / `is ClassicPersonality` 分支，散布在
   150 个文件里**。`KomiButton` 内部直接分流到两套完全独立的渲染实现（`MangaButton` 手绘
   边框+硬阴影，`ClassicButton` 薄封装 Material3），`KomiSegmented` / `KomiIconButton` /
   `KomiFab` 同理。每加一个组件、修一个交互 bug 都要改两遍。
2. **它的「标准 Material」是假的**：全仓库 grep `dynamicLightColorScheme` / `DynamicColors` /
   `wallpaper` 零命中，Classic 只是手工调的 5 个强调色查表，字体还换成了 Geist。
   **心迹已经有真动态取色，这一点比它强，不能为了模仿而降级。**

## 实施纪律（最重要的一条）

> **绝不在 widget 里写 `if (isPaperTheme) ... else ...`。**

品牌差异全部通过令牌值表达 —— 圆角、字重、阴影、颜色都是数值可调的。心迹有条件做到这
一点，因为纸墨和 M3 在**结构**上是兼容的（都是卡片列表 + 设置项），不像 Manga 那样需要
方角 + 硬阴影 + 网点纸的整体视觉改造。

唯一允许破例的是「没法用令牌表达的视觉隐喻」（纸张横线纹理），且必须限制在 1–2 处
（每日一言卡、笔记卡背景），不许铺开。任何新增的 `is PaperStyle` 分支都要在评审时说明
为什么令牌无法表达。

## 技术方案骨架

- `ThemeStyle` 枚举存进 `SettingsService`，和现有的 `useDynamicColor` / `customColor` 并列
- `PaperInkTokens extends ThemeExtension<PaperInkTokens>`：承载 paper 四级、ink 三级、
  line、五个低饱和 accent。和已有的 `AppSemanticColors`（`lib/theme/app_semantic_colors.dart`）
  并列注册进 `ThemeData.extensions`
- 形状和字体差异走 `ThemeData` 本身（`cardTheme`、`textTheme`、`AppTheme.cardRadius`），
  不新增机制
- `AppTheme` 现有的 `_cachedLightThemeData` / `_cachedDarkThemeData` 缓存要按 style 维度
  扩展成 2×2，否则切换风格后拿到旧缓存

## 待决策事项（阻塞实施）

### 1. 中文字体体积 — 需要产品拍板

`Noto Serif SC` 完整版 10MB+，`ZCOOL XiaoWei` 3–5MB。全量打进 APK 会显著增大包体，
影响下载转化。

倾向方案：只给标题和引文用书法字体 + 子集化到常用 3500 字，正文继续用系统字体，增量
压到 1–2MB。**具体体积数字和 Flutter 侧子集化工作流待调研结论补充**（`--tree-shake-icons`
对字体无效，需要 `fonttools pyftsubset` 一类的外部流程）。

### 2. 纸墨是默认还是可选 — 需要产品拍板

- 做成可选（默认仍 M3 动态取色）：风险最低，但大部分用户不会去设置里翻，特色等于白做
- 做成默认（设置里可切回 Material）：真正解决「没特点」，但会盖掉系统取色，部分用户会不适应

审查时的倾向是**默认纸墨、可切回 Material**，因为「没特色」正是要解决的问题。未定。

### 3. 切换时的视觉过渡

切换整个 `ThemeData`（含 `fontFamily` 变化）时，颜色通常能靠隐式动画平滑，但字体和形状
突变基本无法优雅过渡，体感是「啪」一下变了。Komi Store 没有处理这个。是否接受、或者
是否需要额外设计过渡，待定。

## 不在本计划范围内

- **年度报告页**（`annual_report_page.dart` 等）：产品上已放弃，虽然它是 Tailwind 配色和
  模板化统计卡的重灾区（仍有 13 处硬编码 Tailwind 色），但不投入改造。
- 官网 `res/` 下的任何文件：官网的设计系统是本项目质量最高的视觉资产，该做的是让 App
  追上它，不是改它。

## 前置工作（已完成）

- `lib/theme/app_semantic_colors.dart`：`ThemeExtension` 承载 M3 缺失的 success / warning，
  纸墨令牌可以沿用同一套模式（commit `a56158ab`）
- `AGENTS.md`「UI 硬性约束」：禁 Material 命名色、Tailwind 色板、中文斜体、手写 SnackBar、
  手写 `circular(N)`，为品牌主题清出了干净的地基（commit `a56158ab`）
- 手写 SnackBar 统一到 `AppSnackBar`，硬编码状态色 46 → 0（commit `f3ffa8cb`）
- 周年纪念卡改用 `tertiaryContainer`，清掉 11 处 Tailwind 硬编码色
