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

### 0. 字体：改为随包分发子集（2026-08-22 完成，推翻下面整节）

> **下面这一整节已经作废，保留是为了记住 iOS 上那个盲区是怎么形成的。**
>
> 零字节路线（首选族名 `serif`）在 Android 上确实有效，但**在 iOS 上从未生效**：
> CoreText 不解析通用族名，`serif` 解析不到时 CJK 字符直接走引擎默认字体（苹方），
> 而 `fontFamilyFallback` 只在**首选族有字形但缺某个字**时才逐个回退——首选族整个
> 解析不到时，排在后面的 `Songti SC` 根本没机会被查询。所以两套手工风格的正文
> 在 iOS 上一直是黑体，字体这一层等于没做。
>
> 当时的验证全部来自 Android 真机（编辑器里选 "Serif" 中文变衬线），
> 结论被直接推广到了三端。**教训：字体回退的结论必须逐平台验，
> 通用族名的解析行为在 Android / iOS / Windows 上根本不是一回事。**
>
> 现在：`assets/fonts/NotoSerifSC-Subset.ttf`（思源宋体 GB2312 子集，5.17MB，
> 可变字重 400–900），由 `scripts/fonts/build_serif_subset.py` 生成，
> 族名 `ThemeStyleForm.bundledSerif`。产物已签入仓库，日常构建不依赖脚本。
>
> 附带的收获比「三端一致」更要紧：`readingWeightFloor` 从「下限 + 听设备的」
> 变成了**精确取值**——字重轴连续，w500 就是 w500，这个杠杆终于能调、能验。
> `bodyFontScale: 1.0625` 那个字号补偿也可以重新评估了（它原本是为了补偿
> 「不知道多细」的系统衬线横画），但**必须真机看着调，不要闭眼改**。
>
> **多语言覆盖**（应用支持 de/en/es/fr/ja/ko/zh 七种界面语言）：
> - de / es / fr：重音字母全在拉丁补充区，**完整覆盖**；
> - ja：假名整块收进来了（GB2312 本来就带大半）。但日文汉字会用简体字形渲染，
>   这是用简体中文字体的固有代价，子集解决不了；
> - ko：**源字体根本不含谚文**（Noto Serif SC 的谚文音节数为 0），韩文一定落到
>   `fontFamilyFallback` 的系统字体。换成 Noto Serif KR 才行，那是另一个 5MB，
>   目前不值得；
> - ru / el：源字体只有 66 个西里尔、49 个希腊字母，已经全收。
>
> 许可证：SIL OFL 1.1，可商用、可随应用分发、可改名（版权声明后没有指定
> Reserved Font Name）。唯一的禁止项是「单独售卖字体本身」。全文随包在
> `assets/fonts/OFL.txt`，应用内出处见 `lib/pages/license_page.dart`。
>
> **PDF 导出也跟着走了**（2026-08-22）：`pdf` 包有自己的排版引擎，完全不看
> `textTheme`，所以字体得单独递——`AppTypographyTokens.readingFontFamily` 递给
> `PdfFontService.loadFontSet`，族名等于 `bundledSerif` 时正文改用随包那份。
> 判据是族名取值不是风格身份，将来任何一套风格指向随包衬线，PDF 自动跟上。
> 两个前提别拆：
> - **回退链里必须留着下载的黑体**。随包字体是子集，
>   `DeltaToPdfParser.sanitizeTextForPdf` 会把「所有字体都不支持」的字符
>   **直接从文档里删掉**——少一个回退就是少一批字，而且是静默的。
> - `pdf` 包不做字重轴插值，只认默认实例。子集化时已经把默认实例收到 w400，
>   所以拿到的是 Regular；这也是字重轴下限取 400 的另一个理由。
>
> 两个坑，都已固化在代码注释里：
> - **不要改用 `fontVariations`。** 直接指定 wght 轴看着更精确，但它会盖过
>   `fontWeight`，全项目上百处 `copyWith(fontWeight: ...)`（含富文本加粗）
>   会静默失效。交给引擎按 `fontWeight` 映射 wght 轴。
> - 子集是 GB2312（约 7800 字形），**繁体和生僻字不在里面**，会沿
>   `fontFamilyFallback` 落到系统衬线体，同段落里会有轻微混排。
>   加 Big5 一级常用字约 +1.6MB，脚本 `--traditional` 一个开关。

### 0'（已作废）字体：首选族名改成 `serif`，零字节路线成立（2026-08-02 修正）

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

### 2. ~~默认值翻成 `paper`~~（2026-08-16 翻回 `material`，已结案）

历史：产品意向一度定为「默认纸墨、可切回 Material」，2026-08-01 决定先不翻，
后来翻成了 `paper`，并在更新完成页加了一条「外观已更新」的提示。

**2026-08-16 用户决定：翻回 `material`，新装和升级都是。** 理由是这套主题
**没有迁移逻辑**，换默认值等于让所有没选过风格的老用户在没做任何操作的情况下
外观直接变了；一条提示救不回「已经变了」这个既成事实。

结论是这一条不再是待办，而是一个**已经作废的方向**：品牌外观的推广改由更新说明页
（`lib/pages/release_notes_page.dart`）里的行内风格切换器承担——想要的人一点就有，
不想要的人什么都不用做。同时删掉了「外观已更新」提示和它的 `theme_style_notice_shown`
标记。默认值仍然只写在 `ThemeStyle.defaultStyle` 一处，由
`theme_style_contrast_test.dart` 钉死具体是哪一套。

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

- **富文本折叠估算的行高是个全局静态值**，由 `QuoteContent.build` 回填。但折叠判定
  发生在**父组件**（`quote_item_widget._needsExpansionForLayout`），比子组件 build
  早一帧，首帧和刚切风格那一帧会读到上一套的行高。已经在两个判定入口前面加了
  `_syncEstimatedLineHeight(style)` 对齐（口径和 `QuillThemeTypography.paragraphStyle`
  一致，都只认传进来的 style）。**根治要把行高做成参数传进估算接口**，
  不再依赖全局静态值——那要改一串静态方法的签名，这轮没做。

- **横线只做了间距对齐，没做相位对齐。** 间距等于行高后，文字与横线的相对偏移
  已经恒定（不再逐行漂），这是绝大部分收益。要让文字精确「坐」在线上还需要给
  `PaperRuleBackground` 传 `topInset`，而卡片顶部结构随展开/选择模式变化，
  算不准反而更糟，先不做。
- **每日一言卡（`sliding_card.dart`）的横线对不齐是设计使然**：正文是外部传入的
  居中大字，相位随内容长度变，做不到对齐。不要试图在那里对齐。
- ~~**富文本字号仍硬写 16**~~ **2026-08-06 已修**，见下一节。

### 5. 字重、字号与标签字体（2026-08-06 已完成）

用户再次反馈「可读性还是比 Material 差很多，主要是粗细」。上一轮（第 4 节）只把
**减重**关掉，回到 M3 原生 w400——**「不减重」不等于「够粗」**。这一轮补齐。

**根因：中文衬线的横画只有竖画三分之一粗。** 16sp 配 2x 屏时，一根横画落到大约
半个物理像素上，抗锯齿后只剩一条浅灰线。这跟对比度无关——四套色板的正文/次要文字
全部在 WCAG AA 以上（正文 14:1 以上），是笔画物理宽度的问题，WCAG 也不看这个。
所以补偿必须落在**笔画宽度**上，一共三根杠杆，按「在多少设备上一定生效」排序：

| 杠杆 | 令牌 | 取值 | 生效范围 |
| --- | --- | --- | --- |
| 字号 | `bodyFontScale` | 1.0625（16 → 17） | **所有平台一定生效** |
| 字重 | `readingWeightFloor` | w500 | 设备的衬线体有多档字重才生效 |
| 墨色 | 色板 `inkMuted` | 四套在纸和卡片上都抬到 7:1（有测试钉死） | 所有平台 |

字重之所以不能单打，是因为**它可能是个空操作**：AOSP 的 `fonts.xml` 里
`NotoSerifCJK` 只有 weight 400 一档，请求 w500 会匹配回 400。三种落地情况分别是
「精确落位（可变字体）/ 匹配到最近档（等于现状，不是回退）/ 落到最接近的一档」，
**只增不减**，所以加它没有风险，但不能指望它一个人扛。字号则一定生效。

**字重是下限不是增量**（`ThemeStyleForm.readingWeight`）。M3 的 `titleMedium` /
`titleSmall` 本来就是 w500，若写成「+100」会把它们顶到 w600，而只有 Regular / Bold
两档的衬线体会把 600 匹配成 **Bold**——列表标题会集体变粗。抬下限对它们零影响。

**排版分三档，依据是光学尺寸**（`AppTheme._applyStyleTypography`）：

- `display*` / `headline*`（24–57sp）：只换字体族。这个尺寸横画不会掉进半像素。
- `title*` / `body*`（11–22sp）：换族 + 抬字重下限；`body*` 另吃字号与行高缩放。
- `label*`：**什么都不改，保持系统黑体**。按钮、胶囊、导航栏标签是功能性文字，
  中文衬线在 11–14sp 下糊成一团，而它们不承担任何风格识别——付出全部可读性代价
  换不到辨识度。这是全局规则，写死在方法里，不做成令牌。

**顺带修掉的三处，每一处都是「主题走到一半断了」：**

1. **AppBar 那条分支一直是空转**（不是「标题没跟风格」——先入为主写成那样是错的，
   实测推翻了）。FlexColorScheme 根本不设 `appBarTheme.titleTextStyle`，
   `?.copyWith(...)` 求值成 null，里面硬写的 `fontSize: 20` 和 `fontWeight: w400`
   **从来没生效过**；M3 的 AppBar 在它为 null 时回落 `textTheme.titleLarge`，
   顶栏标题本来就跟着风格走。现在把这条分支改成跟风格取值（字体族 +
   `form.readingWeight(FontWeight.w400)`）并留下警示注释，为的是它某天非空时不会
   把风格丢掉，**不是修好了什么可见的东西**。
2. **富文本的加粗在衬线风格下会消失**。`quote_content_widget` 那套
   `bold: w500` 的降档是给黑体做的，而系统中文衬线常常只有 Regular / Bold 两档，
   w500 匹配回 Regular——用户标的粗体直接没了。判据改成
   `AppTypographyTokens.variableWeightCompensation <= 0` 时整段跳过。
   这是新加的 `ThemeExtension`，只放**够不着 `textTheme` 的那条路**。
3. **全屏编辑器还吃着 quill 硬写的 16 / 1.15**，比笔记卡片挤得多——同一条笔记
   「写的时候」和「读的时候」行距不一样。纠正规则抽到
   `QuillThemeTypography`（`quill_editor_extensions.dart`），两处共用。

**富文本字号终于跟着 `bodyLarge` 走了。** 上一轮判定「风险大于收益」，这一轮不改
不行：衬线风格把正文放大到 17 之后，同一个列表里富文本笔记会比纯文本笔记小一号，
纸张横线也只跟纯文本对齐。高度估算缓存的键里已经有 `estimatedLineHeight`
（= 字号 × 行高），字号一变键就变，不会读到旧值。

**`ruleSpacing` 的推导公式跟着改成「字号 × 行高」**，不再是「16 × 行高」。
不变量在 `theme_style_contrast_test.dart` 里更新过了。

#### 一个接手必读的坑：`ThemeData.textTheme` 里大部分字段是 null

排查这一轮时才确认：`createLightThemeData()` 产出的 `textTheme` 里，**字号、行高、
字重绝大多数是 null**，它们由 `Theme` widget 在 build 时按 locale 的字形几何补齐
（`ThemeData.localize` + `Typography.dense`，中文走 dense）。所以：

- 想读「正文多大」不能直接看 `theme.textTheme.bodyLarge!.fontSize`，主题层拿到的是
  null；只有在 widget 树里 `Theme.of(context)` 之后才是完整值。
- `_applyStyleTypography` 里那些 `?? m3Size` / `?? m3Height` 兜底**不是防御性代码，
  是主路径**——base 就是 null，全靠它们把 M3 默认值填进来。填错就会静默偏一档。
- 反过来，**一旦写进具体值就等于把这一级从几何里摘出来了**。这就是为什么字号缩放
  只给 `body*`：给 `title*` 也钉上会连带压掉 dense 几何在标题上的取值。
- 字重下限取 w500 还有一层没写在设计里的运气成分：base 字重是 null，代码按 w400 算，
  而 `titleMedium` / `titleSmall` 的真实 M3 值正好也是 w500，两边撞上了才没出错。
  **下限要是取得更高，会连标题一起顶粗，而 base 是 null 这件事会让人看不出来。**

这些不变量钉在 `test/theme/theme_style_typography_test.dart`——它断言的是
`createLightThemeData()` 的产物，和只断言令牌取值的 `theme_style_contrast_test.dart`
是两回事，不要合并。

#### 这一轮没做的部分

- ~~**没有打包字体**~~ **2026-08-22 已打包**，见第 0 节。当时写的「如果真机上
  字重杠杆被证实是空操作……下一步就是打包」正是后来发生的事，只是触发它的
  不是字重，是 iOS 上整个字体族没生效。
- **`bodyFontScale` 只作用于 `body*`**。标题没跟着放大，因为标题字号本来就在
  横画不失真的区间，放大只会挤掉列表密度。

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
