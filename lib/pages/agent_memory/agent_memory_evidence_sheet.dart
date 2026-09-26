import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../gen_l10n/app_localizations.dart';
import '../../models/quote_model.dart';
import '../../services/database_service.dart';
import '../../theme/theme_style.dart';
import '../note_full_editor_page.dart';

/// 记忆归因渊源底部抽屉。
///
/// 展示某条记忆或切片归纳所依据的原始笔记，让用户看到系统并非凭空猜测，
/// 并支持一键跳转到笔记详情查看或编辑。
Future<void> showAgentMemoryEvidenceSheet(
  BuildContext context, {
  required List<String> noteIds,
  required String traitDirective,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppShapeTokens.of(context).dialogRadius),
      ),
    ),
    builder: (sheetContext) => _AgentMemoryEvidenceSheetContent(
      noteIds: noteIds,
      traitDirective: traitDirective,
    ),
  );
}

class _AgentMemoryEvidenceSheetContent extends StatefulWidget {
  const _AgentMemoryEvidenceSheetContent({
    required this.noteIds,
    required this.traitDirective,
  });

  final List<String> noteIds;
  final String traitDirective;

  @override
  State<_AgentMemoryEvidenceSheetContent> createState() =>
      _AgentMemoryEvidenceSheetContentState();
}

class _AgentMemoryEvidenceSheetContentState
    extends State<_AgentMemoryEvidenceSheetContent> {
  late Future<List<Quote?>> _notesFuture;

  @override
  void initState() {
    super.initState();
    _notesFuture = _loadQuotes();
  }

  Future<List<Quote?>> _loadQuotes() async {
    final db = context.read<DatabaseService>();
    final results = <Quote?>[];
    for (final id in widget.noteIds) {
      final quote = await db.getQuoteById(id, includeDeleted: true);
      results.add(quote);
    }
    return results;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final shapeTokens = AppShapeTokens.of(context);
    final colorScheme = theme.colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(shapeTokens.dialogRadius),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.outlineVariant,
                    borderRadius:
                        BorderRadius.circular(shapeTokens.buttonRadius),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.menu_book_outlined,
                          size: 20,
                          color: colorScheme.secondary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            l10n.agentMemoryEvidenceTitle(
                                widget.noteIds.length),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.secondaryContainer
                            .withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(
                          shapeTokens.buttonRadius,
                        ),
                      ),
                      child: Text(
                        widget.traitDirective,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSecondaryContainer,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: FutureBuilder<List<Quote?>>(
                  future: _notesFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final notes = snapshot.data ?? const <Quote?>[];
                    if (notes.isEmpty) {
                      return Center(
                        child: Text(
                          l10n.agentMemoryEvidenceNoteDeleted,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      );
                    }

                    return ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: notes.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final quote = notes[index];
                        if (quote == null) {
                          return Card(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                shapeTokens.cardRadius,
                              ),
                            ),
                            color: colorScheme.surfaceContainerHighest,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                l10n.agentMemoryEvidenceNoteDeleted,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          );
                        }

                        final authorText = quote.sourceAuthor?.trim();
                        final hasAuthor =
                            authorText != null && authorText.isNotEmpty;

                        return Card(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              shapeTokens.cardRadius,
                            ),
                          ),
                          color: colorScheme.surfaceContainer,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(
                              shapeTokens.cardRadius,
                            ),
                            onTap: () async {
                              final allTags = await context
                                  .read<DatabaseService>()
                                  .getTags();
                              if (!context.mounted) return;
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => NoteFullEditorPage(
                                    initialContent: quote.content,
                                    initialQuote: quote,
                                    allTags: allTags,
                                  ),
                                ),
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    quote.content,
                                    maxLines: 4,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      if (hasAuthor) ...[
                                        Text(
                                          '—— $authorText',
                                          style: theme.textTheme.labelMedium
                                              ?.copyWith(
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                        const Spacer(),
                                      ] else ...[
                                        const Spacer(),
                                      ],
                                      Text(
                                        quote.date,
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                          color: colorScheme.outline,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Icon(
                                        Icons.arrow_forward_ios_rounded,
                                        size: 12,
                                        color: colorScheme.outline,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
