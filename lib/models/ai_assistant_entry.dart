enum AIAssistantEntrySource { explore, note }

enum AIAssistantPageMode { chat, noteChat, agent }

class AIAssistantEntryConfig {
  const AIAssistantEntryConfig({required this.source});

  final AIAssistantEntrySource source;

  AIAssistantPageMode get defaultMode => switch (source) {
        AIAssistantEntrySource.explore => AIAssistantPageMode.chat,
        AIAssistantEntrySource.note => AIAssistantPageMode.noteChat,
      };

  bool allowsMode(AIAssistantPageMode mode) => switch (source) {
        AIAssistantEntrySource.explore =>
          mode == AIAssistantPageMode.chat || mode == AIAssistantPageMode.agent,
        AIAssistantEntrySource.note => mode == AIAssistantPageMode.noteChat ||
            mode == AIAssistantPageMode.agent,
      };

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
