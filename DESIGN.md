---
version: alpha
name: 心迹 ThoughtEcho
description: >-
  本地优先的笔记应用。视觉主张是「纸与墨」——观感靠色温、行高和发丝边框这些
  排版层面的选择建立，不靠拟物纹理、投影堆叠或渐变装饰。
omitted:
  - section: colors
    reason: >-
      主题风格是和亮暗并列的第三个维度，共三套。下面的 colors 是特色品牌风格
      paper（纸与墨）的亮色取值，仅作代表。plain（素笺）另有一套手工色板；
      material 风格的颜色由 Material You 动态取色在运行时生成，不存在固定色值。
      全部取值的唯一真源是 lib/theme/theme_style.dart 的 ThemeStylePalette。
  - section: spacing
    reason: >-
      项目沿用 Material 3 的 4dp 网格，未定义独立的具名间距标度。
      取值规则见下方 Layout 一节。

colors:
  background: "#F9F6F0"
  card: "#FEFDFB"
  ink: "#2C2416"
  inkMuted: "#6B5842"
  outline: "#E3D9CC"
  outlineStrong: "#D4C5B9"
  accent: "#8A6440"
  onAccent: "#FEFDFB"
  accentContainer: "#EFE4D6"
  onAccentContainer: "#4A3722"
  secondary: "#9C5F35"
  tertiary: "#4F7355"
  danger: "#9B3B3B"
  onDanger: "#FEFDFB"

typography:
  # 正文字号 = 16 × readingFontScale。衬线风格 1.0625 → 17，material 1 → 16。
  # 标题同乘同一个系数：titleMedium 16 → 17，字重比正文高一档（w600 对 w500）。
  # label* 不在此表：它永远是系统黑体、永远不缩放，见 Typography 一节。
  body:
    fontFamily: serif
    fontSize: 17px
    fontWeight: 500
    lineHeight: 1.75
  bodyMaterial:
    fontFamily: system-ui
    fontSize: 16px
    fontWeight: 350   # Android 减重后的取值；其余平台是 M3 原生 400
    lineHeight: 1.5
  bodyPlain:
    fontFamily: serif
    fontSize: 17px
    fontWeight: 500
    lineHeight: 1.6

rounded:
  card: 6px
  dialog: 8px
  button: 4px
  input: 4px
  fab: 6px

components:
  card:
    background: "{colors.card}"
    borderColor: "{colors.outline}"
    borderWidth: 1px
    radius: "{rounded.card}"
    shadowOpacity: 0.03
  paperRule:
    color: "{colors.outline}"
    opacity: 0.55
    spacing: 28px
  button:
    radius: "{rounded.button}"
    background: "{colors.accent}"
    foreground: "{colors.onAccent}"
  input:
    radius: "{rounded.input}"
    borderColor: "{colors.outline}"
---

# 心迹 ThoughtEcho 设计语言

> **取值真源在代码里，不在这份文档里。** 上面的 token 是为了让 agent 快速拿到
> 一组具体值，真正生效的是 `lib/theme/theme_style.dart` 的常量。两者冲突时以代码
> 为准，并回来修这份文档。**禁止把这里的数值抄成 widget 里的字面量**——
> 具体禁令见 `AGENTS.md` 的「UI 硬性约束」。
>
> 项目概述、需求、技术栈、架构和路线图不在本文件，见 `docs/project-overview.md`。

## Overview

心迹是本地优先的笔记应用，核心场景是「捕捉思维火花」——用户在一天里零散地写下
短句和长文，之后回看。设计上因此偏向**长时间阅读的舒适度**，而不是首屏的视觉冲击。

品牌观感是**纸与墨**：暖白的纸、深褐的墨、发丝般的边框。纸是叠在桌上的，不是浮起来的，
所以层次靠边框而非投影。这套主张贯彻到排版层面——衬线体、放松的行高、与文字行高
严格对齐的纸张横线——而不是靠贴纸纹图片或翻页动效。

### 三套风格是一个维度，不是配色预设

主题风格与亮暗、动态取色**正交**，三选一：

| 风格 | 气质 | 色板来源 | 卡片圆角 | 层次手段 | 正文字体 | 正文字号 | 正文行高 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `material` | 系统观感 | 动态取色 / 用户 seed | 18 | 投影 | 系统默认（黑体） | 16 | 1.5 |
| `paper` 纸与墨 | 暖、温润 | 手工色板 | 6 | 发丝边框 + 极淡投影 | 系统衬线 | 17 | 1.75 |
| `plain` 素笺 | 冷、硬朗 | 手工色板 | 3 | 同上，更硬 | 系统衬线 | 17 | 1.6 |

**默认是 `material`**（`ThemeStyle.defaultStyle`）。纸与墨是心迹的品牌外观，但它不是
默认——这套主题没有迁移逻辑，换默认值意味着老用户在没做任何操作的情况下外观就变了。
品牌表达改由更新说明页（`lib/pages/release_notes_page.dart`）里的行内切换器承担：
想要的人一点就有，不想要的人什么都不用做。

架构上只有一条铁律：**品牌差异全部通过令牌取值表达，widget 里绝不写
`if (style == ThemeStyle.paper)`。** 连「用边框还是用投影」的判据都是 `borderWidth > 0`
这个取值，不是风格身份。加第四套风格 = 新增两组常量并登记，不碰构建逻辑、不碰任何 widget。

## Colors

**不存在一张全局色值表。** Material 风格的颜色由取色算法运行时生成，写死任何十六进制
色值都会与它冲突。页面取色一律走 `Theme.of(context).colorScheme`。

手工色板（`ThemeStylePalette`）按纸与墨的语汇定义角色，再映射到 `ColorScheme`：

| 角色 | 含义 | 映射到 |
| --- | --- | --- |
| `background` | 页面底色（纸） | `surface`、`surfaceContainer` |
| `card` | 卡片底色，比页面**更亮** | `surfaceContainerLowest`、`surfaceBright` |
| `ink` / `inkMuted` | 正文墨色 / 次要墨色 | `onSurface` / `onSurfaceVariant` |
| `outline` | 常规发丝边框，也是**纸张横线的颜色** | `outlineVariant` |
| `outlineStrong` | 强调边框 | `outline` |
| `accent` | 强调色 | `primary`、`surfaceTint` |

注意最后两行是**交叉映射**：色板里叫 `outline` 的角色落到 `ColorScheme.outlineVariant`，
`outlineStrong` 才是 `ColorScheme.outline`（M3 的 outline 比 outlineVariant 更重）。
画纸张横线取的是 `colorScheme.outlineVariant`。

两处刻意偏离 M3 规范，改动前先读注释：

- **卡片色不落在 M3 的 surfaceContainer 梯度上**：两套手工色板都让卡片比页面底色更亮
  （纸叠在桌面上，暗色模式同理），而 M3 暗色下期望 `surfaceContainerLowest` 最暗。
  测试校验的是「卡片比底色亮且可区分」，不是 M3 的梯度假设。
- **手工色板不能喂给 seed 生成器**：亮色路径必须按风格关掉 `keyColors` 和表面混合，
  否则 FlexColorScheme 会拿 primary 当种子把整套色调重新推导掉。

语义状态色（成功 / 警告 / 收藏）走 `AppSemanticColors` 这个 `ThemeExtension`。

**改色板必须先过 `test/theme/theme_style_contrast_test.dart`**（WCAG AA + 令牌不变量）。
原始设计稿有多处不达 AA，已按验算收紧。

## Typography

字体、行高、字重是这套主题里辨识度最高的部分，比颜色更能拉开风格差距。

- **字体走零字节路线**：手工风格的首选族名是**通用族 `serif`**，具名字体
  （Songti SC / SimSun 等）留在回退链里。**顺序不能调换**——Flutter 的
  `fontFamilyFallback` 不是 CSS 的 font-family，只有首选族名就是 `serif` 时，
  Android 才会命中 AOSP 给 NotoSerifCJK 标的 `fallbackFor="serif"`。
  代价是各家 ROM 的衬线体长相不一致；要统一只能打包子集化字体。
- **行高由 `bodyLineHeight` 令牌下发**，只作用于 `body*` 三级。中文衬线体字面率高、
  笔画密，M3 给黑体调的 1.5 偏挤。**纸张横线间距是从「正文字号 × 行高」推导的**——
  两项里写死任何一项都会让文字逐行相对横线漂移，卡片看起来像背了一张格子图。
- **衬线只给阅读文本，`label*` 永远是黑体**。按钮、胶囊、导航栏标签是 11–14sp 的
  功能性文字，中文衬线在这个尺寸下糊成一团，而它们又不承担任何风格识别。
  这是全局排版规则，不是某套风格的选择，所以写死在 `_applyStyleTypography` 里。
- **字重有两个反向的补偿，别混为一谈**：
  - `variableWeightCompensation` 是给**黑体**的**减重**，只跑在 Android——
    Impeller 精准映射 wght 轴后 Roboto 偏粗，正文压到 350 还原视觉。
    衬线体横画本就细，再减就发灰发虚，所以手工风格设 0 关掉它。
  - `titleWeightFloor` / `bodyWeightFloor` 是给**衬线体**的**加重**，所有平台生效。
    是**下限不是增量**。用户标的粗体不受下限约束，但也不是恒定的 w700——
    它按「正文字重 + 300 档」跟着正文走，见下面富文本那条。
    **两档不是重复**：构建期 M3 的字重还是 null（几何要到 build 时才补），
    共用一个下限会把 `title*` 和 `body*` 一起钉成同一个字重——六级阅读文本一样重，
    「最近对话」这种小节标题和它底下的列表正文分不出主次，整页发平。
    标题取 w600、正文取 w500，M3 原本「同字号差一档字重」的关系就还在。
    随包衬线的字重轴是连续的 400–900，600 精确落位；换随包字体之前不能这么写
    （设备的衬线体常常只有 Regular / Bold 两档，600 会被匹配成 Bold）。
- **`readingFontScale` 是可读性的兜底杠杆**。中文衬线的横画只有竖画三分之一粗，16sp
  配 2x 屏时落到半个物理像素上，抗锯齿后只剩一条浅灰线——**同样的墨色，衬线读起来
  就是比黑体虚**，跟对比度无关（色板全部在 AA 以上）。字号是唯一在所有平台、所有
  ROM 上都一定生效的补偿（字重要看设备有几档字体），手工风格取 1.0625（16 → 17）。
  上限 1.15，再高列表密度就崩了。**`title*` 必须和 `body*` 同乘**：只放大正文的话
  `bodyLarge`(17) 会比它上面一级的 `titleMedium`(16) 还大，层级是倒的。
  中日韩几何（`Typography.dense2021`）这六级的字号和英文完全一致，按 M3 英文取值
  钉下去，中文下不丢东西。
- **次要墨色比 AA 再保守一档**：四套色板在**纸和卡片两种底色上**都要达到 7:1，
  由 `theme_style_contrast_test.dart` 钉死。WCAG 只算两个色值，不看笔画多宽；
  同样 6:1 的灰落在衬线的半像素横画上，看到的反差要打对折。两种底色都要验，
  是因为次要文字大量渲染在卡片上——只按页面底色算会漏。
- **富文本是独立的一条路**：`flutter_quill` 的段落基准样式不继承 `textTheme`
  （`fontSize` / `height` 被硬写成 16 / 1.15），字号和行高都要按令牌纠正，才能和
  纯文本、横线间距对齐。纠正规则只有 `QuillThemeTypography` 一处，笔记卡片和全屏
  编辑器共用——否则同一条笔记「写的时候」和「读的时候」行距不一样。
  **用户标的加粗也走这条路，而且它不是一个绝对值**：加粗恒等于「正文实际字重
  + 300 档」（`ThemeStyleForm.emphasisWeight`，300 就是 M3 w400 正文对 w700 加粗
  的那个差）。正文两头都被动过——衬线抬到 w500、Android 黑体压到 350——加粗若
  钉死在 w700，差就变成 200 / 350：同一个「加粗」在三套风格里轻重不一，衬线下
  几乎看不出标过。跟着正文走之后，material 非 Android 算出来正好是 w700（像素
  不变），衬线是 w800。折叠预览、展开态、全屏编辑器三条路都从
  `QuillThemeTypography.boldWeight` 取同一个值。

## Layout

- 间距用 **4 的倍数**（4 / 8 / 12 / 16 / 24 / 32），沿用 M3 的 4dp 网格，
  没有独立的具名标度。
- 笔记卡片外边距：左右 12、上下 6（`QuoteItemWidget.defaultCardMarginVertical`）。
  记录页第一条的顶部间距就来自它，**不要用负 padding 去调**，会命中
  `SliverPadding` 断言。
- 视觉重点靠**留白、字号层级和单一强调色**，不靠色块和分隔线堆叠。

## Elevation & Depth

**层次二选一，由 `borderWidth` 决定**：Material 用投影，手工风格用发丝边框 +
近乎为零的投影。纸是叠在桌上的，不是浮起来的。

投影四档——`restShadow` / `lowShadow` / `raisedShadow` / `accentShadow`——由
`shadowOpacity` 和 `shadowBlur` 按固定比例推导，风格一变自动跟着压扁。
自绘表面用这四个 getter，不要引用 `AppTheme.*Shadow` 静态常量。

## Shapes

圆角令牌由 `AppShapeTokens` 这个 `ThemeExtension` 下发，widget 读
`AppShapeTokens.of(context).cardRadius`：

- 五档：`cardRadius` / `dialogRadius` / `buttonRadius` / `inputRadius` / `fabRadius`。
  FAB 单独一档**不是遗漏**——M3 里 FAB 圆角本就独立于卡片和按钮。
- `AppTheme.cardRadius` 那组 `static const` 是 material 的取值，**不随风格变化**，
  只为老代码保留，新代码不要引用。
- `AppShapeTokens.of(context)` 是方法调用，**不能出现在 `const` 表达式里**。
  遇到 `const RoundedRectangleBorder(...)` 是去掉 `const`，不是退回静态常量。

**纸张横线**是这套设计里唯一的纹理破例（令牌表达不了纹理本身），但「画不画、多密、
多淡」仍是令牌取值：`ruleSpacing` 为 0 就不插入任何绘制层。只用在笔记卡片和每日一言卡
两处，不要铺开。**素笺刻意不画横线**——「素」就是素的。

## Components

**一律优先复用现成组件**，不要另搓一套——同屏时圆角和高光会对不齐。

- **笔记卡片**：`Card`（已配好 `cardTheme`），不要用 `Container` + `BoxDecoration` 重搓。
  圆角随风格（18 / 6 / 3），展开折叠 170ms、淡入 130ms。卡片增删动画的不变量锁在
  `test/widget/note_item_motion_test.dart`——反复复发的问题是「包装层进出树 +
  `Align` 放松宽度约束」，不是曲线时长。
- **按钮**：主按钮填充、次按钮轮廓、文本按钮无背景；圆角读 `buttonRadius`。
- **输入框**：M3 轮廓输入框 + 浮动标签，圆角读 `inputRadius`。
  **`OutlineInputBorder` 不能删**——项目未设置 `inputDecoratorBorderType`，
  FlexColorScheme 该参数默认是 `underline`，删掉会把描边输入框变成下划线输入框。
- **反馈与状态**：`AppSnackBar.info/success/error/warning`、`AppLoadingView`、
  `AppEmptyView`、`AppErrorView`。不要手写 `ScaffoldMessenger` 或裸
  `CircularProgressIndicator`。

## Do's and Don'ts

**Do**

- 颜色走 `Theme.of(context).colorScheme`，语义状态色走 `AppSemanticColors`。
- 圆角走 `AppShapeTokens.of(context)`，投影走它的四个 shadow getter。
- 字号走 `theme.textTheme.*`，需要微调用 `.copyWith()`。
- 新增风格差异时，先问「这能不能表达成一个令牌取值」。

**Don't**

- ❌ `Colors.red` / `grey` / `white` 等 Material 命名色，以及 Tailwind 色板
  （`#3B82F6` 一类）。它们不随动态取色变化，换主题色后会突兀。
- ❌ 手写 `BorderRadius.circular(N)` 造卡片 / 按钮 / 输入框。
- ❌ 写死正文 `height` 或 `fontWeight` 来「调得好看点」——会盖掉令牌，
  并让文字与纸张横线错位。
- ❌ `fontStyle: FontStyle.italic` 用作 **UI 装饰**。中文字体没有真斜体字形，
  Flutter 会做合成倾斜，小字号下明显发虚。要弱化层次用 `onSurfaceVariant` +
  字号或字重差。**例外**：用户在编辑器里手动标记的斜体、PDF 导出还原用户格式，
  那是在忠实呈现内容，不是 UI 自己的装饰选择。
- ❌ 渐变背景、多层 `RadialGradient` 光晕、「大数字 + 小标签 + 渐变强调色」的统计卡。
  这是 AI 生成设计的通用模板，与本项目气质无关。

### 已否决的方向

不要重新提案，除非有新的理由：

- **便签纸色**（按标签给卡片自动上色）——与用户已有的单条笔记手动配色
  （`quote.colorHex`）打架。
- **打包字体**——目前走零字节路线；真机观察到各 ROM 差异不可接受时才启用，
  方案（Noto Serif SC 可变字体子集，保留 wght 轴）已写在交接文档里。
- **年度报告**——产品上已废弃，相关页面不要再改。

> 主题相关的完整设计推导、色板沿革和踩过的坑见
> `docs/paper-ink-theme-handoff-2026-07-31.md`，那是**唯一事实来源**，动主题前先读。
