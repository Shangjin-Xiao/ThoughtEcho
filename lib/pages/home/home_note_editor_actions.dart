import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:thoughtecho/constants/app_constants.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/models/ai_assistant_entry.dart';
import 'package:thoughtecho/models/note_category.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/pages/ai_assistant_page.dart';
import 'package:thoughtecho/pages/note_full_editor_page.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/utils/app_logger.dart';
import 'package:thoughtecho/widgets/add_note_dialog.dart';
import 'package:thoughtecho/widgets/note_list_view.dart';

/// Owns the add/edit routes and persistence feedback launched by the home page.
///
/// The page supplies its observable tag state through narrow callbacks. This
/// keeps editor policy and error handling together without giving this module
/// ownership of the page controller.
class HomeNoteEditorActions {
  HomeNoteEditorActions({
    required this.context,
    required this.isMounted,
    required this.readTags,
    required this.isLoadingTags,
    required this.loadTags,
    required this.releaseNoteSearchFocus,
    required this.noteListKey,
  });

  final BuildContext context;
  final bool Function() isMounted;
  final List<NoteCategory> Function() readTags;
  final bool Function() isLoadingTags;
  final Future<void> Function() loadTags;
  final VoidCallback releaseNoteSearchFocus;
  final GlobalKey<NoteListViewState> noteListKey;

  bool get _active => isMounted() && context.mounted;

  Future<void> add({
    String? prefilledContent,
    String? prefilledAuthor,
    String? prefilledWork,
    Map<String, dynamic>? hitokotoData,
  }) async {
    if (!_active) return;
    releaseNoteSearchFocus();
    FocusScope.of(context).unfocus();
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);

    await loadTags();
    if (!isMounted() || !context.mounted) return;

    if (isLoadingTags() || readTags().isEmpty) {
      logDebug('标签数据未准备好，重新加载标签数据...');
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.loadingDataPleaseWait),
          duration: const Duration(seconds: 1),
        ),
      );
      await loadTags();
      if (!isMounted() || !context.mounted) return;
      if (readTags().isEmpty) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(l10n.noTagsAvailable),
            duration: const Duration(seconds: 2),
          ),
        );
        return;
      }
    }

    final settings = context.read<SettingsService>();
    if (settings.skipNonFullscreenEditor) {
      await _openFullscreenEditor(
        prefilledContent: prefilledContent,
        prefilledAuthor: prefilledAuthor,
        prefilledWork: prefilledWork,
        hitokotoData: hitokotoData,
      );
      return;
    }

    await Future<void>.delayed(Duration.zero);
    if (!isMounted() || !context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      requestFocus: false,
      builder: (sheetContext) => AddNoteDialog(
        prefilledContent: prefilledContent,
        prefilledAuthor: prefilledAuthor,
        prefilledWork: prefilledWork,
        hitokotoData: hitokotoData,
        tags: readTags(),
        onSave: (quote) => _save(quote, isEditing: false),
      ),
    );
    if (!isMounted() || !context.mounted) return;
    releaseNoteSearchFocus();
  }

  void edit(Quote quote) {
    if (!_active) return;
    releaseNoteSearchFocus();
    FocusScope.of(context).unfocus();
    if (quote.editSource == 'fullscreen') {
      _openExistingFullscreenEditor(quote);
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).brightness == Brightness.light
          ? Colors.white
          : Theme.of(context).colorScheme.surface,
      requestFocus: false,
      builder: (sheetContext) => AddNoteDialog(
        initialQuote: quote,
        tags: readTags(),
        onSave: (updatedQuote) => _save(updatedQuote, isEditing: true),
      ),
    ).whenComplete(() {
      if (_active) releaseNoteSearchFocus();
    });
  }

  void askAi(Quote quote) {
    if (!_active) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (routeContext) => AIAssistantPage(
          quote: quote,
          entrySource: AIAssistantEntrySource.note,
        ),
      ),
    );
  }

  Future<void> _save(Quote quote, {required bool isEditing}) async {
    if (!_active) return;
    final database = context.read<DatabaseService>();
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);

    try {
      if (isEditing) {
        final result = await database.updateQuote(quote);
        if (result != QuoteUpdateResult.updated) {
          if (!isMounted() || !context.mounted) return;
          _showSaveFailure(
            quote,
            isEditing: true,
            message: switch (result) {
              QuoteUpdateResult.notFound => l10n.noteNotFound,
              QuoteUpdateResult.skippedDeleted => l10n.noteUpdateSkippedDeleted,
              QuoteUpdateResult.updated => l10n.noteUpdated,
            },
          );
          return;
        }
      } else {
        await database.addQuote(quote);
      }

      if (!isMounted() || !context.mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(isEditing ? l10n.noteUpdated : l10n.noteSaved),
          duration: AppConstants.snackBarDurationImportant,
        ),
      );
      unawaited(loadTags());
      final quoteId = quote.id;
      if (quoteId != null) {
        noteListKey.currentState?.triggerInsertAnimation(
          quoteId,
          animateListInsertion: !isEditing,
        );
      }
    } catch (error, stackTrace) {
      logError(
        '非全屏编辑器保存失败: id=${quote.id}, isEditing=$isEditing',
        error: error,
        stackTrace: stackTrace,
        source: 'HomeNoteEditorActions',
      );
      if (!isMounted() || !context.mounted) return;
      _showSaveFailure(
        quote,
        isEditing: isEditing,
        message: l10n.saveFailedWithError(error.toString()),
      );
    }
  }

  void _showSaveFailure(
    Quote quote, {
    required bool isEditing,
    required String message,
  }) {
    if (!_active) return;
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: AppConstants.snackBarDurationError,
        backgroundColor: Colors.red,
        action: SnackBarAction(
          label: l10n.retry,
          onPressed: () => unawaited(_save(quote, isEditing: isEditing)),
        ),
      ),
    );
  }

  Future<void> _openFullscreenEditor({
    String? prefilledContent,
    String? prefilledAuthor,
    String? prefilledWork,
    Map<String, dynamic>? hitokotoData,
  }) async {
    try {
      final settings = context.read<SettingsService>();
      var content = prefilledContent ?? '';
      var author = prefilledAuthor;
      var work = prefilledWork;
      final isHitokotoQuickAdd = hitokotoData != null;
      if (isHitokotoQuickAdd) {
        content = hitokotoData['hitokoto'] ?? content;
        author = hitokotoData['from_who'] ?? author;
        work = hitokotoData['from'] ?? work;
      }
      final hasExplicitAuthorOrWork = author != null || work != null;
      if (author == null && settings.defaultAuthor?.isNotEmpty == true) {
        author = settings.defaultAuthor;
      }
      if (work == null && settings.defaultSource?.isNotEmpty == true) {
        work = settings.defaultSource;
      }
      if (!_active) return;

      final saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (routeContext) => NoteFullEditorPage(
            initialContent: content,
            initialQuote: null,
            allTags: readTags(),
            initialAuthor: author,
            initialWork: work,
            skipDefaultMetadataAutofill: hasExplicitAuthorOrWork,
            isFromDailyQuote: isHitokotoQuickAdd,
          ),
        ),
      );
      if (saved == true && isMounted()) unawaited(loadTags());
    } catch (error, stackTrace) {
      logError(
        '打开全屏编辑器失败',
        error: error,
        stackTrace: stackTrace,
        source: 'HomeNoteEditorActions',
      );
      if (!isMounted() || !context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).openFullEditorFailedSimple,
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _openExistingFullscreenEditor(Quote quote) {
    try {
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (routeContext) => NoteFullEditorPage(
            initialContent: quote.content,
            initialQuote: quote,
            allTags: readTags(),
          ),
        ),
      );
    } catch (error, stackTrace) {
      logError(
        '打开已有笔记的全屏编辑器失败',
        error: error,
        stackTrace: stackTrace,
        source: 'HomeNoteEditorActions',
      );
      if (!_active) return;
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.cannotOpenFullEditor(error.toString())),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: l10n.retry,
            onPressed: () => _openExistingFullscreenEditor(quote),
            textColor: Colors.white,
          ),
        ),
      );
    }
  }
}
