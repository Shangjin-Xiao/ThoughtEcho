import 'dart:convert';

import '../../models/agent_memory.dart';
import '../agent_memory_service.dart';
import '../agent_tool.dart';

/// 维护 Thoughter 长期记忆的写入口。
///
/// 一个工具管 add/update/delete 三个动作，而不是拆成三个工具——工具表已经有
/// 十个条目，弱模型在长列表里选错工具的概率比选错枚举值高得多。
class RememberTool extends AgentTool {
  const RememberTool(this._memory);

  final AgentMemoryService _memory;

  @override
  String get name => 'remember';

  @override
  String get description => '维护你对这个用户的长期记忆。分两层：\n'
      '- `profile`（画像层）：身份、内容偏好、表达偏好、用户对你的纠正。每次对话都会自动注入，'
      '所以只放"应该一直影响你怎么回应"的内容，写成指令句（"回复保持碎句，不要展开成段"），'
      '不要写成观察句。\n'
      '- `fact`（事实层）：不会自动注入，之后靠 `recall` 按需检索。用来放细节：常去的地方、'
      '在做的项目、习惯、他提过的人和事。\n'
      '\n'
      '什么时候写：用户透露了身份或长期偏好、纠正了你的做法（"别写这么长"）、明确说"记住…"。\n'
      '什么时候不写：用户笔记里写过的内容（那归 `explore_notes`，两套检索会打架）、'
      '本轮对话的临时信息、你自己的推测、以及已经记过的同一件事。\n'
      '\n'
      '偏好变了用 `action: "update"` 改同一条，不要再 add 一条相反的——两条互相矛盾的'
      '画像指令会让你随机挑一条遵守。用户说"忘掉…"用 `action: "delete"`。\n'
      '写入后简短告诉用户你记下了什么，不要闷声记。';

  @override
  bool get isReadOnly => false;

  @override
  bool get isConcurrencySafe => false;

  @override
  Map<String, Object?> get parametersSchema => <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'action': <String, Object?>{
            'type': 'string',
            'enum': <String>['add', 'update', 'delete'],
            'description': '默认 add。update 与 delete 需要 `id`，'
                'id 只能来自 `recall` 的返回，不能编造。',
          },
          'layer': <String, Object?>{
            'type': 'string',
            'enum': <String>['profile', 'fact'],
            'description': 'profile 每次对话注入，fact 按需检索。默认 profile。',
          },
          'content': <String, Object?>{
            'type': 'string',
            'description': 'add 与 update 必填。profile 层写成一句指令，'
                '事实层写成一句自包含的陈述（脱离上下文也能看懂）。',
          },
          'id': <String, Object?>{
            'type': 'string',
            'description': 'update 与 delete 必填，指向要改或要删的那条记忆。',
          },
          'kind': <String, Object?>{
            'type': 'string',
            'enum': <String>['identity', 'preference', 'style', 'feedback'],
            'description': 'profile 层的类别：identity 身份与长期在做的事，'
                'preference 想聊/不想被提起什么，style 篇幅语气格式，'
                'feedback 用户对你做法的纠正。默认 preference。',
          },
          'category': <String, Object?>{
            'type': 'string',
            'description': 'fact 层的归类，例如 `地点`、`项目`、`人物`。可省略。',
          },
          'importance': <String, Object?>{
            'type': 'integer',
            'description': 'fact 层的重要度 1-10，参与检索排序。默认 5，'
                '只有长期有效且用户明显在意的才给 8 以上。',
          },
          'trigger_phrases': <String, Object?>{
            'type': 'array',
            'items': <String, Object?>{'type': 'string'},
            'description': 'fact 层的额外检索词：内容里没出现、但用户可能拿来提问的说法。',
          },
        },
        'required': <String>['content'],
      };

  @override
  Future<ToolResult> execute(ToolCall call) async {
    if (!_memory.isEnabled) {
      return ToolResult(
        toolCallId: call.id,
        content: '用户已在设置中关闭长期记忆，本次不写入。不要重试，'
            '也不要向用户解释工具细节。',
        isError: true,
      );
    }

    final action = call.getString('action', defaultValue: 'add').trim();
    final layer = call.getString('layer', defaultValue: 'profile').trim();
    final content = call.getString('content').trim();
    final id = call.getString('id').trim();

    try {
      return switch (action) {
        'delete' => await _delete(call, layer: layer, id: id),
        'update' => await _update(call, layer: layer, id: id, content: content),
        _ => await _add(call, layer: layer, content: content),
      };
    } catch (error) {
      return ToolResult(
        toolCallId: call.id,
        content: '写入记忆失败：$error',
        isError: true,
        retryable: false,
      );
    }
  }

  Future<ToolResult> _add(
    ToolCall call, {
    required String layer,
    required String content,
  }) async {
    if (content.isEmpty) {
      return _invalid(call, 'content 不能为空');
    }

    if (layer == 'fact') {
      final fact = await _memory.addFact(
        content: content,
        category: call.getString('category').trim().isEmpty
            ? null
            : call.getString('category').trim(),
        importance: call.getInt('importance', defaultValue: 5),
        triggerPhrases: _stringList(call.arguments['trigger_phrases']),
      );
      return _ok(call, <String, Object?>{
        'action': 'add',
        'layer': 'fact',
        'id': fact.id,
        'content': fact.content,
        'importance': fact.importance,
      });
    }

    final entry = await _memory.rememberProfile(
      kind: AgentMemoryKindStorage.fromStorage(
        call.getString('kind', defaultValue: 'preference').trim(),
      ),
      directive: content,
    );
    return _ok(call, <String, Object?>{
      'action': 'add',
      'layer': 'profile',
      'id': entry.id,
      'kind': entry.kind.storageValue,
      'directive': entry.directive,
    });
  }

  Future<ToolResult> _update(
    ToolCall call, {
    required String layer,
    required String id,
    required String content,
  }) async {
    if (id.isEmpty) {
      return _invalid(call, 'update 需要 id，先用 recall 拿到要改的那条');
    }
    if (content.isEmpty) {
      return _invalid(call, 'content 不能为空');
    }

    if (layer == 'fact') {
      // 事实层没有原位改写：内容变了就是另一条事实，旧的删掉更干净。
      final removed = await _memory.forgetFact(id);
      if (!removed) {
        return _invalid(call, '没有找到 id 为 $id 的事实');
      }
      final fact = await _memory.addFact(
        content: content,
        category: call.getString('category').trim().isEmpty
            ? null
            : call.getString('category').trim(),
        importance: call.getInt('importance', defaultValue: 5),
        triggerPhrases: _stringList(call.arguments['trigger_phrases']),
      );
      return _ok(call, <String, Object?>{
        'action': 'update',
        'layer': 'fact',
        'id': fact.id,
        'content': fact.content,
      });
    }

    final kindArgument = call.getString('kind').trim();
    final updated = await _memory.editProfileDirective(
      id: id,
      directive: content,
      kind: kindArgument.isEmpty
          ? null
          : AgentMemoryKindStorage.fromStorage(kindArgument),
    );
    if (!updated) {
      return _invalid(call, '没有找到 id 为 $id 的画像条目');
    }
    return _ok(call, <String, Object?>{
      'action': 'update',
      'layer': 'profile',
      'id': id,
      'directive': content,
    });
  }

  Future<ToolResult> _delete(
    ToolCall call, {
    required String layer,
    required String id,
  }) async {
    if (id.isEmpty) {
      return _invalid(call, 'delete 需要 id，先用 recall 拿到要删的那条');
    }
    final removed = layer == 'fact'
        ? await _memory.forgetFact(id)
        : await _memory.forgetProfile(id);
    if (!removed) {
      return _invalid(call, '没有找到 id 为 $id 的记忆');
    }
    return _ok(call, <String, Object?>{
      'action': 'delete',
      'layer': layer,
      'id': id,
    });
  }

  ToolResult _ok(ToolCall call, Map<String, Object?> payload) => ToolResult(
        toolCallId: call.id,
        content: jsonEncode(<String, Object?>{'ok': true, ...payload}),
      );

  ToolResult _invalid(ToolCall call, String message) => ToolResult(
        toolCallId: call.id,
        content: message,
        isError: true,
      );

  static List<String> _stringList(Object? value) {
    if (value is! List) {
      return const <String>[];
    }
    return value
        .map((item) => item?.toString().trim() ?? '')
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }
}
