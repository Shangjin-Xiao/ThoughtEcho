import '../../models/note_proposal_artifact.dart';
import '../../models/rich_text_edit.dart';
import '../../utils/agent_note_document_codec.dart';
import '../../utils/quill_structured_edit.dart';
import '../agent_tool.dart';
import '../database_service.dart';
import 'tag_argument_resolver.dart';
import 'tool_argument_validator.dart';

class ProposeNoteCreateTool extends AgentTool {
  const ProposeNoteCreateTool(this._databaseService);

  final DatabaseService _databaseService;

  @override
  String get name => 'propose_note_create';

  @override
  String get description => '提议创建普通或富文本笔记（提案需要用户确认，不会直接落库）。\n'
      'document_kind=plain 时必须提供 content；document_kind=rich 时必须提供 document_blocks，'
      '缺失会得到「普通笔记必须提供 content。」或「富文本笔记必须提供 document_blocks。」错误。\n'
      '只有用户明确要求格式，或正文确有标题、列表、引用等结构时才选 rich；'
      '不要写 Markdown 标记，也不要自行生成 Quill Delta（会被拒绝）。';

  @override
  Map<String, Object?> get parametersSchema => const {
        'type': 'object',
        'properties': {
          'proposal_title': {
            'type': 'string',
            'description': '提案标题，展示在确认卡片顶部。必填且不能为空，否则返回'
                '「proposal_title 不能为空。」',
          },
          'reason': {
            'type': 'string',
            'description': '为什么建议创建这条笔记（一句话）。会展示给用户帮助其判断是否采纳。',
          },
          'document_kind': {
            'type': 'string',
            'enum': ['plain', 'rich'],
            'description': '笔记形态。plain=普通文本（默认首选，必须提供 content）；'
                'rich=富文本（必须提供 document_blocks）。',
          },
          'content': {
            'type': 'string',
            'description': 'document_kind=plain 时的完整正文纯文本。'
                '不要写 Markdown 标记；rich 模式下会被忽略。',
          },
          'document_blocks': _documentBlocksSchema,
          'tag_ids': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': '标签 ID 列表。ID 只能来自 get_tags 的返回，不能编造；'
                '传入不存在的 ID 会得到「不存在的标签 ID: xxx」错误。',
          },
          'tag_names': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': '标签名称列表（仅在拿不到 ID 时的回退）。同名标签存在多个时会返回'
                '「标签名称不唯一，请改用标签 ID」。',
          },
          'author': {
            'type': 'string',
            'description': '摘录来源的作者，只填名字本身（如 `苏轼`）。'
                '显示时应用会自动加上「——」前缀，所以不要自带破折号、书名号或引号。'
                '仅当笔记确实是摘录他人内容时填写，用户原创内容留空，不要臆造。',
          },
          'source': {
            'type': 'string',
            'description': '摘录来源的作品或出处，只填作品名本身（如 `东坡志林`）。'
                '显示时应用会自动包上《》，所以不要自带书名号，否则会显示成《《东坡志林》》。',
          },
          'include_location': {
            'type': 'boolean',
            'description': '是否建议附加当前位置。写此刻见闻、心情、日常片段的笔记通常值得附加；'
                '纯知识整理、待办、摘录通常不需要。不必等用户点名要求，但设为 true 前'
                '必须先调用 get_location_weather 确认确实拿得到数据，不得编造位置。',
          },
          'include_weather': {
            'type': 'boolean',
            'description': '是否建议附加当前天气，判断标准同 include_location。',
          },
        },
        'required': ['proposal_title', 'document_kind'],
      };

  @override
  Future<ToolResult> execute(ToolCall call) async {
    final validationError = validateToolArguments(
      toolName: name,
      schema: parametersSchema,
      arguments: call.arguments,
    );
    if (validationError != null) {
      return _error(call, validationError);
    }
    try {
      final title = call.getString('proposal_title').trim();
      final kind = NoteDocumentKind.values.byName(
        call.getString('document_kind'),
      );
      if (title.isEmpty) {
        throw const FormatException('proposal_title 不能为空。');
      }
      final ops = _documentOps(call, kind);
      final content = AgentNoteDocumentCodec.plainTextOf(ops);
      if (content.trim().isEmpty) {
        throw const FormatException('笔记正文不能为空。');
      }
      final tags = await resolveTagArguments(_databaseService, call.arguments);
      if (tags.hasError) {
        return _error(call, tags.errorMessage!);
      }
      final metadata = <String, Object?>{
        'tag_ids': tags.ids,
        'tag_names': tags.names,
        if (call.getString('author').trim().isNotEmpty)
          'author': call.getString('author').trim(),
        if (call.getString('source').trim().isNotEmpty)
          'source': call.getString('source').trim(),
        if (call.arguments['include_location'] is bool)
          'include_location': call.arguments['include_location'],
        if (call.arguments['include_weather'] is bool)
          'include_weather': call.arguments['include_weather'],
      };
      final artifact = NoteProposalArtifact(
        action: NoteProposalAction.create,
        proposalTitle: title,
        reason: call.getString('reason').trim(),
        resultKind: kind,
        content: content,
        documentOps: kind == NoteDocumentKind.rich ? ops : null,
        metadata: metadata,
        changes: const [],
      );
      return ToolResult(
        toolCallId: call.id,
        content: '笔记提案已准备好，等待用户确认。',
        artifact: artifact,
      );
    } on ArgumentError catch (_) {
      return _error(call, 'document_kind 必须为 plain 或 rich。');
    } on FormatException catch (error) {
      return _error(call, error.message);
    } on AgentNoteDocumentException catch (error) {
      return _error(call, error.code);
    }
  }

  ToolResult _error(ToolCall call, String message) => ToolResult(
        toolCallId: call.id,
        content: message,
        isError: true,
        retryable: true,
      );

  List<Map<String, dynamic>> _documentOps(
    ToolCall call,
    NoteDocumentKind kind,
  ) {
    if (kind == NoteDocumentKind.plain) {
      final content = call.getString('content');
      if (content.isNotEmpty) {
        return AgentNoteDocumentCodec.validateAndNormalize(
          kind,
          [
            {'insert': content}
          ],
        );
      }
      throw const FormatException('普通笔记必须提供 content。');
    } else {
      final blocks = _parseBlocks(call.arguments['document_blocks']);
      if (blocks.isNotEmpty) {
        return AgentNoteDocumentCodec.validateAndNormalize(
          kind,
          QuillStructuredEdit.documentFromBlocks(blocks),
        );
      }
      throw const FormatException('富文本笔记必须提供 document_blocks。');
    }
  }

  List<RichTextBlock> _parseBlocks(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => RichTextBlock.fromJson(
              item.map((key, value) => MapEntry(key.toString(), value)),
            ))
        .toList(growable: false);
  }
}

const Map<String, Object?> _documentBlocksSchema = {
  'type': 'array',
  'minItems': 1,
  'description': '语义化富文本块数组，由应用负责转换成 Quill Delta。'
      'document_kind=rich（或 result_kind=rich）时必须提供；不要提交原始 Delta。',
  'items': {
    'type': 'object',
    'properties': {
      'type': {
        'type': 'string',
        'enum': ['paragraph', 'heading', 'bullet', 'ordered', 'quote', 'code'],
        'description': '块类型：paragraph 段落、heading 标题、bullet 无序列表项、'
            'ordered 有序列表项、quote 引用、code 代码块。',
      },
      'level': {
        'type': 'integer',
        'minimum': 1,
        'maximum': 6,
        'description': 'type=heading 时的标题级别 1-6，其他块类型不要提供。',
      },
      'children': {
        'type': 'array',
        'minItems': 1,
        'description': '该块内的文本片段，按顺序拼接成整块内容；至少一段。',
        'items': {
          'type': 'object',
          'properties': {
            'text': {
              'type': 'string',
              'description': '这一段的纯文本，必填。不要在其中写 Markdown 标记。',
            },
            'bold': {'type': 'boolean', 'description': '是否加粗。'},
            'italic': {'type': 'boolean', 'description': '是否斜体。'},
            'underline': {'type': 'boolean', 'description': '是否下划线。'},
            'strike': {'type': 'boolean', 'description': '是否删除线。'},
            'code': {'type': 'boolean', 'description': '是否行内代码样式。'},
            'link': {'type': 'string', 'description': '超链接地址（可选）。'},
          },
          'required': ['text'],
        },
      },
    },
    'required': ['type', 'children'],
  },
};
