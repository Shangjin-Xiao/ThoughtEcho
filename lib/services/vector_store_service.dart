import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:sqflite/sqflite.dart';
import 'package:thoughtecho/services/database_service.dart';

class VectorStoreService {
  final DatabaseService _databaseService;

  VectorStoreService(this._databaseService);

  Future<void> ensureTableExists() async {
    final db = await _databaseService.safeDatabase;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS note_embeddings(
        quote_id TEXT PRIMARY KEY,
        embedding BLOB NOT NULL
      )
    ''');
  }

  // Convert list of doubles to BLOB (Float32 buffer as Uint8List) for speed
  Future<void> saveEmbedding(String quoteId, List<double> embedding) async {
    await ensureTableExists();
    final db = await _databaseService.safeDatabase;

    final Float32List float32List = Float32List.fromList(embedding);
    final Uint8List bytes = float32List.buffer.asUint8List();

    await db.insert(
      'note_embeddings',
      {'quote_id': quoteId, 'embedding': bytes},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<String>> search(List<double> queryVector, {int limit = 10}) async {
    await ensureTableExists();
    final db = await _databaseService.safeDatabase;
    final List<Map<String, dynamic>> rows = await db.query('note_embeddings');

    // Brute force cosine similarity
    final List<Map<String, dynamic>> scores = []; // {id, score}

    for (final row in rows) {
      final id = row['quote_id'] as String;
      final embeddingBlob = row['embedding'] as Uint8List;

      // Convert BLOB back to List<double>
      final Float32List vectorFloat32 = Float32List.view(embeddingBlob.buffer);
      final List<double> vector = vectorFloat32.toList();

      final score = _cosineSimilarity(queryVector, vector);
      scores.add({'id': id, 'score': score});
    }

    // Sort descending
    scores.sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));

    return scores.take(limit).map((e) => e['id'] as String).toList();
  }

  double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) return 0.0;
    double dot = 0.0;
    double normA = 0.0;
    double normB = 0.0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    if (normA == 0 || normB == 0) return 0.0;
    return dot / (sqrt(normA) * sqrt(normB));
  }
}
