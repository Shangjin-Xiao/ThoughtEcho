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

part 'trash/data_loading.dart';
part 'trash/formatters.dart';
part 'trash/retention_selector.dart';
part 'trash/actions.dart';
part 'trash/ui_builders.dart';

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
    _scrollController.addListener(handleScroll);
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
    loadTrashQuotes();
  }

  @override
  void dispose() {
    _categoriesSubscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _trashQuotes.isEmpty
              ? l10n.trash
              : l10n.trashCount(_displayTrashCount),
        ),
        actions: [
          TextButton(
            onPressed: (_trashQuotes.isEmpty ||
                    _isLoadingMore ||
                    _isLoading ||
                    _isRunningAction)
                ? null
                : emptyTrash,
            child: Text(l10n.emptyTrash),
          ),
        ],
      ),
      body: buildMainContent(context),
    );
  }
}
