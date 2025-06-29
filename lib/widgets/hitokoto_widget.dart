import 'package:flutter/material.dart';
import '../utils/color_utils.dart'; // Import color_utils

class HitokotoWidget extends StatelessWidget {
  final Map<String, dynamic> quote;
  final Function(String?, String?) formatSource;

  const HitokotoWidget({
    super.key,
    required this.quote,
    required this.formatSource,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '每日一言',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              quote['content'] ?? '加载中...',
              style: const TextStyle(fontSize: 14, height: 1.5),
            ),
            if (quote['author'] != null && quote['author'].isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  formatSource(quote['author'], quote['source']),
                  style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.applyOpacity(0.6), // MODIFIED
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
