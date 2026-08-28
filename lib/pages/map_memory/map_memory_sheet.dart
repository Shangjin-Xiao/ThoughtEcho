part of '../map_memory_page.dart';

/// 点开一个标记后从底部滑出的笔记面板，以及面板上那几个动作。
extension _MapMemorySheet on _MapMemoryPageState {
  Future<void> _openNoteSheet(String quoteId) async {
    final database = context.read<DatabaseService>();

    Quote? quote;
    try {
      quote = await database.getQuoteById(quoteId);
    } catch (e, stack) {
      logError(
        '打开地图笔记失败',
        error: e,
        stackTrace: stack,
        source: 'MapMemoryPage',
      );
    }

    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    if (quote == null) {
      // 地图上的点是上一次加载的快照，这条可能已经在别处被删了
      AppSnackBar.error(context, l10n.noteNotFound);
      return;
    }

    final target = quote;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        builder: (context, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
          children: [
            QuoteItemWidget(
              quote: target,
              tagMap: _tagMap,
              // 面板本来就只放一条笔记，没有"和别的卡片挤在一起"的问题，
              // 直接展开省掉一次点击。
              isExpanded: true,
              onToggleExpanded: (_) {},
              onEdit: () {
                Navigator.pop(sheetContext);
                _editNote(target);
              },
              onDelete: () {
                Navigator.pop(sheetContext);
                _deleteNote(target);
              },
              onAskAI: () {
                Navigator.pop(sheetContext);
                _askThoughter(target);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editNote(Quote quote) async {
    final navigator = Navigator.of(context);
    final saved = await navigator.push<bool>(
      MaterialPageRoute(
        builder: (_) => NoteFullEditorPage(
          initialContent: quote.content,
          initialQuote: quote,
          allTags: _tagMap.values.toList(),
        ),
      ),
    );

    if (!mounted || saved != true) return;
    // 编辑里可能换了位置，标记得跟着挪
    await _load();
  }

  Future<void> _deleteNote(Quote quote) async {
    final quoteId = quote.id;
    if (quoteId == null) return;

    final database = context.read<DatabaseService>();
    final l10n = AppLocalizations.of(context);

    try {
      await database.deleteQuote(quoteId);
      if (!mounted) return;
      AppSnackBar.success(context, l10n.noteMovedToTrash);
      await _load();
    } catch (e, stack) {
      logError(
        '从地图删除笔记失败',
        error: e,
        stackTrace: stack,
        source: 'MapMemoryPage',
      );
      if (!mounted) return;
      AppSnackBar.error(context, l10n.deleteFailed(e.toString()));
    }
  }

  Future<void> _askThoughter(Quote quote) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ThoughterPage(
          entrySource: ThoughterEntrySource.note,
          quote: quote,
        ),
      ),
    );
  }
}
