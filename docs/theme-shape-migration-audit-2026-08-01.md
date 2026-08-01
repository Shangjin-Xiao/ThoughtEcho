# 纸墨主题形状/阴影迁移审计（2026-08-01）

> 本文档只做审计，**未修改任何 `lib/` 代码**。范围是 `lib/` 下全部 dart 文件里，
> 卡片/对话框/底部弹窗/输入框/按钮/面板这类表面上硬编码的圆角、阴影、投影、描边。
> 目标令牌下发口是 `AppShapeTokens.of(context)`（`lib/theme/theme_style.dart`），
> 三个字段最常用：`cardRadius` / `dialogRadius` / `buttonRadius` / `inputRadius` /
> `borderWidth`；阴影目前令牌只有 `shadowOpacity` / `shadowBlur` 两个数值，
> 没有现成的 `List<BoxShadow>` getter——这是本次审计发现的**一个缺口**，见「六、令牌缺口」。

## 一、总数统计

| 类别 | 数量 | 说明 |
| --- | --- | --- |
| 硬编码 `BorderRadius.circular(<字面量>)`，卡片/对话框/输入框/按钮/面板类表面 | **151 处** | 已过滤掉正确使用 `AppShapeTokens.of(context).xxxRadius` 的多行写法；已过滤三处显式排除文件 |
| `AppTheme.defaultShadow` / `lightShadow` / `accentShadow` / `hoverShadow` 静态阴影直接引用 | **14 处**（`lib/theme/app_theme.dart` 定义处不计） | 这些阴影本身不随风格变化，纸墨/素笺下应该几乎不投影 |
| 自绘 `boxShadow: [BoxShadow(...)]`（不经 `AppTheme.*Shadow`，手写数值） | 约 **25 处**（分布在 25 个文件） | 同样不随风格变化 |
| `Card` / `Dialog` 上显式 `elevation: N`（N>0），覆盖 `CardThemeData` 里按风格算好的 0 投影 | **23 处** | 纸墨/素笺下这些卡片会继续带 Material 投影，和其余卡片不统一 |
| `AppTheme.cardRadius` 等静态圆角常量的使用点（本次审计范围内，不含已排除区域） | **0 处** | 聊天气泡（`thinking_widget.dart`/`tool_progress_panel.dart`/`ai_assistant_page_ui.dart`）在写作本文档期间已被另一子代理迁移完成，`AppTheme.chatBubbleRadius` 已删除；`AppTheme.cardRadius` 等常量目前只剩年度报告一处依赖，见下表 |
| `Border.all(...)` 未显式给 `width`（隐式取 Flutter 默认 1.0，未经 `AppShapeTokens.of(context).borderWidth`） | 数十处，未逐条列出 | 优先级最低：paper/plain 的 `borderWidth` 恰好也是 1，观感上暂时不出错，只是没有把"要不要画描边"这个判据交给令牌（material 风格下 `borderWidth=0`，理论上不该画） |

**结论**：真正影响观感的大头是 151 处硬编码圆角 + 23 处显式 `elevation` + 约 39 处硬编码阴影。
`Border.all` 缺 `width` 令牌优先级最低，可以放到最后一批或干脆不做。

## 二、建议分几批做

按用户可见度从高到低分 6 批，每批控制在可以一次性验证完的规模（3~8 个文件）。
每批做完建议跑一遍 `test/theme/theme_style_contrast_test.dart` 和涉及页面的现有 widget 测试。

> **进度（2026-08-01）**：第 1 批、第 5 批**已完成**；第 6 节的「阴影令牌缺口」**已补上**
> （`AppShapeTokens` 现有 `restShadow` / `lowShadow` / `raisedShadow` / `accentShadow`
> 四个 getter，一一对应 `AppTheme` 那四组静态常量，material 下 alpha 差 < 0.002）。
> **2026-08-01 全部六批已完成。** 本文档转为存档，剩下的只有两类刻意未做的：
> - **`Border.all` 的宽度**：`borderWidth` 在 material 下是 0，接过去会让默认风格的
>   描边整体消失，属观感变更而非迁移。
> - **`Chip` 的 elevation**：不在 `CardThemeData` 覆盖范围内，也没有对应令牌路径。
>   要做得先补 `ChipThemeData`，别临时糊。
>
> 另外 `svg_card_widget.dart` 有一片硬编码颜色（`Colors.grey[*]` / `Colors.red[*]` /
> 预览画布的 `Colors.white`）违反 AGENTS.md，属另一类问题，未处理。
>
> 另外，第三节列的「疑似死代码集群」已确认是死代码并**删除**
> （`markdown_message_bubble.dart`、`typing_indicator_bubble.dart`、
> `chat_theme_helper.dart`、`chat_markdown_styles.dart` 及其两个测试），
> 连带从 pubspec 移除 `flutter_chat_ui` / `flutter_chat_core` / `flutter_chat_types`
> 三个依赖。`ai_annual_report_webview.dart` 用户已确认归入「年度报告，不动」。

- **第 1 批 · 首页与记录页**（天天看到，收益最大）— ✅ 已完成
  `lib/pages/home_page.dart`、`lib/pages/home/daily_prompt_panel.dart`、
  `lib/widgets/note_list/note_list_items.dart`、`lib/widgets/note_list/note_list_filters.dart`、
  `lib/widgets/quote_card_helpers.dart`、`lib/widgets/weather_widget.dart`、
  `lib/widgets/hitokoto_widget.dart`
  （`quote_item_widget.dart`、`sliding_card.dart` 已排除，你在改）

- **第 2 批 · 编辑器与快速添加**
  `lib/pages/note_editor/editor_build.dart`、`editor_color_and_media.dart`、
  `editor_metadata_dialog.dart`、`editor_metadata_ai_section.dart`、
  `editor_metadata_location_section.dart`、`lib/widgets/add_note_dialog.dart`、
  `lib/widgets/add_note_dialog_parts.dart`、`lib/widgets/unified_media_import_dialog.dart`、
  `lib/widgets/note_filter_sort_sheet.dart`

- **第 3 批 · 分享卡片与媒体**
  `lib/widgets/svg_card_widget.dart`（笔记分享图生成，注意里面同时混了
  `Colors.white`/`Colors.grey`/`Colors.red` 等硬编码色，属于另一类问题，本文档只记形状）、
  `lib/widgets/media_player_widget.dart`、`lib/widgets/accessible_color_grid.dart`、
  `lib/services/clipboard_service.dart`、`lib/utils/quill_editor_extensions.dart`、
  `lib/widgets/quill_enhanced_toolbar_unified.dart`

- **第 4 批 · AI 助手页（气泡/思考面板/工具进度面板之外的部分）**
  `lib/pages/ai_assistant_page.dart`、`lib/pages/ai_assistant/session_history_page.dart`、
  `session_history_page_content.dart`、`lib/widgets/ai/ai_card_parts.dart`、
  `lib/widgets/ai/experimental_badge.dart`、`lib/widgets/ai/slash_commands_menu.dart`、
  `lib/widgets/ai_options_menu.dart`、`lib/widgets/streaming_text_dialog.dart`、
  `lib/widgets/enhanced_ai_loading_dialog.dart`、`lib/widgets/chat_input_suggestions.dart`、
  `lib/pages/ai_analysis_history_page_clean.dart`、`lib/pages/ai_settings_page.dart`、
  `lib/pages/ai_provider_edit_page.dart`
  （气泡本体、`thinking_widget.dart`、`tool_progress_panel.dart` 已由另一子代理迁移完成，
  不在这一批范围内）

- **第 5 批 · 主题设置页本身 + 高频设置页** — ✅ 已完成（顺带修掉了风格预览卡的 bug，见 5.5）
  `lib/pages/theme_settings_page.dart`（**吃自己的狗粮，优先级应该拉高**——用户选纸墨风格
  的入口页自己却满屏硬编码圆角，观感上最讽刺）、`lib/pages/settings_page.dart`、
  `lib/pages/category_settings_page.dart`、`lib/pages/hitokoto_settings_page.dart` 及
  `_layout_sections` / `_widgets` / `_info_sections`、`lib/pages/preferences_detail_page.dart`、
  `lib/pages/local_ai_settings_page.dart`、`lib/pages/smart_push_settings_page_*_sections.dart`、
  `lib/widgets/local_ai/*`、`lib/widgets/city_search_widget.dart`、`lib/widgets/update_dialog.dart`

- **第 6 批 · 同步/备份/存储 + 引导/帮助/关于（低频深处）**
  `lib/pages/note_sync_page.dart`、`lib/pages/webdav_sync_page.dart`、
  `lib/pages/storage_management_page.dart`、`lib/pages/backup_restore_page.dart`、
  `lib/pages/logs_page.dart`、`lib/services/apk_download_service.dart`、
  `lib/pages/onboarding_page.dart`、`lib/widgets/onboarding/page_views.dart`、
  `lib/widgets/onboarding/preferences_page_view.dart`、`lib/pages/user_guide_page.dart`、
  `lib/pages/license_page.dart`、`lib/pages/custom_feedback_page.dart`、
  `lib/pages/emergency_pages.dart`、`lib/widgets/enhanced_markdown_widgets.dart`

## 三、明确不动 / 需要你二次确认

**按你的要求排除，本审计跳过：**
- `lib/pages/annual_report_page.dart`、`lib/pages/ai_report/`
- `lib/widgets/ai/thinking_widget.dart`、`lib/widgets/ai/tool_progress_panel.dart`、
  `lib/pages/ai_assistant/ai_assistant_page_ui.dart` 聊天气泡部分——
  **写这份审计期间，另一子代理已经把这部分迁移完成**（`git status` 可见这几个文件已改动，
  `AppTheme.chatBubbleRadius` 已删除，气泡圆角改读 `AppShapeTokens.of(context).dialogRadius`，
  面板内部圆角改读 `buttonRadius`）。本文档第五节涉及这三个文件的地方已按新状态更正，
  不再需要处理。
- `lib/widgets/quote_item_widget.dart`、`lib/widgets/sliding_card.dart`、`lib/theme/theme_style.dart`
  ——同样在 `git status` 里显示已被改动（纸张横线纹理 `PaperRuleBackground` 已接入），
  你正在改，本文档不涉及。

**审计中发现、建议你确认的灰色地带：**

1. **`lib/pages/ai_annual_report_webview.dart`**——文件名和路径不在排除清单字面范围内，
   但内容就是渲染年度报告 HTML，唯一调用方是
   `lib/pages/ai_analysis_history_page_clean.dart:845`（点"年度报告"按钮才会跳进去）。
   按功能归属它应该和 `annual_report_page.dart` 一起算"已废弃、不动"，但字面指令没提它，
   本文档先不列入任何一批，等你确认。
2. **疑似死代码集群**：`lib/widgets/markdown_message_bubble.dart`、
   `lib/widgets/typing_indicator_bubble.dart`、`lib/utils/chat_theme_helper.dart`、
   `lib/utils/chat_markdown_styles.dart`（仅被 `markdown_message_bubble.dart` 引用）。
   全仓库搜索 `MarkdownMessageBubble(` / `TypingIndicatorBubble(` / `ChatThemeHelper(`
   除定义处外**没有任何调用点**。如果确认是死代码，直接删除比迁移更划算；如果是预留将来要用的，
   再按第 4 批的方式迁移。本文档不把它们排进任何一批。

## 四、明确不该跟随主题的装饰性元素

以下即便有硬编码圆角/阴影，也不建议改成 `AppShapeTokens`，理由分别标注：

- **色板选色圆点**（`lib/widgets/accessible_color_grid.dart:106/112` 的 `circular(21)`、
  `lib/pages/theme_settings_page.dart` 里 `BoxShape.circle` 的取色/风格预览圆点、
  `lib/pages/note_editor/editor_color_and_media.dart:97` 的颜色选择圆点）——
  色块本身画成接近圆形是"色板"这个交互控件的通用语言，不是卡片/按钮，不该跟纸墨的方正化走。
- **胶囊/圆形进度环、录音按钮**（`lib/widgets/local_ai/voice_input_overlay.dart` 的
  `BoxShape.circle` 麦克风按钮和外圈光晕、`lib/widgets/local_ai/ocr_capture_page.dart:115`
  的快门圆按钮、`lib/widgets/local_ai/{ocr,voice}_result_sheet.dart` 里 `circular(999)`
  的胶囊芯片）——功能性圆形/胶囊控件，和卡片语义无关。
- **分段进度条**（`lib/pages/storage_management_page.dart:541/622/1075` 的
  `circular(2)`/`circular(4)`，`lib/services/apk_download_service.dart:608` 的下载进度条
  `circular(8)`）——`LinearProgressIndicator`/进度条本身的小圆角是进度条控件的通用做法，
  不是"表面"。
- **节日彩蛋**（`lib/widgets/anniversary_animation_overlay.dart` 全部——彩带、气球、
  庆祝卡片的圆角和光晕）——特效层，低频出现，硬编码是刻意的视觉效果不是表面令牌能表达的。
- **小徽章/标签**（`lib/widgets/ai/experimental_badge.dart:39` 的
  `compact ? 6 : 8`、多个页面里 `withValues(alpha: 0.1~0.15)` 的图标背景色块用的
  `circular(8)`/`circular(10)` 小圆角）——这类"图标底色块"更接近 AGENTS.md 里说的
  "纯装饰性小元素（徽章、色块）可自行取值"，可以不改，但如果后续要做也不会出错
  （风险最低，可以顺手做，不必单开一批）。

## 五、按可见度排序的详细清单

以下每个文件给出行号列表、当前值/建议令牌、风险提示。同一文件内模式雷同的行合并说明。

### 5.1 首页 / 记录页（第 1 批）

**`lib/pages/home_page.dart`**
- `:91` `boxShadow: AppTheme.defaultShadow` → 纸墨/素笺下应该用近乎无投影的阴影，
  但目前 `AppShapeTokens` 没有现成的 `List<BoxShadow>` getter，需要先补令牌（见六）。
  这一处的 `borderRadius` 本身已经在用 `AppShapeTokens.of(context).cardRadius`（`:90`），
  只有 `boxShadow` 没跟上。
- `:992` `borderRadius: BorderRadius.circular(16)` + `:993`
  `boxShadow: AppTheme.accentShadow` → FAB 长按菜单容器。`:1004-1005`
  `shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))` 是 FAB 自身形状。
  **风险提示**：FAB 是否要跟随 `buttonRadius` 需要你判断——FAB 传统上是独立于卡片系统的强调
  控件，Material 3 默认就是大圆角/圆形，跟太死可能反而奇怪，建议单独决定，不要和其它按钮
  一刀切。
- `:1027` `elevation: 0`（底部导航栏）——已经是 0，不用动，列出仅供确认无遗漏。

**`lib/pages/home/daily_prompt_panel.dart`**
- `:251` `borderRadius` 已用令牌（正确）；`:252` `boxShadow: AppTheme.defaultShadow` →
  同 home_page，需要先有阴影令牌。这是首页顶部"每日一言"卡片，**可见度最高**。

**`lib/widgets/note_list/note_list_items.dart`**
- `:101` 底部弹窗 `shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(...))`
  ——**`const` 上下文**，圆角数值需要确认（截断在 grep 里未看到具体数字，建议直接打开确认，
  如果引用 `AppShapeTokens` 必须先去掉 `const`）。
- `:144/154/164` 输入框 border 已用 `AppShapeTokens.of(context).inputRadius`（正确）。
- `:235-238`、`:297-300` 卡片 `borderRadius` 已用令牌，但 `boxShadow: [...]` 是手写
  `BoxShadow`，同样属于"阴影没跟令牌"。
- `:677` InkWell 的 `borderRadius` 已用 `cardRadius` 令牌（正确）。
  **这个文件圆角基本已经迁移完，唯一缺口是 boxShadow。**

**`lib/widgets/note_list/note_list_filters.dart`**（记录页顶部筛选栏，天天可见）
- `:195` 清除按钮 `circular(10)`、`:196` `Border.all` 未给 width
- `:208` InkWell `circular(10)`
- `:249` 已用 `AppShapeTokens.of(context).cardRadius`（正确，标签面板容器）
- `:266` 标签 chip `circular(10)`
- `:309` 分类 chip `circular(10)`
→ 建议统一换成 `AppShapeTokens.of(context).buttonRadius`（这些是可点击的过滤 chip，
不是卡片）。**风险**：chip 类通常允许比卡片更小的圆角，若统一到 `buttonRadius` 观感要过一遍
真机确认，不要盲改。

**`lib/widgets/quote_card_helpers.dart`**
- `:69` `circular(14)`、`:70` `Border.all` 未给 width →
  这是笔记卡片内部的"高亮标记/标签块"辅助函数，建议换 `buttonRadius` 或
  `cardRadius`（取决于视觉权重，需要看调用处）。

**`lib/widgets/weather_widget.dart`**
- `:29` `Card(elevation: 2, ...)` → 覆盖了 `CardThemeData` 按风格算好的 0 投影，
  纸墨/素笺下这张天气卡会继续带 Material 阴影。建议删掉显式 `elevation`，让 `CardTheme`
  接管，或换成 `AppShapeTokens.of(context).shadowOpacity` 驱动的自定义阴影。
- `:63` `circular(12)`（卡片内图标背景色块）→ 可保留（见四「小徽章」一类），也可顺手换
  `buttonRadius`。

**`lib/widgets/hitokoto_widget.dart`**
- `:17` `Card(elevation: 2, ...)` → 同上，覆盖主题投影。

### 5.2 编辑器 / 快速添加（第 2 批）

**`lib/pages/note_editor/editor_build.dart`**
- `:162` 图片容器 `circular(8)` + `:163` `Border.all` 未给 width
- `:261-264` 卡片 `borderRadius` 已用 `cardRadius` 令牌（正确），但 `boxShadow: [...]`
  手写，同 home_page 问题
- `:303` 进度条 `circular(4)` → 建议保留（进度条类，见四）

**`lib/pages/note_editor/editor_color_and_media.dart`**
- `:58` `circular(16)`（颜色选择面板容器）→ 应该是 `cardRadius`
- `:97` 颜色圆点 `circular(21)` → 保留（色板圆点，见四）
- `:107` `boxShadow: [...]` 手写

**`lib/pages/note_editor/editor_metadata_dialog.dart`**（笔记元数据编辑，`showModalBottomSheet`）
- `:11-14` 底部弹窗 `shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(...))`
  ——需要确认具体数值，建议换 `AppShapeTokens.of(context).dialogRadius`
- `:45` `circular(2)`（拖拽把手条）→ 保留，装饰性
- `:97/121/263/301` 输入框已用 `inputRadius` 令牌（正确）
- `:151-153/262-264/397` 卡片已用 `cardRadius` 令牌（正确）
- `:183` `circular(16)`（选中态色块背景）→ 建议换 `cardRadius` 或 `buttonRadius`
- `:203-204`、`:274-275` `ListTile` 的 `shape: RoundedRectangleBorder(borderRadius:
  BorderRadius.all(...))` ——需要看具体数值，大概率也该换令牌

**`lib/pages/note_editor/editor_metadata_ai_section.dart`**
- `:64` 已用 `cardRadius`（正确）
- `:182-183/189-190` 已用 `cardRadius`（正确）
- `:234` `circular(8)`（代码块背景）→ 可保留（markdown 代码块，通常允许独立小圆角）

**`lib/pages/note_editor/editor_metadata_location_section.dart`**
- `:44` 已用 `cardRadius`（正确，仅列出确认无遗漏）

**`lib/widgets/add_note_dialog.dart` / `add_note_dialog_parts.dart`**（快速记录弹窗，高频入口）
- `add_note_dialog.dart:2382` `circular(9)` + `:2383` `Border.all`（颜色选择器里的小方块，
  数值 9 很怪，可能是历史遗留，建议顺手统一）
- `add_note_dialog.dart:2446` `circular(8)`（工具栏容器）
- `add_note_dialog.dart:2471` InkWell `circular(12)`
- `add_note_dialog_parts.dart:336` `circular(8)`（提示条容器）
→ 都建议换 `buttonRadius` 或 `cardRadius`，具体看视觉层级。

**`lib/widgets/unified_media_import_dialog.dart`**
- `:99`、`:160` 两处 `circular(8)`（媒体导入选项卡片）→ 建议 `cardRadius`

**`lib/widgets/note_filter_sort_sheet.dart`**
- `:230-238` `Card(elevation: 0, shape: RoundedRectangleBorder(borderRadius:
  AppShapeTokens.of(context).cardRadius))` ——已经在用令牌，**但 `color: Colors.white`
  硬编码浅色背景**是另一类问题（AGENTS.md 明令禁止），本文档只记录形状部分已正确，颜色问题
  建议一并顺手修。

### 5.3 分享卡片 / 媒体（第 3 批）

**`lib/widgets/svg_card_widget.dart`**（笔记生成分享图，长按笔记卡片可触发，较高频）
- `:47-48`、`:57-59`、`:134-135`、`:248-249` 已用 `AppShapeTokens.of(context).cardRadius`
  （正确）
- `:49` `boxShadow: [...]` 手写
- `:133` `Border.all(color: Colors.grey[300]!, width: 1)`——**同时是颜色硬编码问题**
  （`Colors.grey` 被 AGENTS.md 明令禁止），描边宽度也没用 `borderWidth` 令牌
- `:168` `circular(4)`（小色块）→ 可保留
- `:247` `Border.all(color: Colors.red[200]!, width: 2)`——同上，颜色 + 宽度都硬编码
- `:476-478` 按钮已用 `buttonRadius`（正确）
- `:619-621` 弹窗已用 `dialogRadius`（正确），`:622` `boxShadow: [...]` 手写
→ **这个文件形状令牌大部分已经接好，剩下的是阴影和硬编码颜色**（后者超出本次审计范围，
但顺手一起改成本更低）。

**`lib/widgets/media_player_widget.dart`**
- `:448/492/521/561` 四处已用 `cardRadius`（正确）
- `:449/522/562` `Border.all` 未给 width
- `:493/565` `boxShadow: [...]` 手写
- `:584` `circular(8)`（播放按钮背景）→ 可保留或换 `buttonRadius`

**`lib/widgets/accessible_color_grid.dart`**
- `:54` `circular(16)`（整个色板面板容器）→ 应该是 `cardRadius`，这一处不是色块本体，
  是外层面板，**不属于四里排除的"色板圆点"**
- `:106/112` 色块圆角 `circular(21)` → 保留（见四）
- `:121` `boxShadow: [...]` 手写（选中色块的高亮投影，可保留，属于选中态强调，不是表面阴影）

**`lib/services/clipboard_service.dart`**（选中文字后的浮动操作条，编辑器内高频触发）
- `:337-338` 已用 `AppShapeTokens.of(context).dialogRadius`（正确）
- `:339` `boxShadow: AppTheme.defaultShadow` → 同前，需要阴影令牌

**`lib/utils/quill_editor_extensions.dart`**（编辑器内嵌图片）
- `:354` `circular(12)`（图片圆角裁切）
- `:550` `circular(12)`（图片操作面板背景）
→ 建议换 `cardRadius`

**`lib/widgets/quill_enhanced_toolbar_unified.dart`**
- `:268/271/276` 三处 `circular(4)`（工具栏按钮）→ 工具栏小按钮，建议换 `buttonRadius`
  或保留（优先级低，Quill 工具栏本身是密集小控件区）

### 5.4 AI 助手页（第 4 批，注意和另一子代理的边界）

**`lib/pages/ai_assistant_page.dart`**
- `:391` `circular(8)`（markdown 代码块背景）→ 可保留

**`lib/pages/ai_assistant/ai_assistant_page_ui.dart`**
- `:122` `Material(elevation: 2, shape: const CircleBorder())` → 圆形按钮，保留
- `:514` 已用 `cardRadius`（输入框外壳，**不是气泡**，属于本次审计范围）
- `:519` `boxShadow: [...]` 手写
- **消息气泡部分（原 `:350` 附近的 `bubbleRadius`）已由另一子代理迁移完成**
  （现在读 `AppShapeTokens.of(context).dialogRadius`，注释写明"气泡圆角随主题风格变化，
  不能是 const"），不在本文档范围，也不需要再处理。

**`lib/pages/ai_assistant/session_history_page.dart` / `session_history_page_content.dart`**
- `session_history_page.dart:204` 输入框已用 `inputRadius`（正确）
- `session_history_page_content.dart:163/170` 已用 `cardRadius`（正确）
- `session_history_page_content.dart:210` `circular(8)`（会话条目里的图标背景块）→ 可保留

**`lib/widgets/ai/ai_card_parts.dart`**
- `:24-26` `Card` 已用 `cardRadius` 令牌（正确）
- `:70` `circular(8)`（图标背景块）→ 可保留

**`lib/widgets/ai/experimental_badge.dart`**
- `:39` `compact ? 6 : 8` → 徽章，保留（见四）
- `:131` `Dialog(elevation: 6, ...)` → 覆盖投影，且这个 Dialog 未见 `shape`/`borderRadius`
  设置，建议连圆角一起补上 `dialogRadius`
- `:227` `circular(8)`（InkWell 命中区域）→ 可保留
- `:273-274` 按钮已用 `buttonRadius`（正确）
- `:310` 卡片已用 `cardRadius`（正确）

**`lib/widgets/ai/slash_commands_menu.dart`**（`/` 命令菜单，AI 输入区高频交互）
- `:103-109` 已用 `cardRadius`，但 `:109` `boxShadow: [...]` 手写
- `:270` `circular(2)`（选中态指示条）→ 可保留
- `:375` 输入框已用 `inputRadius`（正确）

**`lib/widgets/ai_options_menu.dart`**（AI 选项底部弹窗）
- `:70-71` `showModalBottomSheet` 的 `shape` 用 `BorderRadius.vertical(...)`，
  需要确认具体数值是否该走 `dialogRadius`
- `:166` `circular(2)`（拖拽把手）→ 保留
- `:179` `circular(12)`（选项图标背景）→ 可保留
- `:215-219` `Card(elevation: 0, shape: ...)` 已用 `cardRadius`（正确）
- `:228` InkWell 已用 `cardRadius`（正确）
- `:240` `circular(12)`（图标背景块）→ 可保留

**`lib/widgets/streaming_text_dialog.dart`**（AI 生成结果的流式预览弹窗，高频）
- `:131-133/138-139` 已用 `dialogRadius`（正确），`:135` `elevation: 8` → 覆盖投影
- `:186` `circular(12)`（渐变装饰条）→ 可保留
- `:270-271/277` 已用 `cardRadius`（正确）
- `:322` `circular(8)`（代码块）→ 可保留
- `:354` `circular(2)`（进度指示条）→ 保留
- `:430` `circular(12)`（提示条背景）→ 建议换 `cardRadius`
- `:475-477` 按钮已用 `buttonRadius`（正确）

**`lib/widgets/enhanced_ai_loading_dialog.dart`**
- `:80/172` `Dialog(elevation: 0, ...)` — 已经是 0，不用动
- `:86/178` 已用 `dialogRadius`（正确）
- `:87/179` `boxShadow: [...]` 手写

**`lib/widgets/chat_input_suggestions.dart`**
- `:44` `elevation: 2` → 覆盖投影（建议按钮场景确认是否真的需要投影强调）

**`lib/pages/ai_analysis_history_page_clean.dart`**
- `:245` `boxShadow: AppTheme.defaultShadow`（注释写着 "Use AppTheme" 但 `:243`
  的 `borderRadius` 已经用了 `AppShapeTokens.of(context).dialogRadius`，说明这处是
  上一轮迁移漏改阴影的典型例子）
- `:259` `circular(2)`（进度/指示条）→ 保留
- `:362/380` `circular(8)`（卡片内小色块）→ 可保留
- `:459/467` 已用 `cardRadius`（正确）
- `:475` `circular(10)`（图标背景）→ 可保留
- `:1041-1042` 输入框已用 `inputRadius`（正确）
- `:1076` `Card(elevation: 2, shape: RoundedRectangleBorder(borderRadius:
  BorderRadius.circular(AppShapeTokens.of(context).cardRadius)))` ——**圆角已经用了令牌，
  但 `elevation: 2` 单独覆盖投影**，是"圆角改了、投影忘了"的另一个例子
- `:1094` InkWell 已用 `cardRadius`（正确）
- `:1112` `circular(8)`（进度条内部）→ 可保留
- `:1202` `circular(12)`（次级信息块）→ 可保留

**`lib/pages/ai_settings_page.dart`**
- `:111` 输入框已用 `inputRadius`（正确）
- `:584` 已用 `buttonRadius`（正确）
→ 这个文件已经迁移完，仅列出确认无遗漏。

**`lib/pages/ai_provider_edit_page.dart`**
- `:416/535-536` 输入框已用 `inputRadius`（正确）
- `:658` 已用 `buttonRadius`（正确）
→ 同样已迁移完。

### 5.5 主题设置页本身 + 高频设置页（第 5 批）

**`lib/pages/theme_settings_page.dart`**（**优先级建议拉高**：用户切换风格的入口页自己
没吃到自己的令牌，观感上最容易被发现）
- `:75-78`、`:102-105`、`:153-156`、`:206-209` 四处风格预览卡片
  `Card(elevation: 1, shape: RoundedRectangleBorder(borderRadius:
  BorderRadius.circular(AppShapeTokens.of(context).cardRadius)))`——**圆角已经用令牌，
  但 `elevation: 1` 硬编码**，纸墨风格预览卡自己却带 Material 投影，属于最值得先修的一处
- `:274/308` `circular(8)`（提示/说明色块）→ 可保留
- `:386/389` 已用 `cardRadius`（风格选项容器，正确）
- `:400-401` 已用 `buttonRadius`（正确）
- `:450/462-463/500/545` 四处 `circular(12)`（颜色/风格选项的 InkWell 与容器）→
  建议统一换 `buttonRadius` 或 `cardRadius`（这几处目前不一致，12 是 material 的
  `buttonRadius` 数值，但纸墨下 `buttonRadius` 是 4、素笺是 2，硬编码 12 等于让选择器
  UI 在纸墨风格下依然是圆的——**这是本次审计里"最讽刺"的一类**）
- `:521` `boxShadow: [...]`（选中态取色圆点高亮）→ 可保留，圆形选中态属于强调，不是表面

**`lib/pages/settings_page.dart`**
- `:548` `circular(4)` + `:549` `Border.all`（提示色块）→ 可保留
- `:724` `circular(6)`（图标背景）→ 可保留
- `:808` `circular(12)`（列表项装饰）→ 建议换 `buttonRadius`
- `:1315-1317` 按钮已用 `buttonRadius`（正确）

**`lib/pages/category_settings_page.dart`**（标签/分类管理，中频）
- `:53-55` 已用 `cardRadius`（正确）
- `:73-74/338-339/885-886` 输入框已用 `inputRadius`（正确）
- `:84-85/95-96/245/439/530` 已用 `cardRadius`（正确，图标/颜色选择器容器）
- `:242-246` `Card(elevation: 0, shape: ...)` 已用 `cardRadius`（正确）
- `:680` `circular(12)`（分类图标预览背景）→ 建议换 `cardRadius`
- `:710/964/1032` `circular(8)`（选中态色块）→ 可保留
→ 这个文件圆角大部分已迁移，遗留的都是小色块，优先级不高。

**`lib/pages/hitokoto_settings_page.dart` 及 `_layout_sections`/`_widgets`/`_info_sections`**
- `hitokoto_settings_page.dart:234-236` SnackBar 已用 `buttonRadius`（正确）
- `hitokoto_settings_page.dart:413-414` 已用 `cardRadius`（正确）
- `hitokoto_settings_page_layout_sections.dart:27-28` 已用 `cardRadius`，但
  `:28` `boxShadow: AppTheme.lightShadow` → 阴影没跟上，和 home_page 同类问题
- `hitokoto_settings_page_layout_sections.dart:39` `circular(12)`（图标背景）→ 可保留
- `hitokoto_settings_page_layout_sections.dart:103/191/245` 已用 `cardRadius`（正确）
- `hitokoto_settings_page_widgets.dart:17/21/100/104` 已用 `buttonRadius`/`cardRadius`
  （正确）
- `hitokoto_settings_page_widgets.dart:80` `elevation: isSelected ? 2 : 0` → 覆盖投影，
  选中态用投影强调是常见做法，但纸墨风格下更合适的做法是用 `borderWidth` 加粗描边而不是
  加投影，建议改成描边强调
- `hitokoto_settings_page_info_sections.dart:17/62` 已用 `cardRadius`（正确）

**`lib/pages/preferences_detail_page.dart`**（偏好来源选择等，中频）
- `:82-84` 已用 `cardRadius`，`:84` `boxShadow: [...]` 手写
- `:98/276` `circular(12)`（下拉菜单圆角）→ 建议换 `inputRadius` 或 `buttonRadius`
- `:245/400/551/749/872` `circular(8)`（选项色块）→ 可保留
- `:508-511/514` 已用 `cardRadius`，`:514` `boxShadow: [...]` 手写
- `:524` 已用 `cardRadius`（正确）
- `:608/611` 已用 `buttonRadius`（正确）
- `:640-641` 已用 `cardRadius`（正确）
- `:672` `shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(...))`——
  需要确认数值
- `:809-810/978-979` 输入框已用 `inputRadius`（正确）
- `:965` `circular(10)`（搜索框内色块）→ 可保留

**`lib/pages/local_ai_settings_page.dart`**（本地 AI/OCR/语音设置）
- `:29` `elevation: 0`（AppBar，已是 0）
- `:50` `circular(12)`（状态卡片）→ 建议换 `cardRadius`
- `:89-90` 已用 `cardRadius`（正确）
- `:105/173` `circular(12)`（图标背景/选项容器）→ 可保留或换 `cardRadius`
- `:138-141/159-160` 已用 `cardRadius`（正确）
- `:392` `circular(8)`（图标背景）→ 可保留
- `:410-414` `Card(elevation: 0, shape: ...)` 已用 `cardRadius`（正确）
- `:453` `circular(10)`（状态标签）→ 可保留

**`lib/pages/smart_push_settings_page_basic_sections.dart` / `_custom_sections.dart` /
`_misc_sections.dart`**（智能推送设置）
- 三个文件里 `Card(elevation: 0, shape: RoundedRectangleBorder(borderRadius:
  BorderRadius.circular(AppShapeTokens.of(context).cardRadius)))` 的模式反复出现且已正确
  （basic:13-15/153-154、custom:14-15/181-182/268-269、misc:203-204），仅列出确认无遗漏
- `basic_sections.dart:36` `circular(16)`（大图标容器）→ 建议换 `cardRadius`
- `basic_sections.dart:234/236` `circular(12)`（列表项容器/InkWell）→ 建议统一 `cardRadius`
- `basic_sections.dart:249` `circular(10)`（图标背景）→ 可保留
- `basic_sections.dart:285/632` `circular(4)`（小色块）→ 可保留
- `basic_sections.dart:500/554/651` `circular(8)`（InkWell/色块）→ 部分建议换
  `buttonRadius`（`:500/554` 是可点击区域），`:651` 可保留
- `basic_sections.dart:354` 已用 `cardRadius`（错误提示卡片，正确）
- `custom_sections.dart:68` `circular(12)`（选项容器）→ 建议 `cardRadius`
- `custom_sections.dart:79` `circular(10)`（图标背景）→ 可保留
- `misc_sections.dart:244` `circular(12)`（InkWell 命中区）→ 建议 `cardRadius`
- `misc_sections.dart:254` `circular(12)` + `Border.all` 未给 width（子容器）→
  建议 `cardRadius`

**`lib/widgets/local_ai/*`**
- `ocr_capture_page.dart:27` `elevation: 0`（已是 0）；`:43` `circular(8)`
  （提示条背景，可保留）；`:115-121` 圆形快门按钮 + 投影 → 保留（功能性圆形控件）
- `ocr_result_sheet.dart:72`、`voice_result_sheet.dart:73` `circular(999)`
  （胶囊芯片）→ 保留
- `voice_input_overlay.dart:143/158/183` 圆形麦克风按钮/光晕 → 保留；
  `:222-224` `circular(cardRadius)` 已用令牌（正确）；`:286` `circular(2)`
  （音量指示条）→ 保留
- `image_text_selector.dart:95` `Border.all` 未给 width（OCR 文字选择框）→
  低优先级

**`lib/widgets/city_search_widget.dart`**（天气/一言的城市选择，中频）
- `:132/145` `elevation: 0`（已是 0）
- `:246/251/256` 输入框已用 `inputRadius`（正确）
- `:282` `circular(8.0)`（结果项高亮色块）→ 可保留

**`lib/widgets/update_dialog.dart`**（更新提示弹窗，每次有新版本都会弹，其实很高频）
- `:96/279` `circular(2)`（进度条/分隔条）→ 保留
- `:120-122/195-197/303-305` 已用 `cardRadius`，`Border.all(color: ...withAlpha(50))`
  未给 width（三处一致，可以合并处理）
- `:159` `circular(12)`（版本号徽章）→ 可保留
- `:465` `circular(6)`（markdown 引用块）→ 可保留
- `:489-491` `circular(8)` + `Border.all` 未给 width（markdown 代码块）→ 可保留

### 5.6 同步 / 备份 / 存储（第 6 批前段）

**`lib/pages/note_sync_page.dart`**
- `:793-794` 已用 `cardRadius`；`:799` `Border.all`；`:805` `boxShadow: isSendingToThis
  ? [...] : null` 手写（发送中状态强调投影，可保留为交互反馈，不算表面阴影）
- `:818-819` 已用 `cardRadius`（正确）
- `:1064` `circular(8)`（进度条裁切）→ 保留
- `:1099/1163` `circular(12)`（设备卡片内色块）→ 可保留
- `:1431` `circular(6)`（小标签）→ 可保留

**`lib/pages/webdav_sync_page.dart`**
- `:326/342` `elevation: 0`（AppBar，已是 0）
- `:366-369/490-493` `Card(elevation: 1, shape: ...)` 已用 `cardRadius`，
  但 `elevation: 1` 覆盖投影
- `:708-711` `Card(elevation: 2, shape: ...)` 已用 `cardRadius`，`elevation: 2` 同上问题
- `:715-717` 已用 `cardRadius`（渐变背景容器，正确）
- `:783/816` `circular(10)`（提示色块）→ 可保留
- `:917` `Card(elevation: 1, ...)` 未见 shape 设置 → 覆盖投影，且未显式给圆角
  （用的应该是主题默认 `CardTheme`，投影覆盖了但形状没覆盖，混合状态需要确认）

**`lib/pages/storage_management_page.dart`**
- `:499` `Card(elevation: 2, ...)` → 覆盖投影
- `:541/622/1075` `circular(4)`/`circular(2)`（进度条相关）→ 保留（见四）
- `:865` `circular(4)`（存储类型色块）→ 可保留

**`lib/pages/backup_restore_page.dart`**
- `:41` `AppBar(elevation: 0)`——已是 0，不用动，仅列出确认无遗漏

**`lib/pages/logs_page.dart`**
- `:307/333/358` `circular(8)`（日志条目色块）→ 可保留
- `:591-592` 输入框已用 `inputRadius`（正确）
- `:1044-1045` 已用 `cardRadius`（正确）

**`lib/services/apk_download_service.dart`**（更新下载进度浮层，中频）
- `:608` `circular(8)`（进度条裁切）→ 保留
- `:652` `circular(8)`（下载信息卡片）→ 建议换 `cardRadius`

### 5.7 引导 / 帮助 / 关于（第 6 批后段，低频）

**`lib/pages/onboarding_page.dart`**
- `:464` `Card(elevation: 2, ...)` → 覆盖投影（首次启动引导页，虽然低频但是新用户
  第一印象，可以酌情提前）
- `:664` `circular(20)`（选项卡片）→ 建议换 `cardRadius`
- `:696-698` 已用 `cardRadius`，`:697` `boxShadow: [...]` 手写

**`lib/widgets/onboarding/page_views.dart`**
- `:187-189` `circular(14)` + 手写 `boxShadow`（引导插画卡片）
- `:298/308/323` `circular(30)`（引导图片裁切/装饰）→ 装饰性强，可保留
- `:458-459` 已用 `cardRadius`（正确）
- `:511` `Card(elevation: isHighlight ? 8 : 2, ...)` → 覆盖投影
- `:517-518` 已用 `cardRadius`（正确）
- `:540` `circular(12)`（选中态背景）→ 建议换 `buttonRadius`
- `:590` `circular(8)`（图标背景）→ 可保留

**`lib/widgets/onboarding/preferences_page_view.dart`**
- `:172/225/347/406/479/488` 六处 `Card(elevation: 2, ...)` 或 `elevation: isSelected
  ? 2 : 1` → 全部覆盖投影，是这批里 `elevation` 硬编码最集中的文件
- `:598` `elevation: isSelected ? 2 : 1`（同上）
- `:623` `circular(12)`（偏好选项容器）→ 建议换 `cardRadius`
- `:674` 已用 `cardRadius`（正确）

**`lib/pages/user_guide_page.dart`**
- `:418` `elevation: WidgetStateProperty.all(0)`（已是 0）
- `:493-497` `Card(elevation: 0, shape: ...)` 已用 `cardRadius`（正确）
- `:516` `circular(12)`（章节图标背景）→ 可保留
- `:570` `circular(2)`（进度条）→ 保留

**`lib/pages/license_page.dart`**
- `:573-577` `Card(elevation: 0, shape: ...)` 已用 `cardRadius`（正确）
- `:584` InkWell 已用 `cardRadius`（正确）
→ 这个文件已经迁移完。

**`lib/pages/custom_feedback_page.dart`**
- `:116/147/171` 三处输入框已用 `inputRadius`（正确）
→ 这个文件已经迁移完，仅列出确认无遗漏。

**`lib/pages/emergency_pages.dart`**（异常兜底页，极低频，仅崩溃恢复时可见）
- `:215/417` `circular(8)`（状态色块）→ 优先级最低，可以不做

**`lib/widgets/enhanced_markdown_widgets.dart`**
- `:31/138` `circular(8)`（markdown 块）→ 可保留

**`lib/widgets/note_filter_sort_sheet.dart`** 已在 5.2 列出。

## 六、令牌缺口：阴影没有现成的 `List<BoxShadow>` getter

`AppShapeTokens` 目前只有 `shadowOpacity` 和 `shadowBlur` 两个数值字段
（`lib/theme/theme_style.dart`），本次审计中反复出现的
`boxShadow: AppTheme.defaultShadow`（14 处）和自绘 `boxShadow: [BoxShadow(...)]`
（约 25 处），**没有一个能直接替换成 `AppShapeTokens.of(context).xxxShadow`**，
因为这个字段不存在。

在迁移这些之前，建议先在 `AppShapeTokens` 上补一个方法或 getter，形如
`List<BoxShadow> shadow(ColorScheme colorScheme)`，用 `shadowOpacity`/`shadowBlur`
拼出和 `AppTheme.defaultShadow` 结构一致的阴影表（保留双层阴影的层次感，只是把不透明度和
模糊半径换成按风格算的值）。这一步不属于本次审计范围（审计不改代码），但**是后续任何一批
涉及 `boxShadow` 迁移的前置工作**，建议作为第 1 批的第一步先做掉，否则 14+25 处阴影会被
反复卡住。

## 七、注意事项（迁移时踩坑提示，摘自交接文档 + 本次审计观察）

- **`const` 上下文**：本次审计里唯一确认的 `const` 陷阱是
  `lib/widgets/note_list/note_list_items.dart:101`
  （`shape: const RoundedRectangleBorder(...)`）。改动前务必确认具体圆角数值和 `const`
  修饰符范围，`AppShapeTokens.of(context)` 不能进 const 表达式。
- **`part of` 文件**：`smart_push_settings_page_basic_sections.dart` /
  `_custom_sections.dart` / `_misc_sections.dart`、`hitokoto_settings_page_layout_sections.dart`
  / `_widgets.dart` / `_info_sections.dart` 都是 `part of` 文件（按交接文档提示，
  `part of` 声明可能不在首行），新增 import 要加到对应的库主文件
  （`smart_push_settings_page.dart` / `hitokoto_settings_page.dart`），不能加在 part 文件里。
- **"圆角改了、投影/elevation 忘了"是本次审计里最常见的半吊子迁移模式**：
  `home_page.dart:90-91`、`daily_prompt_panel.dart:251-252`、
  `clipboard_service.dart:337-339`、`hitokoto_settings_page_layout_sections.dart:27-28`、
  `ai_analysis_history_page_clean.dart:243-245`、`theme_settings_page.dart` 四张风格预览卡、
  `ai_analysis_history_page_clean.dart:1076`——都是 `borderRadius` 已经接了
  `AppShapeTokens`，但同一个 `BoxDecoration`/`Card` 里的 `boxShadow`/`elevation` 还是硬编码。
  说明上一轮迁移是按"搜 `BorderRadius.circular` 挨个改"做的，阴影字段被系统性漏掉，
  建议这一轮迁移时把"圆角+阴影+描边"当一组一起检查，不要只搜 `BorderRadius.circular`。
- **测试依赖**：搜索 `test/` 目录未发现任何测试对本文档列出的具体圆角数值（如 `circular(8)`、
  `circular(12)`）做硬断言；唯一和形状相关的测试是
  `test/theme/theme_style_contrast_test.dart`，它测的是颜色对比度和 `ThemeStyleForm` 本身的
  取值不变量，不测具体 widget 渲染出的圆角。也就是说本文档列出的 151 处修改**预期不会
  直接跑挂现有测试**，但改完仍建议跑一遍相关页面的 widget 测试（如果有）确认没有布局回归。
