import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/delta_rich_text_parser.dart';
import 'package:thoughtecho/widgets/note_list/collapsed_rich_text.dart';

/// 正文里的**空行**在折叠计划里的待遇。
///
/// 这里守的是一个具体的回归：用户在笔记开头敲一个回车（第一行空、第二行才有字），
/// 列表卡片的折叠预览整个变成空白，只剩一个展开入口；把那个空行删掉，正文又出来
/// 了。原因是空段落量不出任何 line metrics——引擎对空文本直接清空行表，只把段落
/// 高度设成 strut 高度——而计划把「一行都量不出来」当成「一行都放不下」，于是
/// 那个空块连同**它后面的全部内容**一起被丢掉。
///
/// 空行是用户敲进去的内容，展开态照样占一行，折叠预览也必须照样排一行。
void main() {
  const TextStyle baseStyle = TextStyle(fontSize: 16, height: 1.5);
  const double width = 320;
  const double limit = 160;

  CollapsedRichTextPlan planOf(String delta) {
    return CollapsedRichTextMetrics.plan(
      blocks: parseDeltaRichText(delta),
      baseStyle: baseStyle,
      maxWidth: width,
      limit: limit,
      showMedia: false,
    );
  }

  String longBody() => '折叠盒只有 160px，可是正文可以写很长很长。' * 20;

  test('第一行是空行时，后面的正文照样排进计划', () {
    final delta = jsonEncode([
      {'insert': '\n${longBody()}\n'},
    ]);

    final blocks = parseDeltaRichText(delta);
    expect(blocks.first.isBlank, isTrue, reason: '前置条件：第一个块就是那个空行');

    final plan = planOf(delta);

    expect(plan.isEmpty, isFalse, reason: '计划为空时卡片正文整个不画，用户看到一张白卡片');
    expect(plan.entries, hasLength(2), reason: '空行一块、正文一块，都要排上');
    expect(plan.entries.first.block.isBlank, isTrue);
    expect(plan.entries.first.maxLines, 1, reason: '空行占一行，和展开态一致');
    expect(plan.entries.last.maxLines, greaterThan(1), reason: '正文要按剩余像素铺满折叠盒');
    expect(plan.height, greaterThan(limit / 2));
    expect(plan.height, lessThanOrEqualTo(limit + 0.5));
    expect(plan.truncated, isTrue, reason: '长正文没排完，展开入口还得留着');
  });

  test('正文中间的空行不会把后面的段落截掉', () {
    final delta = jsonEncode([
      {'insert': '第一段\n\n第二段\n'},
    ]);

    final plan = planOf(delta);

    expect(plan.entries, hasLength(3));
    expect(plan.entries[1].block.isBlank, isTrue);
    expect(plan.entries.last.block.plainText, '第二段');
    expect(plan.truncated, isFalse, reason: '三行远不到 160px，不该判成截断');
  });

  test('空行占掉的高度算进总高，和渲染出来的一致', () {
    final withBlank = planOf(jsonEncode([
      {'insert': '\n正文\n'},
    ]));
    final withoutBlank = planOf(jsonEncode([
      {'insert': '正文\n'},
    ]));

    // 空行不是零高：多出来的正好是一行加一个块间距。
    expect(
      withBlank.height,
      greaterThan(withoutBlank.height + CollapsedRichText.blockGap),
    );
  });
}
