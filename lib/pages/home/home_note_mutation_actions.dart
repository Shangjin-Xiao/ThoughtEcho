import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/utils/app_logger.dart';
import 'package:thoughtecho/widgets/note_list_view.dart';

/// Owns home-page note deletion and favorite mutations.
class HomeNoteMutationActions {
  HomeNoteMutationActions({
    required this.context,
    required this.isMounted,
    required this.noteListKey,
    required this.onTrashGuideRequested,
  });

  final BuildContext context;
  final bool Function() isMounted;
  final GlobalKey<NoteListViewState> noteListKey;
  final VoidCallback onTrashGuideRequested;

  Timer? _trashSnackBarTimer;
  bool _disposed = false;

  bool get _active => !_disposed && isMounted() && context.mounted;

  Future<void> delete(Quote quote) async {
    final quoteId = quote.id;
    if (!_active || quoteId == null) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final database = context.read<DatabaseService>();

    try {
      await database.deleteQuote(quoteId);
      if (!_active) return;

      _trashSnackBarTimer?.cancel();
      const duration = Duration(seconds: 3);
      messenger.clearSnackBars();
      final controller = messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.noteMovedToTrash),
          duration: duration,
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: l10n.undoDelete,
            onPressed: () => unawaited(_restore(database, quoteId, l10n)),
          ),
        ),
      );
      _trashSnackBarTimer = Timer(duration, () {
        if (_active) controller.close();
      });
      onTrashGuideRequested();
    } catch (error, stackTrace) {
      logError(
        '移动笔记到回收站失败: $error',
        error: error,
        stackTrace: stackTrace,
        source: 'HomeNoteMutationActions',
      );
      if (!_active) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.deleteFailed(error.toString())),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _restore(
    DatabaseService database,
    String quoteId,
    AppLocalizations l10n,
  ) async {
    if (!_active) return;
    _trashSnackBarTimer?.cancel();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await database.restoreQuote(quoteId);
      if (!_active) return;
      noteListKey.currentState?.triggerInsertAnimation(
        quoteId,
        animateListInsertion: true,
      );
    } catch (error, stackTrace) {
      logError(
        '撤销删除失败: $error',
        error: error,
        stackTrace: stackTrace,
        source: 'HomeNoteMutationActions',
      );
      if (!_active) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.restoreFailed),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> favorite(Quote quote) async {
    final quoteId = quote.id;
    if (!_active || quoteId == null) return;
    try {
      await context.read<DatabaseService>().incrementFavoriteCount(quoteId);
      if (!isMounted() || !context.mounted || _disposed) return;
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.favorite, color: Colors.red, size: 16),
              const SizedBox(width: 8),
              Text(l10n.favoriteCountWithNum(quote.favoriteCount + 1)),
            ],
          ),
          duration: const Duration(milliseconds: 1500),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red.shade400,
        ),
      );
    } catch (error, stackTrace) {
      logError(
        '增加收藏次数失败: id=$quoteId',
        error: error,
        stackTrace: stackTrace,
        source: 'HomeNoteMutationActions',
      );
      if (!isMounted() || !context.mounted || _disposed) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).favoriteFailed),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> clearFavorite(Quote quote) async {
    final quoteId = quote.id;
    if (!_active || quoteId == null || quote.favoriteCount <= 0) return;
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.clearFavoriteTitle),
        content: Text(l10n.clearFavoriteMessage(quote.favoriteCount)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !isMounted() || !context.mounted || _disposed) {
      return;
    }

    try {
      await context.read<DatabaseService>().resetFavoriteCount(quoteId);
      if (!isMounted() || !context.mounted || _disposed) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.check_circle_outline,
                color: Colors.white,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(l10n.clearFavoriteSuccess),
            ],
          ),
          duration: const Duration(milliseconds: 1500),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error, stackTrace) {
      logError(
        '清除收藏次数失败: id=$quoteId',
        error: error,
        stackTrace: stackTrace,
        source: 'HomeNoteMutationActions',
      );
      if (!isMounted() || !context.mounted || _disposed) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.clearFavoriteFailed),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void dispose() {
    _disposed = true;
    _trashSnackBarTimer?.cancel();
  }
}
