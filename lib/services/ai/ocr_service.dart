import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Service for Optical Character Recognition (OCR) using Google ML Kit.
class OCRService {
  final TextRecognizer _textRecognizer = TextRecognizer(script: TextRecognitionScript.chinese);

  /// Recognizes text from an image file.
  Future<String> recognizeText(String imagePath) async {
    final inputImage = InputImage.fromFilePath(imagePath);
    final RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);
    return recognizedText.text;
  }

  /// Closes the text recognizer to release resources.
  Future<void> close() async {
    await _textRecognizer.close();
  }
}
