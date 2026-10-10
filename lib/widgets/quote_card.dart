import 'package:flutter/material.dart';

import '../models/quote_model.dart';
import 'quote_card_helpers.dart';

class QuoteCard extends StatelessWidget {
  final Quote quote;

  const QuoteCard({super.key, required this.quote});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = QuoteCardColors.fromHex(quote.colorHex, theme.colorScheme);

    return Card(
      margin: const EdgeInsets.all(16),
      color: colors.cardColor,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              quote.content,
              style: theme.textTheme.titleLarge?.copyWith(
                color: colors.primaryTextColor,
              ),
            ),
            const SizedBox(height: 16),
            _buildSource(context, colors.secondaryTextColor),
          ],
        ),
      ),
    );
  }

  Widget _buildSource(BuildContext context, Color secondaryTextColor) {
    final sourceStyle = Theme.of(context)
        .textTheme
        .bodyMedium
        ?.copyWith(color: secondaryTextColor);

    // 如果有sourceAuthor或sourceWork，优先使用这些值构建显示
    if ((quote.sourceAuthor != null && quote.sourceAuthor!.isNotEmpty) ||
        (quote.sourceWork != null && quote.sourceWork!.isNotEmpty)) {
      String sourceText = '';

      if (quote.sourceAuthor != null && quote.sourceAuthor!.isNotEmpty) {
        sourceText += '——${quote.sourceAuthor}';
      }

      if (quote.sourceWork != null && quote.sourceWork!.isNotEmpty) {
        sourceText += ' 「${quote.sourceWork}」';
      }

      return Text(
        sourceText,
        style: sourceStyle,
        textAlign: TextAlign.right,
      );
    }

    // 如果没有新的字段，则使用原来的source字段
    if (quote.source == null || quote.source!.isEmpty) {
      return const SizedBox.shrink();
    }

    return Text(
      quote.source!,
      style: sourceStyle,
      textAlign: TextAlign.right,
    );
  }
}
