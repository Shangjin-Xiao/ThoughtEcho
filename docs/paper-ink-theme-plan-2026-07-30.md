# 纸墨主题（Paper & Ink）落地计划

> **本文档现在是设计参考**：保留最初的推导、色板沿革、以及参考项目的教训。
> **当前状态和下一步以 `docs/paper-ink-theme-handoff-2026-07-31.md` 为准**，
> 两者冲突时看那一份。
> 创建于 2026-07-30，2026-07-31 更新。

## 当前进度（2026-07-31）

已实现：

- `lib/theme/theme_style.dart`：`ThemeStyle` 枚举（material / paper / plain）+
  `ThemeStylePalette` 手工色板 + 到 `ColorScheme` 的映射。加第四套只需新增一组常量并在
  `ThemeStyle.palette` 里登记，构建逻辑和 widget 都不用碰。
- `AppTheme`：`themeStyle` 读写 + 持久化（key `theme_style`）+ 切换时清主题缓存。
  `lightColorScheme` / `darkColorScheme` 在手工色板下直接返回色板值。
- 亮色构建路径按风格关掉 `keyColors` 和表面混合（暗色路径原本就是关的），
  否则 FlexColorScheme 会拿色板的 primary 当种子把整套色调重新推导掉。
- 设置 → 主题设置：顶部新增「主题风格」三选一，带真实色板预览；选中手工色板时
  自动隐藏「自定义主题色」和「动态取色」两张卡（它们只对 material 生效）。
- `test/theme/theme_style_contrast_test.dart`：把 WCAG AA 钉成测试，21 个用例。

### 第二步：形状、字体、阴影（2026-07-31）

**只做颜色的真机观感是「换了一套 Material 主题色」**（用户装机反馈）。这是可以预见的：
辨识度主要由形状、字体、纹理承担，颜色是四个维度里最弱的一个。第二步补上其中三样。

- `ThemeStyleForm`：每种风格的圆角、描边宽度、阴影不透明度与模糊、字体族。
  material 保持现状取值，改动前后行为一致。
- 纸墨 `cardRadius` 6、素笺 3（Material 是 18）；按钮和输入框相应收到 4 / 2。
  纸不该有 18 圆角，这一条比颜色更能拉开差距。
- 手工风格改用**发丝边框 + 近乎零投影**做层次，而不是 Material 的浮起感
  （`_styleCardTheme`）。判据是 `borderWidth > 0` 这个取值，不是风格身份。
- **字体：指向系统自带的中文衬线体，增量 0 字节。**
  `Songti SC` → `STSong` → `Noto Serif CJK SC` → … → `serif`，命中不了就逐级回退。
  这是原计划漏掉的第三个选项：此前只在「全量 35MB」和「引入 pyftsubset 构建流程」
  之间二选一，结论是都不划算，于是整项推迟。实际上不打包也能拿到衬线观感。
- `AppShapeTokens extends ThemeExtension`：把形状令牌下发给自绘表面的 widget。
  `AppTheme.cardRadius` 那组 `static const` 是 material 取值、无法随风格变化，
  自绘卡片要改读 `AppShapeTokens.of(context).cardRadius`。

### 第三步：圆角长尾迁移完毕（2026-07-31）

`AppTheme.*Radius` 全项目原有 167 处，已全部迁到
`AppShapeTokens.of(context).*Radius`，只剩年度报告相关的 9 处（产品已废弃，不动）。
顺带清掉 34 个因此变得多余的 `app_theme.dart` import。

同轮修掉三条审查意见：`elevatedButtonRadius` 漏配（`ElevatedButton` 会保持 M3
胶囊形状不跟随风格）、初始化失败分支漏重置 `_themeStyle`（会留下半新半旧的主题状态）、
风格选项缺 `inMutuallyExclusiveGroup`（屏幕阅读器读成三个独立按钮）。

**下一步和遗留问题见 `docs/paper-ink-theme-handoff-2026-07-31.md`。**

### 实现中发现的、与本文档原计划不同的地方

1. **不需要「绕开 FlexColorScheme 手搭 ThemeData」**。原计划（见交接文档）以为要在
   `createLightThemeData` 顶部做 if 分叉。实际上整条构建管线都汇聚在
   `lightColorScheme` / `darkColorScheme` 两个 getter 上，手工色板只要产出 `ColorScheme`
   就能复用现有全部 subThemes 和 copyWith，**一个 widget 都不用改**。分叉只剩
   `keyColors` / `blendLevel` 两个参数，而且是由风格令牌驱动的，不是二元判断。
2. **缓存不需要扩成 2×2**。`_clearThemeCache()` 在切换风格时清掉即可，效果等价且更简单。
3. **色板取值按对比度验算做了收紧**。原表是按视觉调的、未验算，实测有几对不过 WCAG AA：
   - 纸墨亮色：次要墨色 `#8b7355` → `#6b5842`，强调 `#a67c52` → `#8a6440`
     （原值配 `#fefdfb` 的白字只有 3.1:1）
   - 素笺亮色：次要墨色 `#71757a` → `#5f6368`
   - 两套的 `danger` 系列是新配的：原表只有一个 `--accent-red #c66b6b`，
     饱和度不足以承载 onError 的白字。
4. **卡片色刻意不落在 M3 的 surfaceContainer 梯度上**。两套色板都让卡片比页面底色更亮
   （「纸叠在桌面上」，暗色模式同理），而 M3 暗色下期望 `surfaceContainerLowest` 最暗。
   App 把 `cardTheme` 绑在 `surfaceContainerLowest` 上，所以这一档必须是卡片色。
   测试里校验的是「卡片比底色亮且可区分」，而不是 M3 的梯度假设。

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

加一个**主题风格维度**，各条路径平等设计（而不是「品牌主题是给标准主题打补丁」）：

| 风格 | 状态 | 内容 |
| --- | --- | --- |
| `ThemeStyle.material` | 保持 | 现有逻辑**一行不改**：真动态取色（`dynamic_color` + `DynamicColorBuilder`）、自定义 seed、FlexColorScheme |
| `ThemeStyle.paper` | 首批实现 | 纸与墨（暖）：官网色板移植 |
| `ThemeStyle.plain` | 首批实现 | 素笺（冷）：冷灰纸、蓝黑墨、深青灰强调 |

> **架构要求：从第一天就按 N 套设计，不要写成二元判断。**
> 已确定至少有两套自有风格（暖、冷），所以任何
> `if (isPaper) ... else ...` 或 `style == paper ? A : B` 的写法从一开始就是错的。
> 正确形态是「风格枚举 → 一组令牌常量 → 同一套构建逻辑」，加第三、第四套时只增加一组
> 常量，不碰构建逻辑，更不碰任何 widget。

### 两套自有风格的色板

亮暗都给全。02 来自官网 `res/style.css`，03 是为避开暖调而专门配的。

> **下表已更新为实际落地值，唯一事实来源是 `lib/theme/theme_style.dart`。**
> 标 ⚑ 的行是相对原始设计稿收紧过的——原稿按视觉调、未验算对比度，实测不足
> WCAG AA。原值记在本节末尾，改回去要先过 `test/theme/theme_style_contrast_test.dart`。

**02 · 纸与墨（暖）**

| 角色 | 亮色 | 暗色 |
| --- | --- | --- |
| 背景 | `#f9f6f0` | `#2a2520` |
| 卡片 | `#fefdfb` | `#342e28` |
| 描边 | `#e3d9cc` | `#4a4037` |
| 描边（强） | `#d4c5b9` | `#5d5147` |
| 正文墨色 | `#2c2416` | `#e8dfd5` |
| 次要墨色 ⚑ | `#6b5842` | `#b8a99a` |
| 强调 ⚑ | `#8a6440` | `#c9a077` |
| 强调上的文字 | `#fefdfb` | `#2a2520` |
| 强调容器 | `#efe4d6` | `#423931` |
| 强调容器上的文字 ⚑ | `#4a3722` | `#e0c9ae` |
| 辅助色 2 / 3 ⚑ | `#9c5f35` / `#4f7355` | `#d4895b` / `#7ca982` |
| 危险 / 其上文字 ⚑ | `#9b3b3b` / `#fefdfb` | `#e49595` / `#2a2520` |
| 危险容器 / 其上文字 ⚑ | `#f5dcdc` / `#5b1f1f` | `#4e2c2c` / `#f2c7c7` |

官网另有四种便签纸色（`--paper-yellow #fff9e6`、`--paper-pink #fff0f5`、
`--paper-blue #f0f8ff`、`--paper-green #f0fff4`），App 完全没用上。可以考虑按标签给笔记
卡片上不同纸色——那才是「纸」的感觉。

**03 · 素笺（冷）**

| 角色 | 亮色 | 暗色 |
| --- | --- | --- |
| 背景 | `#f4f4f2` | `#17191a` |
| 卡片 | `#fbfbfa` | `#1f2224` |
| 描边 | `#dcdcd8` | `#313436` |
| 描边（强） | `#c4c4bf` | `#454a4d` |
| 正文墨色 | `#1f2124` | `#e6e7e8` |
| 次要墨色 ⚑ | `#5f6368` | `#9da2a7` |
| 强调 | `#3f5d5b` | `#8fb5b0` |
| 强调上的文字 | `#fbfbfa` | `#17191a` |
| 强调容器 | `#e3eae9` | `#26302f` |
| 强调容器上的文字 ⚑ | `#233937` | `#b3d1cd` |
| 辅助色 2 / 3 ⚑ | `#56646f` / `#6b664f` | `#9aa8b4` / `#b0a98f` |
| 危险 / 其上文字 ⚑ | `#8f3a3a` / `#fbfbfa` | `#e09a9a` / `#17191a` |
| 危险容器 / 其上文字 ⚑ | `#f2dddd` / `#541e1e` | `#452626` / `#f0c9c9` |

⚑ 各行的原始设计稿取值（未达 WCAG AA，仅作沿革记录）：纸墨亮色次要墨色 `#8b7355`、
强调 `#a67c52`、强调容器上的文字 `#6b4f32`、辅助色 `#d4895b` / `#7ca982`；素笺亮色
次要墨色 `#71757a`、强调容器上的文字 `#2c4442`、辅助色 `#6e7d8a` / `#8a8471`；
素笺暗色次要墨色 `#90959a`。危险色系列原稿只有一个 `--accent-red #c66b6b`，
饱和度撑不住 onError 的白字，两套的四个危险色槽位都是新配的。

**每套色板落地前必须验证对比度**：正文墨色 / 背景、次要墨色 / 背景、强调上的文字 / 强调，
至少满足 WCAG AA（正文 4.5:1，大字 3:1）。这一条现在由
`test/theme/theme_style_contrast_test.dart` 自动把关。参考项目
Komi Store 专门写了一个 `ColorContrast.kt` 来做这件事，说明这是手工色板绕不开的坑——
不像 M3 的 tonal palette 有算法保证。

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

### 2. 哪一套做默认 — 需要产品拍板

现在有三个候选（material / paper 暖 / plain 冷）：

- 默认 Material：风险最低，但大部分用户不会去设置里翻，特色等于白做
- 默认某一套自有风格：真正解决「没特点」，但会盖掉系统动态取色，部分用户会不适应

审查时的倾向是**默认一套自有风格、设置里可切回 Material**，因为「没特色」正是要解决的
问题。选暖还是冷做默认也未定——暖的好处是和官网一致，冷的好处是不撞 AI 生成设计的
常见面孔（见下）。

> 关于 02 暖调的一个提醒：「暖米白底 + 衬线 + 陶土橙」正好是当前 AI 生成设计最常见的
> 三种面孔之一。官网那套色板本身质量很高、命名语义完整，但它确实落在这个聚类里。
> 03 冷调就是为了给出一个不撞这条的选择。两套都做，默认选哪个是产品判断。

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
