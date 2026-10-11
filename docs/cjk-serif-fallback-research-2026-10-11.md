# ThoughtEcho CJK 系统衬线体回退机制与 Flutter 繁体中文（zh-Hant）国际化配置深度调研报告

**调研日期**：2026-10-11  
**依据文件与规范**：
- `docs/paper-ink-theme-handoff-2026-07-31.md`（第 0 节与第 0' 节）
- `lib/theme/theme_style.dart`（`ThemeStyleForm`、`bundledSerif` 与 `_systemSerifFallback`）
- `lib/theme/app_theme.dart`（`_applyStyleTypography`、`_createPlatformTextTheme` 与 `_fixAndroidVariableFontWeight`）
- `scripts/fonts/build_serif_subset.py`（思源宋体子集化流程）
- `lib/utils/localization_resolver.dart` 与 `lib/utils/i18n_language.dart`
- `lib/main.dart`（`MaterialApp` 的 `locale` 与 `supportedLocales`）
- Git 历史记录与 Flutter 官方 SDK 源码（`basicLocaleListResolution` 与 `Locale` 构造规范）

---

## 一、系统衬线体机制深度调研

### 1. 历史沿革：从“零字节”假象到“随包分发子集”的完整推导

ThoughtEcho 在纸与墨（`paper`）和素笺（`plain`）两套手工主题风格的字体演进中，经历过两次重大认知修正与架构重构：

#### 阶段一（2026-07-31）：初版系统字体映射
- **初始设计**：首选字体设为 `fontFamily: 'Songti SC'`（苹果宋体），回退链 `fontFamilyFallback` 末尾追加通用族名 `'serif'`。
- **问题**：在 Android 设备上，`Songti SC` 根本不存在；首选族名查询失败后，Flutter/Skia 直接走引擎默认中文字体（各厂商系统黑体），排在末尾的 `serif` 无法激活。两套风格在 Android 上始终为黑体。

#### 阶段二（2026-08-01 ~ 08-02）：首选通用族 `serif` 的“零字节路线”
- **现场发现**：在富文本编辑器（FlutterQuill）中手动选择 "Serif"，Android 真机上的中文变成了衬线体（宋体）。编辑器生成的样式即 `fontFamily: 'serif'`。
- **技术推导**：AOSP 从 Android 9 开始，在 `/system/etc/fonts.xml` 中配置了 `<family name="serif">`，并标记 `fallbackFor="serif"` 指向 `NotoSerifCJK`。Flutter 的 `fontFamilyFallback` 是**字符级字形回退**而不是 CSS 家族回退；首选族解析不到时，回退链里的 `serif` 无法向系统传递“本次排版需要衬线”的上下文。
- **作出的决定**：将首选字体家族改为 `fontFamily: 'serif'`，将具名字体（`Songti SC`、`SimSun` 等）挪到 `fontFamilyFallback`。团队认为“零字节路线成立”，可避免在安装包中捆绑大体积字体文件。

#### 阶段三（2026-08-22）：推翻通用族路线，改为随包分发子集
- **核心盲区揭露**：阶段二的验证**全部基于 Android 单端真机**，结论被错误推广至全平台。
- **iOS CoreText 的底层事实**：
  1. iOS 的字体排印底层是 Apple 的 **CoreText**，CoreText **不解析 CSS 通用族名关键字**（如 `serif`）。
  2. Flutter 在 iOS 上将 `'serif'` 传给 CoreText 时，CoreText 找不到名为 `serif` 的字体族，首选族宣告解析失败。
  3. **Flutter 回退机制的核心特性**：Flutter 的 `fontFamilyFallback` 只有在**首选字体已被解析成功、但该字体缺少当前字符字形**时，才会逐字触发回退！当首选族名（`serif`）整个无效时，Flutter 直接回退到宿主引擎默认字体（iOS 为 PingFang SC 苹方，黑体）。排在回退链里的 `Songti SC` 压根没有被查询的机会！
  4. **结论**：纸与墨和素笺在 iOS 上发布以来**正文从来都是黑体**，衬线体在 iOS 上从未生效！
- **Android OEM 生态碎片化事实**：
  1. 国内主流 OEM ROM（小米 HyperOS/MIUI、OPPO ColorOS、vivo OriginOS、华为 HarmonyOS）为精简 system 分区空间，几乎**全量剥离了 `NotoSerifCJK`**，系统内仅存 `Roboto` 与自研黑体（MiSans、OPlus Sans 等）。
  2. 即使在保留了 NotoSerifCJK 的原生 Android 上，`fonts.xml` 里也仅包含单一的 `weight="400"` 静态切片。ThoughtEcho 为解决中文衬线横画过细而引入的 `readingWeightFloor: w500 / w600` 字重补偿，在设备端直接被匹配回 400，沦为空操作。
- **最终落地决议**：
  随包分发思源宋体（Noto Serif SC）可变字体 GB2312 子集（5.17MB，可变字重轴 400–900，产物签入 `assets/fonts/NotoSerifSC-Subset.ttf`），族名定义为 `ThemeStyleForm.bundledSerif = 'NotoSerifSC'`。
  这确保了三端渲染绝对一致，且 `readingWeightFloor` 成为精确可调控的连续轴。

---

### 2. 各平台自带繁体中文（TC）与日文（JA）衬线体客观事实

| 操作系统平台 | 繁体中文 (TC) 衬线体 | 日文 (JA) 衬线体 | 客观可用性与渲染质量评估 |
|---|---|---|---|
| **iOS / iPadOS** | `Songti TC` (宋體-繁) | `Hiragino Mincho ProN` (ヒラギノ明朝 ProN) | **系统预装且可用**。字形规范优美，支持 Regular/Bold 等经典字重，但**不具备连续 Variable Font 轴**。CoreText 必须使用确切具名家族名，不认 `serif`。 |
| **macOS** | `Songti TC` (宋體-繁)、`STSong` | `Hiragino Mincho ProN`、`YuMincho` (游明朝体) | **系统预装且完整**。排版质量高，但同样不认 `serif` 通用族名。 |
| **Android (AOSP 原生)** | `NotoSerifCJK-Regular.ttc`（含 TC 分支） | `NotoSerifCJK-Regular.ttc`（含 JP 分支） | 理论上 AOSP `fonts.xml` 配置了 `fallbackFor="serif"`。但**仅有 Regular (w400) 单一档**，无中等字重或粗体变体。 |
| **Android (国内/主流 OEM)** | **主流机型实测缺失** | **主流机型实测缺失** | 主流厂商定制系统（如小米 HyperOS、OPPO ColorOS、vivo OriginOS、华为 HarmonyOS）为压缩系统分区体积，其 `/system/fonts` 默认仅保留黑体（如 MiSans / OPPO Sans / HarmonyOS Sans）与拉丁衬线体，普遍未内置 CJK Serif。依赖系统字体在这些设备上必定回退为系统黑体。 |
| **Windows** | `MingLiU` (細明體) / `PMingLiU` (新細明體) | `MS Mincho` (MS 明朝)、`Yu Mincho` (游明朝，Win 10+) | **自带但质量两极分化**：`MingLiU` 属于 Windows 早期点阵/矢量混合字体，小字号强制内嵌粗糙点阵（Bitmaps），高分屏下笔画生硬无梯度；Win 10+ 的 `Yu Mincho` 质量良好，但旧字体兼容性负担重。 |

---

### 3. 混排机理：为什么拿简体子集 `NotoSerifSC-Subset` 渲染日文/繁体会发生视觉灾难？

#### (1) 子集字符收录边界
查看 `scripts/fonts/build_serif_subset.py`：
- 当前默认收录：GB2312 全量 6,763 个汉字、ASCII、拉丁补充、希腊/西里尔字母、假名平假名/片假名（U+3040..U+3100）、全角及通用标点。
- **未收录**：Big5 常用汉字（约 5,400 个繁体汉字）、JIS 第 1/2 水准特有日文汉字（新字体变体、国字如「込、枠、畑、峠」）。

#### (2) 恶性混排的发生过程（Glyph Patchwork / 字符补丁）
在一段繁体中文句子中（例如：「繁體中文的閱讀體驗」）：
- 「繁」：在 GB2312 编码表中 $\rightarrow$ **命中 `NotoSerifSC`（宋体，按主题阶梯渲染为 w600）**
- 「體」：不在 GB2312 编码表中 $\rightarrow$ **首选族缺失字形，触发回退链** $\rightarrow$ 最终落入系统默认黑体（`PingFang TC` / `Microsoft JhengHei` / `Noto Sans CJK TC`，黑体，字重 w400）
- 「中、文、的」：均在 GB2312 表中 $\rightarrow$ **命中 `NotoSerifSC`（宋体 w600）**
- 「閱、讀、體、驗」：不在 GB2312 表中 $\rightarrow$ **穿透回退至黑体（黑体 w400）**

**视觉后果**：
同一个短语中，「繁」(宋体)「體」(黑体)「中」(宋体)「文」(宋体)「的」(宋体)「閱」(黑体)「讀」(黑体)「體」(黑体)「驗」(黑体)。
**字重从 600 骤降到 400，横竖笔画对比度激烈冲突，字面率与基线频繁跳动**。这在西文和汉字排印学中被称为“字体斑秃”或“补丁混排”，观感极其粗糙。

#### (3) 日文汉字的字形标准偏差（Glyph Dissonance）
虽然日文假名已被完整收进子集，但当渲染日文汉字时：
- 存在于 GB2312 的汉字（如「直、骨、刃、卿」），会强制按照**中国大陆规范字形（PRC 新字形）**渲染，而非日本工业标准（JIS X 0213）字形，对母语日文用户产生字形违和感；
- JIS 特有汉字穿透到系统日文字体，同样造成宋黑交替混排。

---

### 4. 最佳方案：平台差异化系统衬线体显式调用（Platform-Aware System Serif）

#### 为什么直接设为 null（黑体）过于保守？
直接退回系统黑体固然规避了混排，但完全放弃了各平台上现成的优质系统衬线体资产。事实上，**导致单段落内“宋黑斑秃混排”的真正根源是首选族强行绑定了随包简体子集 `NotoSerifSC-Subset`（因其仅收录 GB2312）**。
只要在非简体语言下**脱离该随包子集**，直接向系统请求衬线字体族，整段文本便由系统字体管理器统一排版，根本不会发生字形撕裂。

#### 跨平台显式映射与逐步回退设计
在 `ThemeStyleForm.forLocale(locale)` 中，按当前运行平台精准匹配系统衬线族名：
1. **Android 平台**：
   - 首选族名设为 **`serif`**。
   - Android 系统底层（Minikin / `Typeface.create("serif")`）会通过 `/system/etc/fonts.xml` 将 `serif` 映射至系统衬线字体族。在配置了 CJK Serif（如 NotoSerifCJK）的原生 Android 或特定厂商机型上，CJK 字符能呈现完整的衬线体；而在未内置 CJK Serif 的机型上，由于 Flutter 采用逐字形回退（per-glyph fallback），西文字符呈现 Noto Serif，缺字的 CJK 字符则回落至系统默认黑体。脱离随包 GB2312 简体子集后，汉字自身不再因子集缺字而分裂为半宋半黑。
2. **iOS / macOS 平台**：
   - iOS 的 CoreText 不认通用别名 `serif`，但认具体具名族名：
     - 日文（`ja`）：**`Hiragino Mincho ProN`**（ヒラギノ明朝，苹果内置的高品质印刷级明朝体）；
     - 繁体中文（`zh-Hant`）：**`Songti TC`**（宋體-繁）/ `LiSong Pro`；
     - 韩文（`ko`）：**`AppleMyungjo`**。
   - 在 iPhone / iPad / Mac 上获得原汁原味的系统宋体/明朝体体验。
3. **Windows 平台**：
   - 日文（`ja`）：**`Yu Mincho`**（游明朝，Windows 10/11 默认自带的高质量衬线体）与 `MS Mincho`；
   - 繁体中文（`zh-Hant`）：**`PMingLiU`**（新細明體）与 `MingLiU`。
4. **备选回退链（`fontFamilyFallback`）的定位与局限**：
   - Flutter 的 `fontFamilyFallback` 仅在**主族解析成功但缺失特定字符字形**时触发逐字回退，并不会在主族名称完全无法解析时整体切换到备用族。因此在此处放置跨平台候选衬线体列表，主要用于主字体缺字时（如日文借用汉字、繁体生僻字等）优先借用其他可用衬线字形。

**收益**：
- **零包体增加**（不增添任何离线字体包）；
- **大幅减轻斑秃混排**（汉字统一由系统字体管理器调度，避免随包 GB2312 子集局部截断）；
- **最大化保留纸墨衬线美学**（在支持的 Android、iOS、macOS、Windows 上均呈现地道衬线字体）。

---

## 二、Flutter 繁体中文（zh-Hant）支持调研

### 1. ARB 命名规范与配置要求

1. **ARB 文件命名**：
   - 必须为 **`app_zh_Hant.arb`**。
   - **不能使用短横线**（`app_zh-Hant.arb`）：Flutter 的 `gen-l10n` 和底层 `intl` 工具严格使用下划线 `_` 拆解 `language_script_country`。如果使用 `-`，工具会将整个字符串视为非法的单一语言标识符或直接忽略该文件。
2. **ARB 文件内内容声明**：
   - 内部顶层必须声明 `@@locale`：
     ```json
     {
       "@@locale": "zh_Hant",
       "appTitle": "心跡"
     }
     ```
3. **`l10n.yaml` 配置**：
   - 项目当前 `l10n.yaml` 已配置 `template-arb-file: app_zh.arb`。
   - 在 `lib/l10n/` 放入 `app_zh_Hant.arb` 后，无需改动 `l10n.yaml`，执行 `flutter gen-l10n` 即可自动识别。

### 2. `flutter gen-l10n` 的生成行为与代码结构

当存在 `app_zh.arb` 与 `app_zh_Hant.arb` 时，`flutter gen-l10n` 的生成规则如下：
1. **类继承体系**：
   - 生成 `class AppLocalizationsZh extends AppLocalizations`（对应 `app_zh.arb`）。
   - 生成 `class AppLocalizationsZhHant extends AppLocalizationsZh`（继承自简体中文类，未翻译的键自动回退到简体中文实现）。
2. **`supportedLocales` 列表**：
   ```dart
   static const List<Locale> supportedLocales = <Locale>[
     ...
     Locale('zh'),
     Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
   ];
   ```
3. **`lookupAppLocalizations` 匹配逻辑**：
   ```dart
   AppLocalizations lookupAppLocalizations(Locale locale) {
     switch (locale.languageCode) {
       case 'zh': {
         switch (locale.scriptCode) {
           case 'Hant': return AppLocalizationsZhHant();
         }
         break;
       }
     }
     switch (locale.languageCode) {
       case 'zh': return AppLocalizationsZh();
       ...
     }
     throw FlutterError(...);
   }
   ```

### 3. Locale 构建与匹配规范

- **正确构造语法**：
  对于包含 Script 的 Locale，必须使用 `Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant')`。
  如果调用 `Locale('zh', 'Hant')`，`'Hant'` 会被错误赋值给 `countryCode`，导致 `scriptCode` 为 `null` 而无法命中 `AppLocalizationsZhHant`。
- **港台设备系统语言匹配**：
  若用户的系统语言上报为 `Locale('zh', 'TW')`（未带 `scriptCode`），在 `MaterialApp.localeListResolutionCallback` 中进行识别映射，将其定向至 `Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant')`。
