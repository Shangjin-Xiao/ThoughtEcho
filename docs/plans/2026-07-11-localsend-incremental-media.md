# LocalSend Incremental Media Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Send complete note data but include only missing or size-changed media in ThoughtEcho LocalSend sync packages.

**Architecture:** Extend the approved sync-intent response with a versioned receiver media manifest. Add pure manifest comparison and filtered backup collection while preserving the existing ZIP import path and falling back to full media for legacy peers.

**Tech Stack:** Flutter, Dart, `dart:io`, LocalSend HTTP protocol, existing BackupService and ZipStreamProcessor, `package:test`/Flutter test.

---

### Task 1: Media manifest model and scanner

**Files:**
- Create: `lib/services/media_sync_manifest.dart`
- Create: `test/unit/services/media_sync_manifest_test.dart`

**Step 1:** Write failing tests for normalized relative paths, size comparison, missing files, changed files, and invalid manifest JSON.

**Step 2:** Run `timeout 60s flutter test --reporter compact test/unit/services/media_sync_manifest_test.dart` and confirm failure because the API is absent.

**Step 3:** Implement a small immutable manifest model, JSON parsing, directory scanning, and `shouldTransfer` comparison.

**Step 4:** Run the same test and confirm it passes.

### Task 2: Approved intent manifest negotiation

**Files:**
- Modify: `lib/services/localsend/localsend_server.dart`
- Modify: `lib/services/note_sync_service.dart`
- Modify: `test/sync_integration_test.dart`
- Modify: `test/unit/services/localsend_security_test.dart`

**Step 1:** Add failing tests proving an approved response exposes a versioned manifest and a response without it selects legacy fallback.

**Step 2:** Run the focused tests and confirm the expected failures.

**Step 3:** Add a manifest provider callback to the server, return it only after approval, and parse it into a typed approval result on the sender.

**Step 4:** Run the focused tests and confirm they pass.

### Task 3: Filter media included in backup ZIP

**Files:**
- Modify: `lib/services/backup_service.dart`
- Modify: `lib/utils/backup_media_processor.dart`
- Modify: `lib/services/note_sync_service.dart`
- Modify: `test/unit/utils/backup_media_processor_test.dart` or nearest existing backup test
- Modify: `test/sync_integration_test.dart`

**Step 1:** Add failing tests proving unchanged media is excluded, missing/changed media is included, and legacy targets request all media.

**Step 2:** Run focused tests and confirm failures are due to missing filtering behavior.

**Step 3:** Thread an optional receiver manifest through backup export and filter collected archive entries while retaining relative media path conversion in JSON.

**Step 4:** Run focused and existing sync/backup tests until green.

### Task 4: Verification, review, and delivery

**Files:**
- Review all files changed since `a7cc1092`.

**Step 1:** Format only changed Dart files and run `git diff --check`.

**Step 2:** Run all relevant LocalSend, backup, manifest, integration, and widget tests.

**Step 3:** Run `flutter analyze --no-fatal-infos` and record pre-existing info diagnostics separately.

**Step 4:** Request code review, fix all critical/important findings, and rerun affected verification.

**Step 5:** Commit explicit files, merge or fast-forward the feature branch into `main` without touching unrelated working-tree changes, and push `origin main`.
