import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../gen_l10n/app_localizations.dart';
import '../models/quote_model.dart';
import '../services/database_service.dart';
import '../services/settings_service.dart';
import '../utils/app_logger.dart';
import '../utils/time_utils.dart';

enum _TrashAction { restore, permanentlyDelete }

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
  List<Quote> _trashQuotes = const [];
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    _loadTrashQuotes();
  }

  @override
  void dispose() {
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
      final quotes = await db.getDeletedQuotes(
        offset: reset ? 0 : _trashQuotes.length,
        limit: _pageSize,
      );
      if (!mounted || requestToken != _loadRequestToken) {
        return;
      }
      setState(() {
        _trashQuotes = reset ? quotes : [..._trashQuotes, ...quotes];
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
    return l10n.deletedAt(TimeUtils.formatDateTime(date.toLocal()));
  }

  String _remainingDaysText(BuildContext context, Quote quote) {
    final l10n = AppLocalizations.of(context);
    final retentionDays = context.read<SettingsService>().trashRetentionDays;
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

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.trash),
        actions: [
          TextButton(
            onPressed: (_trashQuotes.isEmpty || _isLoadingMore || _isLoading)
                ? null
                : _emptyTrash,
            child: Text(l10n.emptyTrash),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadError
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, size: 42),
                        const SizedBox(height: 12),
                        Text(
                          l10n.refreshFailed(_lastLoadErrorMessage ?? '-'),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: () => _loadTrashQuotes(reset: true),
                          child: Text(l10n.retry),
                        ),
                      ],
                    ),
                  ),
                )
              : _trashQuotes.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.delete_outline, size: 42),
                          const SizedBox(height: 12),
                          Text(l10n.trashEmpty),
                          const SizedBox(height: 6),
                          Text(l10n.trashEmptyHint),
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline, size: 16),
                              const SizedBox(width: 8),
                              Expanded(child: Text(l10n.trashRetentionHint)),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ListView.separated(
                            controller: _scrollController,
                            itemCount:
                                _trashQuotes.length + (_isLoadingMore ? 1 : 0),
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1, thickness: 0.5),
                            itemBuilder: (context, index) {
                              if (index >= _trashQuotes.length) {
                                return const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 16),
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                );
                              }
                              final quote = _trashQuotes[index];
                              final id = quote.id;
                              return ListTile(
                                title: Text(
                                  quote.content,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(_deletedAtText(context, quote)),
                                    Text(_remainingDaysText(context, quote)),
                                  ],
                                ),
                                isThreeLine: true,
                                trailing: id == null
                                    ? null
                                    : PopupMenuButton<_TrashAction>(
                                        enabled: !_isRunningAction &&
                                            !_isLoadingMore &&
                                            !_isLoading,
                                        onSelected: (action) {
                                          if (action == _TrashAction.restore) {
                                            _restoreQuote(id);
                                            return;
                                          }
                                          _permanentlyDelete(id);
                                        },
                                        itemBuilder: (context) => [
                                          PopupMenuItem<_TrashAction>(
                                            value: _TrashAction.restore,
                                            child: Text(l10n.restoreNote),
                                          ),
                                          PopupMenuItem<_TrashAction>(
                                            value:
                                                _TrashAction.permanentlyDelete,
                                            child: Text(l10n.permanentlyDelete),
                                          ),
                                        ],
                                      ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
    );
  }
}
