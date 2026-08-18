import 'package:thoughtecho/theme/app_semantic_colors.dart';
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
          Icon(Icons.check_circle,
              size: 100, color: AppSemanticColors.of(context).success),
          const SizedBox(height: 16),
          Text(text,
              style: TextStyle(color: AppSemanticColors.of(context).success)),
        ],
      ),
    );
  }
}
