import 'package:flutter/material.dart';
import '../gen_l10n/app_localizations.dart';
import '../models/quote_model.dart';
import '../pages/note_qa_chat_page.dart';

/// 快速问笔记按钮组件
class QuickAskNoteButton extends StatelessWidget {
  final Quote quote;
  final String? initialQuestion;
  final Widget? child;
  final String? tooltip;

  const QuickAskNoteButton({
    super.key,
    required this.quote,
    this.initialQuestion,
    this.child,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: child ?? const Icon(Icons.chat),
      tooltip: tooltip ?? AppLocalizations.of(context).askNote,
      onPressed: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) =>
                NoteQAChatPage(quote: quote, initialQuestion: initialQuestion),
          ),
        );
      },
    );
  }
}

/// 问笔记的浮动按钮组件
class AskNoteFloatingButton extends StatelessWidget {
  final Quote quote;
  final String? initialQuestion;

  const AskNoteFloatingButton({
    super.key,
    required this.quote,
    this.initialQuestion,
  });

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      onPressed: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) =>
                NoteQAChatPage(quote: quote, initialQuestion: initialQuestion),
          ),
        );
      },
      icon: const Icon(Icons.chat),
      label: Text(AppLocalizations.of(context).askNote),
      backgroundColor: Theme.of(
        context,
      ).colorScheme.secondaryContainer, // 使用浅色系
      foregroundColor: Theme.of(
        context,
      ).colorScheme.onSecondaryContainer, // 对应的前景色
    );
  }
}

/// 问笔记的列表项组件
class AskNoteListTile extends StatelessWidget {
  final Quote quote;
  final String? initialQuestion;

  const AskNoteListTile({super.key, required this.quote, this.initialQuestion});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.chat),
      title: Text(AppLocalizations.of(context).askNote),
      subtitle: Text(AppLocalizations.of(context).chatWithAiAssistant),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) =>
                NoteQAChatPage(quote: quote, initialQuestion: initialQuestion),
          ),
        );
      },
    );
  }
}
