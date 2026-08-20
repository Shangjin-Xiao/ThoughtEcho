import 'package:flutter/material.dart';

class AppErrorView extends StatelessWidget {
  final String text;
  const AppErrorView({required this.text, super.key});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error,
              size: 100, color: Theme.of(context).colorScheme.error),
          const SizedBox(height: 16),
          Text(text,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
      ),
    );
  }
}
