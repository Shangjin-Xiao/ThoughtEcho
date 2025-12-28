import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:objectbox/objectbox.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../../models/objectbox/note_vector.dart';
import '../../models/quote_model.dart';
import '../../utils/app_logger.dart';
import 'embedding_service.dart';

// 注意: ObjectBox 需要运行 build_runner 生成 objectbox.g.dart
// 执行: dart run build_runner build
// 生成的文件会自动包含 openStore 函数
// import '../../objectbox.g.dart';

/// 向量搜索结果
class VectorSearchResult {
  /// 笔记 ID
  final String noteId;
  
  /// 相似度分数 (0-1)
  final double score;
  
  /// 内容预览
  final String? preview;

  const VectorSearchResult({
    required this.noteId,
    required this.score,
    this.preview,
  });

  @override
  String toString() => 'VectorSearchResult(noteId: $noteId, score: $score)';
}

/// 向量搜索服务
/// 
/// 使用 ObjectBox 进行向量存储和 HNSW 搜索
class VectorSearchService extends ChangeNotifier {
  static final VectorSearchService _instance = VectorSearchService._internal();
  factory VectorSearchService() => _instance;
  VectorSearchService._internal();

  final EmbeddingService _embeddingService = EmbeddingService();

  /// ObjectBox Store
  Store? _store;
  
  /// 向量 Box
  Box<NoteVector>? _vectorBox;
  
  /// 搜索历史 Box
  Box<SearchHistory>? _searchHistoryBox;
  
  /// 相似笔记缓存 Box
  Box<SimilarNotesCache>? _similarCacheBox;

  /// 是否已初始化
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  /// 当前嵌入模型版本
  String get modelVersion => 
      _embeddingService.currentConfig?.modelId ?? 'unknown';

  /// 初始化向量搜索服务
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // 1. 初始化嵌入服务
      await _embeddingService.initialize();

      // 2. 初始化 ObjectBox
      await _initObjectBox();

      _isInitialized = true;
      logInfo('向量搜索服务初始化成功', source: 'VectorSearchService');
      notifyListeners();
    } catch (e, stackTrace) {
      logError(
        '向量搜索服务初始化失败: $e',
        error: e,
        stackTrace: stackTrace,
        source: 'VectorSearchService',
      );
      rethrow;
    }
  }

  /// 初始化 ObjectBox
  /// 
  /// **重要**: 在使用向量搜索功能前，需要先执行以下步骤:
  /// 
  /// 1. 运行 `dart run build_runner build` 生成 objectbox.g.dart
  /// 2. 在 lib/objectbox.g.dart 中会生成 openStore 函数
  /// 3. 取消下面代码的注释并导入生成的文件
  /// 
  /// 生成的文件会根据 lib/models/objectbox/ 下的实体自动创建。
  Future<void> _initObjectBox() async {
    // ==========================================================
    // TODO: ObjectBox 初始化代码
    // 
    // 在运行 `dart run build_runner build` 后:
    // 1. 取消下面的注释
    // 2. 在文件顶部添加: import '../../objectbox.g.dart';
    // ==========================================================
    
    // final appDir = await getApplicationDocumentsDirectory();
    // final dbPath = path.join(appDir.path, 'objectbox_vectors');
    // 
    // _store = await openStore(directory: dbPath);
    // _vectorBox = _store!.box<NoteVector>();
    // _searchHistoryBox = _store!.box<SearchHistory>();
    // _similarCacheBox = _store!.box<SimilarNotesCache>();
    
    logWarning(
      'ObjectBox 未初始化 - 请先运行 dart run build_runner build 生成代码，'
      '然后取消 _initObjectBox 方法中的注释',
      source: 'VectorSearchService',
    );
  }

  /// 为笔记生成并存储嵌入向量
  /// 
  /// [note] 必须包含有效的 id，否则会抛出 ArgumentError
  Future<void> indexNote(Quote note) async {
    if (!_isInitialized) {
      throw StateError('向量搜索服务未初始化');
    }

    if (note.id == null || note.id!.isEmpty) {
      throw ArgumentError('笔记必须包含有效的 ID 才能索引');
    }

    if (_vectorBox == null) {
      logWarning('ObjectBox 未初始化，跳过索引', source: 'VectorSearchService');
      return;
    }

    final noteId = note.id!;

    try {
      // 生成嵌入向量
      final embeddingResult = await _embeddingService.embed(note.content);

      // 检查是否已存在
      final existing = _vectorBox!
          .query(NoteVector_.noteId.equals(noteId))
          .build()
          .findFirst();

      if (existing != null) {
        // 更新现有记录
        existing.updateEmbedding(embeddingResult.embedding, modelVersion);
        existing.updatePreview(note.content);
        _vectorBox!.put(existing);
        logDebug('更新笔记向量: $noteId', source: 'VectorSearchService');
      } else {
        // 创建新记录
        final noteVector = NoteVector(
          noteId: noteId,
          embedding: embeddingResult.embedding,
          contentPreview: note.content.length > 200 
              ? '${note.content.substring(0, 200)}...' 
              : note.content,
          modelVersion: modelVersion,
        );
        _vectorBox!.put(noteVector);
        logDebug('索引新笔记向量: $noteId', source: 'VectorSearchService');
      }
    } catch (e, stackTrace) {
      logError(
        '索引笔记失败: $noteId, $e',
        error: e,
        stackTrace: stackTrace,
        source: 'VectorSearchService',
      );
      rethrow;
    }
  }

  /// 批量索引笔记
  Future<void> indexNotes(List<Quote> notes, {
    void Function(int indexed, int total)? onProgress,
  }) async {
    for (var i = 0; i < notes.length; i++) {
      await indexNote(notes[i]);
      onProgress?.call(i + 1, notes.length);
    }
  }

  /// 删除笔记的向量
  Future<void> removeNoteVector(String noteId) async {
    if (_vectorBox == null) return;

    final existing = _vectorBox!
        .query(NoteVector_.noteId.equals(noteId))
        .build()
        .findFirst();

    if (existing != null) {
      _vectorBox!.remove(existing.id);
      logDebug('删除笔记向量: $noteId', source: 'VectorSearchService');
    }
  }

  /// 向量相似度搜索
  /// 
  /// [query] 搜索查询文本
  /// [topK] 返回的最大结果数
  /// [threshold] 最低相似度阈值 (0-1)
  Future<List<VectorSearchResult>> search(
    String query, {
    int topK = 10,
    double threshold = 0.5,
  }) async {
    if (!_isInitialized) {
      throw StateError('向量搜索服务未初始化');
    }

    if (_vectorBox == null) {
      logWarning('ObjectBox 未初始化，返回空结果', source: 'VectorSearchService');
      return [];
    }

    try {
      // 1. 生成查询向量
      final queryEmbedding = await _embeddingService.embed(query);

      // 2. 执行 HNSW 向量搜索
      final queryBuilder = _vectorBox!.query(
        NoteVector_.embedding.nearestNeighborsF32(
          queryEmbedding.embedding,
          topK,
        ),
      ).build();

      final results = queryBuilder.findWithScores();
      queryBuilder.close();

      // 3. 过滤并转换结果
      final searchResults = <VectorSearchResult>[];
      for (final result in results) {
        // ObjectBox 返回的是距离，需要转换为相似度
        // 对于归一化向量，余弦距离 = 1 - 余弦相似度
        final similarity = 1.0 - result.score;
        
        if (similarity >= threshold) {
          searchResults.add(VectorSearchResult(
            noteId: result.object.noteId,
            score: similarity,
            preview: result.object.contentPreview,
          ));
        }
      }

      // 4. 记录搜索历史
      await _recordSearchHistory(
        query, 
        queryEmbedding.embedding,
        searchResults.length,
      );

      logDebug(
        '向量搜索完成: "$query" -> ${searchResults.length} 结果',
        source: 'VectorSearchService',
      );

      return searchResults;
    } catch (e, stackTrace) {
      logError(
        '向量搜索失败: $e',
        error: e,
        stackTrace: stackTrace,
        source: 'VectorSearchService',
      );
      rethrow;
    }
  }

  /// 查找相似笔记
  Future<List<VectorSearchResult>> findSimilarNotes(
    String noteId, {
    int topK = 5,
    double threshold = 0.6,
    bool useCache = true,
  }) async {
    if (_vectorBox == null) return [];

    // 1. 检查缓存
    if (useCache && _similarCacheBox != null) {
      final cache = _similarCacheBox!
          .query(SimilarNotesCache_.sourceNoteId.equals(noteId))
          .build()
          .findFirst();

      if (cache != null && !cache.isExpired) {
        return _decodeCachedResults(cache);
      }
    }

    // 2. 获取源笔记的向量
    final sourceVector = _vectorBox!
        .query(NoteVector_.noteId.equals(noteId))
        .build()
        .findFirst();

    if (sourceVector == null) {
      logWarning('未找到笔记向量: $noteId', source: 'VectorSearchService');
      return [];
    }

    // 3. 执行相似度搜索
    final queryBuilder = _vectorBox!.query(
      NoteVector_.embedding.nearestNeighborsF32(
        sourceVector.embedding,
        topK + 1, // +1 因为会包含自身
      ),
    ).build();

    final results = queryBuilder.findWithScores();
    queryBuilder.close();

    // 4. 过滤结果（排除自身）
    final searchResults = <VectorSearchResult>[];
    for (final result in results) {
      if (result.object.noteId == noteId) continue;
      
      final similarity = 1.0 - result.score;
      if (similarity >= threshold) {
        searchResults.add(VectorSearchResult(
          noteId: result.object.noteId,
          score: similarity,
          preview: result.object.contentPreview,
        ));
      }
    }

    // 5. 缓存结果
    if (useCache && _similarCacheBox != null && searchResults.isNotEmpty) {
      await _cacheSimilarResults(noteId, searchResults);
    }

    return searchResults;
  }

  /// 记录搜索历史
  Future<void> _recordSearchHistory(
    String query,
    List<double> embedding,
    int resultCount,
  ) async {
    if (_searchHistoryBox == null) return;

    final history = SearchHistory(
      query: query,
      queryEmbedding: embedding,
      resultCount: resultCount,
    );
    _searchHistoryBox!.put(history);
  }

  /// 缓存相似笔记结果
  Future<void> _cacheSimilarResults(
    String sourceNoteId,
    List<VectorSearchResult> results,
  ) async {
    if (_similarCacheBox == null) return;

    // 删除旧缓存
    final oldCache = _similarCacheBox!
        .query(SimilarNotesCache_.sourceNoteId.equals(sourceNoteId))
        .build()
        .findFirst();

    if (oldCache != null) {
      _similarCacheBox!.remove(oldCache.id);
    }

    // 创建新缓存
    final cache = SimilarNotesCache(
      sourceNoteId: sourceNoteId,
      similarNoteIdsJson: json.encode(results.map((r) => r.noteId).toList()),
      similarityScoresJson: json.encode(results.map((r) => r.score).toList()),
    );
    _similarCacheBox!.put(cache);
  }

  /// 解码缓存的相似笔记结果
  List<VectorSearchResult> _decodeCachedResults(SimilarNotesCache cache) {
    final noteIds = (json.decode(cache.similarNoteIdsJson) as List)
        .cast<String>();
    final scores = (json.decode(cache.similarityScoresJson) as List)
        .cast<double>();

    final results = <VectorSearchResult>[];
    for (var i = 0; i < noteIds.length; i++) {
      results.add(VectorSearchResult(
        noteId: noteIds[i],
        score: scores[i],
      ));
    }
    return results;
  }

  /// 获取向量统计信息
  Future<Map<String, dynamic>> getStats() async {
    if (_vectorBox == null) {
      return {'initialized': false};
    }

    return {
      'initialized': true,
      'totalVectors': _vectorBox!.count(),
      'modelVersion': modelVersion,
      'searchHistoryCount': _searchHistoryBox?.count() ?? 0,
      'similarCacheCount': _similarCacheBox?.count() ?? 0,
    };
  }

  /// 清除所有向量数据
  Future<void> clearAll() async {
    _vectorBox?.removeAll();
    _searchHistoryBox?.removeAll();
    _similarCacheBox?.removeAll();
    logInfo('已清除所有向量数据', source: 'VectorSearchService');
    notifyListeners();
  }

  /// 清除过期的相似笔记缓存
  Future<int> clearExpiredCache() async {
    if (_similarCacheBox == null) return 0;

    final allCache = _similarCacheBox!.getAll();
    var removed = 0;

    for (final cache in allCache) {
      if (cache.isExpired) {
        _similarCacheBox!.remove(cache.id);
        removed++;
      }
    }

    if (removed > 0) {
      logInfo('清除了 $removed 条过期缓存', source: 'VectorSearchService');
    }

    return removed;
  }

  @override
  void dispose() {
    _store?.close();
    _embeddingService.dispose();
    _isInitialized = false;
    super.dispose();
  }
}
