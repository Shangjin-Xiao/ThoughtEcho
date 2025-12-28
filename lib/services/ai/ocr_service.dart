import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class OcrService {
  final _textRecognizer = TextRecognizer(script: TextRecognitionScript.chinese);

  Future<String> recognizeText(String imagePath) async {
    final inputImage = InputImage.fromFilePath(imagePath);
    try {
      final recognizedText = await _textRecognizer.processImage(inputImage);
      return recognizedText.text;
    } catch (e) {
      print("OCR Error: $e");
      rethrow;
    }
  }

  void dispose() {
    _textRecognizer.close();
  }
}
