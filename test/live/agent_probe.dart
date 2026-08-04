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
import 'package:thoughtecho/utils/agent_history_builder.dart';
import 'package:thoughtecho/utils/agent_note_document_codec.dart';
import 'package:thoughtecho/utils/note_proposal_applier.dart';

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

  /// 某个工具返回后立刻在库里搞点事情，用来模拟「用户在另一个入口同时改了笔记」。
  ///
  /// 只在该工具第一次返回时触发一次。事件是流式的、agent 不会等它，所以这里
  /// 记下 Future 由 [finish] 兜底 await，避免测试结束时还有悬空写入。
  void mutateAfterTool(String toolName, Future<void> Function() mutation) {
    _pendingMutations[toolName] = mutation;
  }

  final Map<String, Future<void> Function()> _pendingMutations = {};
  final List<Future<void>> _mutationFutures = [];

  /// 启动探针：装好插件替身、真实 SQLite、真实工具与真实 API 凭据。
  static Future<AgentProbe> start({
    required String scenario,
    required AgentProbeConfig config,
    List<Quote> seedNotes = const [],
    List<String> seedTags = const [],
    List<({String id, String name})> seedTagsWithIds = const [],
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
        await database.addTag(tag);
      } catch (_) {
        // 与系统标签重名时沿用已有的即可。
      }
    }
    // addTag 会拒绝重名，addTagWithId 只记日志不拦——同名标签歧义场景要靠后者播种。
    for (final tag in seedTagsWithIds) {
      await database.addTagWithId(tag.id, tag.name);
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
        required reasoningEffort,
      }) {
        probe._recordRequest(
          messages,
          tools,
          maxTokens,
          streaming,
          reasoningEffort,
        );
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
      // 与 ai_assistant_page_agent.dart:_askAgent 一致：工具轨迹的压缩发生在
      // UI 层而不是 AgentService 里，探针必须自己走同一步，否则喂进去的是
      // 原始消息，AgentService 会把带元数据的消息丢掉，看上去像「记不住」。
      final response = await agent.runAgent(
        userMessage: userMessage,
        history: carryHistory ? AgentHistoryBuilder.build(_history) : const [],
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
    await Future.wait(_mutationFutures);
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
    for (final category in await database.getTags()) {
      try {
        await database.deleteTag(category.id);
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
    openai.ReasoningEffort? reasoningEffort,
  ) {
    _currentTurn?.requests.add({
      'round': (_currentTurn?.requests.length ?? 0) + 1,
      'streaming': streaming,
      'max_tokens': maxTokens,
      'reasoning_effort': reasoningEffort?.name,
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
      case AgentToolCallStartEvent(
          :final toolCallId,
          :final toolName,
          :final arguments
        ):
        turn.events.add('tool_start($toolName)');
        turn.toolCalls.add({
          'id': toolCallId,
          'tool': toolName,
          'arguments': arguments,
          'result': null,
          'isError': false,
        });
      case AgentToolCallResultEvent(
          :final toolCallId,
          :final toolName,
          :final result,
          :final isError
        ):
        turn.events.add('tool_result($toolName, error=$isError)');
        final mutation = _pendingMutations.remove(toolName);
        if (mutation != null) {
          turn.events.add('probe_mutation(after $toolName)');
          _mutationFutures.add(mutation());
        }
        // 只读工具会并行执行：tool_start 先全部发出，结果再陆续回来。按工具名
        // 匹配会把结果挂到同名的另一次调用上，transcript 里就出现「入参 A 配出参
        // B」的假象——必须按 toolCallId 配对。
        final pending = turn.toolCalls.firstWhere(
          (call) => call['id'] == toolCallId,
          orElse: () => turn.toolCalls.lastWhere(
            (call) => call['tool'] == toolName && call['result'] == null,
            orElse: () => <String, Object?>{},
          ),
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
/// 直接调生产的 [NoteProposalApplier.validatedArtifactOps]——这正是采纳按钮走的
/// 那一条校验。以前这里复刻了一份，等于有两份真相；`NoteProposalApplier` 把它
/// 从 `_ThoughterPageState` 里抽出来之后就不需要了。
///
/// 生产那边校验不过是抛 [FormatException]（UI 捕获后提示冲突），跑测台要的是
/// 把问题写进 transcript，所以这里把异常翻成人话。
class ProposalCheck {
  ProposalCheck._(this.problems, this.ops);

  final List<String> problems;
  final List<Map<String, dynamic>>? ops;

  bool get isValid => problems.isEmpty;

  static ProposalCheck of(NoteProposalArtifact artifact, {Quote? original}) {
    try {
      final ops = NoteProposalApplier.validatedArtifactOps(
        artifact,
        original: original,
      );
      return ProposalCheck._(const [], ops);
    } on FormatException catch (error) {
      return ProposalCheck._([_explain(error.message, artifact)], null);
    } catch (error) {
      return ProposalCheck._(['Delta 非法：$error'], null);
    }
  }

  static String _explain(String code, NoteProposalArtifact artifact) {
    switch (code) {
      case 'plain proposal contains delta':
        return 'plain 提案却带了 Delta';
      case 'proposal content and delta differ':
        final plain = AgentNoteDocumentCodec.plainTextOf(
          artifact.documentOps!.cast<Map<String, dynamic>>(),
        );
        return 'content 与 deltaContent 不一致：'
            'content ${artifact.content.length} 字 / delta 还原 ${plain.length} 字';
      case 'proposal changes media references':
        return '提案改动了媒体引用';
      default:
        return code;
    }
  }
}

// ---------------------------------------------------------------------------
// 场景文件共用的输出与校验
// ---------------------------------------------------------------------------

/// 把一轮的概况打到控制台，跑的时候能直接看出轮次、工具和耗时。
void reportTurn(String label, ProbeTurn turn) {
  print('── $label ──');
  print('  轮次 ${turn.roundCount} · 工具 ${turn.toolNames} · '
      '${turn.elapsed.inSeconds}s');
  if (turn.error != null) print('  ❌ ${turn.error}');
  final content = turn.response?.content ?? '';
  print('  回复 ${content.length} 字');
}

/// 对提案做落库前的确定性校验——这是模型行为之外真正该断言的部分。
void checkProposals(ProbeTurn turn, {Quote? original}) {
  final proposals =
      turn.response?.artifacts.whereType<NoteProposalArtifact>().toList() ??
          const <NoteProposalArtifact>[];

  if (proposals.isEmpty) {
    turn.findings.add('这一轮没有产出任何提案卡片。');
    return;
  }
  print('  提案 ${proposals.length} 个');

  for (final proposal in proposals) {
    final check = ProposalCheck.of(
      proposal,
      original: proposal.action == NoteProposalAction.edit ? original : null,
    );
    print('  · ${proposal.action.name}/${proposal.resultKind.name} '
        '${check.isValid ? "✅" : "❌ ${check.problems}"}');
    for (final problem in check.problems) {
      turn.findings.add('提案「${proposal.proposalTitle}」$problem');
    }
    expect(
      check.isValid,
      isTrue,
      reason: '提案无法通过采纳前校验，用户点「采纳」会失败：${check.problems}',
    );
  }
}

/// 自我纠正类场景的统一判据：**有没有走出来**，而不是第一次就填对。
///
/// 模型第一次填错参很正常；真正的问题是错误信息说不清楚、它原样重试撞满
/// `_maxToolFailuresPerSignature`，整轮 `toolExecutionFailed`，用户拿到 0 字。
void reportRecovery(ProbeTurn turn) {
  final failed = turn.toolCalls.where((call) => call['isError'] == true);
  final content = turn.response?.content ?? '';
  print('  失败工具调用 ${failed.length} 次');
  for (final call in failed) {
    print('    ↳ ${call['tool']}: ${_firstLine(call['result']?.toString())}');
  }
  if (turn.error != null) {
    turn.findings.add('没能走出来：整轮抛异常，用户拿不到任何回复。');
  } else if (content.trim().isEmpty) {
    turn.findings.add('没能走出来：没抛异常但最终回复是空的。');
  } else if (failed.isNotEmpty) {
    turn.findings.add(
      '走出来了：${failed.length} 次工具失败后仍给出了 ${content.length} 字回复。'
      '回喂给模型的错误信息见上方工具出参，需人工判断是否说人话。',
    );
  }
}

String _firstLine(String? value) {
  if (value == null || value.isEmpty) return '(空)';
  final line = value.split('\n').first;
  return line.length <= 120 ? line : '${line.substring(0, 120)}…';
}
