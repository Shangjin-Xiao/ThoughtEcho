import 'dart:io';
import 'dart:math';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:thoughtecho/utils/bert_tokenizer.dart';

class LocalEmbeddingService {
  Interpreter? _interpreter;
  BertTokenizer? _tokenizer;
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  Future<void> initialize(String modelPath, String vocabPath) async {
    if (_isInitialized) return;

    try {
      final options = InterpreterOptions();
      // Use XNNPACK or GPU delegate if available/needed
      // options.addDelegate(XNNPackDelegate());

      // Interpreter.fromFile is synchronous in some versions, but error says "await on ... not a subtype of Future"
      // So we remove await. And pass File object.
      _interpreter = Interpreter.fromFile(File(modelPath), options: options);
      _tokenizer = await BertTokenizer.fromFile(vocabPath);
      _isInitialized = true;
    } catch (e) {
      // print('Error initializing LocalEmbeddingService: $e'); // Avoid print
      rethrow;
    }
  }

  Future<List<double>> generateEmbedding(String text) async {
    if (!_isInitialized || _interpreter == null || _tokenizer == null) {
      throw Exception('Service not initialized');
    }

    // 1. Tokenize
    final tokens = _tokenizer!.tokenize(text);
    // Pad to 256 or whatever the model expects, or let it be dynamic if model supports
    // MiniLM usually expects fixed size or dynamic. Let's pad/truncate to 128 for speed.
    final int maxLen = 128;
    List<int> inputIds = List.filled(maxLen, 0);
    List<int> attentionMask = List.filled(maxLen, 0);
    List<int> tokenTypeIds = List.filled(maxLen, 0); // MiniLM usually doesn't need this but BERT does

    for (int i = 0; i < min(tokens.length, maxLen); i++) {
      inputIds[i] = tokens[i];
      attentionMask[i] = 1;
    }

    // 2. Prepare Inputs
    // Shape: [1, maxLen]
    var input0 = [inputIds];
    var input1 = [attentionMask];
    var input2 = [tokenTypeIds];

    // 3. Prepare Output
    // Output shape for MiniLM-L12-v2 is usually [1, maxLen, 384] (last_hidden_state)
    // We need to verify the output index. Usually output 0.
    var outputBuffer = List.filled(1 * maxLen * 384, 0.0).reshape([1, maxLen, 384]);

    // 4. Run Inference
    // Map inputs/outputs based on model signature.
    // Standard BERT TFLite inputs: 0: ids, 1: mask, 2: segment_ids (sometimes order varies)
    // We'll assume standard order. If needed, we check `_interpreter.getInputTensors()`.
    // For safety, let's map by signature if possible, but map is easier.
    // final inputs = {0: input0, 1: input1, 2: input2}; // Unused
    final outputs = {0: outputBuffer};

    _interpreter!.runForMultipleInputs([input0, input1, input2], outputs);

    // 5. Mean Pooling
    // Calculate mean of all token embeddings, weighted by attention mask
    List<double> embedding = List.filled(384, 0.0);
    double maskSum = 0;

    for (int i = 0; i < maxLen; i++) {
      if (attentionMask[i] == 1) {
        maskSum += 1;
        for (int j = 0; j < 384; j++) {
          embedding[j] += outputBuffer[0][i][j];
        }
      }
    }

    if (maskSum > 0) {
      for (int j = 0; j < 384; j++) {
        embedding[j] /= maskSum;
      }
    }

    // 6. Normalize (L2 norm)
    double norm = 0;
    for (var val in embedding) {
      norm += val * val;
    }
    norm = sqrt(norm);
    if (norm > 0) {
      for (int j = 0; j < 384; j++) {
        embedding[j] /= norm;
      }
    }

    return embedding;
  }

  void dispose() {
    _interpreter?.close();
    _isInitialized = false;
  }
}
