import '../../models/note_proposal_artifact.dart';
import '../../models/rich_text_edit.dart';
import '../../utils/agent_note_document_codec.dart';
import '../../utils/quill_structured_edit.dart';
import '../agent_tool.dart';
import '../database_service.dart';
import 'tag_argument_resolver.dart';

class ProposeNoteCreateTool extends AgentTool {
  const ProposeNoteCreateTool(this._databaseService);

  final DatabaseService _databaseService;

  @override
  String get name => 'propose_note_create';

  @override
  String get description => '提议创建普通或富文本笔记。普通笔记传 content；富文本传语义化的 '
      'document_blocks，由应用生成 Quill Delta。只有用户要求格式或内容确有结构时才选择 rich。';

  @override
  Map<String, Object?> get parametersSchema => const {
        'type': 'object',
        'properties': {
          'proposal_title': {'type': 'string'},
          'reason': {'type': 'string'},
          'document_kind': {
            'type': 'string',
            'enum': ['plain', 'rich'],
          },
          'content': {'type': 'string'},
          'document_blocks': _documentBlocksSchema,
          'tag_ids': {
            'type': 'array',
            'items': {'type': 'string'},
          },
          'author': {'type': 'string'},
          'source': {'type': 'string'},
          'include_location': {'type': 'boolean'},
          'include_weather': {'type': 'boolean'},
        },
        'required': ['proposal_title', 'document_kind'],
      };

  @override
  Future<ToolResult> execute(ToolCall call) async {
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
  'items': {
    'type': 'object',
    'properties': {
      'type': {
        'type': 'string',
        'enum': ['paragraph', 'heading', 'bullet', 'ordered', 'quote', 'code'],
      },
      'level': {'type': 'integer', 'minimum': 1, 'maximum': 6},
      'children': {
        'type': 'array',
        'minItems': 1,
        'items': {
          'type': 'object',
          'properties': {
            'text': {'type': 'string'},
            'bold': {'type': 'boolean'},
            'italic': {'type': 'boolean'},
            'underline': {'type': 'boolean'},
            'strike': {'type': 'boolean'},
            'code': {'type': 'boolean'},
            'link': {'type': 'string'},
          },
          'required': ['text'],
        },
      },
    },
    'required': ['type', 'children'],
  },
};
