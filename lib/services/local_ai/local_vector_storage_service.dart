import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import '../../utils/app_logger.dart';
import 'local_embedding_service.dart';

/// Service for storing and searching note embeddings using SQLite
/// 
/// Uses brute-force cosine similarity search, suitable for < 10k notes.
/// For larger collections, consider using a dedicated vector database.
class LocalVectorStorageService extends ChangeNotifier {
  Database? _database;
  bool _isInitialized = false;
  String? _error;

  /// Whether the service is initialized
  bool get isInitialized => _isInitialized;

  /// Error message if initialization failed
  String? get error => _error;

  /// Embedding dimension (must match the embedding model)
  static const int embeddingDimension = 384;

  /// Database name
  static const String _databaseName = 'note_embeddings.db';

  /// Initialize the vector storage service
  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }

    try {
      final documentsDirectory = await getApplicationDocumentsDirectory();
      final path = join(documentsDirectory.path, _databaseName);

      _database = await openDatabase(
        path,
        version: 1,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );

      _isInitialized = true;
      logDebug('Vector storage service initialized at: $path');
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      logDebug('Failed to initialize vector storage: $e');
    }
  }

  /// Create database tables
  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS note_embeddings (
        note_id TEXT PRIMARY KEY,
        embedding BLOB NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_note_embeddings_updated 
      ON note_embeddings(updated_at)
    ''');

    logDebug('Created note_embeddings table');
  }

  /// Handle database upgrades
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Future migrations go here
  }

  /// Store embedding for a note
  /// 
  /// [noteId] - The unique ID of the note
  /// [embedding] - The embedding vector (must be 384 dimensions)
  Future<bool> storeEmbedding(String noteId, List<double> embedding) async {
    if (!_isInitialized || _database == null) {
      logDebug('Vector storage not initialized');
      return false;
    }

    if (embedding.length != embeddingDimension) {
      logDebug('Invalid embedding dimension: ${embedding.length}, expected $embeddingDimension');
      return false;
    }

    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final embeddingBlob = _embeddingToBlob(embedding);

      await _database!.insert(
        'note_embeddings',
        {
          'note_id': noteId,
          'embedding': embeddingBlob,
          'created_at': now,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      return true;
    } catch (e) {
      logDebug('Error storing embedding: $e');
      return false;
    }
  }

  /// Get embedding for a note
  Future<List<double>?> getEmbedding(String noteId) async {
    if (!_isInitialized || _database == null) {
      return null;
    }

    try {
      final results = await _database!.query(
        'note_embeddings',
        columns: ['embedding'],
        where: 'note_id = ?',
        whereArgs: [noteId],
      );

      if (results.isEmpty) {
        return null;
      }

      final blob = results.first['embedding'] as Uint8List;
      return _blobToEmbedding(blob);
    } catch (e) {
      logDebug('Error getting embedding: $e');
      return null;
    }
  }

  /// Delete embedding for a note
  Future<bool> deleteEmbedding(String noteId) async {
    if (!_isInitialized || _database == null) {
      return false;
    }

    try {
      await _database!.delete(
        'note_embeddings',
        where: 'note_id = ?',
        whereArgs: [noteId],
      );
      return true;
    } catch (e) {
      logDebug('Error deleting embedding: $e');
      return false;
    }
  }

  /// Search for similar notes using brute-force cosine similarity
  /// 
  /// [queryEmbedding] - The query embedding vector
  /// [topK] - Number of results to return (default 10)
  /// [threshold] - Minimum similarity threshold (0.0 - 1.0, default 0.3)
  /// [excludeNoteIds] - Note IDs to exclude from results
  Future<List<SimilarityResult>> searchSimilar(
    List<double> queryEmbedding, {
    int topK = 10,
    double threshold = 0.3,
    List<String>? excludeNoteIds,
  }) async {
    if (!_isInitialized || _database == null) {
      return [];
    }

    if (queryEmbedding.length != embeddingDimension) {
      logDebug('Invalid query embedding dimension');
      return [];
    }

    try {
      // Get all embeddings
      final results = await _database!.query('note_embeddings');
      
      if (results.isEmpty) {
        return [];
      }

      // Calculate similarities
      final similarities = <SimilarityResult>[];
      final excludeSet = excludeNoteIds?.toSet() ?? <String>{};

      for (final row in results) {
        final noteId = row['note_id'] as String;
        
        // Skip excluded notes
        if (excludeSet.contains(noteId)) {
          continue;
        }

        final blob = row['embedding'] as Uint8List;
        final embedding = _blobToEmbedding(blob);
        
        final similarity = LocalEmbeddingService.cosineSimilarity(
          queryEmbedding,
          embedding,
        );

        if (similarity >= threshold) {
          similarities.add(SimilarityResult(
            noteId: noteId,
            similarity: similarity,
          ));
        }
      }

      // Sort by similarity (descending) and take top K
      similarities.sort((a, b) => b.similarity.compareTo(a.similarity));
      
      return similarities.take(topK).toList();
    } catch (e) {
      logDebug('Error searching similar notes: $e');
      return [];
    }
  }

  /// Find related notes for a given note
  /// 
  /// [noteId] - The note ID to find related notes for
  /// [topK] - Number of results to return
  /// [threshold] - Minimum similarity threshold
  Future<List<SimilarityResult>> findRelatedNotes(
    String noteId, {
    int topK = 5,
    double threshold = 0.4,
  }) async {
    final embedding = await getEmbedding(noteId);
    if (embedding == null) {
      return [];
    }

    return searchSimilar(
      embedding,
      topK: topK,
      threshold: threshold,
      excludeNoteIds: [noteId],  // Exclude the query note itself
    );
  }

  /// Get the number of stored embeddings
  Future<int> getEmbeddingCount() async {
    if (!_isInitialized || _database == null) {
      return 0;
    }

    try {
      final result = await _database!.rawQuery(
        'SELECT COUNT(*) as count FROM note_embeddings'
      );
      return Sqflite.firstIntValue(result) ?? 0;
    } catch (e) {
      logDebug('Error getting embedding count: $e');
      return 0;
    }
  }

  /// Check if embedding exists for a note
  Future<bool> hasEmbedding(String noteId) async {
    if (!_isInitialized || _database == null) {
      return false;
    }

    try {
      final result = await _database!.query(
        'note_embeddings',
        columns: ['note_id'],
        where: 'note_id = ?',
        whereArgs: [noteId],
        limit: 1,
      );
      return result.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// Delete all embeddings
  Future<bool> clearAllEmbeddings() async {
    if (!_isInitialized || _database == null) {
      return false;
    }

    try {
      await _database!.delete('note_embeddings');
      logDebug('Cleared all embeddings');
      return true;
    } catch (e) {
      logDebug('Error clearing embeddings: $e');
      return false;
    }
  }

  /// Batch store embeddings
  Future<int> batchStoreEmbeddings(
    Map<String, List<double>> embeddings,
  ) async {
    if (!_isInitialized || _database == null) {
      return 0;
    }

    int stored = 0;
    final batch = _database!.batch();
    final now = DateTime.now().millisecondsSinceEpoch;

    for (final entry in embeddings.entries) {
      if (entry.value.length != embeddingDimension) {
        continue;
      }

      batch.insert(
        'note_embeddings',
        {
          'note_id': entry.key,
          'embedding': _embeddingToBlob(entry.value),
          'created_at': now,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      stored++;
    }

    try {
      await batch.commit(noResult: true);
      logDebug('Batch stored $stored embeddings');
      return stored;
    } catch (e) {
      logDebug('Error batch storing embeddings: $e');
      return 0;
    }
  }

  /// Convert embedding to BLOB for storage
  Uint8List _embeddingToBlob(List<double> embedding) {
    final buffer = Float32List(embedding.length);
    for (int i = 0; i < embedding.length; i++) {
      buffer[i] = embedding[i];
    }
    return buffer.buffer.asUint8List();
  }

  /// Convert BLOB to embedding
  List<double> _blobToEmbedding(Uint8List blob) {
    final buffer = Float32List.view(blob.buffer);
    return buffer.map((v) => v.toDouble()).toList();
  }

  /// Get storage statistics
  Future<Map<String, dynamic>> getStatistics() async {
    if (!_isInitialized || _database == null) {
      return {'error': 'Not initialized'};
    }

    try {
      final count = await getEmbeddingCount();
      final estimatedSize = count * embeddingDimension * 4; // 4 bytes per float32
      
      return {
        'embeddingCount': count,
        'embeddingDimension': embeddingDimension,
        'estimatedSizeBytes': estimatedSize,
        'estimatedSizeMB': (estimatedSize / (1024 * 1024)).toStringAsFixed(2),
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  /// Dispose resources
  Future<void> disposeService() async {
    await _database?.close();
    _database = null;
    _isInitialized = false;
    notifyListeners();
  }

  @override
  void dispose() {
    // Use unawaited to explicitly indicate that we're intentionally not awaiting
    // This is acceptable because database close is not critical for app shutdown
    unawaited(disposeService());
    super.dispose();
  }
}

/// Result of a similarity search
class SimilarityResult {
  /// The note ID
  final String noteId;
  
  /// Similarity score (0.0 - 1.0)
  final double similarity;

  const SimilarityResult({
    required this.noteId,
    required this.similarity,
  });

  Map<String, dynamic> toJson() {
    return {
      'noteId': noteId,
      'similarity': similarity,
    };
  }

  @override
  String toString() => 'SimilarityResult(noteId: $noteId, similarity: ${(similarity * 100).toStringAsFixed(1)}%)';
}
