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
        // Requires a query.
        // Query<NoteVector> query = _box.query(NoteVector_.quoteId.equals(quoteId)).build();
        // Since we don't have generated code for NoteVector_, we can't write type-safe queries here easily
        // without the build step. We will assume the generated code allows:
        // final existing = query.findFirst();

        // MOCK LOGIC for "find existing":
        // In a real scenario with generated code:
        // final query = _box.query(NoteVector_.quoteId.equals(quoteId)).build();
        // final existing = query.findFirst();
        // query.close();

        NoteVector vectorEntity;
        // if (existing != null) {
        //   vectorEntity = existing;
        //   vectorEntity.embedding = embedding;
        // } else {
           vectorEntity = NoteVector(quoteId: quoteId, embedding: embedding);
        // }

        _box.put(vectorEntity);

    } catch (e) {
        print("Error updating vector index: $e");
    }
  }

  Future<void> removeIndex(String quoteId) async {
      if (!_initialized) return;
      // final query = _box.query(NoteVector_.quoteId.equals(quoteId)).build();
      // _box.remove(query.findIds());
      // query.close();
  }

  Future<List<Map<String, dynamic>>> search(String queryText, {int topK = 5}) async {
    if (!_initialized) return [];

    try {
        final queryEmbedding = await _embeddingService.getEmbedding(queryText);

        // Perform Nearest Neighbor Search
        // Query<NoteVector> query = _box.query(
        //   NoteVector_.embedding.nearestNeighbors(queryEmbedding, topK)
        // ).build();
        // final results = query.findWithScores();

        // Mock return for now since we can't compile the query
        return [];

    } catch (e) {
        print("Vector search error: $e");
        return [];
    }
  }
}
