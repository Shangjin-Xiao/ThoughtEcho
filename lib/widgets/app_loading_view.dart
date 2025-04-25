import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

class AppLoadingView extends StatelessWidget {
  final double size;
  const AppLoadingView({this.size = 80, super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Lottie.asset('assets/lottie/three-dots-loading.json', width: size, height: size, repeat: true),
    );
  }
} 