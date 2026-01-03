/// 端侧 AI 服务模块
/// 
/// 提供 ONNX Runtime + ObjectBox 方案的本地 AI 功能实现
/// 
/// 核心服务:
/// - [ONNXInferenceService] - ONNX 模型推理引擎
/// - [TokenizerService] - WordPiece 分词服务
/// - [EmbeddingService] - 文本嵌入向量生成
/// - [VectorSearchService] - ObjectBox 向量搜索
/// - [ASRService] - 语音转文字 (sherpa_onnx)
/// - [OCRService] - 图片文字识别 (Google ML Kit)

library local_ai;

export 'onnx_inference_service.dart';
export 'tokenizer_service.dart';
export 'embedding_service.dart';
export 'vector_search_service.dart';
export 'asr_service.dart';
export 'ocr_service.dart';
