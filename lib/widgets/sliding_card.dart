import 'package:flutter/material.dart';

class SlidingCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onSlideComplete;

  const SlidingCard({
    super.key,
    required this.child,
    this.onSlideComplete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return GestureDetector(
      onHorizontalDragEnd: (details) {
        // 检测左滑动作
        if (details.primaryVelocity != null && details.primaryVelocity! < 0 && onSlideComplete != null) {
          onSlideComplete!();
        }
      },
      child: Container(
        padding: const EdgeInsets.all(24),
        child: Card(
          child: Container(
            padding: const EdgeInsets.all(24),
            alignment: Alignment.center,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.format_quote, size: 40),
                const SizedBox(height: 16),
                child,
                const SizedBox(height: 16),
                if (onSlideComplete != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      '← 左滑添加到笔记',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurface.withOpacity(0.5),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
