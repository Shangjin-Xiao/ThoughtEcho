import 'package:flutter/material.dart';

import 'explore_page.dart';

class AIFeaturesWrapperPage extends StatelessWidget {
  const AIFeaturesWrapperPage({super.key});

  @override
  Widget build(BuildContext context) {
    // 直接展示 ExplorePage 内容（作为 tab 内嵌使用）
    return const ExplorePage();
  }
}
