import 'dart:io';

import 'agent_memory_service.dart';
import 'chat_session_service.dart';
import 'database_service.dart';
import 'large_file_manager.dart';
import 'settings_service.dart';
import '../models/merge_report.dart';
import '../utils/app_logger.dart';

/// AI 对话记录（`chat.db`）与 Thoughter 长期记忆（`agent_memory.db`）的跨端同步编排器。
///
/// 职责边界：
/// - 不直接操作 SQLite 表，SQL 由 [ChatSessionService] 与 [AgentMemoryService] 各自维护；
/// - 统一保证固定合并顺序：笔记（主库已先提交）→ 对话 → 长期记忆；
/// - 基于合并后的 [DatabaseService] 向长期记忆合并提供 Dreaming 笔记依据“看全了”判定；
/// - 严控异常与日志脱敏：任何错误摘要仅保留阶段与异常类型，绝不输出对话正文、笔记正文或记忆文本。
class AssistantDataSyncService {
  AssistantDataSyncService({
    required ChatSessionService chatSessionService,
    required AgentMemoryService agentMemoryService,
    required SettingsService settingsService,
    required DatabaseService databaseService,
  })  : _chatSessionService = chatSessionService,
        _agentMemoryService = agentMemoryService,
        _settingsService = settingsService,
        _databaseService = databaseService;

  ChatSessionService _chatSessionService;
  AgentMemoryService _agentMemoryService;
  // ignore: unused_field
  SettingsService _settingsService;
  DatabaseService _databaseService;

  void updateDependencies({
    required ChatSessionService chatSessionService,
    required AgentMemoryService agentMemoryService,
    required SettingsService settingsService,
    required DatabaseService databaseService,
  }) {
    _chatSessionService = chatSessionService;
    _agentMemoryService = agentMemoryService;
    _settingsService = settingsService;
    _databaseService = databaseService;
  }

  /// 向已写出前序键值（尚未写末尾 `}`）的顶层 JSON 流追加 `chat` 与（开启时）`agent_memory` 段。
  Future<void> writeSections(
    IOSink sink, {
    CancelToken? cancelToken,
  }) async {
    cancelToken?.throwIfCancelled();
    sink.write(',"chat":');
    await _chatSessionService.exportChatSectionStreaming(
      sink,
      cancelToken: cancelToken,
    );

    cancelToken?.throwIfCancelled();
    if (_agentMemoryService.isEnabled) {
      sink.write(',"agent_memory":');
      await _agentMemoryService.exportMemorySectionStreaming(
        sink,
        cancelToken: cancelToken,
      );
    }
  }

  /// 按固定顺序合并载荷中的 `chat` 与 `agent_memory` 段。
  ///
  /// - [throwOnError] 为 `false`（默认，用于手动合并备份与 LocalSend 同步）时，
  ///   将异常脱敏记入 [AssistantSyncStats.errors]，不回滚已提交的主库笔记；
  /// - [throwOnError] 为 `true`（用于 WebDAV 同步）时，遇到任何异常立即抛出脱敏后的
  ///   [StateError]，由调用方中止后续快照上传与水位推进。
  Future<AssistantSyncStats> mergeSections(
    Map<String, dynamic> payload, {
    bool throwOnError = false,
  }) async {
    ChatMergeStats chatStats = const ChatMergeStats();
    MemoryMergeStats memoryStats = const MemoryMergeStats();
    final errors = <String>[];

    // 1. 先合并对话记录
    if (payload.containsKey('chat') && payload['chat'] != null) {
      final rawChat = payload['chat'];
      try {
        if (rawChat is! Map) {
          throw const FormatException('chat 段格式无效');
        }
        final chatMap = rawChat is Map<String, dynamic>
            ? rawChat
            : rawChat.map((k, v) => MapEntry(k.toString(), v));
        chatStats = await _chatSessionService.mergeChatSection(chatMap);
      } catch (e, stack) {
        final safeMsg = _sanitizeSectionError('对话记录', e);
        AppLogger.e(
          safeMsg,
          error: StateError(safeMsg),
          stackTrace: stack,
          source: 'AssistantDataSyncService',
        );
        if (throwOnError) {
          throw StateError(safeMsg);
        }
        errors.add(safeMsg);
      }
    }

    // 2. 再合并长期记忆（基于已合并完成的本地主库判定 Dreaming 笔记依据）
    if (payload.containsKey('agent_memory') &&
        payload['agent_memory'] != null) {
      final rawMemory = payload['agent_memory'];
      try {
        memoryStats = await _agentMemoryService.mergeMemorySection(
          rawMemory,
          isBasisCovered: _isDreamingBasisCovered,
        );
      } catch (e, stack) {
        final safeMsg = _sanitizeSectionError('长期记忆', e);
        AppLogger.e(
          safeMsg,
          error: StateError(safeMsg),
          stackTrace: stack,
          source: 'AssistantDataSyncService',
        );
        if (throwOnError) {
          throw StateError(safeMsg);
        }
        errors.add(safeMsg);
      }
    }

    return AssistantSyncStats(
      sessionsAdded: chatStats.sessionsAdded,
      sessionsUpdated: chatStats.sessionsUpdated,
      sessionsDeleted: chatStats.sessionsDeleted,
      sessionsSkipped: chatStats.sessionsSkipped,
      messagesAdded: chatStats.messagesAdded,
      messagesUpdated: chatStats.messagesUpdated,
      messagesDeleted: chatStats.messagesDeleted,
      messagesSkipped: chatStats.messagesSkipped,
      profilesAdded: memoryStats.profilesAdded,
      profilesUpdated: memoryStats.profilesUpdated,
      profilesDeleted: memoryStats.profilesDeleted,
      factsAdded: memoryStats.factsAdded,
      factsUpdated: memoryStats.factsUpdated,
      factsDeleted: memoryStats.factsDeleted,
      slicesAdded: memoryStats.slicesAdded,
      slicesUpdated: memoryStats.slicesUpdated,
      slicesDeleted: memoryStats.slicesDeleted,
      memorySkippedCount: memoryStats.skippedCount,
      memorySkippedBecauseDisabled: memoryStats.skippedBecauseDisabled,
      errors: List<String>.unmodifiable(errors),
    );
  }

  /// 覆盖恢复载荷中的 `chat` 与 `agent_memory` 段。
  ///
  /// 旧备份包不包含对应顶层键时，保持本地原有对话或记忆不动。
  Future<void> restoreSections(Map<String, dynamic> payload) async {
    if (payload.containsKey('chat') && payload['chat'] != null) {
      final rawChat = payload['chat'];
      if (rawChat is! Map) {
        throw const FormatException('chat 备份段格式无效');
      }
      final chatMap = rawChat is Map<String, dynamic>
          ? rawChat
          : rawChat.map((k, v) => MapEntry(k.toString(), v));
      await _chatSessionService.restoreChatSection(chatMap);
    }

    if (payload.containsKey('agent_memory') &&
        payload['agent_memory'] != null) {
      await _agentMemoryService.restoreMemorySection(payload['agent_memory']);
    }
  }

  Future<bool> _isDreamingBasisCovered(
    String? basisWatermark,
    int? basisNoteCount,
  ) async {
    if (basisWatermark == null ||
        basisNoteCount == null ||
        basisNoteCount < 0) {
      return false;
    }
    final trimmed = basisWatermark.trim();
    if (trimmed.isEmpty || DateTime.tryParse(trimmed) == null) {
      return false;
    }
    final count = await _databaseService.countActiveNotesUpToWatermark(trimmed);
    return count <= basisNoteCount;
  }

  static String _sanitizeSectionError(String sectionLabel, Object error) {
    if (error is FormatException) {
      return '$sectionLabel同步数据格式无效';
    }
    return '$sectionLabel合并失败 (${error.runtimeType})';
  }
}
