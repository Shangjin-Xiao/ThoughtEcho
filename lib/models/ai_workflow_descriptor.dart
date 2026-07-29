enum AIWorkflowId {
  polish,
  continueWriting,
  deepAnalysis,
  sourceAnalysis,
  insights,
  webFetch,
}

class AIWorkflowDescriptor {
  const AIWorkflowDescriptor({
    required this.id,
    required this.command,
    required this.displayName,
    required this.requiresBoundNote,
    required this.allowedInStandardMode,
    required this.allowAgentNaturalLanguageTrigger,
    required this.producesEditableResult,
    this.description,
    this.icon,
  });

  final AIWorkflowId id;
  final String command;
  final String displayName;
  final bool requiresBoundNote;
  final bool allowedInStandardMode;
  final bool allowAgentNaturalLanguageTrigger;
  final bool producesEditableResult;
  final String? description; // 简短描述
  final String? icon; // icon标记符
}
