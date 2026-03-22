# Note List Filter Subscription Race Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Eliminate intermittent note-list loading and stale-filter states caused by duplicate subscriptions during filter changes and notification-driven record-page entry.

**Architecture:** Keep `NoteListView` as the single owner of list subscription updates, but ensure filter changes only trigger re-subscription after parent widget props have updated. Avoid changing database pagination architecture in this pass; fix the UI race at the call sites that currently re-subscribe with stale widget values.

**Tech Stack:** Flutter, Dart, Provider, widget tests, existing `DatabaseService` pagination stream.

---

### Task 1: Add a failing regression test for stale filter re-subscription

**Files:**
- Modify: `test/widget/note_list_view_filter_test.dart`
- Reference: `lib/widgets/note_list_view.dart`

**Step 1: Write the failing test**

Add a widget test that pumps `NoteListView` inside providers with a fake `DatabaseService`, changes filters through widget callbacks, and asserts `watchQuotes` is not called with stale pre-update filter params during the same interaction.

**Step 2: Run test to verify it fails**

Run: `flutter test test/widget/note_list_view_filter_test.dart`

Expected: FAIL because `NoteListView` currently calls `_updateStreamSubscription()` before parent props update.

**Step 3: Keep test minimal**

Use a lightweight fake `DatabaseService` subclass that records `watchQuotes` arguments and returns a broadcast stream with fixed data.

### Task 2: Remove premature subscription refreshes from filter UI actions

**Files:**
- Modify: `lib/widgets/note_list/note_list_items.dart`
- Modify: `lib/widgets/note_list/note_list_filters.dart`
- Reference: `lib/widgets/note_list/note_list_data_stream.dart`

**Step 1: Implement minimal code**

Delete manual `_updateStreamSubscription()` calls that run immediately after `widget.onTagSelectionChanged` / `widget.onFilterChanged` in filter apply, chip delete, and clear-all actions.

**Step 2: Preserve current behavior**

Leave `didUpdateWidget()` subscription refresh logic intact so it re-subscribes once with the new widget props after parent `setState`.

**Step 3: Run regression test**

Run: `flutter test test/widget/note_list_view_filter_test.dart`

Expected: PASS.

### Task 3: Verify targeted regressions

**Files:**
- Modify if needed: `test/unit/services/smart_push_service_test.dart`

**Step 1: Re-run relevant tests**

Run: `flutter test test/widget/note_list_view_filter_test.dart`

Run: `flutter test test/unit/services/smart_push_service_test.dart`

**Step 2: Run targeted analysis**

Run: `flutter analyze --no-fatal-infos lib/widgets/note_list_view.dart test/widget/note_list_view_filter_test.dart`

**Step 3: Commit**

```bash
git add lib/widgets/note_list/note_list_items.dart \
  lib/widgets/note_list/note_list_filters.dart \
  test/widget/note_list_view_filter_test.dart \
  docs/plans/2026-03-22-note-list-filter-subscription-race.md
git commit -m "Fix note list filter subscription race"
```
