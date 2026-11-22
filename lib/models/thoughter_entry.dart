enum ThoughterEntrySource { explore, note }

/// 开场引文的业务来源，用于在模型上下文中区分周期回顾洞察与每日心迹提示。
enum ThoughterOpeningSource { periodicInsight, dailyPrompt }

extension ThoughterOpeningSourceStorage on ThoughterOpeningSource {
  String get storageValue => switch (this) {
        ThoughterOpeningSource.periodicInsight => 'periodic_insight',
        ThoughterOpeningSource.dailyPrompt => 'daily_prompt',
      };

  static ThoughterOpeningSource? fromStorage(String? value) {
    return switch (value) {
      'periodic_insight' => ThoughterOpeningSource.periodicInsight,
      'daily_prompt' => ThoughterOpeningSource.dailyPrompt,
      _ => null,
    };
  }
}

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
