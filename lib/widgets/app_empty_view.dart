import 'package:flutter/material.dart';

class AppEmptyView extends StatelessWidget {
  final String? svgAsset;
  final String text;
  final String? message;
  final Widget? animation;
  final VoidCallback? onRefresh;

  const AppEmptyView({
    this.svgAsset,
    required this.text,
    this.message,
    this.animation,
    this.onRefresh,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.inbox,
            size: 72,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(text, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}
