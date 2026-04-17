import 'dart:io';

import 'package:ddgs/ddgs.dart';

import '../../utils/app_logger.dart';
import '../agent_tool.dart';
import '../settings_service.dart';

/// 搜索互联网获取实时信息（使用 ddgs 库）
///
/// 语言检测优先级：
/// 1. 应用语言设置（最优先）
/// 2. 系统语言环境（仅当应用设置为null时）
/// 3. 搜索词是否包含中文（备选指标，仅当无法获取应用设置时）
class WebSearchTool extends AgentTool {
  static const int _defaultLimit = 5;
  static const int _maxLimit = 10;

  final SettingsService? _settingsService;

  /// 创建 WebSearchTool
  ///
  /// [settingsService] 可选，用于获取用户应用语言设置。
  /// 如果不提供，将仅使用系统语言和搜索词检测。
  const WebSearchTool([this._settingsService]);

  @override
  String get name => 'web_search';

  @override
  String get description => '【只读】通过外部搜索引擎搜索实时信息。此工具仅用于获取信息。';

  @override
  Map<String, Object?> get parametersSchema => {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description': '搜索关键词',
          },
          'limit': {
            'type': 'integer',
            'description': '最大返回结果数（默认 5）',
          },
        },
        'required': ['query'],
      };

  @override
  Future<ToolResult> execute(ToolCall call) async {
    final query = call.getString('query');
    final requestedLimit = call.getInt('limit', defaultValue: _defaultLimit);
    final limit = requestedLimit.clamp(1, _maxLimit);

    if (query.trim().isEmpty) {
      return ToolResult(
        toolCallId: call.id,
        content: '搜索关键词不能为空',
        isError: true,
      );
    }

    try {
      final isChinese = _detectLanguageIsChinese(query);

      // 中文查询优先使用 bing（中文搜索质量更高），否则使用 auto（多引擎）
      final backend = isChinese ? 'bing' : 'auto';
      final region = isChinese ? 'cn-zh' : 'us-en';

      final appLangInfo = _settingsService?.localeCode != null
          ? '应用语言: ${_settingsService!.localeCode}'
          : '应用语言: 跟随系统';
      logDebug(
          'WebSearchTool: $appLangInfo, 检测结果: ${isChinese ? "Chinese" : "Other"}, 使用 $backend ($region) 搜索 "$query"');

      final ddgs = DDGS(timeout: const Duration(seconds: 15));
      try {
        final results = await ddgs.text(
          query,
          backend: backend,
          region: region,
          maxResults: limit,
        );

        if (results.isEmpty) {
          return ToolResult(
            toolCallId: call.id,
            content: '未找到与「$query」相关的搜索结果。',
          );
        }

        final buffer = StringBuffer('搜索「$query」的结果：\n\n');
        for (var i = 0; i < results.length; i++) {
          final result = results[i];
          final title = result['title']?.toString() ?? '无标题';
          final snippet = result['body']?.toString() ??
              result['description']?.toString() ??
              '';
          final href = result['href']?.toString() ?? '';

          buffer.writeln('${i + 1}. $title');
          if (href.isNotEmpty) {
            buffer.writeln('   链接: $href');
          }
          if (snippet.isNotEmpty) {
            buffer.writeln('   摘要: $snippet');
          }
          buffer.writeln();
        }

        return ToolResult(toolCallId: call.id, content: buffer.toString());
      } finally {
        ddgs.close();
      }
    } catch (e, stack) {
      call.logError('WebSearchTool.execute 失败', error: e, stackTrace: stack);
      return ToolResult(
        toolCallId: call.id,
        content: '网络搜索时出错：$e',
        isError: true,
      );
    }
  }

  /// 检测语言是否为中文
  ///
  /// 优先级顺序：
  /// 1. 检查应用语言设置（如果提供了SettingsService）
  /// 2. 检查系统语言环境 (Platform.localeName)
  /// 3. 检查搜索词是否包含中文字符（备选指标）
  bool _detectLanguageIsChinese(String query) {
    // 优先级1：应用语言设置
    if (_settingsService != null) {
      final localeCode = _settingsService.localeCode;
      if (localeCode != null) {
        // 用户显式设置了应用语言
        return localeCode.toLowerCase().startsWith('zh');
      }
      // 如果localeCode为null，表示跟随系统，继续检查系统语言
    }

    // 优先级2：系统语言环境
    if (Platform.localeName.toLowerCase().startsWith('zh')) {
      return true;
    }

    // 优先级3：搜索词是否包含中文（备选指标）
    return _containsChinese(query);
  }

  /// 检查字符串是否包含中文字符
  static bool _containsChinese(String text) {
    return RegExp(r'[\u4e00-\u9fa5]').hasMatch(text);
  }
}
