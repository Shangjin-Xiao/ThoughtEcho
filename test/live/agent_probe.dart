// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openai_dart/openai_dart.dart' as openai;
import 'package:path/path.dart' as p;
import 'package:thoughtecho/models/ai_provider_settings.dart';
import 'package:thoughtecho/models/chat_message.dart' as app_chat;
import 'package:thoughtecho/models/multi_ai_settings.dart';
import 'package:thoughtecho/models/note_proposal_artifact.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/services/agent_service.dart';
import 'package:thoughtecho/services/agent_tool.dart';
import 'package:thoughtecho/services/agent_tools/explore_notes_tool.dart';
import 'package:thoughtecho/services/agent_tools/get_app_context_tool.dart';
import 'package:thoughtecho/services/agent_tools/get_note_detail_tool.dart';
import 'package:thoughtecho/services/agent_tools/propose_note_create_tool.dart';
import 'package:thoughtecho/services/agent_tools/propose_note_edit_tool.dart';
import 'package:thoughtecho/services/agent_tools/web_fetch_tool.dart';
import 'package:thoughtecho/services/agent_tools/web_search_tool.dart';
import 'package:thoughtecho/services/api_key_manager.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/location_service.dart';
import 'package:thoughtecho/services/secure_storage_service.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/services/weather_service.dart';
import 'package:thoughtecho/services/web_fetch_service.dart';
import 'package:thoughtecho/utils/agent_note_document_codec.dart';

import '../test_harness.dart';

/// 无头 agent 跑测台。
///
/// 用真实 API 驱动完整的 [AgentService.runAgent] 循环，把每轮的请求体、模型
/// 返回的 tool_calls、工具入参出参、事件流全部落到 transcript 文件供人阅读。
/// 生产代码除了一个只读的 [AgentRequestObserver] 钩子外没有任何改动，走的是
/// 和 App 里完全一样的流式路径、工具实现和历史构造。
///
/// 定位是**探针**而非断言式测试：模型行为有随机性，写死断言只会得到无谓的
/// 红叉。只有确定性不变量（Delta 合法性、content/deltaContent 一致）才断言。
///
/// 运行见 `test/live/README.md`。

// ---------------------------------------------------------------------------
// 配置
// ---------------------------------------------------------------------------

/// 真实 API 凭据。仓库外文件优先级低于环境变量，两者都没有则整组跳过。
class AgentProbeConfig {
  AgentProbeConfig({
    required this.baseUrl,
    required this.model,
    required this.apiKey,
  });

  final String baseUrl;
  final String model;
  final String apiKey;

  bool get isAvailable => apiKey.isNotEmpty;

  /// 换一个模型跑同一套场景，用于对照不同模型的表现。
  AgentProbeConfig withModel(String model) => AgentProbeConfig(
        baseUrl: baseUrl,
        model: model,
        apiKey: apiKey,
      );

  /// 普通用户能用到的较好模型，按推荐顺序。
  static const String recommendedModel = 'gemma4:31b-cloud';
  static const String strongModel = 'minimax-m3:cloud';

  /// 仓库外的凭据文件，绝不进版本库。
  static String get credentialsPath => p.join(
        Platform.environment['HOME'] ?? '',
        '.thoughtecho-dev',
        'agent-test.env',
      );

  /// 读取顺序：`TE_TEST_*` 环境变量 > `AGENT_TEST_*` 环境变量 > 凭据文件。
  ///
  /// 凭据文件用的是 `AGENT_TEST_*` 前缀，仓库测试约定是 `TE_TEST_*`，
  /// 这里把两套都认下来，跑测台不需要手动 export。
  static AgentProbeConfig load() {
    final fromFile = _readEnvFile(credentialsPath);
    final env = Platform.environment;

    String pick(String suffix, String fallback) {
      return env['TE_TEST_$suffix'] ??
          env['AGENT_TEST_$suffix'] ??
          fromFile['AGENT_TEST_$suffix'] ??
          fromFile['TE_TEST_$suffix'] ??
          fallback;
    }

    return AgentProbeConfig(
      baseUrl: pick('BASE_URL', 'https://ollama.com/v1'),
      model: pick('MODEL', 'gpt-oss:20b-cloud'),
      apiKey: pick('API_KEY', ''),
    );
  }

  static Map<String, String> _readEnvFile(String path) {
    final file = File(path);
    if (!file.existsSync()) return const {};
    final result = <String, String>{};
    for (final rawLine in file.readAsLinesSync()) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final separator = line.indexOf('=');
      if (separator <= 0) continue;
      result[line.substring(0, separator).trim()] =
          line.substring(separator + 1).trim();
    }
    return result;
  }
}

// ---------------------------------------------------------------------------
// Transcript
// ---------------------------------------------------------------------------

/// 一次 [AgentProbe.ask] 的完整记录。
class ProbeTurn {
  ProbeTurn(this.index, this.userMessage);

  final int index;
  final String userMessage;

  /// 每轮发给模型的请求（消息列表已脱敏，不含任何密钥）。
  final List<Map<String, Object?>> requests = [];

  /// 事件流按序落盘，用于判断流式与状态推进是否符合预期。
  final List<String> events = [];

  /// 工具调用的入参与出参。
  final List<Map<String, Object?>> toolCalls = [];

  AgentResponse? response;
  Object? error;
  Duration elapsed = Duration.zero;

  /// 探针自己发现的问题，写进 transcript 供人读。
  final List<String> findings = [];

  int get roundCount => requests.length;

  /// 本轮调用过的工具名，按调用顺序。
  List<String> get toolNames =>
      toolCalls.map((call) => call['tool'].toString()).toList(growable: false);
}

/// 把 transcript 写成人类可读的 Markdown。
class ProbeTranscript {
  ProbeTranscript(this.scenario, this.config);

  final String scenario;
  final AgentProbeConfig config;
  final List<ProbeTurn> turns = [];
  final List<String> notes = [];

  static Directory get outputDirectory =>
      Directory(p.join(Directory.current.path, 'build', 'agent-probe'));

  File write() {
    final directory = outputDirectory;
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }
    final file = File(p.join(directory.path, '$scenario.md'));
    file.writeAsStringSync(_render());
    return file;
  }

  String _render() {
    final buffer = StringBuffer()
      ..writeln('# Agent 跑测台 · $scenario')
      ..writeln()
      ..writeln('- 时间：${DateTime.now().toIso8601String()}')
      ..writeln('- 模型：`${config.model}`')
      ..writeln('- 端点：`${config.baseUrl}`')
      ..writeln();

    if (notes.isNotEmpty) {
      buffer.writeln('## 场景说明');
      buffer.writeln();
      for (final note in notes) {
        buffer.writeln('- $note');
      }
      buffer.writeln();
    }

    final allFindings = [
      for (final turn in turns)
        for (final finding in turn.findings) '第 ${turn.index} 轮：$finding',
    ];
    if (allFindings.isNotEmpty) {
      buffer
        ..writeln('## ⚠️ 观察到的问题')
        ..writeln();
      for (final finding in allFindings) {
        buffer.writeln('- $finding');
      }
      buffer.writeln();
    }

    for (final turn in turns) {
      buffer
        ..writeln('---')
        ..writeln()
        ..writeln('## 第 ${turn.index} 轮')
        ..writeln()
        ..writeln('**用户**：${turn.userMessage}')
        ..writeln()
        ..writeln(
          '**概况**：${turn.roundCount} 个模型轮次 · '
          '${turn.toolCalls.length} 次工具调用 · '
          '${turn.elapsed.inMilliseconds}ms',
        )
        ..writeln();

      if (turn.error != null) {
        buffer
          ..writeln('**❌ 抛出异常**：`${turn.error}`')
          ..writeln();
      }

      if (turn.toolCalls.isNotEmpty) {
        buffer
          ..writeln('### 工具调用')
          ..writeln();
        for (final call in turn.toolCalls) {
          buffer
            ..writeln('#### `${call['tool']}`'
                '${call['isError'] == true ? ' ❌' : ''}')
            ..writeln()
            ..writeln('入参：')
            ..writeln('```json')
            ..writeln(_pretty(call['arguments']))
            ..writeln('```')
            ..writeln()
            ..writeln('出参：')
            ..writeln('```')
            ..writeln(_clip(call['result']?.toString() ?? '', 4000))
            ..writeln('```')
            ..writeln();
        }
      }

      final content = turn.response?.content ?? '';
      buffer
        ..writeln('### 最终回复')
        ..writeln()
        ..writeln(content.isEmpty ? '_（空）_' : content)
        ..writeln();

      buffer
        ..writeln('<details><summary>请求体（${turn.requests.length} 轮）</summary>')
        ..writeln()
        ..writeln('```json')
        ..writeln(_pretty(turn.requests))
        ..writeln('```')
        ..writeln()
        ..writeln('</details>')
        ..writeln()
        ..writeln('<details><summary>事件流（${turn.events.length} 条）</summary>')
        ..writeln()
        ..writeln('```')
        ..writeln(turn.events.join('\n'))
        ..writeln('```')
        ..writeln()
        ..writeln('</details>')
        ..writeln();
    }
    return buffer.toString();
  }

  static String _pretty(Object? value) =>
      const JsonEncoder.withIndent('  ').convert(value);

  static String _clip(String value, int limit) => value.length <= limit
      ? value
      : '${value.substring(0, limit)}\n…（截断，共 ${value.length} 字）';
}

// ---------------------------------------------------------------------------
// 测试替身（只替掉真正碰硬件/网络定位的部分）
// ---------------------------------------------------------------------------

class _ProbeSettingsService extends ChangeNotifier implements SettingsService {
  _ProbeSettingsService(this._provider);

  final AIProviderSettings _provider;

  @override
  String? get localeCode => 'zh';

  @override
  MultiAISettings get multiAISettings => MultiAISettings(
        providers: [_provider],
        currentProviderId: _provider.id,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _ProbeLocationService extends LocationService {
  @override
  String getLocationDisplayText() => '北京市 海淀区';

  @override
  String getFormattedLocation() => '北京市海淀区';
}

class _ProbeWeatherService extends WeatherService {
  @override
  String? get currentWeather => 'clear';

  @override
  String? get temperature => '25°C';
}

// ---------------------------------------------------------------------------
// 探针
// ---------------------------------------------------------------------------

/// 驱动一次完整 agent 会话的无头跑测台。
class AgentProbe {
  AgentProbe._({
    required this.config,
    required this.transcript,
    required this.database,
    required this.agent,
  });

  final AgentProbeConfig config;
  final ProbeTranscript transcript;
  final DatabaseService database;
  final AgentService agent;

  static const String _providerId = 'agent-probe-provider';
  static const MethodChannel _secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  /// 会话历史，形状与 `ai_assistant_page_agent.dart` 保持一致：
  /// 用户消息 + 带 `tool_progress` 元数据的助手消息 + 助手正文。
  final List<app_chat.ChatMessage> _history = [];
  final List<ProbeTurn> _turns = [];

  ProbeTurn? _currentTurn;
  StreamSubscription<AgentEvent>? _subscription;

  /// 启动探针：装好插件替身、真实 SQLite、真实工具与真实 API 凭据。
  static Future<AgentProbe> start({
    required String scenario,
    required AgentProbeConfig config,
    List<Quote> seedNotes = const [],
    List<String> seedTags = const [],
  }) async {
    // flutter_test 默认注入返回 400 的 mock HttpClient，必须解除才能走真实网络。
    HttpOverrides.global = null;

    await TestHarness.initialize();

    final secureStore = <String, String>{};
    SecureStorageService.resetForTesting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, (call) async {
      switch (call.method) {
        case 'read':
          return secureStore[call.arguments['key']];
        case 'write':
          secureStore[call.arguments['key']] = call.arguments['value'];
          return null;
        case 'delete':
          secureStore.remove(call.arguments['key']);
          return null;
        case 'readAll':
          return secureStore;
      }
      return null;
    });

    // 密钥只经 APIKeyManager 写进模拟安全存储，和线上路径一致。
    await APIKeyManager().saveProviderApiKey(_providerId, config.apiKey);

    final database = DatabaseService();
    await database.init();
    // DatabaseService 是单例、TestHarness 的临时根也按 isolate 复用，
    // 场景之间必须清干净，否则上一个场景的笔记会污染 explore_notes 的结果。
    await _resetDatabase(database);
    for (final tag in seedTags) {
      try {
        await database.addCategory(tag);
      } catch (_) {
        // 与系统标签重名时沿用已有的即可。
      }
    }
    for (final note in seedNotes) {
      await database.addQuote(note);
    }

    final settings = _ProbeSettingsService(
      AIProviderSettings(
        id: _providerId,
        name: 'Agent Probe',
        apiKey: '',
        apiUrl: config.baseUrl,
        model: config.model,
      ),
    );

    final transcript = ProbeTranscript(scenario, config);
    late final AgentProbe probe;

    final agent = AgentService(
      settingsService: settings,
      // 与 app_providers.dart:_buildAgentTools 保持一致，只把定位与天气换成
      // 确定性替身——它们依赖平台插件，且不是本次要观察的对象。
      tools: [
        ExploreNotesTool(database),
        GetTagsTool(database),
        GetLocationWeatherTool(
          locationService: _ProbeLocationService(),
          weatherService: _ProbeWeatherService(),
        ),
        GetNoteDetailTool(database),
        WebSearchTool(settings),
        WebFetchTool(WebFetchService()),
        ProposeNoteCreateTool(database),
        ProposeNoteEditTool(database),
      ],
      requestObserver: ({
        required messages,
        required tools,
        required maxTokens,
        required streaming,
      }) {
        probe._recordRequest(messages, tools, maxTokens, streaming);
      },
    );

    probe = AgentProbe._(
      config: config,
      transcript: transcript,
      database: database,
      agent: agent,
    );
    probe._subscription = agent.events.listen(probe._recordEvent);
    return probe;
  }

  /// 发一轮消息并等 agent 跑完，返回该轮的完整记录。
  ///
  /// [carryHistory] 为 false 时模拟「重开会话」——历史仍然保留在探针里，
  /// 但不喂给模型，用于对照跨会话记忆。
  Future<ProbeTurn> ask(
    String userMessage, {
    AgentNoteContext? noteContext,
    bool carryHistory = true,
  }) async {
    final turn = ProbeTurn(_turns.length + 1, userMessage)
      ..findings.addAll(const []);
    _turns.add(turn);
    transcript.turns.add(turn);
    _currentTurn = turn;

    final stopwatch = Stopwatch()..start();
    try {
      final response = await agent.runAgent(
        userMessage: userMessage,
        history: carryHistory ? List.of(_history) : const [],
        noteContext: noteContext,
      );
      turn.response = response;
      _appendHistory(userMessage, response, turn);
    } catch (error) {
      turn.error = error;
      turn.findings.add('runAgent 抛出：$error');
    } finally {
      stopwatch.stop();
      turn.elapsed = stopwatch.elapsed;
      _currentTurn = null;
    }
    return turn;
  }

  /// 关闭探针并落盘 transcript，返回文件路径。
  Future<File> finish() async {
    await _subscription?.cancel();
    agent.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, null);
    final file = transcript.write();
    print('📄 transcript: ${file.path}');
    return file;
  }

  static Future<void> _resetDatabase(DatabaseService database) async {
    final quotes = await database.getAllQuotes(includeDeleted: true);
    for (final quote in quotes) {
      final id = quote.id;
      if (id != null) {
        await database.permanentlyDeleteQuote(id);
      }
    }
    for (final category in await database.getCategories()) {
      try {
        await database.deleteCategory(category.id);
      } catch (_) {
        // 系统标签删不掉，留着即可——它在真机上本来也存在。
      }
    }
  }

  // -- 记录 ---------------------------------------------------------------

  void _recordRequest(
    List<openai.ChatMessage> messages,
    List<openai.Tool> tools,
    int maxTokens,
    bool streaming,
  ) {
    _currentTurn?.requests.add({
      'round': (_currentTurn?.requests.length ?? 0) + 1,
      'streaming': streaming,
      'max_tokens': maxTokens,
      'tools': tools.map((tool) => tool.function.name).toList(),
      'messages': messages.map((message) => message.toJson()).toList(),
    });
  }

  void _recordEvent(AgentEvent event) {
    final turn = _currentTurn;
    if (turn == null) return;
    switch (event) {
      case AgentThinkingEvent():
        turn.events.add('thinking');
      case AgentReasoningDeltaEvent(:final delta):
        turn.events.add('reasoning_delta(${delta.length})');
      case AgentTextDeltaEvent(:final delta):
        turn.events.add('text_delta(${delta.length})');
      case AgentToolCallStartEvent(:final toolName, :final arguments):
        turn.events.add('tool_start($toolName)');
        turn.toolCalls.add({
          'tool': toolName,
          'arguments': arguments,
          'result': null,
          'isError': false,
        });
      case AgentToolCallResultEvent(:final toolName, :final result, :final isError):
        turn.events.add('tool_result($toolName, error=$isError)');
        final pending = turn.toolCalls.lastWhere(
          (call) => call['tool'] == toolName && call['result'] == null,
          orElse: () => <String, Object?>{},
        );
        if (pending.isNotEmpty) {
          pending['result'] = result;
          pending['isError'] = isError;
        }
      case AgentResponseEvent(:final content, :final reachedMaxRounds):
        turn.events.add(
          'response(chars=${content.length}, maxRounds=$reachedMaxRounds)',
        );
        if (reachedMaxRounds) {
          turn.findings.add('命中 maxToolRounds=${AgentService.maxToolRounds}');
        }
      case AgentErrorEvent(:final failureType):
        turn.events.add('error($failureType)');
        turn.findings.add('agent 报错：$failureType');
    }
  }

  /// 复刻 UI 的历史构造，让「记不记得住」的观察结论对生产有效。
  void _appendHistory(
    String userMessage,
    AgentResponse response,
    ProbeTurn turn,
  ) {
    final now = DateTime.now();
    _history.add(
      app_chat.ChatMessage(
        id: 'user-${_history.length}',
        role: 'user',
        isUser: true,
        content: userMessage,
        timestamp: now,
      ),
    );
    if (turn.toolCalls.isNotEmpty) {
      _history.add(
        app_chat.ChatMessage(
          id: 'tools-${_history.length}',
          role: 'assistant',
          isUser: false,
          content: '',
          timestamp: now,
          metaJson: jsonEncode({
            'type': 'tool_progress',
            'items': [
              for (final call in turn.toolCalls)
                {
                  'toolCallId': '',
                  'toolName': call['tool'],
                  'description': '',
                  'status': call['isError'] == true ? 'error' : 'success',
                  'result': call['result'] ?? '',
                  'narrationText': '',
                },
            ],
            'inProgress': false,
            'thinkingText': '',
          }),
        ),
      );
    }
    _history.add(
      app_chat.ChatMessage(
        id: 'assistant-${_history.length}',
        role: 'assistant',
        isUser: false,
        content: response.content,
        timestamp: now,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 提案校验（复刻 ai_assistant_page_ui.dart 的采纳前校验）
// ---------------------------------------------------------------------------

/// 提案落库前的确定性校验结果。
///
/// 采纳逻辑长在 `_AIAssistantPageState` 里，无头跑不动；这里复刻它的
/// `_validatedArtifactOps` 不变量，这几条是模型行为之外真正该断言的东西。
class ProposalCheck {
  ProposalCheck._(this.problems, this.ops);

  final List<String> problems;
  final List<Map<String, dynamic>>? ops;

  bool get isValid => problems.isEmpty;

  static ProposalCheck of(NoteProposalArtifact artifact, {Quote? original}) {
    final problems = <String>[];
    if (artifact.resultKind == NoteDocumentKind.plain) {
      if (artifact.documentOps != null) {
        problems.add('plain 提案却带了 Delta');
      }
      return ProposalCheck._(problems, null);
    }
    List<Map<String, dynamic>>? ops;
    try {
      ops = AgentNoteDocumentCodec.validateAndNormalize(
        NoteDocumentKind.rich,
        artifact.documentOps,
        allowExistingEmbeds: original != null,
      );
    } catch (error) {
      problems.add('Delta 非法：$error');
      return ProposalCheck._(problems, null);
    }
    final plain = AgentNoteDocumentCodec.plainTextOf(ops);
    if (plain != artifact.content) {
      problems.add(
        'content 与 deltaContent 不一致：'
        'content ${artifact.content.length} 字 / delta 还原 ${plain.length} 字',
      );
    }
    if (original != null &&
        !AgentNoteDocumentCodec.hasSameEmbeds(
          ProposeNoteEditTool.opsForQuote(original),
          ops,
        )) {
      problems.add('提案改动了媒体引用');
    }
    return ProposalCheck._(problems, ops);
  }
}
