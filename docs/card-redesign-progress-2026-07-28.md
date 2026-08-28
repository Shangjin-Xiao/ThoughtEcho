# AI 智能卡片统一重设计 — 进度与决策记录 [已归档]

> [!NOTE]
> ### 📦 本进度与决策记录已归档 (Archived)
> - **落实状态**：智能结果卡片重设计（`SmartResultCard` / `NoteProposalCard` 骨架统一在 `lib/widgets/ai/ai_card_parts.dart`）已全部完成；第八节记录的「让 AI 知道建议被采纳」待办也已在代码中彻底实现并闭环。
> - **归档时间**：2026-07-31
> - **当前生效事实源**：[`lib/widgets/ai/ai_card_parts.dart`](../lib/widgets/ai/ai_card_parts.dart) 与 [`lib/pages/thoughter/thoughter_agent.dart`](../lib/pages/thoughter/thoughter_agent.dart)
> - **保留目的**：本文仅供 AI 智能卡片统一重设计过程、决策记录及历史反馈追溯参考。

> 日期：2026-07-28
> 背景：接手 Claude Code 遗留任务中的「智能结果卡片重设计」（原任务清单 cc365afe 任务 6）。
> 本文档随做随更，供后续接手者（人或 agent）接续。**按用户习惯，本文档与另两份审查文档一样只留本地，不提交。**

---

## 一、用户已拍板的关键决策

| # | 决策 | 来源 |
|---|---|---|
| 1 | **两张卡一起统一**：润色/续写结果卡（SmartResultCard）与 agent 提案卡（NoteProposalCard）用同一副骨架 | 用户确认 |
| 2 | **整篇覆盖（replaceDocument）保留但加闸门**：研究 ai-reference 三家（claude-code/gemini-cli/opencode）结论——覆盖能力都保留，但必须有约束（read-first / 用户确认 / 自纠错）。本项目的 revision 校验+用户确认已够强，只需把工具 schema 描述升级为硬约束（要求说明为何局部 op 不适用）。段落级锚点替换仍是默认优先路径 | ai-reference 研究 + 用户认同"按段落替换更好" |
| 3 | **卡片不加**：理由行、忽略/拒绝键、diff（含修改记录查看）、覆盖警示 | 设计终稿 + 用户多次强调 |
| 4 | **验证方式**：本机可以跑 `flutter test`，不编译 APK；远程 CI 兜底 | 用户明确（机器卡） |
| 5 | **天气/位置保存链路复核 + 集成测试**：另开一轮，不在本轮 | 用户明确 |
| 6 | UI/UX 细节用户授权我自行把关，"觉得不对可以改" | 用户明确 |

## 二、统一卡片设计（已实施）

骨架（两张卡一致）：

```
卡头：动作徽章（✚新建/✎修改）+ 标题《目标笔记》（分析类无徽章）
内容：限高 220 / 展开 520；富文本走 QuoteContent（Quill 真实渲染），纯文本走 MarkdownBody
来源行：——作者《出处》（StringUtils.formatSource，与笔记列表一致）
标签：QuoteTagChip（quote_card_helpers.dart 里抽好的笔记列表同款，之前零使用方，正式启用）
元数据行：位置/天气 FilterChip（AddNoteDialog 同款参数）+ ✏️快编 ActionChip
底部：打开编辑器 / 保存  →  保存后变「✓已保存 · 查看笔记」（可点，打开笔记）
```

快编规则：
- 弹窗字段 = 内容（可选）+ 作者 + 出处 + 标签（TagSelectionSection，AddNoteDialog 同款）
- **结果卡**：纯文本可改正文；富文本（有 rich_document）只能改来源/标签（正文走全屏编辑器）
- **提案卡**：仅"纯文本新建"可改正文；富文本新建和一切 edit 提案只能改来源/标签
  （理由：edit 提案按 ops 应用，改了预览正文也不会改变落库结果，会造成误导）
- 弹窗确认后由页面写回 metaJson + 会话持久化，卡片自身不存副本

其他：
- 保存报错不再裸露 `e.toString()`，改通用文案 `aiCardSaveFailedGeneric`（报告 #22）
- edit 提案的 metadata 只有 tag_ids（模型 metadata_patch 不带名字），标签展示退化为 id；create 提案工具本身已存 tag_names，正常

## 三、已完成（本机未提交的工作区）

| 文件 | 变更 |
|---|---|
| `lib/widgets/ai/ai_card_parts.dart` | **新增**：共享部件（外壳/卡头/来源行/标签行/限高内容/元数据 chip/快编 chip/已保存按钮） |
| `lib/widgets/ai/smart_result_card.dart` | **重写**：仅保留 SmartResultCard+SmartResultDraft；新增 action/targetNoteTitle/previewDeltaOps/onQuickEdit/onViewNote；删除 _MetaToggleChip/_TagChip/_InlineMetadata 私有类 |
| `lib/widgets/ai/note_proposal_card.dart` | **新增**：NoteProposalCard 从 smart_result_card.dart 迁入并重设计；onApply 改为返回 noteId；去掉理由行/修改记录 diff |
| `lib/pages/ai_assistant/ai_assistant_page_quick_edit.dart` | **新增** part：快编弹窗、写回持久化、标签解析、查看笔记导航 |
| `lib/pages/ai_assistant_page.dart` | import note_proposal_card + add_note_dialog_parts；挂新 part |
| `lib/pages/ai_assistant/ai_assistant_page_ui.dart` | 两张卡实例化接线（action/目标标题/previewDeltaOps/快编/查看笔记） |
| `lib/l10n/app_zh.arb` / `app_en.arb` | 新增 7 个 key（aiCardBadgeCreate/Edit、aiCardQuickEdit(+Tooltip)、aiCardSavedViewNote、aiCardSaveFailedGeneric、aiCardEditContentHint），已跑 gen-l10n |
| 3 个卡片测试文件 | 按新设计更新（保存态文本、来源合并行、快编行为、去 diff 断言），**15 项全绿** |

## 四、CI/测试修复与 schema 硬约束

1. **页面测试 Mock 协议升级与 Key 修复**：
   - 将 `_FakeAgentService` 的 `emitSmartResultCard` 升级为真实协议 `artifacts: [NoteProposalArtifact(...)]`。
   - `test/widget/pages/ai_assistant_page_test.dart` 补充 `ExperimentalBadge` import 及 `InkRipple.splashFactory` 主题适配，解决 headless 测试下 Material 3 默认 `InkSparkle` 着色器缺失异常。
   - 27 项页面测试全部通过绿透。

2. **`propose_note_edit_tool.dart` replaceDocument Schema 硬约束**：
   - 升级 `replaceDocument` 的 schema 描述，明确约束：仅当整篇重构且局部替换/插入/删除明显不适用时才允许使用，且必须在 `reason` 中显式说明原因。

3. **全量静态分析与格式化**：
   - 跑通 `dart format`，无未格式化文件。
   - 清理 `lib/pages/ai_assistant/ai_assistant_page_ui.dart` 中未引用的私有函数 `_buildExperimentalNoticeBanner`。
   - 运行 `flutter analyze --no-fatal-infos`，0 警告 0 错误（4 项仅为现有代码的 info 提示）。

## 五、完成状态总结

- [x] 修 mock 的 propose_edit 死协议 → artifacts 路径 & Key 断言适配
- [x] `propose_note_edit_tool.dart` 的 replaceDocument schema 加硬约束（决策 #2）
- [x] `dart format` 改动文件 + `flutter analyze` 全量（0 error/warning）
- [x] 相关测试复跑（3 个卡片测试文件 + `ai_assistant_page_test.dart` 全部绿透）
- [x] 更新进度文档 `docs/card-redesign-progress-2026-07-28.md`

## 六、注意事项（接手必看）

- 本机慢：`flutter test` 冷编译 2~4 分钟，单文件超时给 300~500s
- `lib/gen_l10n/` 是生成物，不要手改
- 工作区还有用户的两份本地文档（`THOUGHTER_ISSUES_REPORT.md`、`docs/growth-and-product-direction-2026-07-26.md`），按要求不提交
- Gemini 也在动这个仓库（并行代理），提交前先 `git fetch` 看有没有新提交撞车


---

## 七、2026-07-29 用户反馈三修

1. **展开按钮无条件显示** → `AiCardExpandableContent` 加 `ScrollController` 折叠态测量
   `maxScrollExtent`，只有真溢出才渲染「展开全文/收起全文」；未溢出时禁用滚动并补 8px 间距。
   展开后不再重测，避免收起按钮消失。
2. **提案卡不显示位置/天气** → `NoteProposalCard` 新增 `locationPreview`/`weatherPreview`/
   `onMetadataChanged`，create 提案渲染与 SmartResultCard 同款 `AiMetaChip`；页面
   `_persistNoteProposalMetadataFlags` 把开关写回 artifact.metadata 并持久化会话，
   保证「保存」与「打开编辑器」两条路径读同一份状态。
3. **任何类型都开全屏编辑器** → 新增 `_opsHaveRichFormatting(ops)`：全是无属性纯文本
   insert 视为普通笔记。`_openNoteProposalInEditor`（create 分支）与
   `_openSmartResultAsNewNote` 都按实际形态而非模型声明的 `document_kind` 选编辑器，
   `plainCreateOpensRich` 提示同步用该判定。

测试：`note_proposal_card_test.dart` 新增 2 例（展开阈值、位置/天气 chip），
4 个卡片/页面测试文件共 44 项全绿；`flutter analyze` 无新增问题。

---

## 八、让 AI 知道自己的建议被采纳了（已解决 / 2026-07-31 落地）

> **解决状态**：✅ **已彻底解决**  
> **代码落地**：已在 `lib/utils/ai_smart_result_utils.dart:29-45` 与 `lib/pages/thoughter/thoughter_agent.dart:699-715` 中实现。在构建 Agent 历史请求时自动扫描解析 `saved_note_id` 并向模型历史追加系统采纳提示，确保 AI 感知到建议已保存并获取笔记 ID。

**用户诉求（原话）**：「AI 怎么可能记不住建议？他自己写的欸，我只是需要让 AI 知道自己的建议保存了。」

**澄清**：AI 确实记得自己写过什么——它那句「我帮你起草了一条笔记…」是普通
assistant 消息、没有 metaJson，正常留在历史里。缺的只是**采纳结果**这一个状态位。

**为什么当时没生效**：commit 44ea7bb0 已在 `lib/utils/ai_request_helper.dart:68-74`
实现了「meta 带 saved_note_id / applied 就追加 [系统提示：用户已采纳…]」，
但 `lib/pages/ai_assistant/ai_assistant_page_agent.dart:10` 的历史过滤是

```dart
_messages.where((m) => m.role != 'system' && m.metaJson == null)
```

**带 metaJson 的消息全被滤掉**，而采纳状态恰恰写在提案卡消息的 metaJson 里
（`saved_note_id`）。所以 `msg.parsedMeta` 恒为 null，那段 if 一次都没进过。

**最终修法**：在构造 history 时扫一遍卡片消息，若其 meta 有 `saved_note_id`，就在历史末尾追加系统说明（「[系统提示：用户已采纳你上一条笔记建议并保存为笔记，ID 为 xxx]」）。

