import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/ai_smart_result_utils.dart';

/// 用最小的替身代表一条聊天消息：只关心它的 meta。
class _Msg {
  const _Msg([this.meta]);
  final Map<String, dynamic>? meta;
}

Map<String, dynamic>? _metaOf(_Msg message) => message.meta;

Map<String, dynamic> _card({
  String type = 'note_proposal',
  String? savedNoteId,
}) =>
    <String, dynamic>{
      'type': type,
      if (savedNoteId != null) 'saved_note_id': savedNoteId,
    };

void main() {
  group('latestAdoptedProposalNoteId', () {
    test('没有卡片时返回 null', () {
      expect(
        AiSmartResultUtils.latestAdoptedProposalNoteId(
          const [_Msg(), _Msg()],
          _metaOf,
        ),
        isNull,
      );
    });

    test('最近一张卡片未采纳时返回 null', () {
      final messages = [
        _Msg(_card(savedNoteId: 'note-1')),
        const _Msg(),
        _Msg(_card()),
      ];
      expect(
        AiSmartResultUtils.latestAdoptedProposalNoteId(messages, _metaOf),
        isNull,
      );
    });

    test('最近一张卡片已采纳时返回它的笔记 id', () {
      final messages = [
        _Msg(_card(savedNoteId: 'old-note')),
        const _Msg(),
        _Msg(_card(savedNoteId: 'note-2')),
        const _Msg(),
      ];
      expect(
        AiSmartResultUtils.latestAdoptedProposalNoteId(messages, _metaOf),
        'note-2',
      );
    });

    test('非卡片类 meta（工具进度等）不参与判定', () {
      final messages = [
        _Msg(_card(savedNoteId: 'note-3')),
        _Msg(<String, dynamic>{'type': 'tool_progress'}),
      ];
      expect(
        AiSmartResultUtils.latestAdoptedProposalNoteId(messages, _metaOf),
        'note-3',
      );
    });

    test('saved_note_id 是空串时视为未采纳', () {
      final messages = [_Msg(_card(savedNoteId: '  '))];
      expect(
        AiSmartResultUtils.latestAdoptedProposalNoteId(messages, _metaOf),
        isNull,
      );
    });
  });

  test('采纳说明带上笔记 id 且不使用「上述」这类指代', () {
    final notice = AiSmartResultUtils.proposalAdoptionNotice('note-9');
    expect(notice, contains('note-9'));
    expect(notice, isNot(contains('上述')));
  });

  test('卡片类型集合与 NoteProposalArtifact.typeName 对齐', () {
    final decoded = jsonDecode('{"type":"note_proposal"}') as Map;
    expect(
      AiSmartResultUtils.proposalCardTypes.contains(decoded['type']),
      isTrue,
    );
  });
}
