# Smart Result Card UX Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Simplify AI smart result cards, preserve AI-first metadata decisions, show tag icons, expose location/weather consistently, and remove duplicate saved status.

**Architecture:** Keep the card as a preview and confirmation surface. Put tri-state AI/default precedence in `AiSmartResultUtils`; load full tag and existing-note metadata through narrow callbacks so the card can render existing domain data without duplicating database logic. Existing-note location/weather taps delegate to the full editor, while new-note chips remain locally selectable.

**Tech Stack:** Flutter, Dart, Provider, package:flutter_test

---

### Task 1: Resolve AI location/weather intent

**Files:**
- Modify: `lib/utils/ai_smart_result_utils.dart`
- Modify: `lib/services/agent_tools/propose_new_note_tool.dart`
- Modify: `lib/services/agent_service.dart`
- Modify: `lib/pages/ai_assistant/ai_assistant_page_agent.dart`
- Test: `test/unit/utils/ai_smart_result_utils_test.dart`
- Test: `test/unit/services/agent_note_tools_test.dart`

**Steps:**
1. Add failing tests showing explicit AI booleans override user defaults and omitted values fall back to defaults.
2. Run the focused unit tests and confirm the intended failures.
3. Make AI include flags nullable through parsing/persistence and update the agent instruction.
4. Re-run the focused tests.

### Task 2: Simplify and enrich the card

**Files:**
- Modify: `lib/widgets/ai/smart_result_card.dart`
- Delete: `lib/widgets/ai/smart_result_card_editing.dart`
- Test: `test/widgets/smart_result_card_test.dart`
- Test: `test/widget/smart_result_card_test.dart`

**Steps:**
1. Add failing widget tests for no inline editors, tag icons, all-card location/weather affordances, delegated existing-note taps, and one saved indicator.
2. Run the focused widget tests and confirm failures.
3. Remove inline content/metadata editing, render author/source separately, render tag icons with `IconUtils`, and implement location/weather behavior.
4. Re-run the focused widget tests.

### Task 3: Wire assistant data and verify

**Files:**
- Modify: `lib/pages/ai_assistant/ai_assistant_page_ui.dart`
- Test: `test/widget/pages/ai_assistant_page_test.dart`

**Steps:**
1. Add or update focused integration assertions for card metadata.
2. Wire complete categories and existing-note metadata into the card.
3. Format changed Dart files.
4. Run focused tests and `flutter analyze --no-fatal-infos`.
5. Inspect status/diff, stage explicit files, and commit.
