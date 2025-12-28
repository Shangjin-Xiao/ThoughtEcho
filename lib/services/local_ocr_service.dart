import 'dart:io';
import 'package:google_ml_kit_text_recognition/google_ml_kit_text_recognition.dart';

class LocalOCRService {
  bool _isInitialized = false; // Kept for API consistency, though ML Kit lazy loads
  final TextRecognizer _textRecognizer = TextRecognizer(script: TextRecognitionScript.chinese);

  bool get isInitialized => _isInitialized;

  // Parameters kept for compatibility with previous interface, but unused for ML Kit
  Future<void> initialize(String detPath, String recPath, String keysPath) async {
    // ML Kit manages its own models. We just mark as initialized.
    _isInitialized = true;
  }

  Future<String> extractText(String imagePath) async {
    if (!_isInitialized) {
       // Auto-initialize if needed or strictly enforce?
       // For compatibility, we assume initialize was called, but ML Kit works without it.
       // Let's just run.
    }

    final InputImage inputImage = InputImage.fromFilePath(imagePath);
    try {
      final RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);
      return recognizedText.text;
    } catch (e) {
      print("OCR Failed: $e");
      throw Exception("OCR Processing Failed: $e");
    }
  }

  void dispose() {
    _textRecognizer.close();
  }
}
