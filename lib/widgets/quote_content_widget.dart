import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import '../models/quote_model.dart';
import '../utils/quill_editor_extensions.dart';
import 'package:provider/provider.dart';
import '../services/settings_service.dart';

/// 统一显示Quote内容的组件，支持富文本和普通文本
class QuoteContent extends StatelessWidget {
  final Quote quote;
  final TextStyle? style;
  final int? maxLines;
  final bool showFullContent;

  const QuoteContent({
    super.key,
    required this.quote,
    this.style,
    this.maxLines,
    this.showFullContent = false,
  });

  // 性能优化:提取为静态常量,避免每次 build 创建
  static final quill.QuillEditorConfig _staticEditorConfig =
      quill.QuillEditorConfig(
    enableInteractiveSelection: false,
    enableSelectionToolbar: false,
    showCursor: false,
    embedBuilders: QuillEditorExtensions.getEmbedBuilders(
      optimizedImages: true,
    ),
    padding: EdgeInsets.zero,
    expands: false,
    scrollable: false,
  );

  static const double collapsedContentMaxHeight = 160.0;
  static const double _estimatedLineHeight = 24.0;
  static const double _lineSpacing = 4.0;
  static const int _averageCharsPerLine = 28;
  static const double _estimatedImageHeight = 200.0;
  static const double _estimatedVideoHeight = 240.0;
  static const double _estimatedAudioHeight = 140.0;
  static const Key collapsedWrapperKey = ValueKey(
    'quote_content.collapsed_wrapper',
  );

  static void resetCaches() {
    _QuoteDocumentCache.clear();
    _QuoteContentControllerCache.clear();
  }

  /// 预热 Document 缓存：在数据加载后、用户滚动前，分批异步预解析富文本 JSON
  /// 使用 Timer.run 将每批任务推入 event queue，确保让出主线程给渲染帧
  static void prewarmDocumentCache(List<Quote> quotes) {
    final richQuotes = quotes
        .where(
          (q) => q.deltaContent != null && q.editSource == 'fullscreen',
        )
        .toList();
    if (richQuotes.isEmpty) return;

    const batchSize = 3;
    void processBatch(int startIndex) {
      if (startIndex >= richQuotes.length) return;
      final end = (startIndex + batchSize).clamp(0, richQuotes.length);
      for (int i = startIndex; i < end; i++) {
        final deltaContent = richQuotes[i].deltaContent!;
        _QuoteDocumentCache.getOrCreate(
          deltaContent: deltaContent,
          prioritizeBold: false,
          builder: () => _buildDocumentFromDelta(deltaContent),
        );
      }
      if (end < richQuotes.length) {
        Timer.run(() => processBatch(end));
      }
    }

    Timer.run(() => processBatch(0));
  }

  /// 静态版本的 Document 构建，供预热缓存使用
  static quill.Document _buildDocumentFromDelta(String deltaContent) {
    try {
      final decoded = jsonDecode(deltaContent);
      if (decoded is List) {
        return quill.Document.fromJson(decoded);
      }
      if (decoded is Map && decoded.containsKey('ops')) {
        final ops = decoded['ops'];
        if (ops is List) {
          return quill.Document.fromJson(ops);
        }
      }
    } catch (_) {}
    return quill.Document()..insert(0, '');
  }

  /// 修复问题1：清理特定笔记的缓存（用于笔记删除/更新）
  static void removeCacheForQuote(String quoteId) {
    _QuoteContentControllerCache.removeByQuoteId(quoteId);
    // Document 缓存基于内容哈希，不需要按 ID 清理
  }

  @visibleForTesting
  static void clearCacheForTesting() => resetCaches();

  @visibleForTesting
  static Map<String, dynamic> debugCacheStats() => {
        'document': _QuoteDocumentCache.stats,
        'controller': _QuoteContentControllerCache.stats,
      };

  /// 检查是否为媒体软连接或其他应该过滤的内容
  bool _shouldFilterBoldContent(String content) {
    // 去除空白字符进行检查
    final trimmed = content.trim();

    // 过滤空内容
    if (trimmed.isEmpty) return true;

    // 过滤只包含换行符的内容
    if (trimmed == '\n' || trimmed.replaceAll('\n', '').isEmpty) return true;

    // 过滤媒体软连接模式 (通常是特殊字符或占位符)
    if (trimmed.length == 1 && trimmed.codeUnitAt(0) > 127) return true;

    // 过滤包含媒体占位符的内容
    if (trimmed.contains('�') || trimmed.contains('\uFFFC')) return true;

    return false;
  }

  /// 提取有效的加粗文本内容，过滤媒体软连接
  List<Map<String, dynamic>> _extractValidBoldOps(String deltaContent) {
    try {
      final decoded = jsonDecode(deltaContent);
      if (decoded is List) {
        List<Map<String, dynamic>> validBoldOps = [];

        for (var op in decoded) {
          if (op is Map && op['insert'] != null) {
            final String insert = op['insert'].toString();
            final Map<String, dynamic>? attributes = op['attributes'];

            // 检查是否有加粗属性且内容有效
            if (attributes != null &&
                attributes['bold'] == true &&
                !_shouldFilterBoldContent(insert)) {
              validBoldOps.add(Map<String, dynamic>.from(op));
            }
          }
        }
        return validBoldOps;
      }
    } catch (_) {
      // 解析失败，返回空列表
    }
    return [];
  }

  /// 获取非加粗的正文内容（包括媒体嵌入）
  List<Map<String, dynamic>> _extractNonBoldOps(String deltaContent) {
    try {
      final decoded = jsonDecode(deltaContent);
      if (decoded is List) {
        List<Map<String, dynamic>> nonBoldOps = [];

        for (var op in decoded) {
          if (op is Map && op['insert'] != null) {
            // 如果是嵌入内容（图片、视频等），直接保留
            if (op['insert'] is Map) {
              nonBoldOps.add(Map<String, dynamic>.from(op));
              continue;
            }

            final String insert = op['insert'].toString();
            final Map<String, dynamic>? attributes = op['attributes'];

            // 非加粗内容或没有加粗属性的内容
            if (attributes == null || attributes['bold'] != true) {
              // 跳过空内容
              if (insert.trim().isNotEmpty) {
                nonBoldOps.add(Map<String, dynamic>.from(op));
              }
            }
          }
        }
        return nonBoldOps;
      }
    } catch (_) {
      // 解析失败，返回空列表
    }
    return [];
  }

  static bool exceedsCollapsedHeight(Quote quote) {
    return _estimateRenderedHeight(quote) > collapsedContentMaxHeight;
  }

  static double _estimateRenderedHeight(Quote quote) {
    if (quote.deltaContent != null && quote.editSource == 'fullscreen') {
      return _estimateDeltaHeight(quote.deltaContent!);
    }
    return _estimatePlainTextHeight(quote.content);
  }

  static double _estimatePlainTextHeight(String content) {
    if (content.trim().isEmpty) {
      return _estimatedLineHeight;
    }

    final lines = content.split('\n');
    double height = 0;

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) {
        height += _estimatedLineHeight * 0.5;
        continue;
      }

      int approxLines = line.length ~/ _averageCharsPerLine;
      if (line.length % _averageCharsPerLine != 0) {
        approxLines += 1;
      }
      if (approxLines < 1) {
        approxLines = 1;
      }

      height += approxLines * _estimatedLineHeight;
    }

    if (lines.length > 1) {
      height += (lines.length - 1) * _lineSpacing;
    }

    return height;
  }

  static double _estimateDeltaHeight(String deltaContent) {
    double height = 0;

    try {
      final decoded = jsonDecode(deltaContent);
      if (decoded is List) {
        for (final node in decoded) {
          if (node is! Map || !node.containsKey('insert')) continue;
          final insert = node['insert'];

          if (insert is Map) {
            if (insert.containsKey('image')) {
              height += _estimatedImageHeight;
            } else if (insert.containsKey('video')) {
              height += _estimatedVideoHeight;
            } else if (insert.containsKey('audio')) {
              height += _estimatedAudioHeight;
            } else {
              height += _estimatedLineHeight;
            }
            continue;
          }

          if (insert != null) {
            height += _estimatePlainTextHeight(insert.toString());
          }
        }
      } else if (decoded is Map && decoded.containsKey('ops')) {
        // 某些备份格式可能包含 ops 包裹
        return _estimateDeltaHeight(jsonEncode(decoded['ops']));
      } else {
        height += _estimatePlainTextHeight(deltaContent);
      }
    } catch (_) {
      height += _estimatePlainTextHeight(deltaContent);
    }

    return height;
  }

  /// 创建优先显示加粗内容的 Document（保持原始嵌入，重新排序）。
  quill.Document? _createBoldPriorityDocument(String deltaContent) {
    try {
      final boldOps = _extractValidBoldOps(deltaContent);
      if (boldOps.isEmpty) {
        return null;
      }

      final nonBoldOps = _extractNonBoldOps(deltaContent);
      final List<Map<String, dynamic>> orderedOps = [];

      orderedOps.addAll(boldOps);

      if (nonBoldOps.isNotEmpty) {
        if (orderedOps.isNotEmpty &&
            !(orderedOps.last['insert']?.toString() ?? '').endsWith('\n')) {
          orderedOps.add({'insert': '\n'});
        }
        orderedOps.add({'insert': '\n'});
        orderedOps.addAll(nonBoldOps);
      }

      if (orderedOps.isNotEmpty) {
        final last = orderedOps.last;
        if (last['insert'] is String &&
            !last['insert'].toString().endsWith('\n')) {
          orderedOps.add({'insert': '\n'});
        }
      }

      return quill.Document.fromJson(orderedOps);
    } catch (_) {
      return null;
    }
  }

  quill.Document _buildRichTextDocument(
    String deltaContent,
    bool prioritizeBold,
  ) {
    if (prioritizeBold) {
      final prioritizedDoc = _createBoldPriorityDocument(deltaContent);
      if (prioritizedDoc != null) {
        return prioritizedDoc;
      }
    }

    return _documentFromDelta(deltaContent);
  }

  quill.Document _documentFromDelta(String deltaContent) {
    try {
      final decoded = jsonDecode(deltaContent);
      if (decoded is List) {
        return quill.Document.fromJson(decoded);
      }
      if (decoded is Map && decoded.containsKey('ops')) {
        final ops = decoded['ops'];
        if (ops is List) {
          return quill.Document.fromJson(ops);
        }
      }
    } catch (_) {
      // ignore and fall back to plain text content
    }

    return quill.Document()..insert(0, quote.content);
  }

  @override
  Widget build(BuildContext context) {
    final settingsService = Provider.of<SettingsService>(context);
    final prioritizeBoldContent =
        settingsService.prioritizeBoldContentInCollapse;
    final bool needsExpansion = exceedsCollapsedHeight(quote);

    if (quote.deltaContent != null && quote.editSource == 'fullscreen') {
      final bool usePrioritizedDoc = !showFullContent && prioritizeBoldContent;
      final String cacheQuoteId =
          quote.id ?? 'local_${quote.date}_${quote.content.hashCode}';
      final String contentVariant = _QuoteContentControllerCache.resolveVariant(
        showFullContent: showFullContent,
        usePrioritizedDoc: usePrioritizedDoc,
        needsExpansion: needsExpansion,
      );
      final String contentSignature =
          '${quote.deltaContent!.hashCode}_${quote.deltaContent!.length}_$contentVariant';

      final _CachedControllerSet controllerSet =
          _QuoteContentControllerCache.getOrCreate(
        quoteId: cacheQuoteId,
        contentSignature: contentSignature,
        variant: contentVariant,
        documentBuilder: () => _QuoteDocumentCache.getOrCreate(
          deltaContent: quote.deltaContent!,
          prioritizeBold: usePrioritizedDoc,
          builder: () => _buildRichTextDocument(
            quote.deltaContent!,
            usePrioritizedDoc,
          ),
        ),
      );

      Widget richTextEditor = quill.QuillEditor(
        controller: controllerSet.quillController,
        scrollController: controllerSet.scrollController,
        focusNode: controllerSet.focusNode,
        config: _staticEditorConfig,
      );

      if (style != null) {
        richTextEditor = DefaultTextStyle.merge(
          style: style!,
          child: richTextEditor,
        );
      }

      if (!showFullContent && needsExpansion) {
        richTextEditor = _CollapsedContentWrapper(
          key: collapsedWrapperKey,
          maxHeight: collapsedContentMaxHeight,
          child: richTextEditor,
        );
      }

      return richTextEditor;
    }

    Widget plainText = Text(
      quote.content,
      style: style,
      softWrap: true,
      overflow: TextOverflow.visible,
    );

    if (!showFullContent && needsExpansion) {
      plainText = _CollapsedContentWrapper(
        key: collapsedWrapperKey,
        maxHeight: collapsedContentMaxHeight,
        child: plainText,
      );
    }

    return plainText;
  }
}

class _CollapsedContentWrapper extends StatelessWidget {
  final Widget child;
  final double maxHeight;

  const _CollapsedContentWrapper({
    super.key,
    required this.child,
    required this.maxHeight,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double resolvedMaxWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : double.infinity;

        return ClipRect(
          child: SizedBox(
            height: maxHeight,
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: 0,
              maxWidth: resolvedMaxWidth,
              minHeight: 0,
              maxHeight: double.infinity,
              child: child,
            ),
          ),
        );
      },
    );
  }
}

class _QuoteDocumentCache {
  static final LinkedHashMap<_DocumentCacheKey, _DocumentCacheEntry> _cache =
      LinkedHashMap<_DocumentCacheKey, _DocumentCacheEntry>();
  static const int _maxCacheSize = 120;
  static const int _pruneBatchSize = 20;

  static int _hitCount = 0;
  static int _missCount = 0;

  static quill.Document getOrCreate({
    required String deltaContent,
    required bool prioritizeBold,
    required quill.Document Function() builder,
  }) {
    final key = _DocumentCacheKey(
      deltaContent: deltaContent,
      prioritizeBold: prioritizeBold,
    );

    final existing = _cache.remove(key);
    if (existing != null) {
      _hitCount++;
      existing.touch();
      _cache[key] = existing;
      return existing.document;
    }

    _missCount++;
    if (_cache.length >= _maxCacheSize) {
      _pruneOldest();
    }

    quill.Document document;
    try {
      document = builder();
    } catch (_) {
      document = quill.Document()..insert(0, '');
    }

    _cache[key] = _DocumentCacheEntry(document: document);
    return document;
  }

  static void clear() {
    _cache.clear();
    _hitCount = 0;
    _missCount = 0;
  }

  static Map<String, dynamic> get stats {
    final total = _hitCount + _missCount;
    final double hitRate = total == 0 ? 0 : _hitCount / total;
    return {
      'cacheSize': _cache.length,
      'maxSize': _maxCacheSize,
      'hitCount': _hitCount,
      'missCount': _missCount,
      'hitRate': hitRate,
    };
  }

  static void _pruneOldest() {
    if (_cache.isEmpty) {
      return;
    }

    final entries = _cache.entries.toList()
      ..sort((a, b) => a.value.lastAccess.compareTo(b.value.lastAccess));

    for (final entry in entries.take(_pruneBatchSize)) {
      _cache.remove(entry.key);
    }
  }
}

class _DocumentCacheKey {
  const _DocumentCacheKey({
    required this.deltaContent,
    required this.prioritizeBold,
  });

  final String deltaContent;
  final bool prioritizeBold;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is _DocumentCacheKey &&
        other.prioritizeBold == prioritizeBold &&
        other.deltaContent == deltaContent;
  }

  @override
  int get hashCode => Object.hash(deltaContent, prioritizeBold);
}

class _DocumentCacheEntry {
  _DocumentCacheEntry({required this.document}) : lastAccess = DateTime.now();

  final quill.Document document;
  DateTime lastAccess;

  void touch() {
    lastAccess = DateTime.now();
  }
}

class _QuoteContentControllerCache {
  static final LinkedHashMap<_ControllerCacheKey, _ControllerCacheEntry>
      _cache = LinkedHashMap<_ControllerCacheKey, _ControllerCacheEntry>();

  static const int _maxCacheSize = 50;
  static const int _pruneBatchSize = 10;

  static int _hitCount = 0;
  static int _missCount = 0;
  static int _createCount = 0;
  static int _disposeCount = 0;

  static _CachedControllerSet getOrCreate({
    required String quoteId,
    required String contentSignature,
    required String variant,
    required quill.Document Function() documentBuilder,
  }) {
    final key = _ControllerCacheKey(
      quoteId: quoteId,
      contentSignature: contentSignature,
      variant: variant,
    );

    final existing = _cache.remove(key);
    if (existing != null) {
      _hitCount++;
      existing.touch();
      _cache[key] = existing;

      // contentSignature 已包含内容哈希+长度，key 匹配即内容一致，无需重建 Document
      existing.controllers.prepareForReuse();
      return existing.controllers;
    }

    _missCount++;
    if (_cache.length >= _maxCacheSize) {
      _pruneOldest();
    }

    final document = documentBuilder();
    final controllers = _CachedControllerSet(
      quillController: quill.QuillController(
        document: document,
        selection: const TextSelection.collapsed(offset: 0),
      ),
      scrollController: ScrollController(),
      focusNode: FocusNode(),
      variant: variant,
    );

    final entry = _ControllerCacheEntry(controllers: controllers);
    _cache[key] = entry;
    _createCount++;
    return controllers;
  }

  static void clear() {
    for (final entry in _cache.values) {
      entry.controllers.dispose();
      _disposeCount++;
    }
    _cache.clear();
    _hitCount = 0;
    _missCount = 0;
    _createCount = 0;
    _disposeCount = 0;
  }

  static Map<String, dynamic> get stats {
    final total = _hitCount + _missCount;
    final double hitRate = total == 0 ? 0 : _hitCount / total;
    return {
      'cacheSize': _cache.length,
      'maxSize': _maxCacheSize,
      'hitCount': _hitCount,
      'missCount': _missCount,
      'createCount': _createCount,
      'disposeCount': _disposeCount,
      'hitRate': hitRate,
    };
  }

  static String resolveVariant({
    required bool showFullContent,
    required bool usePrioritizedDoc,
    required bool needsExpansion,
  }) {
    final buffer = StringBuffer()
      ..write(showFullContent ? 'full' : 'collapsed')
      ..write(usePrioritizedDoc ? '_bold' : '_plain')
      ..write(needsExpansion ? '_expandable' : '_static');
    return buffer.toString();
  }

  static void _pruneOldest() {
    if (_cache.isEmpty) {
      return;
    }

    final entries = _cache.entries.toList()
      ..sort((a, b) => a.value.lastAccess.compareTo(b.value.lastAccess));

    for (final entry in entries.take(_pruneBatchSize)) {
      _cache.remove(entry.key);
      entry.value.controllers.dispose();
      _disposeCount++;
    }
  }

  /// 修复问题1：清理特定笔记的所有缓存（用于笔记删除/更新）
  static void removeByQuoteId(String quoteId) {
    final keysToRemove =
        _cache.keys.where((key) => key.quoteId == quoteId).toList();

    for (final key in keysToRemove) {
      final entry = _cache.remove(key);
      if (entry != null) {
        entry.controllers.dispose();
        _disposeCount++;
      }
    }
  }
}

class _ControllerCacheKey {
  const _ControllerCacheKey({
    required this.quoteId,
    required this.contentSignature,
    required this.variant,
  });

  final String quoteId;
  final String contentSignature;
  final String variant;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is _ControllerCacheKey &&
        other.quoteId == quoteId &&
        other.contentSignature == contentSignature &&
        other.variant == variant;
  }

  @override
  int get hashCode => Object.hash(quoteId, contentSignature, variant);
}

class _ControllerCacheEntry {
  _ControllerCacheEntry({required this.controllers})
      : lastAccess = DateTime.now();

  final _CachedControllerSet controllers;
  DateTime lastAccess;

  void touch() {
    lastAccess = DateTime.now();
  }
}

class _CachedControllerSet {
  _CachedControllerSet({
    required this.quillController,
    required this.scrollController,
    required this.focusNode,
    required this.variant,
  });

  final quill.QuillController quillController;
  final ScrollController scrollController;
  final FocusNode focusNode;
  final String variant;

  void prepareForReuse() {
    focusNode.unfocus();
    if (scrollController.hasClients) {
      try {
        scrollController.jumpTo(0);
      } catch (_) {
        // 忽略跳转失败，可能由于尚未完成布局或控制器已分离
      }
    }

    final selection = quillController.selection;
    if (selection.baseOffset != 0 || selection.extentOffset != 0) {
      quillController.updateSelection(
        const TextSelection.collapsed(offset: 0),
        quill.ChangeSource.local,
      );
    }
  }

  void dispose() {
    try {
      quillController.dispose();
    } catch (_) {}
    try {
      scrollController.dispose();
    } catch (_) {}
    try {
      focusNode.dispose();
    } catch (_) {}
  }
}
