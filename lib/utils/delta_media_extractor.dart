import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// 折叠卡片需要的媒体摘要。
///
/// 它只回答「这条笔记里有几张图/几段音视频，第一张图是哪个」，不碰任何渲染。
/// 折叠卡片靠它把缩略图从 Quill 的嵌入渲染路径里拿出来单独画——图片因此不再等
/// 富文本物化，也不再占用富文本的每帧构建额度。
///
/// **只保留首图的 source，不保留完整列表**：卡片右侧只画一张缩略图，其余用角标
/// 表示，多存的 source 字符串没有用处。带 `data:` URL 的笔记里，一个 source 就是
/// 整段 base64，存一串等于把若干 MB 长期钉在 Dart 堆上。
@immutable
class DeltaMediaSummary {
  const DeltaMediaSummary({
    required this.firstImageSource,
    required this.imageCount,
    required this.videoCount,
    required this.audioCount,
  });

  static const DeltaMediaSummary empty = DeltaMediaSummary(
    firstImageSource: null,
    imageCount: 0,
    videoCount: 0,
    audioCount: 0,
  );

  /// 文档中第一张图片的 source，没有图片时为 null。
  final String? firstImageSource;
  final int imageCount;
  final int videoCount;
  final int audioCount;

  bool get hasImage => imageCount > 0;

  bool get hasMedia => imageCount > 0 || videoCount > 0 || audioCount > 0;

  /// 折叠卡片右侧只画一张缩略图，多余的用角标表示。
  int get totalCount => imageCount + videoCount + audioCount;

  @override
  String toString() => 'DeltaMediaSummary(images=$imageCount, '
      'video=$videoCount, audio=$audioCount)';
}

/// 嵌入媒体的三种类型。
enum DeltaMediaKind { image, video, audio }

/// 一个嵌入媒体节点解出来的类型和来源。
///
/// [source] 允许为 null：`{'image': ''}` 这类畸形节点**仍然是**媒体嵌入（必须被
/// 折叠态摘掉），只是没有可渲染的来源。判断「是不是媒体」用 [isDeltaMediaInsert]，
/// 判断「能不能画出来」才看 [source]。
@immutable
class DeltaMediaRef {
  const DeltaMediaRef({required this.kind, required this.source});

  final DeltaMediaKind kind;
  final String? source;
}

/// 读出一个 delta op 的 insert 所代表的嵌入媒体，不是媒体时返回 null。
///
/// 本项目里三种媒体的序列化形状**并不统一**，这里必须全认（可对照
/// `draft_service.dart`、`media_reference_service.dart`、`editor_color_and_media.dart`
/// 里同样的三段判断）：
///
/// - 图片：`{'insert': {'image': ...}}`
/// - 视频：`{'insert': {'video': ...}}`
/// - 音频：`{'insert': {'custom': {'audio': ...}}}` —— 走 `CustomBlockEmbed`，
///   **不在顶层**。只认顶层 `audio` 会让折叠态漏掉音频：既不计入角标，也不会被
///   摘除逻辑摘掉，于是滚动列表里照旧实例化 `MediaPlayerWidget`。
///
/// 这三段形状的知识**只在这里有一份**：[isDeltaMediaInsert]、[parseDeltaMedia]
/// 和折叠预览的 IR 解析都从这里取，改动媒体序列化时不用再去别处找同样的判断。
DeltaMediaRef? readDeltaMediaEmbed(Object? insert) {
  if (insert is! Map) return null;

  for (final entry in const [
    ('image', DeltaMediaKind.image),
    ('video', DeltaMediaKind.video),
    ('audio', DeltaMediaKind.audio),
  ]) {
    if (insert.containsKey(entry.$1)) {
      return DeltaMediaRef(
        kind: entry.$2,
        source: _readEmbedSource(insert[entry.$1]),
      );
    }
  }

  final custom = _asCustomMap(insert['custom']);
  if (custom == null) return null;
  for (final entry in const [
    ('image', DeltaMediaKind.image),
    ('video', DeltaMediaKind.video),
    ('audio', DeltaMediaKind.audio),
  ]) {
    if (custom.containsKey(entry.$1)) {
      return DeltaMediaRef(
        kind: entry.$2,
        source: _readEmbedSource(custom[entry.$1]),
      );
    }
  }
  return null;
}

/// 判断一个 delta op 的 insert 是不是嵌入媒体。见 [readDeltaMediaEmbed]。
bool isDeltaMediaInsert(Object? insert) => readDeltaMediaEmbed(insert) != null;

/// `custom` 在本项目里解出来是 Map；但 flutter_quill 的 `CustomBlockEmbed`
/// 也可能把它序列化成 JSON 字符串，这里两种都认。
Map<Object?, Object?>? _asCustomMap(Object? raw) {
  if (raw is Map) return raw.cast<Object?, Object?>();
  if (raw is String && raw.isNotEmpty) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return decoded.cast<Object?, Object?>();
    } catch (_) {
      // 不是 JSON 就当普通字符串，不是媒体。
    }
  }
  return null;
}

/// source 是不是内嵌的 `data:` URI。
///
/// 这类 source 本身就是整段 base64，缓存住等于把若干 MB 长期钉在堆上，所以按内容
/// 做键的缓存都要跳过它们。scheme 按 RFC 2397 大小写不敏感，`DATA:` 也算。
bool isInlineDataUri(String? source) {
  if (source == null || source.length < 5) return false;
  return source.substring(0, 5).toLowerCase() == 'data:';
}

String? _readEmbedSource(Object? raw) {
  if (raw is String) {
    return raw.isEmpty ? null : raw;
  }
  if (raw is Map) {
    final source = raw['source'] ?? raw['image'] ?? raw['url'];
    if (source is String && source.isNotEmpty) {
      return source;
    }
  }
  return null;
}

/// 从 delta JSON 里抽出媒体摘要。纯函数，畸形输入一律回退到 [DeltaMediaSummary.empty]。
///
/// 不要在这里做任何 IO（读文件头、取尺寸）——它会被 `build` 直接调用。
DeltaMediaSummary parseDeltaMedia(String? deltaContent) {
  if (deltaContent == null || deltaContent.isEmpty) {
    return DeltaMediaSummary.empty;
  }

  final List<Object?>? ops = _decodeOps(deltaContent);
  if (ops == null || ops.isEmpty) {
    return DeltaMediaSummary.empty;
  }

  String? firstImageSource;
  var imageCount = 0;
  var videoCount = 0;
  var audioCount = 0;

  for (final op in ops) {
    if (op is! Map) continue;
    final media = readDeltaMediaEmbed(op['insert']);
    if (media == null) continue;

    switch (media.kind) {
      case DeltaMediaKind.image:
        // 没有可用来源的图片不计数：角标数得和真能画出来的张数对得上。
        final source = media.source;
        if (source == null) break;
        imageCount++;
        firstImageSource ??= source;
      case DeltaMediaKind.video:
        videoCount++;
      case DeltaMediaKind.audio:
        audioCount++;
    }
  }

  if (imageCount == 0 && videoCount == 0 && audioCount == 0) {
    return DeltaMediaSummary.empty;
  }

  return DeltaMediaSummary(
    firstImageSource: firstImageSource,
    imageCount: imageCount,
    videoCount: videoCount,
    audioCount: audioCount,
  );
}

List<Object?>? _decodeOps(String deltaContent) {
  try {
    final decoded = jsonDecode(deltaContent);
    if (decoded is List) {
      return decoded;
    }
    if (decoded is Map && decoded['ops'] is List) {
      return decoded['ops'] as List<Object?>;
    }
  } catch (_) {
    // 畸形 delta 不该让卡片崩掉，交给上层按无媒体处理。
  }
  return null;
}

/// [parseDeltaMedia] 的 LRU 缓存。
///
/// 折叠卡片每次 build 都要问一次媒体摘要，而同一条笔记的 delta 在生命周期里基本
/// 不变，所以按内容指纹缓存。键**不持有 delta 字符串本身**，避免把整份富文本内容
/// 钉在内存里。
class DeltaMediaCache {
  DeltaMediaCache._();

  static final LinkedHashMap<DeltaContentFingerprint, DeltaMediaSummary>
      _cache = LinkedHashMap<DeltaContentFingerprint, DeltaMediaSummary>();

  static const int _maxCacheSize = 300;
  static const int _pruneBatchSize = 50;

  static int _hitCount = 0;
  static int _missCount = 0;

  static DeltaMediaSummary of(String? deltaContent) {
    if (deltaContent == null || deltaContent.isEmpty) {
      return DeltaMediaSummary.empty;
    }

    final key = DeltaContentFingerprint.of(deltaContent);

    final existing = _cache.remove(key);
    if (existing != null) {
      _hitCount++;
      _cache[key] = existing;
      return existing;
    }

    _missCount++;
    final summary = parseDeltaMedia(deltaContent);

    // 首图是 data: URL 时不进缓存：那个 source 就是整段 base64，缓存住等于把
    // 若干 MB 长期钉在堆上，而这类笔记本来就少，重解一次的代价远小于常驻内存。
    if (isInlineDataUri(summary.firstImageSource)) {
      return summary;
    }

    if (_cache.length >= _maxCacheSize) {
      _pruneOldest();
    }
    _cache[key] = summary;
    return summary;
  }

  /// LinkedHashMap 的迭代顺序就是最近使用顺序，取前 N 个即最旧。
  static void _pruneOldest() {
    final victims = _cache.keys.take(_pruneBatchSize).toList();
    for (final key in victims) {
      _cache.remove(key);
    }
  }

  static void clear() {
    _cache.clear();
    _hitCount = 0;
    _missCount = 0;
  }

  static Map<String, dynamic> get stats {
    final total = _hitCount + _missCount;
    return {
      'cacheSize': _cache.length,
      'maxSize': _maxCacheSize,
      'hitCount': _hitCount,
      'missCount': _missCount,
      'hitRate': total == 0 ? 0.0 : _hitCount / total,
    };
  }
}

/// delta 的内容指纹，供所有「按 delta 内容做键」的缓存共用。
///
/// 除了整串的 `hashCode` 和长度，再补两段边缘切片的哈希：单靠
/// `hashCode + length` 时，两条不同笔记只要这两个值同时相等就会串味——概率极低，
/// 但后果是 A 笔记的缩略图出现在 B 笔记上。多两个 O(1) 内存、O(256) 计算的字段
/// 就能把这种巧合的要求提高到四个值同时相等，而且**依然不持有 delta 本身**。
@immutable
class DeltaContentFingerprint {
  const DeltaContentFingerprint({
    required this.contentHash,
    required this.length,
    required this.headHash,
    required this.tailHash,
  });

  factory DeltaContentFingerprint.of(String deltaContent) {
    const sliceLength = 128;
    final length = deltaContent.length;
    final head = deltaContent.substring(0, math.min(sliceLength, length));
    final tail = deltaContent.substring(math.max(0, length - sliceLength));
    return DeltaContentFingerprint(
      contentHash: deltaContent.hashCode,
      length: length,
      headHash: head.hashCode,
      tailHash: tail.hashCode,
    );
  }

  final int contentHash;
  final int length;
  final int headHash;
  final int tailHash;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DeltaContentFingerprint &&
        other.contentHash == contentHash &&
        other.length == length &&
        other.headHash == headHash &&
        other.tailHash == tailHash;
  }

  @override
  int get hashCode => Object.hash(contentHash, length, headHash, tailHash);
}
