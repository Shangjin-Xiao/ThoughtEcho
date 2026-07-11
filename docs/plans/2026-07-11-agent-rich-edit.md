# Reliable Agent and Rich-Text Editing Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Keep Agent tasks running until explicitly completed and apply AI rich-text edits precisely without Markdown conversion or collateral formatting loss.

**Architecture:** Add an explicit completion tool to the Agent loop and treat premature plain-text responses as recoverable protocol violations. Introduce a structured rich-text edit module whose small interface validates a note revision, uniquely locates old text, converts a constrained rich-content tree directly to Quill Delta operations, and returns a structured preview for the existing confirmation flow.

**Tech Stack:** Dart, Flutter, `openai_dart`, `flutter_quill`, Provider, `package:test`, Flutter widget tests.

---

### Task 1: Agent completion protocol

**Files:**
- Modify: `lib/services/agent_service.dart`
- Create: `lib/services/agent_tools/complete_task_tool.dart`
- Modify: `lib/providers/app_providers.dart`
- Test: `test/unit/services/agent_service_loop_test.dart`

1. Write a failing test where the model emits interim text after a tool result and must receive a continuation prompt.
2. Write a failing test where `complete_task` ends the loop with its result.
3. Run the named tests and confirm they fail for the intended reason.
4. Implement the completion protocol, bounded recovery, and explicit termination result.
5. Run the Agent loop test file and confirm it passes.

### Task 2: Native rich-text edit module

**Files:**
- Create: `lib/models/rich_text_edit.dart`
- Create: `lib/utils/quill_structured_edit.dart`
- Test: `test/unit/utils/quill_structured_edit_test.dart`

1. Write failing tests for unique matching, conflict detection, formatting preservation, embeds, and structured inserted formatting.
2. Run the test file and confirm RED.
3. Implement validated structured-content-to-Delta operations without Markdown parsing.
4. Run the test file and confirm GREEN.

### Task 3: Agent rich-edit proposal tool and UI integration

**Files:**
- Create: `lib/services/agent_tools/propose_rich_edit_tool.dart`
- Modify: `lib/providers/app_providers.dart`
- Modify: `lib/pages/ai_assistant/ai_assistant_page_agent.dart`
- Modify: `lib/pages/ai_assistant/ai_assistant_page_ui.dart`
- Modify: `lib/pages/note_editor/editor_ai_features.dart`
- Test: `test/unit/services/agent_note_tools_test.dart`
- Test: `test/widget/pages/ai_assistant_page_test.dart`

1. Write failing tool and widget tests for a structured proposal and precise application.
2. Implement the tool schema and smart-result payload.
3. Route structured edits into the editor while retaining the existing replace/append fallback.
4. Render a human-readable structured diff rather than raw JSON.
5. Run both related test files.

### Task 4: Verification and delivery

**Files:**
- Modify relevant bilingual user documentation if the interaction changes require explanation.

1. Format only changed Dart files.
2. Run all related unit and widget tests.
3. Run `flutter analyze --no-fatal-infos` and record any pre-existing infos separately.
4. Inspect `git diff`, `git status --short`, and staged diff for secrets and unrelated changes.
5. Commit explicit files, integrate the feature branch into `main`, and push `origin/main`.
