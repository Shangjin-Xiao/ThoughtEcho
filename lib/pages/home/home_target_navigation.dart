import 'dart:async';

import 'package:thoughtecho/utils/app_logger.dart';

/// Owns initial-link and notification note targeting, including retries.
class HomeTargetNavigation {
  HomeTargetNavigation({
    required this.initialTargetNoteId,
    required this.currentPage,
    required this.selectNotesPage,
    required this.isTagsLoading,
    required this.ensureTagsLoaded,
    required this.scrollToNote,
    this.maxRetries = 8,
  });

  final String? initialTargetNoteId;
  final int Function() currentPage;
  final void Function() selectNotesPage;
  final bool Function() isTagsLoading;
  final Future<void> Function() ensureTagsLoaded;
  final Future<bool> Function(String noteId) scrollToNote;
  final int maxRetries;

  String? _notificationTargetNoteId;
  bool _initialTargetConsumed = false;
  bool _attemptInProgress = false;
  int _retryCount = 0;
  Timer? _retryTimer;
  bool _disposed = false;

  Future<void> acceptNotificationTarget(String noteId) async {
    if (_disposed || noteId.isEmpty) return;
    _notificationTargetNoteId = noteId;
    _attemptInProgress = false;
    _retryCount = 0;
    if (currentPage() != 1) selectNotesPage();
    if (isTagsLoading()) await ensureTagsLoaded();
    if (_disposed) return;
    await _consumeAvailableTarget();
  }

  void onNotesReady() {
    if (_disposed || currentPage() != 1) return;
    unawaited(_consumeAvailableTarget());
  }

  Future<void> _consumeAvailableTarget() async {
    if (_disposed || _attemptInProgress || currentPage() != 1) return;
    final notificationTarget = _notificationTargetNoteId;
    final initialTarget = initialTargetNoteId;
    final target = notificationTarget ??
        (_initialTargetConsumed ||
                initialTarget == null ||
                initialTarget.isEmpty
            ? null
            : initialTarget);
    if (target == null) return;

    _attemptInProgress = true;
    final success = await scrollToNote(target);
    _attemptInProgress = false;
    if (_disposed) return;

    final targetStillCurrent = notificationTarget != null
        ? _notificationTargetNoteId == target
        : initialTargetNoteId == target;
    if (!targetStillCurrent) return;

    if (success) {
      if (notificationTarget != null) {
        _notificationTargetNoteId = null;
        // A notification supersedes the cold-start target for this page
        // session, matching the previous single-target navigation contract.
        _initialTargetConsumed = true;
      } else {
        _initialTargetConsumed = true;
      }
      _retryCount = 0;
      return;
    }

    _retryCount++;
    if (_retryCount >= maxRetries) {
      logDebug(
        '目标笔记定位失败，已达到最大重试次数: $target',
        source: 'HomeTargetNavigation',
      );
      if (notificationTarget != null) _notificationTargetNoteId = null;
      return;
    }
    _retryTimer?.cancel();
    _retryTimer = Timer(
      const Duration(milliseconds: 250),
      () => unawaited(_consumeAvailableTarget()),
    );
  }

  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
  }
}
