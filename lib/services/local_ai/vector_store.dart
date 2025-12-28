/// 向量存储服务
///
/// 存储和检索文本嵌入向量，支持语义搜索

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

import '../../models/embedding_result.dart';
import '../../utils/app_logger.dart';
import 'embedding_service.dart';

/// 向量存储服务
class VectorStore extends ChangeNotifier {
  static VectorStore? _instance;

  /// 单例实例
  static VectorStore get instance {
    _instance ??= VectorStore._();
    return _instance!;
  }

  VectorStore._();

  /// 嵌入服务
  final EmbeddingService _embeddingService = EmbeddingService.instance;

  /// 存储的嵌入向量
  final Map<String, Embedding> _embeddings = {};

  /// 存储文件路径
  String? _storagePath;

  /// 是否已初始化
  bool _initialized = false;

  /// 是否已初始化
  bool get isInitialized => _initialized;

  /// 获取存储的嵌入数量
  int get count => _embeddings.length;

  /// 初始化向量存储
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      // 获取存储路径
      final appDir = await getApplicationDocumentsDirectory();
      _storagePath = path.join(appDir.path, 'vector_store.json');

      // 加载已存储的向量
      await _loadFromDisk();

      _initialized = true;
      logInfo('向量存储初始化完成，已加载 ${_embeddings.length} 个向量', source: 'VectorStore');
    } catch (e) {
      logError('向量存储初始化失败: $e', source: 'VectorStore');
      rethrow;
    }
  }

  /// 添加或更新笔记的嵌入向量
  Future<void> upsertNote(String noteId, String content) async {
    if (!_initialized) {
      throw Exception('向量存储未初始化');
    }

    try {
      // 生成嵌入向量
      final embedding = await _embeddingService.generateEmbedding(content);

      // 存储
      _embeddings[noteId] = embedding.copyWith(noteId: noteId);
      notifyListeners();

      // 异步保存到磁盘（使用 unawaited 明确表示不等待）
      unawaited(_saveToDisk());

      logDebug('已更新笔记 $noteId 的嵌入向量', source: 'VectorStore');
    } catch (e) {
      logError('更新嵌入向量失败: $e', source: 'VectorStore');
      rethrow;
    }
  }

  /// 删除笔记的嵌入向量
  Future<void> deleteNote(String noteId) async {
    if (_embeddings.remove(noteId) != null) {
      notifyListeners();
      unawaited(_saveToDisk());
      logDebug('已删除笔记 $noteId 的嵌入向量', source: 'VectorStore');
    }
  }

  /// 搜索相似笔记
  Future<List<SearchResult>> search(
    String query, {
    int topK = 10,
    double minScore = 0.0,
  }) async {
    if (!_initialized) {
      throw Exception('向量存储未初始化');
    }

    if (_embeddings.isEmpty) {
      return [];
    }

    try {
      // 生成查询向量
      final queryEmbedding = await _embeddingService.generateEmbedding(query);

      // 计算相似度并排序
      final results = <SearchResult>[];

      for (final entry in _embeddings.entries) {
        final noteId = entry.key;
        final embedding = entry.value;

        final score = queryEmbedding.cosineSimilarity(embedding);

        if (score >= minScore) {
          results.add(SearchResult(
            noteId: noteId,
            score: score,
            matchedText: embedding.sourceText,
          ));
        }
      }

      // 按相似度降序排序
      results.sort((a, b) => b.score.compareTo(a.score));

      // 返回前 topK 个结果
      return results.take(topK).toList();
    } catch (e) {
      logError('搜索失败: $e', source: 'VectorStore');
      rethrow;
    }
  }

  /// 获取相关笔记
  Future<List<RelatedNote>> getRelatedNotes(
    String noteId, {
    int topK = 5,
    double minSimilarity = 0.3,
  }) async {
    if (!_initialized) {
      throw Exception('向量存储未初始化');
    }

    final sourceEmbedding = _embeddings[noteId];
    if (sourceEmbedding == null) {
      return [];
    }

    try {
      final results = <RelatedNote>[];

      for (final entry in _embeddings.entries) {
        if (entry.key == noteId) continue; // 排除自身

        final similarity = sourceEmbedding.cosineSimilarity(entry.value);

        if (similarity >= minSimilarity) {
          results.add(RelatedNote(
            noteId: entry.key,
            similarity: similarity,
            reason: _generateSimilarityReason(similarity),
          ));
        }
      }

      // 按相似度降序排序
      results.sort((a, b) => b.similarity.compareTo(a.similarity));

      return results.take(topK).toList();
    } catch (e) {
      logError('获取相关笔记失败: $e', source: 'VectorStore');
      rethrow;
    }
  }

  /// 生成相似度原因描述
  String _generateSimilarityReason(double similarity) {
    if (similarity >= 0.8) {
      return '内容高度相关';
    } else if (similarity >= 0.6) {
      return '主题相似';
    } else if (similarity >= 0.4) {
      return '有一定关联';
    } else {
      return '可能相关';
    }
  }

  /// 批量添加笔记嵌入
  Future<void> batchUpsert(Map<String, String> notes) async {
    if (!_initialized) {
      throw Exception('向量存储未初始化');
    }

    try {
      for (final entry in notes.entries) {
        final embedding = await _embeddingService.generateEmbedding(entry.value);
        _embeddings[entry.key] = embedding.copyWith(noteId: entry.key);
      }

      notifyListeners();
      unawaited(_saveToDisk());

      logInfo('批量更新 ${notes.length} 个嵌入向量', source: 'VectorStore');
    } catch (e) {
      logError('批量更新失败: $e', source: 'VectorStore');
      rethrow;
    }
  }

  /// 清空所有向量
  Future<void> clear() async {
    _embeddings.clear();
    notifyListeners();
    unawaited(_saveToDisk());

    logInfo('已清空向量存储', source: 'VectorStore');
  }

  /// 从磁盘加载
  Future<void> _loadFromDisk() async {
    if (_storagePath == null) return;

    try {
      final file = File(_storagePath!);
      if (!await file.exists()) return;

      final content = await file.readAsString();
      final data = json.decode(content) as Map<String, dynamic>;

      for (final entry in data.entries) {
        _embeddings[entry.key] = Embedding.fromJson(
          entry.value as Map<String, dynamic>,
        );
      }
    } catch (e) {
      logError('加载向量存储失败: $e', source: 'VectorStore');
    }
  }

  /// 保存到磁盘
  Future<void> _saveToDisk() async {
    if (_storagePath == null) return;

    try {
      final data = <String, dynamic>{};
      for (final entry in _embeddings.entries) {
        data[entry.key] = entry.value.toJson();
      }

      final file = File(_storagePath!);
      await file.writeAsString(json.encode(data));
    } catch (e) {
      logError('保存向量存储失败: $e', source: 'VectorStore');
    }
  }

  @override
  void dispose() {
    _saveToDisk();
    super.dispose();
  }
}
