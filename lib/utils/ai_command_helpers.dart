import 'package:uuid/uuid.dart';

import '../models/ai_workflow_descriptor.dart';
import '../models/chat_message.dart' as app_chat;

/// 自然语言触发检测器
class NaturalLanguageTriggerDetector {
  /// 检测输入文本是否包含自然语言命令触发
  static (AIWorkflowId, double)? detectTrigger(String text) {
    if (text.isEmpty || text.startsWith('/')) {
      return null; // 不处理斜杠命令或空文本
    }

    return AIWorkflowCommandRegistry.detectNaturalLanguageTrigger(text);
  }

  /// 检测是否应该自动触发命令
  static AIWorkflowId? shouldAutoTrigger(
    String text,
    List<AIWorkflowDescriptor> descriptors,
  ) {
    final result = detectTrigger(text);
    if (result == null) return null;

    final (workflowId, confidence) = result;

    // 只有当匹配度足够高时才自动触发
    if (confidence >= 0.7) {
      // 检查该工作流是否允许自然语言触发
      for (final descriptor in descriptors) {
        if (descriptor.id == workflowId &&
            descriptor.allowAgentNaturalLanguageTrigger) {
          return workflowId;
        }
      }
    }

    return null;
  }
}

/// 笔记查询助手（用于Agent调用）
class NoteQueryHelper {
  /// 创建搜索笔记工具的参数
  static Map<String, dynamic> createSearchNotesToolParams({
    required String query,
    List<String>? tags,
    DateTime? dateStart,
    DateTime? dateEnd,
    int limit = 20,
  }) {
    return {
      'query': query,
      if (tags != null) 'tags': tags,
      if (dateStart != null) 'date_start': dateStart.toIso8601String(),
      if (dateEnd != null) 'date_end': dateEnd.toIso8601String(),
      'limit': limit,
    };
  }

  /// 格式化笔记数据供Agent使用
  static List<Map<String, dynamic>> formatNotesForAgent(
    List<Map<String, dynamic>> notes, {
    List<List<String>>? tagsList,
    List<double>? matchScores,
  }) {
    final formatted = <Map<String, dynamic>>[];

    for (int i = 0; i < notes.length; i++) {
      final note = notes[i];
      final tags = tagsList != null && i < tagsList.length ? tagsList[i] : [];
      final score = matchScores != null && i < matchScores.length
          ? matchScores[i]
          : 1.0;

      formatted.add({
        'id': note['id'] ?? '',
        'title': _extractTitle(note['content'] ?? '', maxLength: 50),
        'content': note['content'] ?? '',
        'tags': tags,
        'createdAt': note['date'] ?? '',
        'matchScore': score,
        'summary': note['summary'],
        'sentiment': note['sentiment'],
        'keywords': _parseKeywords(note['keywords']),
      });
    }

    return formatted;
  }

  /// 从内容提取标题
  static String _extractTitle(String content, {int maxLength = 50}) {
    if (content.isEmpty) return '';
    final lines = content.split('\n');
    final firstLine = lines.first.trim();
    if (firstLine.length <= maxLength) {
      return firstLine;
    }
    return '${firstLine.substring(0, maxLength)}...';
  }

  /// 解析关键词
  static List<String> _parseKeywords(dynamic keywords) {
    if (keywords == null) return [];
    if (keywords is String) {
      return keywords
          .split(',')
          .map((k) => k.trim())
          .where((k) => k.isNotEmpty)
          .toList();
    }
    if (keywords is List) {
      return keywords.map((k) => k.toString().trim()).toList();
    }
    return [];
  }
}

/// 会话消息助手
class SessionMessageHelper {
  static final _uuid = const Uuid();

  /// 创建工具调用指示消息
  static app_chat.ChatMessage createToolCallIndicatorMessage({
    required String toolName,
    required Map<String, dynamic> parameters,
  }) {
    return app_chat.ChatMessage(
      id: _uuid.v4(),
      content: _buildToolIndicatorContent(toolName, parameters),
      isUser: false,
      role: 'assistant',
      timestamp: DateTime.now(),
      metaJson: _buildToolMetaJson(toolName, parameters),
    );
  }

  /// 创建工具结果消息
  static app_chat.ChatMessage createToolResultMessage({
    required String toolName,
    required String result,
    required bool isError,
  }) {
    return app_chat.ChatMessage(
      id: _uuid.v4(),
      content: isError
          ? '工具执行出错: $result'
          : '[工具结果完成]\n$result',
      isUser: false,
      role: 'assistant',
      timestamp: DateTime.now(),
      metaJson: {
        'type': 'tool_result',
        'tool_name': toolName,
        'is_error': isError,
        'timestamp': DateTime.now().toIso8601String(),
      }.toString(),
    );
  }

  static String _buildToolIndicatorContent(
    String toolName,
    Map<String, dynamic> parameters,
  ) {
    final paramStr = parameters.entries
        .map((e) => '${e.key}=${_formatValue(e.value)}')
        .join(', ');
    return '[正在调用] $toolName($paramStr)';
  }

  static String _buildToolMetaJson(
    String toolName,
    Map<String, dynamic> parameters,
  ) {
    return {
      'type': 'tool_call_indicator',
      'tool_name': toolName,
      'parameters': parameters,
      'timestamp': DateTime.now().toIso8601String(),
    }.toString();
  }

  static String _formatValue(dynamic value) {
    if (value is String) {
      return '"$value"';
    } else if (value is List) {
      return '[${value.join(", ")}]';
    }
    return value.toString();
  }
}

/// Web命令助手
class WebCommandHelper {
  /// 从命令文本提取URL
  /// 支持 `/web <url>` 或 `/web: <url>` 格式
  static String? extractUrl(String text) {
    final trimmed = text.trim();

    // 移除命令前缀：/web、/web:
    String urlPart = '';
    if (trimmed.startsWith('/web:')) {
      urlPart = trimmed.substring(5).trim();
    } else if (trimmed.startsWith('/web')) {
      urlPart = trimmed.substring(4).trim();
    } else {
      return null;
    }

    if (urlPart.isEmpty) {
      return null;
    }

    // 确保URL有协议
    if (!urlPart.startsWith('http://') && !urlPart.startsWith('https://')) {
      urlPart = 'https://$urlPart';
    }

    // 验证URL格式
    final uri = Uri.tryParse(urlPart);
    if (uri == null || !uri.isAbsolute) {
      return null;
    }

    return urlPart;
  }

  /// 检测文本是否包含有效的URL（用于自然语言检测）
  static String? extractUrlFromNaturalLanguage(String text) {
    // 寻找http://或https://开头的URL
    final httpPattern = RegExp(r'https?://[^\s]+');
    final match = httpPattern.firstMatch(text);
    if (match != null) {
      final url = match.group(0) ?? '';
      // 移除末尾的常见标点符号
      return url.replaceAll(RegExp(r'[,。!！?？;；:：）)]*$'), '').trim();
    }
    return null;
  }
}
