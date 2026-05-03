import 'package:flutter/material.dart';

import '../models/note_category.dart';
import '../models/quote_model.dart';
import 'quote_item_widget.dart';

enum TrashQuoteCardAction { restore, permanentlyDelete }

class TrashQuoteCard extends StatefulWidget {
  final Quote quote;
  final String deletedAtText;
  final String remainingDaysText;
  final bool actionsEnabled;
  final ValueChanged<TrashQuoteCardAction>? onActionSelected;
  final Map<String, NoteCategory> tagMap;

  const TrashQuoteCard({
    super.key,
    required this.quote,
    required this.deletedAtText,
    required this.remainingDaysText,
    required this.actionsEnabled,
    required this.tagMap,
    this.onActionSelected,
  });

  @override
  State<TrashQuoteCard> createState() => _TrashQuoteCardState();
}

class _TrashQuoteCardState extends State<TrashQuoteCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return QuoteItemWidget(
      quote: widget.quote,
      tagMap: widget.tagMap,
      isExpanded: _isExpanded,
      onToggleExpanded: (expanded) {
        setState(() {
          _isExpanded = expanded;
        });
      },
      // Dummy functions for required parameters that are hidden in trash mode
      onEdit: () {},
      onDelete: () {},
      onAskAI: () {},
      // Enable trash mode
      isTrashMode: true,
      trashDeletedAtText: widget.deletedAtText,
      trashRemainingDaysText: widget.remainingDaysText,
      trashActionsEnabled: widget.actionsEnabled,
      onRestore: () {
        if (widget.onActionSelected != null) {
          widget.onActionSelected!(TrashQuoteCardAction.restore);
        }
      },
      onPermanentlyDelete: () {
        if (widget.onActionSelected != null) {
          widget.onActionSelected!(TrashQuoteCardAction.permanentlyDelete);
        }
      },
    );
  }
}
