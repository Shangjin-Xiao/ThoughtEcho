import 'package:flutter/material.dart';
import 'package:mind_trace/models/quote_model.dart';

class QuoteCard extends StatelessWidget {
  final Quote quote;

  const QuoteCard({Key? key, required this.quote}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              quote.content,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            _buildSource(context),
          ],
        ),
      ),
    );
  }

  Widget _buildSource(BuildContext context) {
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
        style: TextStyle(
          fontSize: 14,
          fontStyle: FontStyle.italic,
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
        ),
        textAlign: TextAlign.right,
      );
    }
    
    // 如果没有新的字段，则使用原来的source字段
    if (quote.source == null || quote.source!.isEmpty) {
      return const SizedBox.shrink();
    }

    return Text(
      quote.source!,
      style: TextStyle(
        fontSize: 14,
        fontStyle: FontStyle.italic,
        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
      ),
      textAlign: TextAlign.right,
    );
  }
} 