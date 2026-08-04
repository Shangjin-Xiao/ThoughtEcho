# 纸墨主题工作交接（2026-07-31）

> 本文档是**当前状态与下一步的唯一事实来源**。
> 配套文档 `docs/paper-ink-theme-plan-2026-07-30.md` 保留设计推导与色板沿革，
> 两者冲突时以本文档为准。

## 一、现在是什么状态

主题风格已经是和亮暗、动态取色并列的一个维度，三选一：

| 风格 | 色板 | 卡片圆角 | 层次 | 正文字体 |
| --- | --- | --- | --- | --- |
| `material` | 系统动态取色 | 18 | 投影 | 系统默认 |
| `paper` 纸与墨（暖） | 手工 | 6 | 发丝边框，近乎无投影 | 系统衬线 |
| `plain` 素笺（冷） | 手工 | 3 | 同上，更硬朗 | 系统衬线 |

**默认仍是 `material`**，用户要去「设置 → 主题设置」顶部自己切。

关键文件：

- `lib/theme/theme_style.dart` —— `ThemeStyle` 枚举、`ThemeStylePalette`（颜色）、
  `ThemeStyleForm`（形状/字体/阴影）、`AppShapeTokens`（下发给 widget 的 ThemeExtension）
- `lib/theme/app_theme.dart` —— 持久化（key `theme_style`）、两条构建路径接令牌
- `lib/pages/theme_settings_page.dart` —— 风格三选一入口
- `test/theme/theme_style_contrast_test.dart` —— WCAG AA 与令牌不变量

### 架构：为什么没有改动任何 widget 的渲染逻辑

整条主题构建管线汇聚在 `AppTheme.lightColorScheme` / `darkColorScheme` 两个 getter。
手工色板只要产出一个 `ColorScheme`，就能复用现有全部 `subThemes` 和 `copyWith`。

> **绝不在 widget 里写 `if (style == ThemeStyle.paper)`。**
> 参考项目 Komi Store 有 90 处这种分支散在 150 个文件里，每加一个组件都要改两遍。
> 心迹的品牌差异**全部**通过令牌值表达。
> 连「用边框还是用投影」的判据都是 `form.borderWidth > 0` 这个**取值**，不是风格身份——
> 将来加一套 `borderWidth: 0` 的风格会自动走 Material 那条路，不用改代码。

**加第四套风格 = 新增一组 `ThemeStylePalette` + 一组 `ThemeStyleForm` 常量，
在 `ThemeStyle.palette` / `ThemeStyle.form` 里登记。不碰构建逻辑，不碰 widget。**

## 二、下一步（按优先级）

### 0. 字体：首选族名改成 `serif`，零字节路线成立（2026-08-02 修正）

**2026-08-01 那条「Android 上 serif 只有拉丁字形、零字节路线走不通」的结论是错的，
已推翻。** 推翻它的证据是用户的现场观察：**在富文本编辑器里选 "Serif"，中文变了衬线。**
编辑器那条路径写进 delta 的就是通用族名 `serif`（`flutter_quill` 的默认项），
渲染时直接 `fontFamily: 'serif'`（`lib/widgets/quote_content_widget.dart`）。

差别只在**首选族名的位置**：

- 原来：`fontFamily: 'Songti SC'`，`serif` 排在 `fontFamilyFallback` 末尾 → Android 中文不变
- 现在：`fontFamily: 'serif'`，具名字体（Songti SC / SimSun 等）留在回退链里 → 生效

原因是 Flutter 的 `fontFamilyFallback` 不是 CSS 的 font-family。首选族名解析不到时，
CJK 字符走的是引擎默认字体通道，回退链里排在后面的 `serif` 拿不到「这次要衬线」这个
上下文，也就命中不了 AOSP 从 Android 9 起给 `NotoSerifCJK` 标的 `fallbackFor="serif"`。
**只有首选族名就是 `serif` 时才会命中。**

iOS / macOS / Windows 的字体管理器基本不解析通用族名，会跳过 `serif` 落到后面的具名
字体上，所以这个顺序对三端都成立。取值和理由固化在 `ThemeStyleForm._systemSerifFallback`
的文档注释与 `test/theme/theme_style_contrast_test.dart`（锁「首选必须是 serif」）。

**遗留的代价：不可控。** 国内 OEM ROM 各改各的字体集，不保证都带中文衬线体，各家衬线体
长相也不一致。要做到「所有设备一个样」仍然只有打包子集化字体一条路：

- `NotoSerifSC[wght].ttf`（OFL）原始 25MB / 31058 字形，**可变字体，wght 200–900**
- `pyftsubset` 子集到 GB2312 全量 6763 汉字 + 拉丁 + 中西文标点（约 7569 字符），
  **保留 wght 轴**，一个文件覆盖全部字重（项目用了 350/450 这种非常规字重，正好需要）
- 子集外的生僻字回落系统黑体，不会出豆腐块
- 需要签入字体产物 + `OFL.txt` + 可复现的子集化脚本

**先按零字节方案观察真机效果，不满意再打包。**

### 1. 纸张横线纹理 —— 签名元素（2026-08-01 已完成）

`lib/widgets/common/paper_rule_background.dart`：`PaperRuleBackground` 包住卡片内容，
在背景上画等距横线。已接到**两处**（计划文档的上限）：

- `lib/widgets/quote_item_widget.dart` —— 笔记卡片
- `lib/widgets/sliding_card.dart` —— 每日一言卡

**开关仍然是令牌取值，不是风格身份**：`ThemeStyleForm.ruleSpacing` 为 0 时
widget 原样返回 child，**不插入任何绘制层**（记录页滚动性能敏感，每张卡多一个
CustomPaint 是实打实的开销）。取值：纸墨 26 / 0.55，material 与素笺都是 0。

**素笺故意不画横线**——「素」就是素的，同时这让两套手工风格除了颜色和圆角之外
终于有了真正的差别，也给用户留了一个「要纸感但不要横线」的选项。

坑（已在代码和测试里固化）：

- **行距不能参与 lerp**。0 → 26 插值会经过 0 附近的极小值，绘制循环次数按 1/spacing
  爆炸。`AppShapeTokens.lerp` 里行距是离散切换，淡入淡出交给 `ruleOpacity`。
- 线宽设 0 让 Canvas 画物理一像素，不随 devicePixelRatio 变粗；关抗锯齿。
- 纹理要包在有 padding 的容器**外面**，否则线会被 padding 缩进去，不满宽。
- 测试：`test/widget/paper_rule_background_test.dart`（核心断言是「没纹理的风格不多一层」）
  + `test/theme/theme_style_contrast_test.dart` 里两条令牌不变量。

### 2. 默认值翻成 `paper`

`app_theme.dart` 的 `_themeStyle = ThemeStyle.material` 改一行即可。
产品意向早已定为「默认纸墨、可切回 Material」，卡在真机验证。

**2026-08-01 用户决定：这轮先不翻。** 将来翻的时候的处理方式也定了——
不做迁移逻辑，直接用新默认值，但**要给老用户一个提示**告诉他们外观变了、可以切回去。

### 3. ~~便签纸色~~（2026-08-01 否决，不要再提）

官网那四种便签纸色（`--paper-yellow` 等）**不做**。
理由：用户本来就能给单条笔记选卡片颜色（`quote.colorHex`），
再按标签自动上纸色会和用户的手动选择打架。

### 4. 排版令牌（2026-08-04 已完成）

用户真机反馈「可读性差、缺点味道」，定位到三个互相独立的根因，一并修掉。
新增两个令牌 `ThemeStyleForm.bodyLineHeight` / `variableWeightCompensation`。

**根因一：字重补偿打在了错的字体上。** `AppTheme._fixAndroidVariableFontWeight`
把 Android 正文从 w400 压到 350，那是为**黑体**（Impeller 精准映射 wght 轴后
Roboto 变粗）做的补偿，却跑在换字体**之前**，衬线体照单全收 → 发灰发虚。
现在补偿强度是令牌：material 为 1（全额，像素不变），两套手工风格为 0
（保留 M3 原生 400）。设 0 后 Android 与 iOS/桌面（本来就不跑补偿）字重才一致。

**根因二：行高是给黑体调的。** 中文衬线字面率高、笔画密，M3 的 1.5 偏挤。
`bodyLineHeight`：material 1.5（M3 原值）、纸墨 1.75、素笺 1.6。
只作用于 `body*` 三级，`bodyLarge` 直接取值，另两级按同比例缩放 M3 默认值。

**根因三（味道）：横线和文字压根没对齐。** `ruleSpacing` 曾写死 26，而正文行高是
16×1.5=24，每往下一行文字就相对横线漂 2px，四五行后完全骑到线上——看起来是
「卡片背了一张格子图」而不是「字写在纸上」。现在 `ruleSpacing` 从
`_bodyLargeFontSize * _paperLineHeight` 推导（= 28），不允许再各写各的。
不变量固化在 `theme_style_contrast_test.dart`。

#### 富文本这条路要单独处理（重要）

**quill 的段落样式不继承 `textTheme`。** `DefaultStyles.getInstance` 的 `baseStyle`
是从 `DefaultTextStyle` 拷的（所以**字体族、颜色确实跟着主题走**——用户观察正确），
但 `fontSize` 和 `height` 被**硬写成 16 / 1.15**。1.15 比 Material 的 1.5 还挤得多，
是可读性问题里最大的一块，且与主题无关（Material 下同样挤，只是黑体扛得住）。

修法在 `quote_content_widget.dart`：build 时复刻 quill 的 baseStyle
（`DefaultTextStyle.of(context).style.merge(style)`），只把 height 换成主题下发的值，
经 `customStyles.paragraph` 注入。两个坑：

- **paragraph 必须给全 color/fontSize**：`TextLine` 用 `RichText` 渲染，它**不继承**
  `DefaultTextStyle`。整体替换 paragraph 后缺 color 会在暗色模式下渲染成黑字。
  所以是「拿到等效 base 再 copyWith」，不能凭空构造 `TextStyle(height: x)`。
- **`_staticEditorConfig` 不能再全静态**：customStyles 随主题和笔记颜色变。
  改成静态基底（`embedBuilders` 是唯一贵的东西，不随主题变）+ 一条 memo。
  用 memo 而不是 Map 是因为同屏卡片正文样式几乎总是同一个，命中率极高，
  又不会像按颜色做键的 Map 那样无界增长。

另外 `QuoteContent.estimatedLineHeight`（富文本折叠估算）原本是 `const 24.0`。
纯文本走 `TextPainter` 实测会自动跟上，**富文本拿不到 context 只能静态估算**，
所以它改成全局值、由 build 回填，并且**进了 `_HeightEstimateCacheKey`**——
否则换主题后会读到上一套风格算出来的高度，把展开按钮判错。

#### 没做的部分

- **横线只做了间距对齐，没做相位对齐。** 间距等于行高后，文字与横线的相对偏移
  已经恒定（不再逐行漂），这是绝大部分收益。要让文字精确「坐」在线上还需要给
  `PaperRuleBackground` 传 `topInset`，而卡片顶部结构随展开/选择模式变化，
  算不准反而更糟，先不做。
- **每日一言卡（`sliding_card.dart`）的横线对不齐是设计使然**：正文是外部传入的
  居中大字，相位随内容长度变，做不到对齐。不要试图在那里对齐。
- **富文本字号仍硬写 16**，没跟着 `bodyLarge` 走。改它会动到所有富文本笔记的
  视觉和高度估算缓存，风险大于收益，留着。

## 三、已知的不一致与遗留

- ~~聊天气泡不随风格~~ **2026-08-01 已迁移**：`AppTheme.chatBubbleRadius` 已删除，
  消息气泡、思考面板、工具进度面板改读 `AppShapeTokens.of(context).dialogRadius`
  （原值 24 与 material 的 dialogRadius 精确相等，material 下像素不变）。
  `thinking_widget.dart` 顶层那个 `const BorderRadius _bubbleShape` 已改成取 context 的函数。
  面板内部三处 12 圆角一并迁到 `buttonRadius`，否则 paper 下会出现内圆大于外圆的破相。
- **纸墨和素笺的字体族仍然相同**，但 2026-08-04 起行高不同了（1.75 / 1.6），
  加上纸墨独有的横线，两套风格终于不只是颜色和圆角的差别。
- **年度报告未迁移**：`annual_report_page.dart` 仍用 `AppTheme.*Radius` 静态值。
  产品上已废弃，**不要动**。

  > ⚠️ 这条原本还写着 `lib/pages/ai_report/`，**是错的**。那个目录全是
  > `part of '../ai_periodic_report_page.dart'`，是**探索页**（周期报告），
  > 和年度报告没有关系。这个错误让后续每一批迁移都把探索页排除在外，
  > 直到 2026-08-02 用户发现探索页没跟着主题走才补上。
  > 排除清单要按「谁 part of 谁」判断归属，不要按目录名猜。
- **`AppTheme.cardRadius` 那组静态常量仍然保留**，作为 material 取值和上面年度报告的依赖。
  自绘表面的新代码应该用 `AppShapeTokens.of(context).cardRadius`。

## 四、接手时必须知道的坑

- **`const` 上下文**：`AppShapeTokens.of(context)` 是方法调用，不能出现在 const 表达式里。
  迁移时遇到 `const RoundedRectangleBorder(...)` 要把 `const` 去掉，
  而不是退回静态常量。上一轮有 5 处踩了这个。
- **`part of` 文件加不了 import**：需要的 import 要加在库主文件。注意
  `smart_push_settings_page_*_sections.dart` 的 `part of` **不在第一行**
  （前面有 `// ignore_for_file:` 注释），按首行判断的脚本会漏掉它们。
- **手工色板不能喂给 seed 生成器**：亮色路径必须按风格关掉 `keyColors` 和表面混合，
  否则 FlexColorScheme 会拿色板的 primary 当种子把整套色调重新推导掉。
  暗色路径原本就是关的。
- **输入框的 border 不能删**：项目未设置 `inputDecoratorBorderType`，FlexColorScheme
  该参数默认是 `underline`。删掉 `OutlineInputBorder` 会把描边输入框变成下划线输入框。
- **改色板必须先过对比度测试**：`test/theme/theme_style_contrast_test.dart`。
  原始设计稿有多处不达 WCAG AA，已按验算收紧，沿革记在计划文档里。
- **卡片色刻意不落在 M3 的 surfaceContainer 梯度上**：两套色板都让卡片比页面底色更亮
  （纸叠在桌面上，暗色模式同理），而 M3 暗色下期望 `surfaceContainerLowest` 最暗。
  测试校验的是「卡片比底色亮且可区分」，不是 M3 的梯度假设。
- **切换风格时字体会瞬跳**：`TextStyle.lerp` 里 `fontFamily` 是 `t < 0.5 ? a : b` 的离散
  切换，动画播到一半会跳变、文字重排。目前没做处理，如果观感不能接受，用 `Duration.zero` 瞬切。
- **`lib/gen_l10n/` 是生成产物，不在仓库里**：拉下来直接 `flutter analyze` 会看到
  一堆 `themeStyle* isn't defined for the type 'AppLocalizations'`。
  这不是代码问题，跑一次 `flutter gen-l10n` 就没了。别去手改生成文件。
- **测试很慢**：这台机器上编译阶段可能几分钟无输出，不要以为卡死。
- **`flutter test | tail` 会吞掉退出码**：`tail` 的状态覆盖了 `flutter test` 的，
  必须 grep `All tests passed` / `Some tests failed` 判断，不能看 exit code。上一轮踩过。
- **仓库是公开的**：commit message 只描述改动本身。
- **用户会并行提交**：提交前 `git status` 确认，只用 `git commit --only <明确路径>`，
  禁止 `git add .`。

## 五、验证基线

- `flutter analyze`：**4 个 info**（`add_note_dialog_parts.dart` 的 cacheExtent、
  test/ 下 1 个 cacheExtent、test/ 下 2 个 doc comment）
- `test/widget/` + `test/theme/`：全部通过
- `test/performance/` **不在 CI 门禁内**（workflow 里是 manual），其中
  `tag_migration_benchmark_test` 挂在一个 SQL 引号 bug 上（`tag_ids != ""` 在 sqlite 里
  被当成列名），与主题无关，是既有问题
