import 'package:flutter/material.dart';
import '../utils/color_utils.dart';

class SlidingCard extends StatelessWidget {
  final Widget child;

  const SlidingCard({
    Key? key,
    required this.child,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Container(
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
              // 删除了左滑提示
            ],
          ),
        ),
      ),
    );
  }
}
