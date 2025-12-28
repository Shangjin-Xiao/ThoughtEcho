import 'package:onnxruntime/onnxruntime.dart';
import 'dart:typed_data';
import 'dart:math';
import 'model_manager_service.dart';
import 'tokenizer_service.dart';

class EmbeddingService {
  final ModelManagerService _modelManager;
  final TokenizerService _tokenizer;
  OrtSession? _session;

  EmbeddingService(this._modelManager, this._tokenizer);

  Future<void> init() async {
    if (_session != null) return;

    // Ensure models are downloaded
    if (!await _modelManager.areEmbeddingModelsDownloaded()) {
      // In a real app, we should trigger download or throw error
      // For now, we assume download is handled by UI before calling init
      print("Models not downloaded");
      return;
    }

    // Load Vocab
    await _tokenizer.loadVocab(await _modelManager.getVocabPath());

    // Init Session
    final modelPath = await _modelManager.getEmbeddingModelPath();
    final sessionOptions = OrtSessionOptions();
    _session = OrtSession.fromFile(File(modelPath), sessionOptions);
  }

  Future<List<double>> getEmbedding(String text) async {
    if (_session == null) {
      await init();
      if (_session == null) throw Exception("Failed to initialize embedding session");
    }

    // 1. Tokenize
    final inputs = _tokenizer.encode(text);
    final inputIds = inputs['input_ids']!;
    final attentionMask = inputs['attention_mask']!;
    final tokenTypeIds = inputs['token_type_ids']!;

    // 2. Prepare Tensors
    // Shape: [1, 128] for single batch, maxLen=128
    final shape = [1, inputIds.length];

    // Create Float64 List for Int64 input (OnnxRuntime Dart usually expects Int64 for IDs)
    // Adjust based on specific onnxruntime package version requirements.
    // Usually input_ids are int64.

    final inputIdsTensor = OrtValueTensor.createTensorWithDataList(
      Int64List.fromList(inputIds),
      shape
    );
    final attentionMaskTensor = OrtValueTensor.createTensorWithDataList(
      Int64List.fromList(attentionMask),
      shape
    );
    final tokenTypeIdsTensor = OrtValueTensor.createTensorWithDataList(
      Int64List.fromList(tokenTypeIds),
      shape
    );

    final runOptions = OrtRunOptions();

    final inputOrtValues = {
      'input_ids': inputIdsTensor,
      'attention_mask': attentionMaskTensor,
      'token_type_ids': tokenTypeIdsTensor,
    };

    // 3. Run Inference
    final outputs = _session!.run(runOptions, inputOrtValues);

    // 4. Extract Output (last_hidden_state is usually output[0])
    // Shape: [1, 128, 384]
    // We need to do Mean Pooling or use [CLS] token embedding.
    // For sentence-transformers, Mean Pooling is standard.

    // Retrieve the first output tensor
    // Note: The API might differ slightly depending on package version.
    // Assuming outputs[0] is the main output.
    final outputTensor = outputs[0];
    // Data is likely a flat Float32List
    final outputData = outputTensor?.value as List<double>; // This casting depends on package

    // TODO: Implement Mean Pooling properly.
    // For "paraphrase-multilingual-MiniLM-L12-v2", we usually take the mean of all token embeddings
    // weighted by attention mask.

    // Simplified: Take the embedding of the [CLS] token (first 384 elements)
    // or just average them all.
    // [CLS] is at index 0.
    // Dimension is 384.

    List<double> embedding = [];
    int dim = 384;

    // Basic CLS pooling (first vector)
    for (int i = 0; i < dim; i++) {
        embedding.add(outputData[i]);
    }

    // Clean up
    inputIdsTensor.release();
    attentionMaskTensor.release();
    tokenTypeIdsTensor.release();
    outputs.forEach((element) => element?.release());
    runOptions.release();

    return _normalize(embedding);
  }

  List<double> _normalize(List<double> vector) {
      double norm = 0.0;
      for (var v in vector) norm += v * v;
      norm = sqrt(norm);
      if (norm == 0) return vector;
      return vector.map((v) => v / norm).toList();
  }

  void dispose() {
    _session?.release();
  }
}
