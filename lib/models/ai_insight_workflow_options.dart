class AIInsightWorkflowOption {
  const AIInsightWorkflowOption({
    required this.key,
    required this.l10nKey,
  });

  final String key;
  final String l10nKey;
}

class AIInsightWorkflowOptions {
  static const List<AIInsightWorkflowOption> analysisTypes = [
    AIInsightWorkflowOption(key: 'comprehensive', l10nKey: 'comprehensive'),
    AIInsightWorkflowOption(key: 'emotional', l10nKey: 'emotional'),
    AIInsightWorkflowOption(key: 'mindmap', l10nKey: 'mindmap'),
    AIInsightWorkflowOption(key: 'growth', l10nKey: 'growth'),
  ];

  static const List<AIInsightWorkflowOption> analysisStyles = [
    AIInsightWorkflowOption(key: 'professional', l10nKey: 'professional'),
    AIInsightWorkflowOption(key: 'friendly', l10nKey: 'friendly'),
    AIInsightWorkflowOption(key: 'humorous', l10nKey: 'humorous'),
    AIInsightWorkflowOption(key: 'literary', l10nKey: 'literary'),
  ];
}
