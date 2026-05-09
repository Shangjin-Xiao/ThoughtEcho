import 'package:flutter/material.dart';

import 'package:thoughtecho/pages/ai_periodic_report_page.dart';

/// Wrapper page that embeds [AIPeriodicReportPage] for use as a tab in navigation.
class AIFeaturesWrapperPage extends StatelessWidget {
  /// Creates an [AIFeaturesWrapperPage] widget.
  const AIFeaturesWrapperPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AIPeriodicReportPage();
  }
}
