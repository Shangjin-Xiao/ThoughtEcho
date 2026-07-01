enum AIAssistantEntrySource { explore, note }

enum AIAssistantPageMode { chat, noteChat, agent }

class AIAssistantEntryConfig {
  const AIAssistantEntryConfig({required this.source});

  final AIAssistantEntrySource source;

  AIAssistantPageMode get defaultMode => AIAssistantPageMode.agent;

  bool allowsMode(AIAssistantPageMode mode) =>
      mode == AIAssistantPageMode.agent;

  AIAssistantPageMode resolveRestoredMode(AIAssistantPageMode? restoredMode) {
    if (restoredMode != null && allowsMode(restoredMode)) {
      return restoredMode;
    }
    return defaultMode;
  }
}

extension AIAssistantPageModeStorage on AIAssistantPageMode {
  String get storageValue => switch (this) {
        AIAssistantPageMode.chat => 'chat',
        AIAssistantPageMode.noteChat => 'note_chat',
        AIAssistantPageMode.agent => 'agent',
      };

  static AIAssistantPageMode? fromStorage(String? value) {
    return switch (value) {
      'chat' => AIAssistantPageMode.chat,
      'note_chat' => AIAssistantPageMode.noteChat,
      'agent' => AIAssistantPageMode.agent,
      _ => null,
    };
  }
}
