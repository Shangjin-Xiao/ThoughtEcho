import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

class AppSuccessView extends StatelessWidget {
  final String text;
  const AppSuccessView({required this.text, super.key});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Lottie.asset('assets/lottie/success.json', width: 100, height: 100),
          const SizedBox(height: 16),
          Text(text, style: const TextStyle(color: Colors.green)),
        ],
      ),
    );
  }
} 