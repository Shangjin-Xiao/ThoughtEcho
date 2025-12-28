import 'package:cactus/cactus.dart';
import '../../utils/app_logger.dart'; // Using AppLogger for consistent logging

/// Service for handling local AI tasks using Cactus.
///
/// ⚠️ cactus 许可证不明，商业使用需先确认
class CactusService {
  CactusLM? _lm;
  CactusSTT? _stt;
  CactusRAG? _rag;

  bool _isLMInitialized = false;
  bool _isSTTInitialized = false;
  bool _isRAGInitialized = false;

  /// Initializes the Cactus service.
  ///
  /// Requires models to be downloaded first via [downloadModel] and [downloadVoiceModel].
  Future<void> initialize() async {
    // LM
    _lm = CactusLM();
    try {
        // Initialize with default or previously downloaded model
        await _lm?.initializeModel();
        _isLMInitialized = true;
    } catch (e) {
        logError('LM Initialization failed (model might need download): $e', source: 'CactusService');
    }

    // STT
    _stt = CactusSTT();
    try {
        await _stt?.initializeModel();
        _isSTTInitialized = true;
    } catch (e) {
        logError('STT Initialization failed: $e', source: 'CactusService');
    }

    // RAG
    _rag = CactusRAG();
    try {
        await _rag?.initialize();
        // Set embedding generator using our LM
        _rag?.setEmbeddingGenerator((text) async {
             return await embed(text);
        });
        _isRAGInitialized = true;
    } catch (e) {
        logError('RAG Initialization failed: $e', source: 'CactusService');
    }
  }

  /// Downloads a model by slug.
  Future<void> downloadModel(String modelSlug, {Function(double?, String, bool)? onProgress}) async {
      final lm = CactusLM();
      await lm.downloadModel(
          model: modelSlug,
          downloadProcessCallback: (progress, status, isError) {
              if (onProgress != null) {
                  onProgress(progress, status, isError);
              }
          }
      );
      lm.unload();
  }

  /// Downloads a voice model by slug.
  Future<void> downloadVoiceModel(String modelSlug, {Function(double?, String, bool)? onProgress}) async {
      final stt = CactusSTT();
      await stt.downloadModel(
          model: modelSlug,
          downloadProcessCallback: (progress, status, isError) {
              if (onProgress != null) {
                  onProgress(progress, status, isError);
              }
          }
      );
      stt.unload();
  }

  /// Chat with the LLM.
  Future<String> chat(String message) async {
    if (!_isLMInitialized) throw Exception('LM not initialized');

    final result = await _lm?.generateCompletion(
      messages: [ChatMessage(role: 'user', content: message)],
    );

    if (result != null && result.success) {
      return result.response;
    } else {
      throw Exception('Chat failed');
    }
  }

  /// Transcribe audio file to text.
  Future<String> transcribe(String audioPath) async {
    if (!_isSTTInitialized) {
         throw Exception('STT not initialized');
    }

    final result = await _stt?.transcribe(
      audioFilePath: audioPath,
    );

    if (result != null && result.success) {
      return result.text;
    } else {
      throw Exception('Transcription failed: ${result?.errorMessage}');
    }
  }

  /// Generate embeddings for text.
  Future<List<double>> embed(String text) async {
    if (!_isLMInitialized) throw Exception('LM not initialized for embedding');

    final result = await _lm?.generateEmbedding(text: text);

    if (result != null && result.success) {
      return result.embeddings;
    } else {
      throw Exception('Embedding failed: ${result?.errorMessage}');
    }
  }

  // --- RAG Methods ---

  /// Stores a document in the vector store.
  Future<void> storeDocument(String fileName, String content) async {
      if (!_isRAGInitialized) throw Exception('RAG not initialized');

      await _rag?.storeDocument(
          fileName: fileName,
          filePath: fileName, // Using fileName as path for simplicity in this abstract interface
          content: content,
          fileSize: content.length,
      );
  }

  /// Searches for similar content.
  Future<List<String>> search(String query, {int limit = 5}) async {
      if (!_isRAGInitialized) throw Exception('RAG not initialized');

      final results = await _rag?.search(text: query, limit: limit);
      if (results == null) return [];

      return results.map((r) => r.chunk.content).toList();
  }

  void dispose() {
    _lm?.unload();
    _stt?.unload();
    _rag?.close();
  }
}
