enum ThoughterEntrySource { explore, note }

enum ThoughterPageMode { chat, noteChat, agent }

class ThoughterEntryConfig {
  const ThoughterEntryConfig({required this.source});

  final ThoughterEntrySource source;

  ThoughterPageMode get defaultMode => ThoughterPageMode.agent;

  bool allowsMode(ThoughterPageMode mode) => mode == ThoughterPageMode.agent;

  ThoughterPageMode resolveRestoredMode(ThoughterPageMode? restoredMode) {
    if (restoredMode != null && allowsMode(restoredMode)) {
      return restoredMode;
    }
    return defaultMode;
  }
}

extension AIAssistantPageModeStorage on ThoughterPageMode {
  String get storageValue => switch (this) {
        ThoughterPageMode.chat => 'chat',
        ThoughterPageMode.noteChat => 'note_chat',
        ThoughterPageMode.agent => 'agent',
      };

  static ThoughterPageMode? fromStorage(String? value) {
    return switch (value) {
      'chat' => ThoughterPageMode.chat,
      'note_chat' => ThoughterPageMode.noteChat,
      'agent' => ThoughterPageMode.agent,
      _ => null,
    };
  }
}
