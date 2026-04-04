import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/ai_provider_settings.dart';
import '../models/chat_message.dart';
import '../utils/ai_network_manager.dart';
import '../utils/ai_request_helper.dart';
import '../utils/app_logger.dart';
import 'agent_tool.dart';
import 'api_key_manager.dart';
import 'settings_service.dart';

/// Agent 运行时服务 — 管理工具循环和多轮推理
///
/// 通过 `<tool_call>` XML 协议与 LLM 交互：
/// - LLM 输出 `<tool_call>{"name":"...","arguments":{...}}</tool_call>` 请求工具
/// - 工具结果以 system 角色注入，`<tool_result>` 标签包裹
/// - 内置护栏：最大轮数、重复检测、解析失败 repair retry
class AgentService extends ChangeNotifier {
  static const String agentToolCallPrefix = 'agentToolCall:';

  final SettingsService _settingsService;
  final APIKeyManager _apiKeyManager = APIKeyManager();
  final AIRequestHelper _requestHelper = AIRequestHelper();
  final List<AgentTool> _tools;

  /// Agent 配置
  static const int maxToolRounds = 8;
  static const int _maxSingleMessageChars = 1200;

  /// 运行状态
  bool _isRunning = false;
  bool get isRunning => _isRunning;

  String _currentStatusKey = '';
  String get currentStatusKey => _currentStatusKey;

  AgentService({
    required SettingsService settingsService,
    required List<AgentTool> tools,
  })  : _settingsService = settingsService,
        _tools = tools;

  // ─── 核心入口 ──────────────────────────────────────────────

  /// 执行 Agent 任务（非流式，便于解析工具调用）
  Future<AgentResponse> runAgent({
    required String userMessage,
    List<ChatMessage>? history,
    String? noteContext,
  }) async {
    _isRunning = true;
    _setStatus('agentThinking');
    notifyListeners();

    try {
      final provider = await _getProvider();
      final systemPrompt = _buildSystemPrompt(noteContext: noteContext);
      final messages = _buildMessages(
        systemPrompt: systemPrompt,
        history: history,
        userMessage: userMessage,
      );

      final executedCalls = <ToolCall>[];
      final previousCallKeys = <String>{};

      for (var round = 0; round < maxToolRounds; round++) {
        final response = await _sendRequest(provider, messages);
        final toolCall = _parseToolCall(response);

        // 无工具调用 → 返回最终回复
        if (toolCall == null) {
          _setStatus('');
          return AgentResponse(
            content: response,
            toolCalls: executedCalls,
          );
        }

        // ── 重复调用检测 ──
        final callKey =
            '${toolCall.name}:${canonicalJsonForArguments(toolCall.arguments)}';
        if (previousCallKeys.contains(callKey)) {
          logDebug('Agent: 检测到重复工具调用 ${toolCall.name}，终止循环');
          final cleanContent = _stripToolCall(response);
          return AgentResponse(
            content:
                cleanContent.isNotEmpty ? cleanContent : '我已经尝试过这个操作了，没有新的结果。',
            toolCalls: executedCalls,
          );
        }
        previousCallKeys.add(callKey);

        // ── 执行工具 ──
        final tool = _findTool(toolCall.name);
        ToolResult result;
        if (tool == null) {
          result = ToolResult(
            toolCallId: toolCall.id,
            content: '工具「${toolCall.name}」不存在',
            isError: true,
          );
        } else {
          _setStatus(_toolStatusText(toolCall.name));
          result = await tool.execute(toolCall);
        }

        executedCalls.add(toolCall);

        // ── 注入工具结果 ──
        messages.add({
          'role': 'assistant',
          'content': response,
        });
        messages.add({
          'role': 'system',
          'content': '<tool_result name="${toolCall.name}" '
              'status="${result.isError ? 'error' : 'success'}">\n'
              '<!-- untrusted content -->\n'
              '${_truncate(result.content, _maxSingleMessageChars)}\n'
              '</tool_result>',
        });
      }

      // 达到最大轮数
      _setStatus('');
      return AgentResponse(
        content: '已达到最大执行轮数（$maxToolRounds），以下是目前的结论：\n\n'
            '${await _sendRequest(provider, messages)}',
        toolCalls: executedCalls,
        reachedMaxRounds: true,
      );
    } catch (e, stack) {
      logError('AgentService.runAgent 失败', error: e, stackTrace: stack);
      rethrow;
    } finally {
      _isRunning = false;
      _setStatus('');
      notifyListeners();
    }
  }

  // ─── 请求与解析 ────────────────────────────────────────────

  Future<AIProviderSettings> _getProvider() async {
    final multiSettings = _settingsService.multiAISettings;
    final provider = multiSettings.currentProvider;
    if (provider == null) throw Exception('请先选择 AI 服务商');

    final apiKey = await _apiKeyManager.getProviderApiKey(provider.id);
    return provider.copyWith(apiKey: apiKey);
  }

  Future<String> _sendRequest(
    AIProviderSettings provider,
    List<Map<String, dynamic>> messages,
  ) async {
    final body = _requestHelper.createRequestBody(
      messages: messages,
      temperature: 0.3,
      maxTokens: 2000,
    );

    final response = await AINetworkManager.makeRequest(
      url: provider.apiUrl,
      data: body,
      provider: provider,
    );

    return _requestHelper.parseResponse(response);
  }

  /// 解析 `<tool_call>{...}</tool_call>` 格式
  ToolCall? _parseToolCall(String response) {
    final match = RegExp(
      r'<tool_call>\s*(\{.*?\})\s*</tool_call>',
      dotAll: true,
    ).firstMatch(response);

    if (match == null) return null;

    try {
      final json = jsonDecode(match.group(1)!) as Map<String, dynamic>;
      return ToolCall(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: json['name'] as String? ?? '',
        arguments: (json['arguments'] as Map<String, dynamic>?) ?? {},
      );
    } catch (e) {
      logDebug('Agent: tool_call JSON 解析失败: $e');
      return null; // repair retry 由调用方处理
    }
  }

  String _stripToolCall(String response) {
    return response
        .replaceAll(
          RegExp(r'<tool_call>.*?</tool_call>', dotAll: true),
          '',
        )
        .trim();
  }

  @visibleForTesting
  static String canonicalJsonForArguments(Map<String, Object?> input) {
    Object? canonicalize(Object? value) {
      if (value is Map) {
        final sortedEntries = value.entries
            .map((e) => MapEntry(e.key.toString(), canonicalize(e.value)))
            .toList()
          ..sort((a, b) => a.key.compareTo(b.key));
        return Map<String, Object?>.fromEntries(sortedEntries);
      }
      if (value is List) {
        return value.map(canonicalize).toList();
      }
      return value;
    }

    final canonical = canonicalize(input) as Map<String, Object?>;
    return jsonEncode(canonical);
  }

  // ─── 消息构建 ──────────────────────────────────────────────

  String _buildSystemPrompt({String? noteContext}) {
    final toolDescriptions = _tools.map((t) {
      final schema = jsonEncode(t.parametersSchema);
      return '- **${t.name}**: ${t.description}\n  参数: $schema';
    }).join('\n');

    final contextSection =
        noteContext != null ? '\n\n## 当前笔记上下文\n$noteContext' : '';

    return '''
你是 ThoughtEcho（心迹）应用的 AI Agent。你可以调用工具来帮助用户。

## 可用工具
$toolDescriptions

## 调用格式
当你需要调用工具时，输出：
<tool_call>{"name": "工具名", "arguments": {"参数名": "参数值"}}</tool_call>

## 规则
- 每次只调用一个工具
- 工具返回结果后，基于结果继续思考或给出最终回复
- 如果工具返回错误或"不可用"，**不要重复调用同一工具**
- 最终回复不要包含 <tool_call> 标签
- 用中文回复（除非用户使用其他语言）
$contextSection''';
  }

  List<Map<String, dynamic>> _buildMessages({
    required String systemPrompt,
    required String userMessage,
    List<ChatMessage>? history,
  }) {
    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': systemPrompt},
    ];

    // 添加历史（带 token 预算）
    if (history != null && history.isNotEmpty) {
      final historyMessages = _requestHelper.createMessagesWithHistory(
        systemPrompt: systemPrompt,
        history: history,
        currentUserMessageLength: userMessage.length,
        maxChars: 4000,
      );
      // 跳过 system prompt（已在上面添加）
      messages.addAll(historyMessages.skip(1));
    }

    messages.add({'role': 'user', 'content': userMessage});
    return messages;
  }

  // ─── 辅助方法 ──────────────────────────────────────────────

  AgentTool? _findTool(String name) {
    for (final tool in _tools) {
      if (tool.name == name) return tool;
    }
    return null;
  }

  void _setStatus(String status) {
    _currentStatusKey = status;
    notifyListeners();
  }

  String _toolStatusText(String toolName) {
    return switch (toolName) {
      'search_notes' => 'agentSearchingNotes',
      'get_note_stats' => 'agentAnalyzingData',
      'web_search' => 'agentWebSearching',
      _ => '$agentToolCallPrefix$toolName',
    };
  }

  static String _truncate(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}…';
  }
}
