part of '../database_service.dart';

/// quotes 行 → [Quote] 的统一反序列化入口，**坏行跳过而不是让整批查询失败**。
///
/// [Quote.fromJson] 对正文为空、日期不可解析、颜色格式不对的行会抛异常。原来七处
/// 读取都是 `maps.map((m) => Quote.fromJson(m))` 裸调用，一条坏行就能让**整页笔记
/// 加载失败**——用户看到的不是「有一条笔记怪怪的」，而是列表整个打不开，且没有任何
/// 途径能自己修好。
///
/// 坏行从哪来：早期版本的导入不做值域收敛（现已在导入边界补上），以及任何绕过导入
/// 直接落库的路径。库里已经存在的行，光靠修导入是清不掉的。
///
/// 兜底只做「跳过 + 告警」，不做修复：能修的（越界 `sentiment`）由启动迁移
/// `repairOutOfDomainSentiment` 负责，那里会先快照原值；这里悄悄改数据反而会把问题
/// 藏起来。
List<Quote> _parseQuoteRows(
  List<Map<String, Object?>> maps, {
  Map<String, List<String>>? tagsByQuoteId,
}) {
  final quotes = <Quote>[];
  final skipped = <String>[];

  for (final map in maps) {
    final quote = _tryParseQuoteRow(map, tagsByQuoteId: tagsByQuoteId);
    if (quote != null) {
      quotes.add(quote);
    } else {
      skipped.add(_shortRowId(map['id']));
    }
  }

  if (skipped.isNotEmpty) {
    logWarning(
      '跳过 ${skipped.length} 条无法解析的笔记（数据不符合本应用的字段要求）: '
      '${skipped.take(10).join(', ')}'
      '${skipped.length > 10 ? ' …另有 ${skipped.length - 10} 条' : ''}',
      source: 'QuoteRowParser',
    );
  }

  return quotes;
}

/// 单行反序列化；失败返回 null 由调用方决定怎么处理。
Quote? _tryParseQuoteRow(
  Map<String, Object?> map, {
  Map<String, List<String>>? tagsByQuoteId,
}) {
  try {
    if (tagsByQuoteId == null) {
      return Quote.fromJson(Map<String, dynamic>.from(map));
    }
    // id 缺失或不是字符串时不能硬转，那本身就是一行坏数据。
    final quoteId = map['id'];
    if (quoteId is! String) {
      return null;
    }
    final mutableMap = Map<String, dynamic>.from(map);
    mutableMap['tag_ids'] = (tagsByQuoteId[quoteId] ?? const <String>[]).join(
      ',',
    );
    return Quote.fromJson(mutableMap);
  } catch (e) {
    logDebug('笔记行解析失败，已跳过: $e', source: 'QuoteRowParser');
    return null;
  }
}

/// 行 id 的日志安全形式：id 也可能来自外来数据，限长并去掉控制字符。
String _shortRowId(Object? id) {
  const maxLength = 40;
  final text = (id?.toString() ?? '<无 id>')
      .replaceAll(RegExp(r'[\x00-\x1F\x7F]'), ' ')
      .trim();
  return text.length > maxLength ? '${text.substring(0, maxLength)}…' : text;
}
