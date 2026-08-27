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
  // 只留固定长度的预览 + 计数：一批全是坏行时，逐行打日志会把「限量」这件事本身
  // 架空，异常文本里还带着原始的非法字段值。
  final skippedPreview = <String>[];
  var skippedCount = 0;
  String? firstReason;

  for (final map in maps) {
    Quote? quote;
    try {
      quote = _tryParseQuoteRow(map, tagsByQuoteId: tagsByQuoteId);
    } catch (e) {
      firstReason ??= _logSafeText(e.toString());
      quote = null;
    }

    if (quote != null) {
      quotes.add(quote);
      continue;
    }

    skippedCount++;
    if (skippedPreview.length < _skippedPreviewLimit) {
      skippedPreview.add(_shortRowId(map['id']));
    }
  }

  if (skippedCount > 0) {
    final omitted = skippedCount - skippedPreview.length;
    logWarning(
      '跳过 $skippedCount 条无法解析的笔记（数据不符合本应用的字段要求）: '
      '${skippedPreview.join(', ')}'
      '${omitted > 0 ? ' …另有 $omitted 条' : ''}'
      '${firstReason != null ? '；首个原因: $firstReason' : ''}',
      source: 'QuoteRowParser',
    );
  }

  return quotes;
}

/// 单行反序列化；解析不了就抛给调用方，由 [_parseQuoteRows] 统一计数和记录。
///
/// 这里**不打日志**：一行一条的话，几千行坏数据就能把日志刷爆，而异常文本里还带着
/// 原始的非法字段值。原因只在汇总那一条里报一次。
Quote? _tryParseQuoteRow(
  Map<String, Object?> map, {
  Map<String, List<String>>? tagsByQuoteId,
}) {
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
}

/// 汇总日志里最多列几个行 id。
const int _skippedPreviewLimit = 10;

/// 异常文本的日志安全形式：去控制字符 + 限长（里面会带上原始的非法字段值）。
String _logSafeText(String text) {
  const maxLength = 120;
  final cleaned = text.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), ' ').trim();
  return cleaned.length > maxLength
      ? '${cleaned.substring(0, maxLength)}…'
      : cleaned;
}

/// 行 id 的日志安全形式：id 也可能来自外来数据，限长并去掉控制字符。
String _shortRowId(Object? id) {
  const maxLength = 40;
  final text = (id?.toString() ?? '<无 id>')
      .replaceAll(RegExp(r'[\x00-\x1F\x7F]'), ' ')
      .trim();
  return text.length > maxLength ? '${text.substring(0, maxLength)}…' : text;
}
