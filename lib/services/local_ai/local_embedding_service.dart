import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import '../../utils/app_logger.dart';

/// Service for generating text embeddings using TFLite models
/// 
/// Uses paraphrase-multilingual-MiniLM-L12-v2 TFLite model:
/// - Quantized ~25MB
/// - 384 dimensional vectors
/// - Supports 50+ languages
class LocalEmbeddingService extends ChangeNotifier {
  Interpreter? _interpreter;
  List<String>? _vocabulary;
  bool _isInitialized = false;
  bool _isInitializing = false;
  String? _error;

  /// Whether the service is initialized and ready
  bool get isInitialized => _isInitialized;

  /// Whether initialization is in progress
  bool get isInitializing => _isInitializing;

  /// Error message if initialization failed
  String? get error => _error;

  /// The dimension of the embedding vectors (384 for MiniLM)
  static const int embeddingDimension = 384;

  /// Maximum sequence length for the model
  static const int maxSequenceLength = 128;

  /// Initialize the embedding service with user-provided model
  /// 
  /// [modelPath] - Path to the .tflite model file
  /// [vocabPath] - Path to the vocabulary file (vocab.txt)
  Future<void> initialize(String modelPath, String vocabPath) async {
    if (_isInitializing) {
      logDebug('Embedding service is already initializing');
      return;
    }

    _isInitializing = true;
    _error = null;
    notifyListeners();

    try {
      // Validate file paths
      if (!await File(modelPath).exists()) {
        throw Exception('Model file not found: $modelPath');
      }
      if (!await File(vocabPath).exists()) {
        throw Exception('Vocabulary file not found: $vocabPath');
      }

      // Load vocabulary
      final vocabFile = File(vocabPath);
      final vocabContent = await vocabFile.readAsString();
      _vocabulary = vocabContent.split('\n').map((e) => e.trim()).toList();
      logDebug('Loaded vocabulary with ${_vocabulary!.length} tokens');

      // Load TFLite model
      _interpreter = await Interpreter.fromFile(
        File(modelPath),
        options: InterpreterOptions()..threads = 4,
      );

      // Log model input/output shapes
      final inputTensors = _interpreter!.getInputTensors();
      final outputTensors = _interpreter!.getOutputTensors();
      logDebug('Model input shapes: ${inputTensors.map((t) => t.shape).toList()}');
      logDebug('Model output shapes: ${outputTensors.map((t) => t.shape).toList()}');

      _isInitialized = true;
      logDebug('Embedding service initialized successfully');
    } catch (e) {
      _error = e.toString();
      logDebug('Failed to initialize embedding service: $e');
      _isInitialized = false;
    } finally {
      _isInitializing = false;
      notifyListeners();
    }
  }

  /// Generate embedding for a text string
  /// 
  /// Returns a 384-dimensional vector or null if service not initialized
  Future<List<double>?> generateEmbedding(String text) async {
    if (!_isInitialized || _interpreter == null || _vocabulary == null) {
      logDebug('Embedding service not initialized');
      return null;
    }

    try {
      // Tokenize the input text
      final inputIds = _tokenize(text);
      final attentionMask = List.filled(maxSequenceLength, 1);
      
      // Pad or truncate to maxSequenceLength
      while (inputIds.length < maxSequenceLength) {
        inputIds.add(0); // PAD token
        attentionMask[inputIds.length - 1] = 0;
      }
      if (inputIds.length > maxSequenceLength) {
        inputIds.length = maxSequenceLength;
      }

      // Prepare input tensors
      final inputIdsBuffer = Int32List.fromList(inputIds);
      final attentionMaskBuffer = Int32List.fromList(attentionMask.take(maxSequenceLength).toList());
      
      // Prepare output buffer
      final outputBuffer = List.filled(embeddingDimension, 0.0);

      // Run inference
      // Note: The exact input format depends on the specific model
      // This is a common format for sentence-transformers models
      _interpreter!.run(
        [inputIdsBuffer, attentionMaskBuffer],
        outputBuffer,
      );

      // Normalize the embedding
      final normalized = _normalizeVector(outputBuffer);
      
      return normalized;
    } catch (e) {
      logDebug('Error generating embedding: $e');
      return null;
    }
  }

  /// Generate embeddings for multiple texts
  Future<List<List<double>?>> generateEmbeddings(List<String> texts) async {
    final results = <List<double>?>[];
    for (final text in texts) {
      results.add(await generateEmbedding(text));
    }
    return results;
  }

  /// Calculate cosine similarity between two embedding vectors
  static double cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) {
      throw ArgumentError('Vectors must have the same dimension');
    }
    
    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;
    
    for (int i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    
    if (normA == 0.0 || normB == 0.0) {
      return 0.0;
    }
    
    return dotProduct / (sqrt(normA) * sqrt(normB));
  }

  /// Simple tokenization using vocabulary
  /// 
  /// Note: This is a simplified tokenizer. For production use,
  /// you should implement proper subword tokenization (e.g., SentencePiece)
  List<int> _tokenize(String text) {
    if (_vocabulary == null) return [];

    final tokens = <int>[];
    
    // Add [CLS] token
    final clsIndex = _vocabulary!.indexOf('[CLS]');
    if (clsIndex >= 0) tokens.add(clsIndex);

    // Simple whitespace tokenization
    // In production, use proper subword tokenization
    final words = text.toLowerCase().split(RegExp(r'\s+'));
    for (final word in words) {
      final index = _vocabulary!.indexOf(word);
      if (index >= 0) {
        tokens.add(index);
      } else {
        // Add [UNK] token for unknown words
        final unkIndex = _vocabulary!.indexOf('[UNK]');
        if (unkIndex >= 0) tokens.add(unkIndex);
      }
    }

    // Add [SEP] token
    final sepIndex = _vocabulary!.indexOf('[SEP]');
    if (sepIndex >= 0) tokens.add(sepIndex);

    return tokens;
  }

  /// Normalize a vector to unit length
  List<double> _normalizeVector(List<double> vector) {
    double norm = 0.0;
    for (final v in vector) {
      norm += v * v;
    }
    norm = sqrt(norm);
    
    if (norm == 0.0) return vector;
    
    return vector.map((v) => v / norm).toList();
  }

  /// Dispose resources
  void disposeService() {
    _interpreter?.close();
    _interpreter = null;
    _vocabulary = null;
    _isInitialized = false;
    notifyListeners();
  }

  @override
  void dispose() {
    disposeService();
    super.dispose();
  }
}

/// Simple square root function to avoid dart:math import conflicts
double sqrt(double x) {
  if (x < 0) return double.nan;
  if (x == 0 || x == 1) return x;
  
  double guess = x / 2;
  for (int i = 0; i < 50; i++) {
    final newGuess = (guess + x / guess) / 2;
    if ((newGuess - guess).abs() < 1e-10) break;
    guess = newGuess;
  }
  return guess;
}
