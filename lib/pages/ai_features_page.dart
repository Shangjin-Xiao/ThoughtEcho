import 'package:flutter/material.dart';

import 'ai_features_wrapper_page.dart';

/// 旧入口保留：统一跳转到新的 Explore 页面壳层。
class AIFeaturesPage extends StatelessWidget {
  const AIFeaturesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AIFeaturesWrapperPage();
  }
}
