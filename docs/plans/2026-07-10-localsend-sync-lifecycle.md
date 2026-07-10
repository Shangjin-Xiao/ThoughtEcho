# LocalSend Sync Lifecycle Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Require explicit peer approval before packaging, make every cancellable sync phase actually cancellable, and make device discovery responses advertise a reachable endpoint.

**Architecture:** Keep `NoteSyncService` as the orchestration boundary, but treat peer approval as a strict protocol gate instead of a best-effort compatibility hint. Propagate cancellation through the approval HTTP request, backup export, and LocalSend HTTP clients; make the page map system back and its cancel action to the same service cancellation. Correct discovery replies to use the active server port and directly answer the announcing peer.

**Tech Stack:** Flutter, Dart, Provider/ChangeNotifier, Dio/http, LocalSend-compatible HTTP and UDP multicast, `flutter_test`, Mockito.

---

### Task 1: Lock the approval gate with regression tests

**Files:**
- Modify: `test/sync_integration_test.dart`
- Modify: `lib/services/note_sync_service.dart`

1. Add a test whose approval future remains pending and assert `BackupService.exportAllData` is never called.
2. Run the focused test and confirm the current implementation cannot provide the required controllable approval/cancellation behavior.
3. Add a small injectable approval request seam, use the target's HTTP/HTTPS setting, and reject timeouts, connection failures, malformed bodies, and non-200 responses instead of treating them as approval.
4. Run the focused test and confirm it passes.
5. Add a cancellation test that cancels while approval is pending and asserts packaging never starts.

### Task 2: Propagate cancellation through packaging and transport

**Files:**
- Modify: `test/sync_integration_test.dart`
- Modify: `test/unit/services/localsend/send_session_test.dart`
- Modify: `lib/services/note_sync_service.dart`
- Modify: `lib/services/localsend/localsend_send_provider.dart`

1. Add a service test proving cancellation reaches `BackupService.exportAllData` and leaves a terminal cancelled state.
2. Add a LocalSend provider test with a deliberately stalled prepare response and assert `cancelSession` terminates it promptly.
3. Run both tests and observe the expected failures.
4. Pass a `CancelToken` into backup export, close active HTTP clients on send cancellation, and prevent a cancelled session from being overwritten as a generic error.
5. Run both tests and confirm they pass.

### Task 3: Fix dialog cancellation and back navigation

**Files:**
- Modify: `test/widget/note_sync_page_test.dart`
- Regenerate: `test/widget/note_sync_page_test.mocks.dart`
- Modify: `lib/pages/note_sync_page.dart`

1. Add widget tests showing a cancel action while waiting for peer approval and showing that system back invokes cancellation rather than merely hiding the dialog.
2. Run the widget test and confirm it fails against the current action conditions.
3. Expose cancellation for peer-waiting, packaging, sending, and receiving states; wrap the modal in `PopScope` so back uses the same action and cannot trigger listener-driven reappearance.
4. Regenerate Mockito mocks and run the widget test.

### Task 4: Correct discovery response endpoint

**Files:**
- Modify: `lib/services/thoughtecho_discovery_service.dart`
- Test: `test/unit/services/thoughtecho_discovery_service_test.dart`

1. Add a focused test for the response DTO/target showing the active server port is advertised.
2. Run the test and confirm the fixed-default-port behavior fails it.
3. Send a direct UDP reply to the announcing peer (while retaining multicast compatibility) and advertise `_actualServerPort`.
4. Run the discovery test and related LocalSend security tests.

### Task 5: Verify, review, commit, and push

**Files:**
- Review only the sync files above plus this plan.

1. Format only changed Dart files.
2. Run focused sync service, LocalSend provider, discovery, and widget tests.
3. Run `flutter analyze --no-fatal-infos` and record any pre-existing findings separately.
4. Inspect `git diff`, `git status --short`, and the staged diff; ensure the unrelated AI assistant changes remain unstaged.
5. Commit with `Fixes THOUGHTECHO-3V` and push `main` to its configured upstream.
