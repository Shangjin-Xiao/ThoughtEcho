/// Local AI Services
/// 
/// Provides on-device AI capabilities using user-imported models:
/// - Embedding: TFLite models for semantic search
/// - ASR: Whisper ONNX models for speech-to-text
/// - OCR: Tesseract/PaddleOCR for text recognition
/// - Vector Storage: SQLite-based similarity search
library local_ai;

export 'local_embedding_service.dart';
export 'local_speech_recognition_service.dart';
export 'local_ocr_service.dart';
export 'local_vector_storage_service.dart';
export 'local_ai_model_manager.dart';
