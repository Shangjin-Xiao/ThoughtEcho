import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';

/// 折叠卡片需要的媒体摘要。
///
/// 它只回答「这条笔记里有哪些图、有没有音视频」，不碰任何渲染。折叠卡片靠它把
/// 缩略图从 Quill 的嵌入渲染路径里拿出来单独画——图片因此不再等富文本物化，
/// 也不再占用富文本的每帧构建额度。
@immutable
class DeltaMediaSummary {
  const DeltaMediaSummary({
    required this.imageSources,
    required this.videoCount,
    required this.audioCount,
  });

  static const DeltaMediaSummary empty = DeltaMediaSummary(
    imageSources: <String>[],
    videoCount: 0,
    audioCount: 0,
  );

  /// 按在文档中出现的顺序排列，已去掉空串。
  final List<String> imageSources;
  final int videoCount;
  final int audioCount;

  bool get hasImage => imageSources.isNotEmpty;

  bool get hasMedia => hasImage || videoCount > 0 || audioCount > 0;

  /// 折叠卡片右侧只画一张缩略图，多余的用角标表示。
  int get totalCount => imageSources.length + videoCount + audioCount;

  String? get firstImageSource =>
      imageSources.isEmpty ? null : imageSources.first;

  @override
  String toString() => 'DeltaMediaSummary(images=${imageSources.length}, '
      'video=$videoCount, audio=$audioCount)';
}

/// 判断一个 delta op 的 insert 是不是嵌入媒体。
///
/// 和 `_OptimizedImageEmbedBuilder._extractSource` 认的形状保持一致：值可能直接是
/// 字符串，也可能是 `{'source': ...}` / `{'image': ...}` 这样的 Map。
bool isDeltaMediaInsert(Object? insert) {
  if (insert is! Map) return false;
  return insert.containsKey('image') ||
      insert.containsKey('video') ||
      insert.containsKey('audio');
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

  final imageSources = <String>[];
  var videoCount = 0;
  var audioCount = 0;

  for (final op in ops) {
    if (op is! Map) continue;
    final insert = op['insert'];
    if (insert is! Map) continue;

    if (insert.containsKey('image')) {
      final source = _readEmbedSource(insert['image']);
      if (source != null) {
        imageSources.add(source);
      }
    } else if (insert.containsKey('video')) {
      videoCount++;
    } else if (insert.containsKey('audio')) {
      audioCount++;
    }
  }

  if (imageSources.isEmpty && videoCount == 0 && audioCount == 0) {
    return DeltaMediaSummary.empty;
  }

  return DeltaMediaSummary(
    imageSources: List<String>.unmodifiable(imageSources),
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
/// 不变，所以按「内容哈希 + 长度」缓存。键不持有 delta 字符串本身，避免把整份
/// 富文本内容钉在内存里。
class DeltaMediaCache {
  DeltaMediaCache._();

  static final LinkedHashMap<_DeltaMediaCacheKey, DeltaMediaSummary> _cache =
      LinkedHashMap<_DeltaMediaCacheKey, DeltaMediaSummary>();

  static const int _maxCacheSize = 300;
  static const int _pruneBatchSize = 50;

  static int _hitCount = 0;
  static int _missCount = 0;

  static DeltaMediaSummary of(String? deltaContent) {
    if (deltaContent == null || deltaContent.isEmpty) {
      return DeltaMediaSummary.empty;
    }

    final key = _DeltaMediaCacheKey(
      contentHash: deltaContent.hashCode,
      length: deltaContent.length,
    );

    final existing = _cache.remove(key);
    if (existing != null) {
      _hitCount++;
      _cache[key] = existing;
      return existing;
    }

    _missCount++;
    if (_cache.length >= _maxCacheSize) {
      _pruneOldest();
    }

    final summary = parseDeltaMedia(deltaContent);
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

@immutable
class _DeltaMediaCacheKey {
  const _DeltaMediaCacheKey({
    required this.contentHash,
    required this.length,
  });

  final int contentHash;
  final int length;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is _DeltaMediaCacheKey &&
        other.contentHash == contentHash &&
        other.length == length;
  }

  @override
  int get hashCode => Object.hash(contentHash, length);
}
