### 2026-04-25T10:00Z: SmartResultCard 交互极简设计决策 (只保留“进入编辑器”与“直接保存”)

**By:** 上晋 (via EVE)
**类型:** UI/UX 决策 + 代码规范

**背景**: 原有的 AI 生成结果卡片 (`SmartResultCard`) 设计中，暴露了“替换原笔记 (Replace)”、“追加到末尾 (Append)”、“打开编辑器 (Open in Editor)”和“直接保存 (Save Directly)”四个选项，并且依据不同场景隐藏不同按钮。这增加了用户的认知负担，违背了笔记类 App 应保持“记录心流无中断”的核心原则。

**核心决策:**

1. **废除冗余的按钮选项**：在 `SmartResultCard` 中，**永久禁止且移除**“替换原笔记”和“追加到末尾”这两个独立的 UI 按钮。
2. **极简且永远可见的核心按钮**：卡片底部**仅保留且必须永远显示**“进入编辑器 (Open in Editor)”和“直接保存 (Save Directly)”这两个核心操作按钮，不再依据 `editorSource` 的不同而随意隐藏，给用户稳定不变的安全预期。
3. **后台自动路由逻辑 (Action Routing)**：
   - 对于 AI 是在做“润色（替换旧文）”还是在做“续写（追加新文）”，这是 AI 在生成 `smart_result` 时内部的 `meta['action']` 就已经决定好的事情。
   - **系统层必须自动处理这层逻辑**。当用户点击“直接保存”或“进入编辑器”时，代码底层应自动根据 action 读取指令进行 `append` 或 `replace` 的数据覆写，**坚决不将这种底层数据合并逻辑的判断题抛给用户做**。

**结论**: 笔记 APP 的 AI 交互必须克制。用户只需要决定“要不要保存/修改这段文本”，由系统自己负责怎么拼接到旧笔记里。不要让用户做二次选择。

**影响文件:**
- `lib/widgets/ai/smart_result_card.dart`
- `lib/pages/ai_assistant/ai_assistant_page_ui.dart`
