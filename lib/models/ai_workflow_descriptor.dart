enum AIWorkflowId {
  polish,
  continueWriting,
  deepAnalysis,
  sourceAnalysis,
  insights,
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
  });

  final AIWorkflowId id;
  final String command;
  final String displayName;
  final bool requiresBoundNote;
  final bool allowedInStandardMode;
  final bool allowAgentNaturalLanguageTrigger;
  final bool producesEditableResult;
}

class AIWorkflowCommandRegistry {
  static const Map<String, AIWorkflowId> aliases = <String, AIWorkflowId>{
    '/润色': AIWorkflowId.polish,
    '/polish': AIWorkflowId.polish,
    '/续写': AIWorkflowId.continueWriting,
    '/continue': AIWorkflowId.continueWriting,
    '/深度分析': AIWorkflowId.deepAnalysis,
    '/分析来源': AIWorkflowId.sourceAnalysis,
    '/智能洞察': AIWorkflowId.insights,
  };

  static AIWorkflowId? match(String text) {
    final trimmed = text.trim();
    return aliases[trimmed] ?? aliases[trimmed.toLowerCase()];
  }
}
