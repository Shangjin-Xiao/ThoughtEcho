part of '../trash_page.dart';

extension _TrashPageActionsExtension on _TrashPageState {
  Future<void> _loadTrashQuotes({bool reset = true}) async {
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

  Future<void> _loadMoreTrashQuotes() async {
    if (_isLoading || _isLoadingMore || !_hasMore) {
      return;
    }
    await _loadTrashQuotes(reset: false);
  }

  String _deletedAtText(BuildContext context, Quote quote) {
    final l10n = AppLocalizations.of(context);
    final deletedAt = quote.deletedAt;
    if (deletedAt == null) {
      return l10n.deletedAt('-');
    }
    final date = DateTime.tryParse(deletedAt);
    if (date == null) {
      return l10n.deletedAt('-');
    }
    // Use relative date format for better readability (e.g., "Today 14:30" vs "2025-06-21 14:30")
    return l10n.deletedAt(
        TimeUtils.formatRelativeDateTimeLocalized(context, date.toLocal()));
  }

  String _remainingDaysText(
    BuildContext context,
    Quote quote,
    int retentionDays,
  ) {
    final l10n = AppLocalizations.of(context);
    final deletedAt = quote.deletedAt;
    if (deletedAt == null) {
      return l10n.trashRemainingDays(retentionDays);
    }
    final deletedTime = DateTime.tryParse(deletedAt)?.toUtc();
    if (deletedTime == null) {
      return l10n.trashRemainingDays(retentionDays);
    }
    final elapsed = DateTime.now().toUtc().difference(deletedTime).inDays;
    final left = (retentionDays - elapsed).clamp(0, retentionDays);
    return l10n.trashRemainingDays(left);
  }

  Future<void> _showTrashRetentionSelector() async {
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

  String _retentionLabel(AppLocalizations l10n, int days) {
    switch (days) {
      case 7:
        return l10n.trashRetentionOption7Days;
      case 90:
        return l10n.trashRetentionOption90Days;
      case 30:
      default:
        return l10n.trashRetentionOption30Days;
    }
  }

  Widget _buildRetentionSelector(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);

    return Consumer<SettingsService>(
      builder: (context, settingsService, _) => Material(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _showTrashRetentionSelector,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  Icons.schedule_outlined,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.trashRetentionPeriod,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _retentionLabel(
                          l10n,
                          settingsService.trashRetentionDays,
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _restoreQuote(String id) async {
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
      await _loadTrashQuotes(reset: true);
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

  Future<void> _permanentlyDelete(String id) async {
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
      await _loadTrashQuotes(reset: true);
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

  Future<void> _emptyTrash() async {
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
      await _loadTrashQuotes(reset: true);
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

  Widget _buildSummaryCard(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.auto_delete_outlined,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.trashCount(_displayTrashCount),
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.trashRetentionHint,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                _buildRetentionSelector(context),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
