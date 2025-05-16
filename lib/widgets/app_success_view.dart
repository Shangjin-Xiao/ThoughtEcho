import 'package:flutter/material.dart';

class AppSuccessView extends StatelessWidget {
  final String text;
  const AppSuccessView({required this.text, super.key});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle, size: 100, color: Colors.green),
          const SizedBox(height: 16),
          Text(text, style: const TextStyle(color: Colors.green)),
        ],
      ),
    );
  }
} 