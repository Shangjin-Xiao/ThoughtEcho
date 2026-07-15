import '../../models/note_proposal_artifact.dart';
import '../../utils/agent_note_document_codec.dart';
import '../agent_tool.dart';
import '../database_service.dart';
import 'tag_argument_resolver.dart';

class ProposeNoteCreateTool extends AgentTool {
  const ProposeNoteCreateTool(this._databaseService);

  final DatabaseService _databaseService;

  @override
  String get name => 'propose_note_create';

  @override
  String get description => '提议创建普通或富文本笔记。正文使用原生 Quill document_ops；'
      '只有用户要求格式或内容确有结构时才选择 rich。';

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
          'document_ops': {
            'type': 'array',
            'items': {'type': 'object'},
          },
          'tag_ids': {
            'type': 'array',
            'items': {'type': 'string'},
          },
          'author': {'type': 'string'},
          'source': {'type': 'string'},
          'include_location': {'type': 'boolean'},
          'include_weather': {'type': 'boolean'},
        },
        'required': ['proposal_title', 'document_kind', 'document_ops'],
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
      final ops = AgentNoteDocumentCodec.validateAndNormalize(
        kind,
        call.arguments['document_ops'],
      );
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
}
