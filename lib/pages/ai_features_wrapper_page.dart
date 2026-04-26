import 'package:flutter/material.dart';

import 'package:thoughtecho/pages/explore_page.dart';

/// Wrapper page that embeds [ExplorePage] for use as a tab in navigation.
class AIFeaturesWrapperPage extends StatelessWidget {
  /// Creates an [AIFeaturesWrapperPage] widget.
  const AIFeaturesWrapperPage({super.key});

  @override
  Widget build(BuildContext context) {
    // 直接展示 ExplorePage 内容（作为 tab 内嵌使用）
    return const ExplorePage();
  }
}
