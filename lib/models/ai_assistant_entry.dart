enum AIAssistantEntrySource { explore, note }

class AIAssistantEntryConfig {
  const AIAssistantEntryConfig({required this.source});

  final AIAssistantEntrySource source;
}
