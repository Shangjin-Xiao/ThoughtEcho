/// 嵌入服务
///
/// 使用 flutter_gemma Gecko 模型生成文本嵌入向量

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/embedding_result.dart';
import '../../utils/app_logger.dart';
import 'model_manager.dart';

/// 嵌入服务
class EmbeddingService extends ChangeNotifier {
  static EmbeddingService? _instance;

  /// 单例实例
  static EmbeddingService get instance {
    _instance ??= EmbeddingService._();
    return _instance!;
  }

  EmbeddingService._();

  /// 模型管理器
  final ModelManager _modelManager = ModelManager.instance;

  /// 是否已初始化
  bool _initialized = false;

  /// 模型是否已加载
  bool _modelLoaded = false;

  /// 嵌入维度
  static const int embeddingDimension = 384;

  /// 是否已初始化
  bool get isInitialized => _initialized;

  /// 模型是否已加载
  bool get isModelLoaded => _modelLoaded;

  /// 检查嵌入模型是否可用
  bool get isModelAvailable {
    return _modelManager.isModelDownloaded('gecko-384');
  }

  /// 初始化服务
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      // 确保模型管理器已初始化
      if (!_modelManager.isInitialized) {
        await _modelManager.initialize();
      }

      // 检查是否有可用的嵌入模型
      if (!isModelAvailable) {
        logInfo('嵌入模型未下载，语义搜索功能暂不可用', source: 'EmbeddingService');
      }

      _initialized = true;
      logInfo('嵌入服务初始化完成', source: 'EmbeddingService');
    } catch (e) {
      logError('嵌入服务初始化失败: $e', source: 'EmbeddingService');
      rethrow;
    }
  }

  /// 加载模型
  Future<void> loadModel() async {
    if (!_initialized) {
      throw Exception('service_not_initialized');
    }

    if (_modelLoaded) {
      logDebug('模型已加载', source: 'EmbeddingService');
      return;
    }

    if (!isModelAvailable) {
      throw Exception('embedding_model_required');
    }

    try {
      // TODO: 集成 flutter_gemma 加载 Gecko 模型
      logInfo('加载嵌入模型（占位实现）', source: 'EmbeddingService');

      // 模拟加载过程
      await Future.delayed(const Duration(seconds: 1));

      _modelLoaded = true;
      notifyListeners();

      logInfo('嵌入模型加载完成', source: 'EmbeddingService');
    } catch (e) {
      logError('加载嵌入模型失败: $e', source: 'EmbeddingService');
      rethrow;
    }
  }

  /// 卸载模型
  Future<void> unloadModel() async {
    if (!_modelLoaded) return;

    try {
      // TODO: 卸载 Gecko 模型释放内存
      _modelLoaded = false;
      notifyListeners();

      logInfo('嵌入模型已卸载', source: 'EmbeddingService');
    } catch (e) {
      logError('卸载嵌入模型失败: $e', source: 'EmbeddingService');
    }
  }

  /// 生成文本嵌入向量
  Future<Embedding> generateEmbedding(String text) async {
    if (!_initialized) {
      throw Exception('service_not_initialized');
    }

    if (!isModelAvailable) {
      throw Exception('embedding_model_required');
    }

    try {
      // TODO: 集成 flutter_gemma 生成嵌入向量
      logDebug('生成嵌入向量（占位实现）: ${text.substring(0, text.length.clamp(0, 50))}...', source: 'EmbeddingService');

      // 模拟生成嵌入
      await Future.delayed(const Duration(milliseconds: 100));

      // 返回占位的零向量
      final vector = List<double>.filled(embeddingDimension, 0.0);

      return Embedding(
        vector: vector,
        sourceText: text,
        createdAt: DateTime.now(),
      );
    } catch (e) {
      logError('生成嵌入向量失败: $e', source: 'EmbeddingService');
      rethrow;
    }
  }

  /// 批量生成嵌入向量
  Future<List<Embedding>> generateEmbeddings(List<String> texts) async {
    if (!_initialized) {
      throw Exception('service_not_initialized');
    }

    final results = <Embedding>[];

    for (final text in texts) {
      final embedding = await generateEmbedding(text);
      results.add(embedding);
    }

    return results;
  }

  /// 计算两段文本的相似度
  Future<double> computeSimilarity(String text1, String text2) async {
    final embedding1 = await generateEmbedding(text1);
    final embedding2 = await generateEmbedding(text2);

    return embedding1.cosineSimilarity(embedding2);
  }

  @override
  void dispose() {
    unloadModel();
    super.dispose();
  }
}
