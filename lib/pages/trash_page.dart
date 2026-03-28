import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../gen_l10n/app_localizations.dart';
import '../models/quote_model.dart';
import '../services/database_service.dart';
import '../services/settings_service.dart';
import '../utils/time_utils.dart';

class TrashPage extends StatefulWidget {
  const TrashPage({super.key});

  @override
  State<TrashPage> createState() => _TrashPageState();
}

class _TrashPageState extends State<TrashPage> {
  bool _isLoading = true;
  bool _isRunningAction = false;
  List<Quote> _trashQuotes = const [];

  @override
  void initState() {
    super.initState();
    _loadTrashQuotes();
  }

  Future<void> _loadTrashQuotes() async {
    setState(() {
      _isLoading = true;
    });
    final db = context.read<DatabaseService>();
    final quotes = await db.getDeletedQuotes(limit: 1000);
    if (!mounted) {
      return;
    }
    setState(() {
      _trashQuotes = quotes;
      _isLoading = false;
    });
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
    if (_isRunningAction) {
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).noteRestored),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _loadTrashQuotes();
    } finally {
      if (mounted) {
        setState(() {
          _isRunningAction = false;
        });
      }
    }
  }

  Future<void> _permanentlyDelete(String id) async {
    if (_isRunningAction) {
      return;
    }
    final l10n = AppLocalizations.of(context);
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
    try {
      await context.read<DatabaseService>().permanentlyDeleteQuote(id);
      if (!mounted) {
        return;
      }
      await _loadTrashQuotes();
    } finally {
      if (mounted) {
        setState(() {
          _isRunningAction = false;
        });
      }
    }
  }

  Future<void> _emptyTrash() async {
    if (_isRunningAction || _trashQuotes.isEmpty) {
      return;
    }
    final l10n = AppLocalizations.of(context);
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
    try {
      await context.read<DatabaseService>().emptyTrash();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.trashEmptied),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _loadTrashQuotes();
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
            onPressed: _trashQuotes.isEmpty ? null : _emptyTrash,
            child: Text(l10n.emptyTrash),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
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
                        itemCount: _trashQuotes.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, thickness: 0.5),
                        itemBuilder: (context, index) {
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
                                : Wrap(
                                    spacing: 4,
                                    children: [
                                      TextButton(
                                        onPressed: _isRunningAction
                                            ? null
                                            : () => _restoreQuote(id),
                                        child: Text(l10n.restoreNote),
                                      ),
                                      TextButton(
                                        onPressed: _isRunningAction
                                            ? null
                                            : () => _permanentlyDelete(id),
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
