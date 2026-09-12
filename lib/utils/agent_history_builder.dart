import '../models/chat_message.dart';

/// 把界面消息列表转换成可以喂给 Agent 的历史。
///
/// 设计取向：会话里存的是「完整事件序列」（含工具轨迹），而发给模型的上下文是
/// 从这个序列**推导**出来的，早期轮次压成摘要而不是原样回放。
///
/// 之所以不把历史工具调用还原成 `assistant.tool_calls` + `tool` 消息对：
/// 跨会话恢复后旧的 `tool_call_id` 已经失效，OpenAI 兼容端点会校验二者配对，
/// 硬塞回去会直接 400。摘要成文本则任何模型都能读，也不影响本轮内真正的
/// tool calling（那部分由 `AgentService.pruneMessages` 按 token 预算裁剪）。
class AgentHistoryBuilder {
  const AgentHistoryBuilder._();

  /// 单条工具结果在摘要里保留的字符数上限。
  static const int defaultToolResultCap = 300;

  /// 单条工具轨迹消息保留的字符数上限。
  static const int defaultTraceCap = 1200;

  /// 工具轨迹摘要消息的前缀，UI 不展示，仅用于喂给模型。
  static const String traceHeader = '[已执行的工具轨迹]';

  /// 构建喂给 Agent 的历史消息列表。
  ///
  /// - 普通 user/assistant 文本消息原样保留；
  /// - `tool_progress` 元数据消息压缩成一条工具轨迹摘要，让模型知道自己
  ///   上一轮（或上一次会话）查过什么、拿到了什么；
  /// - 其余带元数据的消息（提案卡片等）保留其正文，不再整条丢弃；
  /// - 仍在进行中的消息和空消息跳过。
  static List<ChatMessage> build(
    List<ChatMessage> messages, {
    int toolResultCap = defaultToolResultCap,
    int traceCap = defaultTraceCap,
  }) {
    final history = <ChatMessage>[];

    for (final message in messages) {
      if (message.role == 'system' || message.isLoading) {
        continue;
      }

      final meta = message.parsedMeta;
      if (meta == null) {
        if (message.content.trim().isEmpty) continue;
        history.add(message);
        continue;
      }

      if (meta['type'] == 'tool_progress') {
        final trace = _summarizeToolProgress(
          meta,
          toolResultCap: toolResultCap,
          traceCap: traceCap,
        );
        if (trace == null) continue;
        history.add(
          ChatMessage(
            id: '${message.id}_trace',
            role: 'assistant',
            isUser: false,
            content: trace,
            timestamp: message.timestamp,
          ),
        );
        continue;
      }

      if (meta['type'] == 'note_proposal' || meta['type'] == 'noteProposal') {
        final proposalSummary = _summarizeNoteProposal(meta);
        if (proposalSummary != null) {
          final effectiveContent = message.content.trim().isNotEmpty
              ? '${message.content.trim()}\n\n$proposalSummary'
              : proposalSummary;
          history.add(
            ChatMessage(
              id: '${message.id}_proposal',
              role: 'assistant',
              isUser: false,
              content: effectiveContent,
              timestamp: message.timestamp,
            ),
          );
          continue;
        }
      }

      // 提案卡片等：正文本身是模型上一轮的产出，丢掉会让它忘记自己提过什么。
      if (message.content.trim().isNotEmpty) {
        history.add(message);
      }
    }

    return history;
  }

  /// 把建议卡片消息（包含待确认或已保存提案）压成清晰的摘要喂给模型。
  static String? _summarizeNoteProposal(Map<String, dynamic> meta) {
    final artifactMap = meta['artifact'];
    final savedNoteId = meta['saved_note_id']?.toString().trim();
    if (artifactMap is! Map) {
      if (savedNoteId != null && savedNoteId.isNotEmpty) {
        return '[系统提示：用户已采纳你此前生成的笔记建议并保存，笔记 ID 为 $savedNoteId。]';
      }
      return null;
    }

    final action = artifactMap['action']?.toString() ?? 'create';
    final targetTitle = artifactMap['proposal_title']?.toString() ??
        artifactMap['target_title']?.toString() ??
        artifactMap['title']?.toString();
    final targetNoteId = artifactMap['note_id']?.toString() ??
        artifactMap['target_note_id']?.toString();
    final content = artifactMap['content']?.toString() ?? '';
    final changesSummary = artifactMap['reason']?.toString() ??
        artifactMap['changes_summary']?.toString();

    if (savedNoteId != null && savedNoteId.isNotEmpty) {
      return '[已采纳并保存的笔记提案] '
          '笔记 ID: $savedNoteId'
          '${targetTitle != null && targetTitle.isNotEmpty ? '，标题: $targetTitle' : ''}'
          '${changesSummary != null && changesSummary.isNotEmpty ? '，说明: $changesSummary' : ''}';
    }

    final preview =
        content.length > 200 ? '${content.substring(0, 200)}...' : content;
    final actionLabel = action == 'edit' ? '修改笔记' : '新建笔记';
    return '[待确认的笔记提案] '
        '类型: $actionLabel'
        '${targetTitle != null && targetTitle.isNotEmpty ? '，标题: $targetTitle' : ''}'
        '${targetNoteId != null && targetNoteId.isNotEmpty ? '，笔记 ID: $targetNoteId' : ''}'
        '${changesSummary != null && changesSummary.isNotEmpty ? '，修改说明: $changesSummary' : ''}'
        '${preview.isNotEmpty ? '\n提案内容预览: $preview' : ''}';
  }

  /// 把一条 `tool_progress` 元数据压成人类/模型都可读的一段轨迹。
  ///
  /// 返回 null 表示这条消息没有可用信息（例如工具还没跑完）。
  static String? _summarizeToolProgress(
    Map<String, dynamic> meta, {
    required int toolResultCap,
    required int traceCap,
  }) {
    final items = meta['items'];
    if (items is! List || items.isEmpty) return null;

    final lines = <String>[];
    for (final item in items) {
      if (item is! Map) continue;
      final toolName = item['toolName']?.toString().trim() ?? '';
      if (toolName.isEmpty) continue;

      final status = item['status']?.toString().trim() ?? '';
      // 仍在执行中的条目没有结论，写进历史只会误导模型。
      if (status == 'running' || status == 'pending') continue;

      final description = item['description']?.toString().trim() ?? '';
      final result = item['result']?.toString().trim() ?? '';

      final buffer = StringBuffer('- $toolName');
      if (description.isNotEmpty) {
        buffer.write('（$description）');
      }
      if (status == 'error' || status == 'failed') {
        buffer.write(' → 失败');
        if (result.isNotEmpty) {
          buffer.write('：${_truncate(result, toolResultCap)}');
        }
      } else if (result.isNotEmpty) {
        buffer.write(' → ${_truncate(result, toolResultCap)}');
      } else {
        buffer.write(' → 已执行');
      }
      lines.add(buffer.toString());
    }

    if (lines.isEmpty) return null;

    final body = lines.join('\n');
    return '$traceHeader\n${_truncate(body, traceCap)}';
  }

  static String _truncate(String text, int cap) {
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= cap) return normalized;
    return '${normalized.substring(0, cap)}…（已截断）';
  }
}
