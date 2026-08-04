import 'dart:convert';

import '../models/note_proposal_artifact.dart';
import '../models/quote_model.dart';
import '../services/agent_tools/propose_note_edit_tool.dart';
import '../services/database_service.dart';
import 'agent_note_document_codec.dart';

/// 采纳提案时的落库结果。
enum NoteProposalApplyStatus {
  /// 已写入数据库。
  applied,

  /// 笔记不存在，或 revision 与提案生成时不一致（用户在别处改过）。
  conflict,
}

class NoteProposalApplyResult {
  const NoteProposalApplyResult(this.status, {this.noteId});

  final NoteProposalApplyStatus status;
  final String? noteId;

  bool get isApplied => status == NoteProposalApplyStatus.applied;
}

/// 提案采纳的纯逻辑部分：校验、合成笔记、落库。
///
/// 这些原本长在 `_ThoughterPageState` 里，导致「采纳后到底写进去了什么」只能靠
/// 手点验证，跑测台碰不到。抽出来之后 UI 只负责弹窗与提示，校验和落库这条真正
/// 会出问题的路径可以被无头驱动。
///
/// UI 与跑测台必须共用这里的 [validatedArtifactOps]——两份实现就会有两份真相。
class NoteProposalApplier {
  const NoteProposalApplier(this._databaseService);

  final DatabaseService _databaseService;

  /// 采纳一个修改提案并直接落库。
  ///
  /// 提案生成后笔记又被改过时返回 [NoteProposalApplyStatus.conflict]，不写库——
  /// 这同时挡住了「同一个提案被重复采纳」：第一次采纳会改变笔记的 revision，
  /// 第二次就对不上了。
  Future<NoteProposalApplyResult> applyEdit(
    NoteProposalArtifact artifact,
  ) async {
    final noteId = artifact.noteId;
    if (noteId == null) {
      return const NoteProposalApplyResult(NoteProposalApplyStatus.conflict);
    }
    final note = await _databaseService.getQuoteById(noteId);
    if (note == null ||
        ProposeNoteEditTool.revisionForQuote(note) != artifact.baseRevision) {
      return const NoteProposalApplyResult(NoteProposalApplyStatus.conflict);
    }
    final result =
        await _databaseService.updateQuote(quoteFromArtifact(note, artifact));
    if (result != QuoteUpdateResult.updated) {
      return const NoteProposalApplyResult(NoteProposalApplyStatus.conflict);
    }
    return NoteProposalApplyResult(
      NoteProposalApplyStatus.applied,
      noteId: noteId,
    );
  }

  /// 把提案合成到原笔记上，得到准备落库的笔记。
  static Quote quoteFromArtifact(
    Quote original,
    NoteProposalArtifact artifact,
  ) {
    var tagIds = original.tagIds;
    String? author = original.sourceAuthor;
    String? source = original.sourceWork;
    final tagPatch = artifact.metadata['tag_ids'];
    final authorPatch = artifact.metadata['author'];
    final sourcePatch = artifact.metadata['source'];
    if (tagPatch is Map) {
      tagIds = tagPatch['action'] == 'clear'
          ? const []
          : extractStringList(tagPatch['value']);
    }
    if (authorPatch is Map) {
      author = authorPatch['action'] == 'clear'
          ? null
          : authorPatch['value']?.toString();
    }
    if (sourcePatch is Map) {
      source = sourcePatch['action'] == 'clear'
          ? null
          : sourcePatch['value']?.toString();
    }
    final rich = artifact.resultKind == NoteDocumentKind.rich;
    final documentOps = validatedArtifactOps(artifact, original: original);
    return original.copyWith(
      content: artifact.content,
      source: authorPatch is Map || sourcePatch is Map ? null : original.source,
      deltaContent: rich ? jsonEncode(documentOps) : null,
      editSource: rich ? 'fullscreen' : null,
      tagIds: tagIds,
      sourceAuthor: author,
      sourceWork: source,
      lastModified: DateTime.now().toUtc().toIso8601String(),
    );
  }

  /// 采纳前的确定性校验，任一条不满足都抛 [FormatException]。
  ///
  /// 三条不变量：plain 提案不得带 Delta；`content` 必须与 Delta 还原出的正文
  /// 完全一致（AGENTS.md 硬性要求）；改笔记时不得增删媒体。
  static List<Map<String, dynamic>>? validatedArtifactOps(
    NoteProposalArtifact artifact, {
    Quote? original,
  }) {
    if (artifact.resultKind == NoteDocumentKind.plain) {
      if (artifact.documentOps != null) {
        throw const FormatException('plain proposal contains delta');
      }
      return null;
    }
    final ops = AgentNoteDocumentCodec.validateAndNormalize(
      NoteDocumentKind.rich,
      artifact.documentOps,
      allowExistingEmbeds: original != null,
    );
    if (AgentNoteDocumentCodec.plainTextOf(ops) != artifact.content) {
      throw const FormatException('proposal content and delta differ');
    }
    if (original != null) {
      if (!AgentNoteDocumentCodec.hasSameEmbeds(
        ProposeNoteEditTool.opsForQuote(original),
        ops,
      )) {
        throw const FormatException('proposal changes media references');
      }
    }
    return ops;
  }

  static List<String> extractStringList(Object? value) {
    final rawItems = value is List ? value : const [];
    return rawItems
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }
}
