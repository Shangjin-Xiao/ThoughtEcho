import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../gen_l10n/app_localizations.dart';
import '../models/note_category.dart'; // Added
import '../models/quote_model.dart';
import '../services/database_service.dart';
import '../services/settings_service.dart';
import '../utils/app_logger.dart';
import '../utils/time_utils.dart';
import '../widgets/trash_quote_card.dart';

class TrashPage extends StatefulWidget {
  const TrashPage({super.key});

  @override
  State<TrashPage> createState() => _TrashPageState();
}

class _TrashPageState extends State<TrashPage> {
  static const int _pageSize = 50;

  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  bool _loadError = false;
  String? _lastLoadErrorMessage;
  bool _isRunningAction = false;
  int _loadRequestToken = 0;
  int _trashTotalCount = 0;
  List<Quote> _trashQuotes = const [];
  Map<String, NoteCategory> _tagMap = const {}; // Added
  StreamSubscription<List<NoteCategory>>? _categoriesSubscription;
  final ScrollController _scrollController = ScrollController();

  int get _displayTrashCount =>
      _trashTotalCount > 0 ? _trashTotalCount : _trashQuotes.length;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    _categoriesSubscription =
        context.read<DatabaseService>().watchCategories().listen(
      (tags) {
        if (!mounted) {
          return;
        }
        setState(() {
          _tagMap = {for (var tag in tags) tag.id: tag};
        });
      },
    );
    _loadTrashQuotes();
  }

  @override
  void dispose() {
    _categoriesSubscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients ||
        _isLoading ||
        _isLoadingMore ||
        !_hasMore) {
      return;
    }
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 200) {
      _loadMoreTrashQuotes();
    }
  }

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
    final theme = Theme.of(context);
    try {
      final selected = await showModalBottomSheet<int>(
        context: context,
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  child: Text(
                    l10n.trashRetentionPeriod,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                  leading: const Icon(Icons.history_toggle_off_rounded),
                  title: Text(l10n.trashRetentionOption7Days),
                  trailing: current == 7
                      ? Icon(Icons.check_circle_rounded,
                          color: theme.colorScheme.primary)
                      : null,
                  onTap: () => Navigator.of(context).pop(7),
                ),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                  leading: const Icon(Icons.history_toggle_off_rounded),
                  title: Text(l10n.trashRetentionOption30Days),
                  trailing: current == 30
                      ? Icon(Icons.check_circle_rounded,
                          color: theme.colorScheme.primary)
                      : null,
                  onTap: () => Navigator.of(context).pop(30),
                ),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                  leading: const Icon(Icons.history_toggle_off_rounded),
                  title: Text(l10n.trashRetentionOption90Days),
                  trailing: current == 90
                      ? Icon(Icons.check_circle_rounded,
                          color: theme.colorScheme.primary)
                      : null,
                  onTap: () => Navigator.of(context).pop(90),
                ),
              ],
            ),
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
        _trashTotalCount = (_trashTotalCount - 1).clamp(0, _trashTotalCount);
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
        _trashTotalCount = (_trashTotalCount - 1).clamp(0, _trashTotalCount);
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final retentionDays = context.watch<SettingsService>().trashRetentionDays;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _trashQuotes.isEmpty
              ? l10n.trash
              : l10n.trashCount(_displayTrashCount),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: _showTrashRetentionSelector,
            tooltip: l10n.trashRetentionPeriod,
          ),
          if (_trashQuotes.isNotEmpty)
            TextButton(
              onPressed: (_isLoadingMore || _isLoading || _isRunningAction)
                  ? null
                  : _emptyTrash,
              child: Text(l10n.emptyTrash),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadError
              ? _buildErrorState(l10n)
              : _trashQuotes.isEmpty
                  ? _buildEmptyState(l10n, colorScheme, theme)
                  : RefreshIndicator(
                      onRefresh: () => _loadTrashQuotes(reset: true),
                      child: ListView.builder(
                        controller: _scrollController,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.only(bottom: 32),
                        // +1 for the info banner at the top
                        itemCount:
                            _trashQuotes.length + 1 + (_isLoadingMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            return _buildInfoBanner(l10n, theme, colorScheme);
                          }
                          final itemIndex = index - 1;
                          if (itemIndex >= _trashQuotes.length) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Center(
                                child: CircularProgressIndicator(),
                              ),
                            );
                          }
                          final quote = _trashQuotes[itemIndex];
                          final id = quote.id;
                          return TrashQuoteCard(
                            quote: quote,
                            deletedAtText: _deletedAtText(context, quote),
                            remainingDaysText: _remainingDaysText(
                                context, quote, retentionDays),
                            actionsEnabled: !_isRunningAction &&
                                !_isLoadingMore &&
                                !_isLoading,
                            onActionSelected: id == null
                                ? null
                                : (action) {
                                    if (action ==
                                        TrashQuoteCardAction.restore) {
                                      _restoreQuote(id);
                                    } else {
                                      _permanentlyDelete(id);
                                    }
                                  },
                            tagMap: _tagMap,
                          );
                        },
                      ),
                    ),
    );
  }

  Widget _buildInfoBanner(
      AppLocalizations l10n, ThemeData theme, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 12, 32, 20),
      child: Text(
        l10n.trashRetentionHint,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
          height: 1.5,
        ),
      ),
    );
  }

  Widget _buildEmptyState(
      AppLocalizations l10n, ColorScheme colorScheme, ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.delete_outline_rounded,
              size: 72,
              color: colorScheme.surfaceContainerHighest,
            ),
            const SizedBox(height: 24),
            Text(
              l10n.trashEmpty,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              l10n.trashEmptyHint,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(AppLocalizations l10n) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 16),
            Text(
              l10n.refreshFailed(_lastLoadErrorMessage ?? '-'),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => _loadTrashQuotes(reset: true),
              child: Text(l10n.retry),
            ),
          ],
        ),
      ),
    );
  }
}
