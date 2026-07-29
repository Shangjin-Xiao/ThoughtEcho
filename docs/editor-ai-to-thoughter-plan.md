# 编辑器 AI 功能迁移至 Thoughter 实施方案

## 背景

当前编辑器（`NoteFullEditorPage`）和新建笔记对话框（`AddNoteDialog`）中的 AI 功能有两套实现：
- **直接调用 AIService**：「分析来源」和「深度分析」通过 `AIService.analyzeSource()` / `AIService.streamSummarizeNote()` 直接与 AI 通信
- **跳转 Thoughter**：「润色」和「续写」已经通过 `_openAiAssistant()` 跳转到 `AIAssistantPage`

问题：直接调用 AIService 的路径功能有限（无法利用 Agent 工具链），且两条路径的用户体验不一致。此外，`AddNoteDialog` 中的润色/续写仍在使用旧的 `StreamingTextDialog` 弹窗，未跳转 Thoughter。

## 变更目标

### 目标 1：编辑器 AI 全部跳转 Thoughter
将编辑器中「分析来源」和「深度分析」也改为跳转 Thoughter（AIAssistantPage），通过 `initialQuestion` 传递相应的斜杠命令。

### 目标 2：AddNoteDialog AI 全部跳转 Thoughter
将 `AddNoteDialog` 中的「润色」「续写」「深度分析」也改为跳转 Thoughter，与编辑器行为一致。「分析来源」也跳转 Thoughter。

### 目标 3：进入 Agent 前处理编辑器状态
- 编辑器有未保存更改时，提示用户先保存
- 从 AddNoteDialog 跳转时，关闭对话框再打开 Thoughter

### 目标 4：Agent 中用户明确要求改笔记时跳过二次确认
修改 Agent 系统提示词，当用户明确要求创建或修改笔记时，Agent 应直接调用 propose 工具生成卡片，不需要先问用户"你确定要修改吗？"。因为 Agent 本身不能直接修改，卡片已经是确认界面。

---

## 涉及文件

| 文件 | 变更类型 | 说明 |
|------|----------|------|
| [editor_ai_features.dart](file:///home/azureuser/ThoughtEcho/lib/pages/note_editor/editor_ai_features.dart) | 修改 | 将 `_analyzeSource` 和 `_analyzeContent` 改为跳转 Thoughter |
| [add_note_ai_menu.dart](file:///home/azureuser/ThoughtEcho/lib/widgets/add_note_ai_menu.dart) | 修改 | 将所有 AI 功能改为跳转 Thoughter |
| [agent_service.dart](file:///home/azureuser/ThoughtEcho/lib/services/agent_service.dart) | 修改 | 优化系统提示词，明确要求时直接出提案 |
| [app_zh.arb](file:///home/azureuser/ThoughtEcho/lib/l10n/app_zh.arb) | 修改 | 添加新的命令字符串（如果需要） |
| [app_en.arb](file:///home/azureuser/ThoughtEcho/lib/l10n/app_en.arb) | 修改 | 添加新的命令字符串（如果需要） |

---

## 详细实施步骤

### 步骤 1：编辑器 AI 功能统一跳转 Thoughter ⬜
**文件**: `lib/pages/note_editor/editor_ai_features.dart`

**当前状态**：
- `_analyzeSource()` (L19-L103)：直接调用 `AIService.analyzeSource()`，弹出加载 dialog，显示 `SourceAnalysisResultDialog`
- `_analyzeContent()` (L119-L207)：直接调用 `AIService.streamSummarizeNote()`，弹出 `StreamingTextDialog`
- `_polishText()` (L107-L109)：已跳转 Thoughter ✅
- `_continueText()` (L113-L115)：已跳转 Thoughter ✅
- `_askNoteQuestion()` (L211-L213)：已跳转 Thoughter ✅

**变更方案**：
- `_analyzeSource()` → 改为 `_openAiAssistant('/${l10n.commandSourceAnalysis}')`（复用已有的 `/分析来源` 命令）
- `_analyzeContent()` → 改为 `_openAiAssistant('/${l10n.commandDeepAnalysis}')`（复用已有的 `/深度分析` 命令）
- 删除原有的直接 AIService 调用逻辑和相关 dialog 代码

> [!NOTE]
> 已有的 `/分析来源` 和 `/深度分析` 命令在 `AIWorkflowCommandRegistry` 中已注册，`AIAssistantPage` 已能处理这些命令。无需新增命令。

### 步骤 2：AddNoteDialog AI 功能统一跳转 Thoughter ⬜
**文件**: `lib/widgets/add_note_ai_menu.dart`

**当前状态**：
- `_analyzeSource()` (L49-L124)：直接调用 `AIService.analyzeSource()`
- `_polishText()` (L128-L181)：直接调用 `AIService.streamPolishText()` + `StreamingTextDialog`
- `_continueText()` (L185-L238)：直接调用 `AIService.streamContinueText()` + `StreamingTextDialog`
- `_analyzeContent()` (L242-L305)：直接调用 `AIService.streamSummarizeNote()` + `StreamingTextDialog`
- `_askNoteQuestion()` (L309-L343)：已跳转 Thoughter ✅

**变更方案**：
- 统一所有 AI 操作为跳转 Thoughter
- 跳转前需要处理 AddNoteDialog 的状态（内容 → 创建临时 Quote → 导航到 AIAssistantPage）
- 复用 `_askNoteQuestion()` 的 `tempQuote` 创建逻辑，为各操作添加 `initialQuestion`

### 步骤 3：进入 Agent 前处理编辑器/对话框状态 ⬜
**编辑器**（`editor_ai_features.dart`）：
- `_openAiAssistant()` 已有未保存检查逻辑 ✅（L232-L255 的 `_hasUnsavedChanges()` 检查）
- 由于所有 AI 功能现在都走 `_openAiAssistant()`，自动获得此保护

**AddNoteDialog**（`add_note_ai_menu.dart`）：
- 跳转 Thoughter 时需要先关闭 AddNoteDialog
- 或者在 AddNoteDialog 之上 push Thoughter 页面（更好的方案，因为用户返回时还能继续编辑）
- 选择方案：在 AddNoteDialog 之上直接 push AIAssistantPage（与现有 `_askNoteQuestion` 行为一致）

### 步骤 4：优化 Agent 系统提示词 ⬜
**文件**: `lib/services/agent_service.dart`

**当前提示词** (L1040)：
> "只有用户明确要求创建或修改笔记时才生成提案。若关键对象或预期结果不明确且会导致错误操作，先提出一个简短澄清问题。"

**优化方案**：
调整措辞，强调当用户意图明确时（如"帮我改一下这篇笔记"、"新建一条笔记记录xxx"），应直接生成提案卡片，不需要额外确认。因为提案本身就是确认环节——用户可以在卡片上查看内容、快编修改、或选择不应用。

**修改后**：
> "用户明确要求创建或修改笔记时，直接生成提案卡片供用户确认，不要额外询问'是否确定'——提案本身就是确认步骤。只有关键信息不足以正确操作时（如不知道改哪篇笔记、不清楚要改成什么），才简短澄清。"

### 步骤 5：清理不再需要的导入和代码 ⬜
- `editor_ai_features.dart`：移除对 `AIService`、`SourceAnalysisResultDialog`、`StreamingTextDialog` 等的直接使用
- `add_note_ai_menu.dart`：同上
- 检查 `AIService.analyzeSource()`、`AIService.streamPolishText()`、`AIService.streamContinueText()` 是否还有其他调用方，如果没有则标注但不删除（保持兼容性）

### 步骤 6：格式化、测试和提交 ⬜
- `dart format` 格式化变更文件
- `flutter analyze` 静态分析
- 运行相关测试
- `git add` 具体文件 → `git commit` → `git push`

---

## 验收标准

1. ✅ 编辑器中点击任何 AI 选项都跳转到 Thoughter 并自动发送对应命令
2. ✅ AddNoteDialog 中点击任何 AI 选项都跳转到 Thoughter
3. ✅ 编辑器有未保存更改时，提示先保存再跳转
4. ✅ Agent 收到明确的笔记操作请求时，直接生成提案卡片，不二次确认
5. ✅ 代码通过 `flutter analyze` 和格式化检查
6. ✅ 变更已提交并推送

## 进度追踪

| 步骤 | 状态 | 备注 |
|------|------|------|
| 步骤 1：编辑器 AI 跳转 Thoughter | ✅ 已完成 | `editor_ai_features.dart` 已统一跳转 Thoughter |
| 步骤 2：AddNoteDialog AI 跳转 Thoughter | ✅ 已完成 | `add_note_ai_menu.dart` 已统一跳转 Thoughter |
| 步骤 3：状态处理 | ✅ 已完成 | 编辑器有未保存更改时提示保存，AddNoteDialog 在顶部 push |
| 步骤 4：优化 Agent 提示词 | ✅ 已完成 | `agent_service.dart` 提示词已更新，明确改动直接出提案卡片 |
| 步骤 5：清理代码 | ✅ 已完成 | 清理 `note_full_editor_page.dart` 中未使用的 AI 弹窗及服务导入 |
| 步骤 6：格式化和提交 | ✅ 已完成 | 完成 `dart format`、`flutter analyze` 验证及提交推送 |
