# Unified AI Mode Rules Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Rebuild `AIAssistantPage` into the single AI container with explicit entry source, in-page mode switching, unified workflow command handling, inherited legacy AI workflows, and split mode persistence that matches `docs/plans/2026-04-05-unified-ai-mode-rules-design.md`.

**Architecture:** Introduce a small page-domain layer for AI entry source, page mode, workflow descriptors, and workflow card metadata, then refactor `AIAssistantPage` around that model instead of implicit `quote != null` branching. Reuse existing `AIService`, `AgentService`, note-editor workflow prompts, and insights parameters while moving workflow configuration/result cards into the assistant message stream. Persist last-selected mode separately for Explore and note entry via `SettingsService`.

**Tech Stack:** Flutter, Dart, Provider, MMKV-backed `SettingsService`, existing `AIService`/`AgentService`, widget tests.

---

### Task 1: Model the unified AI container state

**Files:**
- Create: `lib/models/ai_assistant_entry.dart`
- Create: `lib/models/ai_workflow_descriptor.dart`
- Modify: `lib/pages/ai_assistant_page.dart`
- Test: `test/widget/pages/ai_assistant_page_test.dart`

**Step 1: Write the failing tests**

Add widget tests that prove:
- Explore entry defaults to chat mode.
- Note entry defaults to note-chat mode.
- Persisted Explore mode and note-entry mode are read independently.

**Step 2: Run test to verify it fails**

Run: `flutter test test/widget/pages/ai_assistant_page_test.dart`
Expected: FAIL because the page has no explicit entry/mode model and no split mode persistence.

**Step 3: Write minimal implementation**

Add:
- explicit entry source enum (`explore`, `note`)
- explicit page mode enum (`chat`, `noteChat`, `agent`)
- page config helpers resolving allowed modes and defaults
- `AIAssistantPage` constructor support for explicit entry source

**Step 4: Run test to verify it passes**

Run: `flutter test test/widget/pages/ai_assistant_page_test.dart`
Expected: PASS for the new mode-resolution tests.

### Task 2: Persist mode separately for Explore and note entry

**Files:**
- Modify: `lib/services/settings_service.dart`
- Modify: `lib/pages/ai_assistant_page.dart`
- Test: `test/widget/pages/ai_assistant_page_test.dart`

**Step 1: Write the failing tests**

Add tests that toggle Explore to Agent and note entry to Agent / note-chat, then rebuild each page and verify the remembered mode does not leak across entry sources.

**Step 2: Run test to verify it fails**

Run: `flutter test test/widget/pages/ai_assistant_page_test.dart`
Expected: FAIL because persistence fields and restore logic do not exist.

**Step 3: Write minimal implementation**

Add `SettingsService` getters/setters for:
- Explore entry last AI mode
- Note entry last AI mode

Restore mode on page init and save immediately on mode change.

**Step 4: Run test to verify it passes**

Run: `flutter test test/widget/pages/ai_assistant_page_test.dart`
Expected: PASS for split persistence coverage.

### Task 3: Replace hard-coded slash branches with unified workflow descriptors

**Files:**
- Create: `lib/widgets/ai/ai_workflow_cards.dart`
- Modify: `lib/pages/ai_assistant_page.dart`
- Test: `test/widget/pages/ai_assistant_page_test.dart`

**Step 1: Write the failing tests**

Add tests that verify:
- slash commands render as workflow actions instead of switching mode
- unsupported commands remain visible but show restriction guidance
- note entry without explicit slash does not produce editable result cards

**Step 2: Run test to verify it fails**

Run: `flutter test test/widget/pages/ai_assistant_page_test.dart`
Expected: FAIL because slash behavior is still hard-coded and incomplete.

**Step 3: Write minimal implementation**

Create a workflow descriptor registry containing:
- command id/name/display name
- note binding requirement
- agent natural-language eligibility
- managed workflow entry point
- editable-result eligibility

Render workflow parameter/result/status cards inside the chat list with metadata-backed message items.

**Step 4: Run test to verify it passes**

Run: `flutter test test/widget/pages/ai_assistant_page_test.dart`
Expected: PASS for workflow-routing behavior.

### Task 4: Inline legacy note workflows inside the assistant stream

**Files:**
- Modify: `lib/pages/ai_assistant_page.dart`
- Modify: `lib/widgets/source_analysis_result_dialog.dart`
- Modify: `lib/widgets/ai/smart_result_card.dart`
- Test: `test/widget/pages/ai_assistant_page_test.dart`

**Step 1: Write the failing tests**

Add tests that verify `/润色`, `/续写`, `/深度分析`, `/分析来源` are available in note context and that editable-result actions only appear for explicit editing workflows.

**Step 2: Run test to verify it fails**

Run: `flutter test test/widget/pages/ai_assistant_page_test.dart`
Expected: FAIL because only two commands exist and source/deep-analysis flows still live outside the assistant stream.

**Step 3: Write minimal implementation**

Reuse existing service calls and prompts:
- `streamPolishText`
- `streamContinueText`
- `streamSummarizeNote`
- `streamAnalyzeSource`

Move results into message cards and preserve apply actions where allowed.

**Step 4: Run test to verify it passes**

Run: `flutter test test/widget/pages/ai_assistant_page_test.dart`
Expected: PASS for note workflow coverage.

### Task 5: Inline legacy insights workflow inside the assistant stream

**Files:**
- Create: `lib/models/ai_insight_workflow_options.dart`
- Modify: `lib/pages/ai_assistant_page.dart`
- Modify: `lib/pages/explore_page.dart`
- Test: `test/widget/pages/ai_assistant_page_test.dart`

**Step 1: Write the failing tests**

Add tests that verify `/智能洞察`:
- remains available from Explore chat and note chat
- shows inline parameter selection
- uses managed full-note analysis instead of agent search

**Step 2: Run test to verify it fails**

Run: `flutter test test/widget/pages/ai_assistant_page_test.dart`
Expected: FAIL because insights still require the old page flow.

**Step 3: Write minimal implementation**

Reuse `InsightsPage` analysis types/styles and `AIService.streamGenerateInsights`, but render parameter selection and results as assistant-stream cards.

Also pass an Explore entry summary into `AIAssistantPage` and show it as the dynamic greeting block inside the page.

**Step 4: Run test to verify it passes**

Run: `flutter test test/widget/pages/ai_assistant_page_test.dart`
Expected: PASS for managed insights workflow and Explore guidance rendering.

### Task 6: Finish integration and verify

**Files:**
- Modify: `lib/pages/explore_page.dart`
- Modify: `lib/widgets/ask_note_widgets.dart`
- Modify: `lib/widgets/add_note_ai_menu.dart`
- Modify: `lib/pages/note_editor/editor_ai_features.dart`
- Test: `test/widget/pages/ai_assistant_page_test.dart`

**Step 1: Write the failing tests**

Add or extend tests to prove wrapper/entry callers create the correct entry source and mode defaults.

**Step 2: Run test to verify it fails**

Run: `flutter test test/widget/pages/ai_assistant_page_test.dart`
Expected: FAIL until all callers are migrated.

**Step 3: Write minimal implementation**

Update every AI entry point to use the explicit entry model and ensure all workflow cards stay inside `AIAssistantPage`.

**Step 4: Run test to verify it passes**

Run: `flutter test test/widget/pages/ai_assistant_page_test.dart`
Expected: PASS.

**Step 5: Run required verification**

Run: `flutter analyze --no-fatal-infos`
Run: `flutter test test/widget/pages/ai_assistant_page_test.dart`
Expected: analyze succeeds; targeted widget tests pass.
