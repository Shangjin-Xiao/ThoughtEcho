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
          const Icon(Icons.error, size: 100, color: Colors.red),
          const SizedBox(height: 16),
          Text(text, style: const TextStyle(color: Colors.red)),
        ],
      ),
    );
  }
}
