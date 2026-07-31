# 探索页 → Thoughter 改造交接（2026-07-31）

这一轮从「进入探索页会来回闪」的 bug 开始，最后变成探索页的重新设计 +
Thoughter 入口的重做。下面按「已完成」「关键发现」「待决项」「下一步」四段写。

---

## 一、已完成

### 0. 闪烁修复（已并入 main）

进入探索页来回闪有四个独立成因，全部修掉：

| 成因 | 修法 |
|---|---|
| `_onDatabaseChanged` 每次 `notifyListeners` 都重查并把 `_isLoadingData` 置回 true，整页内容被转圈顶掉。启动/同步期间数据库会连着通知多次 | 300ms 防抖 + 加载令牌（丢弃过期结果）；刷新静默化，只有首次加载才显示整页 loading |
| 同一份数据签名下每次刷新都清空洞察重新流式生成，文字先消失再长出来 | `_insightSignature` 去重 |
| 流式洞察逐 chunk `setState`，整页重排抖动 | 120ms 节流缓冲（`_insightPending` + `_insightFlushTimer`） |
| 顶部时间选择器折叠改变内容高度 → 触发滚动通知 → 又翻回来，自振 | 先加了 350ms 冷却；**后来整个折叠机制被删掉了**（见下），这条不再存在 |

回归测试在 `test/widget/pages/ai_periodic_report_page_test.dart`。

### 1. 视觉重构（PR #440，已合并）

| 之前 | 之后 |
|---|---|
| 4 张 `elevation:2` 计数卡（两行） | 一条摘要带：笔记 / 字数 / 活跃 / 均字数，竖分隔线分列 |
| 3 张「最多」数字卡 | 3 个 chip（图标 + 值） |
| 7~10 个交错动画，400~1000ms，最长 1.4s 落位 | 一层 300ms 淡入 + 8px 上移 |
| 空周期叠 7 张全 0 卡 + 3 处「暂无」+ 插画 | 摘要带（四个 0）+ 一次空状态 |

三个「最多」改 chip 的理由：它们的值是**分类**（"午后"/"多云"/标签名）不是量，
套数字卡的 `headlineMedium` + `FittedBox` 会让中文标签一长就被缩成小字。

### 2. Thoughter 入口重做

洞察卡下方接三个快捷追问（追问这条 / 总结本周 / 随便聊聊），替掉原来那张独立的
「与 Thoughter 对话」卡；新增「最近对话」区（`getAgentSessions()` +
`getSessionOverviews()`，列最近两条，点击 `AIAssistantPage(session:)` 深链回去，
「全部」通往 `SessionHistoryPage(noteId: '')`）。

### 3. 日期选择器重做

删掉顶部那张「时间范围」卡片，周期选择改成挂在「数据概览」标题右侧的一枚 chip
（下拉：本周/本月/本年/选择日期）。三个理由：

- 全页都是填充容器，只有它用描边卡片 + 自带标题行，是唯一一块旧版语言
- 折叠态「周 - 7月27日 - 8月2日」和紧挨着的「数据概览」副标题**完全重复**
- 展开态占近 300px，里面填充底色的日历方块是全页最重的元素，可它只是个筛选器

随之删掉滚动折叠那整套机制（`NotificationListener` + 冷却 + `AnimatedContainer`）。

### 4. 首页每日思考的 Thoughter 入口

标题行右侧一枚 ✨ 按钮，带着当天的提示进入 Thoughter。

---

## 二、关键发现（这些不在代码里，翻代码翻不出来）

### `includedInContext` 是个坑

`ai_service.dart:1208` / `:1254` 构造模型上下文时按 `m.includedInContext` 过滤。
而 `AIAssistantPage` 的几处欢迎消息（`ai_assistant_page_session.dart:250/272/385`、
`ai_assistant_page_agent.dart:327`、`ai_assistant_page.dart:280`）都是
`includedInContext: false`。

**后果**：探索页原本通过 `exploreGuideSummary` 把洞察传过去，以为 agent 拿到了
上下文——实际那段文字只是显示给用户看的装饰，模型从来没收到过。所以第一版
「追问这条」发出去，agent 不知道「这条」是什么。

**解法**：新增 `AIAssistantPage.openingMessage`——作为 Thoughter 的第一句显示，
`role: 'assistant'`，**`includedInContext` 用默认的 true**。调用方手上已有现成
正文（每日提示、周期洞察）时用它，既不用再花一次生成，模型也确实知道开场说了什么。

`exploreGuideSummary` 保留但不再承担传上下文的职责。

> 遗留：`openingMessage` 用 `persist: true` 追加，但 `_appendMessage` 里
> `_currentSessionId` 此时还是 null（会话在首条消息时才建），所以实际没落库。
> 活着的会话里 `_messages` 有它、上下文也有它；但如果用户杀掉重进这个会话，
> 开场白会丢。要彻底解决得让 explore 入口提前建会话。

### 探索页入口没有会话连续性

`_initServicesAndLoad` 里只有 `note` 入口会 `getLatestSessionForNote` 恢复会话，
explore 分支直接落到「留空，首条消息时再建」。所以从探索页进 Thoughter 永远是
白纸一张，昨天聊到一半的要点两层才能翻回来。

这就是为什么「最近对话」区比快捷 chips 更重要——它解决的是连续性，不是入口位置。

### 生成中点击入口怎么办

洞察流 / 每日提示流都由各自的页面 state 持有。跳到 Thoughter 页**不会中断生成**
（探索页在 IndexedStack 里活着，首页面板也活着），回来就是完整的；但流**没法
"继承"到 Thoughter 页继续**——那需要把流的所有权提到 service 层，是个架构改动。

当前策略：**生成中禁用入口**。
- 探索页：`hasInsight = insight.isNotEmpty && !_insightLoading`
- 首页：`_canAskThoughter = !_isGeneratingDailyPrompt && text.isNotEmpty`

理由：半截文本带进对话，Thoughter 会看到一句没说完的话。

### 现成可复用的 API（省得再翻一遍）

- `AIAssistantPage.initialQuestion` — **会自动发送**（`_initServicesAndLoad` 里
  直接 `_handleSubmitted`），传进去等于替用户问出第一句
- `AIAssistantPage.session` — 深链回某次会话
- `SessionHistoryPage` — 独立页，`noteId: ''` 时走 `getAgentSessions()`，
  可以直接 push，不必绕经助手页
- `ChatSessionService.getAgentSessions()` / `getSessionOverviews()`
- `ChatSessionService` 是全局 provider（`buildAppProviders`），但**测试里没注册**，
  所以探索页读它是 try/catch 静默降级的

---

## 三、待决项

### 收藏红心的 `Colors.red.shade400`（全局）

AGENTS.md 禁 `Colors.*`，但这个色值在三处用着：
`quote_item_widget.dart:1155`、`home_note_mutation_actions.dart:123`、
`report_overview.dart` 的 `_favoriteAccent`。单改一处只会造成不一致。

`AppSemanticColors` 目前只有 success/warning，error 复用 `colorScheme.error`——
但收藏红心不是「错误」语义，没有现成槽位。需要决定：加一组 `favorite` 语义色并
统一迁移三处，还是把红心明确记为例外。

### 字数按 UTF-16 码元计数

`quote.content.length` 是既有逻辑。中文没问题，但英文语境下把字符数标成 "words"
不准。修它要动 l10n 单位词条和统计口径，是独立改动。

### 收藏预览的空 `onTap`

`report_overview.dart` 的 `_buildFavoritePreviewChip`，点了只有 `HapticFeedback`
没有任何反应，注释写着「可以添加跳转到笔记详情的逻辑」。既有代码，排在下一步。

---

## 四、下一步

### 探索页剩下的

1. 笔记预览接真跳转（顺带解决上面那个假 `onTap`）
2. 每条笔记预览加「问 Thoughter」入口——和「追问这条」同一个模式：带具体上下文
   进去，而不是又一个泛泛的「打开 AI」

### 底部常驻输入条（曾经砍掉，可能要捡回来）

原计划有一条贴底的伪输入框。砍掉的理由：摘要带瘦身后页面约 1.5 屏，洞察卡和
快捷 chips 已在首屏；而且 `home_page` 的 `centerDocked` FAB 会和它打架。

若要捡回来：`extendBody` 没开，body 不伸到导航栏下面，输入条挂在探索页自己
Scaffold 的 `bottomNavigationBar` 上即可，不用碰毛玻璃；但 FAB 冲突仍需处理
（隐藏 / 换语义 / 挪位）。

### AI 页（Thoughter）设计

**尚未开始讨论。** 建议从干净的上下文开始——`AIAssistantPage` + 5 个 part 文件 +
agent 工作流，比探索页大得多。已知的相关背景：

- `THOUGHTER_ISSUES_REPORT.md`（仓库根，未跟踪）里有 32 个问题，5 个 P0 未修：
  fail-fast、假取消、死工具、上下文不裁剪、卡片全灰
- `fullNotesContent` 未裁剪就整个喂给 AI，和上面「上下文不裁剪」是同一个问题，
  年度周期笔记多了会爆 token
- 洞察卡是纯文本一段，没有重新生成 / 复制 / 反馈；AI 生成和本地兜底两条路径的
  产出外观完全一样，用户分不出来

### 真机验证（一直没做）

整轮改动**没有编译过、没上过真机**，只有 widget 测试 + `flutter analyze`。
重点看：

- `PopupMenuButton` 的弹出位置，以及周期 chip 在「本年」这种长名下的宽度
- `SessionHistoryPage` 的 `onSelect` 里先 pop 再 push 的导航栈行为
- 从助手页返回后刷新最近会话的时序
- 深色模式下 `surfaceContainerLow` 摘要带与页面背景的分层对比
- 窄屏 + 大字号下摘要带四列标签是否被 ellipsis 截断

---

## 五、协作注意

改动期间有另一个 agent 在同一个工作区操作，发生过：

- 本地 main 被重写/压平，独立 commit 记录被折叠进别人的提交
- 推送后工作区被切回 main

如果继续多方并行，建议隔离工作区或各自开分支。
