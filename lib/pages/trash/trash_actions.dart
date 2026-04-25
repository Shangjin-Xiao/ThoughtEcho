part of '../trash_page.dart';

extension _TrashPageActions on _TrashPageState {
  void handleScroll() {
    if (!_scrollController.hasClients ||
        _isLoading ||
        _isLoadingMore ||
        !_hasMore) {
      return;
    }
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 200) {
      loadMoreTrashQuotes();
    }
  }

  Future<void> loadTrashQuotes({bool reset = true}) async {
    final db = context.read<DatabaseService>();
    final requestToken = ++_loadRequestToken;
    if (reset) {
      setState(() {
        _isLoading = true;
        _hasMore = true;
        _loadError = false;
        _lastLoadErrorMessage = null;
      });
    } else {
      setState(() {
        _isLoadingMore = true;
      });
    }

    try {
      final quotesFuture = db.getDeletedQuotes(
        offset: reset ? 0 : _trashQuotes.length,
        limit: _pageSize,
      );
      final countFuture = reset ? db.getDeletedQuotesCount() : null;
      final quotes = await quotesFuture;
      final totalCount =
          countFuture == null ? _trashTotalCount : await countFuture;
      if (!mounted || requestToken != _loadRequestToken) {
        return;
      }
      setState(() {
        _trashQuotes = reset ? quotes : [..._trashQuotes, ...quotes];
        _trashTotalCount = totalCount;
        _hasMore = quotes.length == _pageSize;
        _loadError = false;
        _lastLoadErrorMessage = null;
      });
    } catch (e, stackTrace) {
      logError(
        '加载回收站失败: $e',
        error: e,
        stackTrace: stackTrace,
        source: 'TrashPage',
      );
      if (!mounted || requestToken != _loadRequestToken) {
        return;
      }
      setState(() {
        if (reset) {
          _loadError = true;
        }
        _lastLoadErrorMessage = e.toString();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(AppLocalizations.of(context).refreshFailed(e.toString())),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted && requestToken == _loadRequestToken) {
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  Future<void> loadMoreTrashQuotes() async {
    if (_isLoading || _isLoadingMore || !_hasMore) {
      return;
    }
    await loadTrashQuotes(reset: false);
  }

  Future<void> showTrashRetentionSelector() async {
    final l10n = AppLocalizations.of(context);
    final settingsService = context.read<SettingsService>();
    final current = settingsService.trashRetentionDays;
    try {
      final selected = await showModalBottomSheet<int>(
        context: context,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(l10n.trashRetentionOption7Days),
                trailing: current == 7 ? const Icon(Icons.check) : null,
                onTap: () => Navigator.of(context).pop(7),
              ),
              ListTile(
                title: Text(l10n.trashRetentionOption30Days),
                trailing: current == 30 ? const Icon(Icons.check) : null,
                onTap: () => Navigator.of(context).pop(30),
              ),
              ListTile(
                title: Text(l10n.trashRetentionOption90Days),
                trailing: current == 90 ? const Icon(Icons.check) : null,
                onTap: () => Navigator.of(context).pop(90),
              ),
            ],
          ),
        ),
      );
      if (selected == null || selected == current) {
        return;
      }
      await settingsService.setTrashRetentionDays(selected);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.success),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e, stackTrace) {
      logError(
        '设置回收站保留期失败: $e',
        error: e,
        stackTrace: stackTrace,
        source: 'TrashPage',
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.error),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> restoreQuote(String id) async {
    if (_isRunningAction || _isLoadingMore || _isLoading) {
      return;
    }
    setState(() {
      _isRunningAction = true;
    });
    try {
      await context.read<DatabaseService>().restoreQuote(id);
      if (!mounted) {
        return;
      }
      setState(() {
        _trashQuotes = _trashQuotes.where((quote) => quote.id != id).toList();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).noteRestored),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await loadTrashQuotes(reset: true);
    } catch (e, stackTrace) {
      logError(
        '恢复回收站笔记失败: $e',
        error: e,
        stackTrace: stackTrace,
        source: 'TrashPage',
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).restoreFailed),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isRunningAction = false;
        });
      }
    }
  }

  Future<void> permanentlyDelete(String id) async {
    if (_isRunningAction || _isLoadingMore || _isLoading) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.permanentlyDelete),
          content: Text(l10n.permanentlyDeleteConfirmation),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.permanentlyDelete),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) {
        return;
      }

      setState(() {
        _isRunningAction = true;
      });
      await context.read<DatabaseService>().permanentlyDeleteQuote(id);
      if (!mounted) {
        return;
      }
      setState(() {
        _trashQuotes = _trashQuotes.where((quote) => quote.id != id).toList();
      });
      await loadTrashQuotes(reset: true);
    } catch (e, stackTrace) {
      logError(
        '永久删除回收站笔记失败: $e',
        error: e,
        stackTrace: stackTrace,
        source: 'TrashPage',
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.deleteFailed(e.toString())),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isRunningAction = false;
        });
      }
    }
  }

  Future<void> emptyTrash() async {
    if (_isRunningAction ||
        _isLoadingMore ||
        _isLoading ||
        _trashQuotes.isEmpty) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.emptyTrash),
          content: Text(l10n.emptyTrashConfirmation),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.emptyTrash),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) {
        return;
      }

      setState(() {
        _isRunningAction = true;
      });
      await context.read<DatabaseService>().emptyTrash();
      if (!mounted) {
        return;
      }
      setState(() {
        _trashQuotes = const [];
        _trashTotalCount = 0;
        _hasMore = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.trashEmptied),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await loadTrashQuotes(reset: true);
    } catch (e, stackTrace) {
      logError(
        '清空回收站失败: $e',
        error: e,
        stackTrace: stackTrace,
        source: 'TrashPage',
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.deleteFailed(e.toString())),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isRunningAction = false;
        });
      }
    }
  }
}
