import 'dart:math';
import 'package:thoughtecho/services/embedding_service.dart';
import 'package:thoughtecho/services/unified_log_service.dart';

class SearchResult {
  final String id;
  final double score;
  final String content;

  SearchResult({required this.id, required this.score, required this.content});
}

class VectorStore {
  static final VectorStore _instance = VectorStore._internal();
  static VectorStore get instance => _instance;

  VectorStore._internal();

  // Simple in-memory store for demonstration.
  // In production, this should be backed by SQLite (using sqlite-vec or similar) or Hive.
  final Map<String, List<double>> _vectors = {};
  final Map<String, String> _contents = {};

  Future<void> addDocument(String id, String content) async {
    try {
      // NOTE: Vector Search is currently experimental as flutter_gemma embedding API access is unconfirmed.
      // This will gracefully fail if embeddings return empty.
      final embedding = await EmbeddingService.instance.generateEmbedding(content);
      if (embedding.isNotEmpty) {
        _vectors[id] = embedding;
        _contents[id] = content;
      } else {
         // Log warning only once per session or debug
         // UnifiedLogService.instance.log(UnifiedLogLevel.warning, 'Empty embedding generated, skipping vector store add', source: 'VectorStore');
      }
    } catch (e) {
      UnifiedLogService.instance.log(
        UnifiedLogLevel.error,
        'Failed to add document to vector store: $e',
        source: 'VectorStore',
        error: e,
      );
    }
  }

  Future<void> removeDocument(String id) async {
    _vectors.remove(id);
    _contents.remove(id);
  }

  Future<List<SearchResult>> search(String query, {int topK = 10}) async {
    try {
      final queryEmbedding = await EmbeddingService.instance.generateEmbedding(query);
      if (queryEmbedding.isEmpty) return [];

      final List<SearchResult> results = [];

      _vectors.forEach((id, vector) {
        final score = _cosineSimilarity(queryEmbedding, vector);
        results.add(SearchResult(
          id: id,
          score: score,
          content: _contents[id] ?? ''
        ));
      });

      results.sort((a, b) => b.score.compareTo(a.score));

      return results.take(topK).toList();
    } catch (e) {
      UnifiedLogService.instance.log(
        UnifiedLogLevel.error,
        'Vector search failed: $e',
        source: 'VectorStore',
        error: e,
      );
      return [];
    }
  }

  // Basic cosine similarity
  double _cosineSimilarity(List<double> vecA, List<double> vecB) {
    if (vecA.length != vecB.length) return 0.0;

    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;

    for (int i = 0; i < vecA.length; i++) {
      dotProduct += vecA[i] * vecB[i];
      normA += vecA[i] * vecA[i];
      normB += vecB[i] * vecB[i];
    }

    if (normA == 0.0 || normB == 0.0) return 0.0;

    return dotProduct / (sqrt(normA) * sqrt(normB));
  }

  Future<List<String>> getRelatedNotes(String noteId) async {
    // Basic implementation: find content of noteId, then search
    final content = _contents[noteId];
    if (content == null) return [];

    final results = await search(content);
    // Filter out the note itself
    return results
        .where((r) => r.id != noteId)
        .map((r) => r.id)
        .toList();
  }
}
