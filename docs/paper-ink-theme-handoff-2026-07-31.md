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

### 0. 字体：已决定不打包，接受平台差异（2026-08-01 结案）

**用户 2026-08-01 决定：不打包字体。** 下面 (a)(b) 两条不再是待办，保留作为背景。

现状因此是确定的、可接受的：Android 上**只有拉丁字形变衬线，中文不变**——
用户观察到的「笔记卡片日期数字有点变化」正是这个，说明回退链本身生效了，
只是中文那一环在 Android 上没有字体可落。iOS / macOS 上中文也是衬线。

**不要再重开这个话题**，除非用户主动提出要吞 2.5MB 的子集化字体。
`test/theme/theme_style_contrast_test.dart` 里那条字体测试的注释已经写明
它只保证「不出豆腐块」，不是「字体已生效」的证据。

<details>
<summary>背景：为什么零字节路线在 Android 上走不通</summary>

**「指向系统自带衬线体」这条零字节路线在 Android 上不成立。**

- 多数 Android 设备只带 **Noto Sans CJK，不带 Noto Serif CJK**。国内 OEM ROM
  （MIUI / ColorOS / OriginOS 等）各有各的字体集，不能假定有衬线中文。
- 通用族 `serif` 在 Android 映射到 **Noto Serif，只有拉丁字形**；中文字形仍旧
  回落到系统黑体。所以英文可能变了衬线，中文没变——观感上等于没变。
- `Songti SC` / `STSong` 是 iOS 和 macOS 的系统字体，Android 上必然落空。
- Flutter 的 `fontFamilyFallback` **不是 CSS 的 font-family**：它走 Flutter 自己的
  字体管理去解析，解析不到就静默跳过，不会报错，所以问题很难被发现。

**下一轮要做两件事：**

**(a) 加诊断，让「字体没生效」可见。** Flutter 没有「查询字体是否存在」的 API，
但可以用排版结果反推：用 `TextPainter` 把同一段中文分别以目标字族和一个**肯定不存在**的
字族（如 `__definitely_missing__`）排版，比较宽高。完全相同说明目标字族没解析到，
落到了同一个回退字体上。启动时或主题切换时跑一次，`logWarning` 出来。

```dart
// 思路示意，不是最终代码
double _width(String? family) {
  final tp = TextPainter(
    text: TextSpan(text: '测试中文字形宽度', style: TextStyle(fontFamily: family)),
    textDirection: TextDirection.ltr,
  )..layout();
  return tp.width;
}
final resolved = _width('Songti SC') != _width('__definitely_missing__');
```

注意这个探针有假阴性：如果目标字族和回退字体宽度恰好一致（等宽中文很常见），
会误判成没生效。中文字形宽度普遍相同，**所以宽度比较对中文很可能不可靠**，
更稳的做法是比较**拉丁字符**的排版宽度，或者直接改用光栅化后的像素差异比较。
这一点要实测确认，别照抄。

**(b) 决定真正的解法。** 零字节路线在 Android 上走不通，剩下两条：

1. **打包子集化字体**（回到最初被推迟的方案）：`Noto Serif SC` 子集到 3500 常用字
   约 2.5MB，需要 `fonttools pyftsubset` 外部构建步骤、产物二进制签入仓库，
   文案一改要重跑。这是唯一能保证「所有设备都是衬线」的路。
2. **接受平台差异**：iOS 有衬线、Android 没有。← **用户选了这条。**

</details>

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

### 4. 字重与间距令牌

Komi Store 值得学的一点：把字重、间距也做成主题令牌。衬线体在小字号下偏细，
纸墨风格可能需要比 Material 稍重的正文字重。目前 `ThemeStyleForm` 没有这两项。

## 三、已知的不一致与遗留

- ~~聊天气泡不随风格~~ **2026-08-01 已迁移**：`AppTheme.chatBubbleRadius` 已删除，
  消息气泡、思考面板、工具进度面板改读 `AppShapeTokens.of(context).dialogRadius`
  （原值 24 与 material 的 dialogRadius 精确相等，material 下像素不变）。
  `thinking_widget.dart` 顶层那个 `const BorderRadius _bubbleShape` 已改成取 context 的函数。
  面板内部三处 12 圆角一并迁到 `buttonRadius`，否则 paper 下会出现内圆大于外圆的破相。
- **纸墨和素笺的字体相同**，只靠颜色和圆角区分。如果两套要拉开更多差距，字体是下一个抓手。
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
