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

  /// 用户选择摘要消息的前缀，用于历史上下文中表示用户对提问的回复。
  static const String askUserHeader = '[用户选择]';

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

      if (meta['type'] == 'ask_user') {
        final summary = _summarizeAskUser(
          meta,
          cap: traceCap,
        );
        if (summary == null) continue;
        history.add(
          ChatMessage(
            id: '${message.id}_selection',
            role: 'user',
            isUser: true,
            content: summary,
            timestamp: message.timestamp,
          ),
        );
        continue;
      }

      // 提案卡片等：正文本身是模型上一轮的产出，丢掉会让它忘记自己提过什么。
      if (message.content.trim().isNotEmpty) {
        history.add(message);
      }
    }

    return history;
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

  /// 把一条 `ask_user` 元数据压成一段代表用户选择的上下文。
  ///
  /// 返回 null 表示这条提问尚未完成或处于取消状态外且无可用回复。
  static String? _summarizeAskUser(
    Map<String, dynamic> meta, {
    required int cap,
  }) {
    final isCompleted = meta['isCompleted'] == true;
    if (!isCompleted) return null;

    final question = meta['question']?.toString().trim() ?? '';
    final isCancelled = meta['isCancelled'] == true;
    final customText = meta['customText']?.toString().trim();
    final rawOptions = meta['selectedOptions'];
    final selectedOptions = rawOptions is List
        ? rawOptions
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList()
        : const <String>[];

    final buffer = StringBuffer(askUserHeader);
    if (question.isNotEmpty) {
      buffer.write(' 针对「$question」');
    }

    final hasCustom = customText != null && customText.isNotEmpty;
    final hasOptions = selectedOptions.isNotEmpty;

    if (isCancelled) {
      buffer.write('，用户取消了选择。');
    } else if (hasOptions && hasCustom) {
      buffer.write('，用户选择了：${selectedOptions.join('、')}，并补充回复：$customText');
    } else if (hasCustom) {
      buffer.write('，用户回复：$customText');
    } else if (hasOptions) {
      buffer.write('，用户选择了：${selectedOptions.join('、')}');
    } else {
      buffer.write('，用户取消了选择。');
    }

    return _truncate(buffer.toString(), cap);
  }

  static String _truncate(String text, int cap) {
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= cap) return normalized;
    return '${normalized.substring(0, cap)}…（已截断）';
  }
}
