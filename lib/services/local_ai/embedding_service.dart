import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:onnxruntime/onnxruntime.dart';
import '../../utils/app_logger.dart';
import 'onnx_inference_service.dart';
import 'tokenizer_service.dart';

/// 嵌入模型配置
class EmbeddingModelConfig {
  /// 模型 ID
  final String modelId;
  
  /// 模型路径或 URL
  final String modelPath;
  
  /// 词汇表路径
  final String vocabPath;
  
  /// 嵌入维度
  final int dimension;
  
  /// 最大序列长度
  final int maxLength;
  
  /// 是否为 asset 资源
  final bool isAsset;

  const EmbeddingModelConfig({
    required this.modelId,
    required this.modelPath,
    required this.vocabPath,
    required this.dimension,
    this.maxLength = 512,
    this.isAsset = false,
  });
}

/// 预设嵌入模型配置
class EmbeddingModels {
  /// paraphrase-multilingual-MiniLM-L12-v2 (推荐)
  /// 支持 50+ 语言，量化后 ~118MB, 384 维
  static const multilingualMiniLM = EmbeddingModelConfig(
    modelId: 'paraphrase-multilingual-MiniLM-L12-v2',
    modelPath: 'assets/models/paraphrase-multilingual-MiniLM-L12-v2.onnx',
    vocabPath: 'assets/models/vocab.txt',
    dimension: 384,
    maxLength: 512,
    isAsset: true,
  );

  /// text2vec-base-multilingual (中文优化备选)
  /// ~110MB, 768 维
  static const text2vecMultilingual = EmbeddingModelConfig(
    modelId: 'text2vec-base-multilingual',
    modelPath: 'assets/models/text2vec-base-multilingual.onnx',
    vocabPath: 'assets/models/vocab_text2vec.txt',
    dimension: 768,
    maxLength: 512,
    isAsset: true,
  );
}

/// 嵌入向量结果
class EmbeddingResult {
  /// 嵌入向量
  final List<double> embedding;
  
  /// 原始文本
  final String text;
  
  /// 处理时间 (毫秒)
  final int processingTimeMs;

  const EmbeddingResult({
    required this.embedding,
    required this.text,
    required this.processingTimeMs,
  });

  /// 计算与另一个嵌入的余弦相似度
  double cosineSimilarity(EmbeddingResult other) {
    return _cosineSimilarity(embedding, other.embedding);
  }

  /// 计算两个向量的余弦相似度
  static double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) {
      throw ArgumentError('向量维度不匹配: ${a.length} vs ${b.length}');
    }

    var dotProduct = 0.0;
    var normA = 0.0;
    var normB = 0.0;

    for (var i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }

    final denominator = math.sqrt(normA) * math.sqrt(normB);
    if (denominator == 0) return 0.0;
    
    return dotProduct / denominator;
  }
}

/// 嵌入服务
/// 
/// 使用 ONNX 模型生成文本嵌入向量，支持多语言
class EmbeddingService extends ChangeNotifier {
  static final EmbeddingService _instance = EmbeddingService._internal();
  factory EmbeddingService() => _instance;
  EmbeddingService._internal();

  final ONNXInferenceService _onnxService = ONNXInferenceService();
  final TokenizerService _tokenizer = TokenizerService();

  /// 当前加载的模型配置
  EmbeddingModelConfig? _currentConfig;
  EmbeddingModelConfig? get currentConfig => _currentConfig;

  /// 是否已就绪
  bool get isReady => 
      _currentConfig != null && 
      _onnxService.isModelLoaded(_currentConfig!.modelId) &&
      _tokenizer.isLoaded;

  /// 初始化嵌入服务
  /// 
  /// [config] 嵌入模型配置
  Future<void> initialize([
    EmbeddingModelConfig config = EmbeddingModels.multilingualMiniLM,
  ]) async {
    if (isReady && _currentConfig?.modelId == config.modelId) {
      logDebug('嵌入服务已初始化，跳过', source: 'EmbeddingService');
      return;
    }

    try {
      // 1. 加载词汇表
      logInfo('正在加载词汇表: ${config.vocabPath}', source: 'EmbeddingService');
      await _tokenizer.loadVocab(config.vocabPath, isAsset: config.isAsset);

      // 2. 加载 ONNX 模型
      logInfo('正在加载嵌入模型: ${config.modelId}', source: 'EmbeddingService');
      await _onnxService.loadModel(
        config.modelId,
        config.modelPath,
        isAsset: config.isAsset,
      );

      _currentConfig = config;
      logInfo(
        '嵌入服务初始化成功, 模型: ${config.modelId}, 维度: ${config.dimension}',
        source: 'EmbeddingService',
      );
      notifyListeners();
    } catch (e, stackTrace) {
      logError(
        '嵌入服务初始化失败: $e',
        error: e,
        stackTrace: stackTrace,
        source: 'EmbeddingService',
      );
      rethrow;
    }
  }

  /// 从 URL 下载并初始化模型
  Future<void> initializeFromUrl(
    String modelUrl,
    String vocabUrl,
    EmbeddingModelConfig config, {
    void Function(double progress)? onProgress,
  }) async {
    try {
      // 1. 下载并加载词汇表
      // TODO: 实现词汇表下载
      
      // 2. 下载并加载模型
      await _onnxService.loadModelFromUrl(
        config.modelId,
        modelUrl,
        onProgress: onProgress,
      );

      _currentConfig = config;
      notifyListeners();
    } catch (e, stackTrace) {
      logError(
        '从 URL 初始化嵌入服务失败: $e',
        error: e,
        stackTrace: stackTrace,
        source: 'EmbeddingService',
      );
      rethrow;
    }
  }

  /// 生成单个文本的嵌入向量
  Future<EmbeddingResult> embed(String text) async {
    if (!isReady) {
      throw StateError('嵌入服务未初始化，请先调用 initialize');
    }

    final stopwatch = Stopwatch()..start();
    
    try {
      // 1. 分词
      final tokenized = _tokenizer.encode(
        text,
        maxLength: _currentConfig!.maxLength,
        addSpecialTokens: true,
        padding: true,
        truncation: true,
      );

      // 2. 准备输入张量
      final inputIds = Int64List.fromList(tokenized.inputIds);
      final attentionMask = Int64List.fromList(tokenized.attentionMask);
      final tokenTypeIds = Int64List.fromList(tokenized.tokenTypeIds);

      final inputs = <String, OrtValue>{
        'input_ids': OrtValueTensor.createTensorWithDataList(
          inputIds,
          [1, tokenized.length],
        ),
        'attention_mask': OrtValueTensor.createTensorWithDataList(
          attentionMask,
          [1, tokenized.length],
        ),
        'token_type_ids': OrtValueTensor.createTensorWithDataList(
          tokenTypeIds,
          [1, tokenized.length],
        ),
      };

      // 3. 运行推理
      final outputs = await _onnxService.runInference(
        _currentConfig!.modelId,
        inputs,
      );

      // 4. 提取嵌入向量 (通常是第一个输出的 [CLS] token)
      final embedding = _extractEmbedding(outputs, tokenized.attentionMask);

      // 5. 释放输入资源
      for (final value in inputs.values) {
        value.release();
      }

      stopwatch.stop();

      return EmbeddingResult(
        embedding: embedding,
        text: text,
        processingTimeMs: stopwatch.elapsedMilliseconds,
      );
    } catch (e, stackTrace) {
      stopwatch.stop();
      logError(
        '生成嵌入向量失败: $e',
        error: e,
        stackTrace: stackTrace,
        source: 'EmbeddingService',
      );
      rethrow;
    }
  }

  /// 批量生成嵌入向量
  Future<List<EmbeddingResult>> embedBatch(List<String> texts) async {
    final results = <EmbeddingResult>[];
    
    for (final text in texts) {
      results.add(await embed(text));
    }
    
    return results;
  }

  /// 计算两个文本的相似度
  Future<double> similarity(String text1, String text2) async {
    final embedding1 = await embed(text1);
    final embedding2 = await embed(text2);
    return embedding1.cosineSimilarity(embedding2);
  }

  /// 在文本列表中搜索最相似的项
  Future<List<(String, double)>> search(
    String query,
    List<String> candidates, {
    int topK = 10,
    double threshold = 0.0,
  }) async {
    final queryEmbedding = await embed(query);
    final results = <(String, double)>[];

    for (final candidate in candidates) {
      final candidateEmbedding = await embed(candidate);
      final score = queryEmbedding.cosineSimilarity(candidateEmbedding);
      
      if (score >= threshold) {
        results.add((candidate, score));
      }
    }

    // 按相似度降序排序
    results.sort((a, b) => b.$2.compareTo(a.$2));

    // 返回 top-K
    return results.take(topK).toList();
  }

  /// 提取嵌入向量
  /// 
  /// 使用 mean pooling: 对所有非 padding token 的表示取平均
  List<double> _extractEmbedding(
    Map<String, OrtValue> outputs,
    List<int> attentionMask,
  ) {
    // 获取模型输出 (通常名为 'last_hidden_state' 或类似)
    final outputValue = outputs.values.first;
    final outputData = outputValue.value as List<List<List<double>>>;
    
    final seqLength = outputData[0].length;
    final hiddenSize = outputData[0][0].length;

    // Mean pooling with attention mask
    final embedding = List<double>.filled(hiddenSize, 0.0);
    var count = 0;

    for (var i = 0; i < seqLength; i++) {
      if (i < attentionMask.length && attentionMask[i] == 1) {
        for (var j = 0; j < hiddenSize; j++) {
          embedding[j] += outputData[0][i][j];
        }
        count++;
      }
    }

    // 计算平均值
    if (count > 0) {
      for (var j = 0; j < hiddenSize; j++) {
        embedding[j] /= count;
      }
    }

    // L2 归一化
    return _l2Normalize(embedding);
  }

  /// L2 归一化
  List<double> _l2Normalize(List<double> vector) {
    var norm = 0.0;
    for (final v in vector) {
      norm += v * v;
    }
    norm = math.sqrt(norm);

    if (norm == 0) return vector;

    return vector.map((v) => v / norm).toList();
  }

  /// 释放资源
  void dispose() {
    if (_currentConfig != null) {
      _onnxService.unloadModel(_currentConfig!.modelId);
    }
    _tokenizer.clear();
    _currentConfig = null;
    notifyListeners();
  }
}
