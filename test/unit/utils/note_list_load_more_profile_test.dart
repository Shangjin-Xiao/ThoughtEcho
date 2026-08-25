import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/note_list_load_more_profile.dart';

/// 这个累加器是进程级的、没有请求令牌：`getUserQuotes` 埋得太深，为一个诊断把 token
/// 一路穿到数据库层不划算。代价是窗口里可能混进别的查询或数据事件 —— 所以采样次数
/// (`q=` / `ev=`) 必须一起打出来，否则会静悄悄给出一份错的拆分。
void main() {
  setUp(NoteListLoadMoreProfile.resetForTesting);

  test('begin 把上一次分页的分段清零', () {
    NoteListLoadMoreProfile.begin();
    NoteListLoadMoreProfile.recordQuery(
      sqlMicros: 1000,
      tagsMicros: 2000,
      parseMicros: 3000,
      rowCount: 50,
    );
    NoteListLoadMoreProfile.recordServiceCall(9000);
    expect(NoteListLoadMoreProfile.toCompactText(), contains('sql=1.0ms'));

    NoteListLoadMoreProfile.begin();
    final text = NoteListLoadMoreProfile.toCompactText();
    expect(text, contains('sql=0.0ms'));
    expect(text, contains('rows=0'));
    expect(text, contains('q=0'));
    expect(text, contains('ev=0'));
  });

  test('序号累计，不随 begin 清零 —— 清零的话它永远是 1', () {
    NoteListLoadMoreProfile.begin();
    NoteListLoadMoreProfile.recordServiceCall(1000);
    expect(NoteListLoadMoreProfile.toCompactText(), contains('seq=1'));

    NoteListLoadMoreProfile.begin();
    NoteListLoadMoreProfile.recordServiceCall(1000);
    expect(NoteListLoadMoreProfile.toCompactText(), contains('seq=2'));
  });

  test('只有一次查询、一次数据事件时，采样次数说明这份拆分干净', () {
    NoteListLoadMoreProfile.begin();
    NoteListLoadMoreProfile.recordQuery(
      sqlMicros: 1000,
      tagsMicros: 1000,
      parseMicros: 1000,
      rowCount: 50,
    );
    NoteListLoadMoreProfile.recordReuse(500);
    NoteListLoadMoreProfile.recordApply(500);
    NoteListLoadMoreProfile.recordServiceCall(4000);

    expect(NoteListLoadMoreProfile.debugQueryCount, 1);
    expect(NoteListLoadMoreProfile.debugEventCount, 1);
    expect(NoteListLoadMoreProfile.toCompactText(), contains('q=1,ev=1'));
  });

  test('窗口里混进别的查询和数据事件时，采样次数把它暴露出来', () {
    NoteListLoadMoreProfile.begin();
    // 分页自己的那次查询。
    NoteListLoadMoreProfile.recordQuery(
      sqlMicros: 1000,
      tagsMicros: 0,
      parseMicros: 0,
      rowCount: 50,
    );
    // 同一窗口里跑了一次搜索：它的数字也会记进来。
    NoteListLoadMoreProfile.recordQuery(
      sqlMicros: 5000,
      tagsMicros: 0,
      parseMicros: 0,
      rowCount: 10,
    );
    NoteListLoadMoreProfile.recordReuse(100);
    NoteListLoadMoreProfile.recordApply(100);
    NoteListLoadMoreProfile.recordReuse(100);
    NoteListLoadMoreProfile.recordApply(100);

    final text = NoteListLoadMoreProfile.toCompactText();
    expect(text, contains('q=2'));
    expect(text, contains('ev=2'));
    expect(
      text,
      contains('sql=6.0ms'),
      reason: '混进来的部分确实会被累加 —— 正因如此才必须把 q= 打出来',
    );
  });
}
