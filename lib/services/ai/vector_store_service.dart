import 'package:objectbox/objectbox.dart';
import '../../models/note_vector.dart';
import 'embedding_service.dart';
// Note: In a real environment, we would import 'objectbox.g.dart' here.
// But since we cannot run build_runner, we will simulate the Store creation.

class VectorStoreService {
  final EmbeddingService _embeddingService;
  late final Store _store;
  late final Box<NoteVector> _box;
  bool _initialized = false;

  VectorStoreService(this._embeddingService);

  Future<void> init(Store store) async {
    _store = store;
    _box = _store.box<NoteVector>();
    _initialized = true;
  }

  // Method to create the store (usually called in main.dart)
  // static Future<Store> createStore() async {
  //   final docsDir = await getApplicationDocumentsDirectory();
  //   return Store(getObjectBoxModel(), directory: join(docsDir.path, "objectbox"));
  // }

  Future<void> updateIndex(String quoteId, String content) async {
    if (!_initialized) return;

    // 1. Get Embedding
    try {
        final embedding = await _embeddingService.getEmbedding(content);

        // 2. Check if vector exists for this quoteId
        // Note: The ideal implementation requires generated code (objectbox.g.dart) to query by quoteId.
        // Query<NoteVector> query = _box.query(NoteVector_.quoteId.equals(quoteId)).build();
        // Since we don't have generated code for NoteVector_ available in this environment,
        // we cannot write type-safe queries here.
        // The active code below creates a NEW entity. If quoteId is unique, this will throw a constraint error
        // if an entity with the same quoteId exists.

        // TEMPORARY FIX: We wrap this in a try-catch to ignore unique constraint violations for now.
        // In a real build, you MUST uncomment the query logic below to find the existing entity ID.

        /* UNCOMMENT AFTER RUNNING BUILD_RUNNER:
        final query = _box.query(NoteVector_.quoteId.equals(quoteId)).build();
        final existing = query.findFirst();
        query.close();

        NoteVector vectorEntity;
        if (existing != null) {
          vectorEntity = existing;
          vectorEntity.embedding = embedding;
        } else {
           vectorEntity = NoteVector(quoteId: quoteId, embedding: embedding);
        }
        _box.put(vectorEntity);
        */

        // Mock Implementation (Safe for compilation, potentially unsafe for data without unique check):
        try {
           final vectorEntity = NoteVector(quoteId: quoteId, embedding: embedding);
           _box.put(vectorEntity);
        } catch (dbError) {
           // Ignore unique constraint error for now since we can't query properly without generated code
           print("Vector index update failed (likely duplicate): $dbError");
        }

    } catch (e) {
        print("Error updating vector index: $e");
    }
  }

  Future<void> removeIndex(String quoteId) async {
      if (!_initialized) return;
      // UNCOMMENT AFTER BUILD_RUNNER:
      // final query = _box.query(NoteVector_.quoteId.equals(quoteId)).build();
      // _box.remove(query.findIds());
      // query.close();
  }

  Future<List<Map<String, dynamic>>> search(String queryText, {int topK = 5}) async {
    if (!_initialized) return [];

    try {
        final queryEmbedding = await _embeddingService.getEmbedding(queryText);

        // Perform Nearest Neighbor Search
        // UNCOMMENT AFTER BUILD_RUNNER:
        // Query<NoteVector> query = _box.query(
        //   NoteVector_.embedding.nearestNeighbors(queryEmbedding, topK)
        // ).build();
        // final results = query.findWithScores();
        // return results.map((r) => {'id': r.item.quoteId, 'score': r.score}).toList();

        // Mock return for now since we can't compile the query
        return [];

    } catch (e) {
        print("Vector search error: $e");
        return [];
    }
  }
}
