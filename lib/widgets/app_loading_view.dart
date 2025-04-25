import 'package:flutter/material.dart';

class AppLoadingView extends StatelessWidget {
  final double size;
  const AppLoadingView({this.size = 80, super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: size,
        height: size,
        child: const CircularProgressIndicator(strokeWidth: 3),
      ),
    );
  }
} 