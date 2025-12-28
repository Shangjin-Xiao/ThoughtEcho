import 'dart:io';
import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';
import 'package:thoughtecho/services/model_manager.dart';
import 'package:thoughtecho/services/unified_log_service.dart';

class OCRService {
  static final OCRService _instance = OCRService._internal();
  static OCRService get instance => _instance;

  OCRService._internal();

  /// Perform OCR on an image file.
  ///
  /// [imagePath] path to the image file.
  /// Returns the recognized text.
  Future<String> recognizeFromFile(String imagePath) async {
    try {
      // Check if models are available (optional, Tesseract might use system tessdata if not specified)
      // But we managed downloads in ModelManager.
      // flutter_tesseract_ocr allows specifying tessdata path or language args.
      // Usually it manages its own tessdata in assets or specific folder.
      // However, for custom downloaded models, we might need to configure it.

      // flutter_tesseract_ocr API: extractText(imagePath, language: 'eng', args: {...})
      // It doesn't explicitly support custom tessdata path easily in all versions,
      // often relies on standard locations.
      // BUT, if we can't control the path, we rely on the plugin's default behavior
      // or we copy our downloaded models to where the plugin expects them (if possible).

      // Plan A requirement: use downloaded models.
      // Pass the directory containing the traineddata files.
      // FlutterTesseractOcr.extractText supports 'args' which includes config variables,
      // but the data path is usually a positional arg or managed internally.
      // However, looking at the plugin signature: extractText(imagePath, language: 'eng', args: {})
      // Some forks/versions support 'datapath' in args or map.
      // If not supported, we must rely on default or copied assets.
      // But assuming the plugin exposes the standard Tesseract API capability to set datapath via map if implemented.

      final languages = 'chi_sim+eng';

      // Get parent directory of tesseract models (where tessdata folder should be or directly traineddata)
      // Tesseract expects /path/to/tessdata/eng.traineddata
      // ModelManager stores them in /models/tesseractEng/eng.traineddata
      // We need to consolidate them or point to a common root.
      // Currently ModelManager separates them.
      // Fix: We should ideally copy them to a 'tessdata' folder.

      // Let's create a temp tessdata dir
      final dir = Directory((await ModelManager.instance.getModelDir(AppModelType.tesseractEng)).replaceAll('tesseractEng', 'tessdata'));
      if (!dir.exists()) dir.createSync(recursive: true);

      // Symlink or copy required models
      final chiPath = await ModelManager.instance.getModelPath(AppModelType.tesseractChi);
      final engPath = await ModelManager.instance.getModelPath(AppModelType.tesseractEng);

      final chiLink = File('${dir.path}/chi_sim.traineddata');
      final engLink = File('${dir.path}/eng.traineddata');

      if (chiLink.existsSync() == false && File(chiPath).existsSync()) {
        File(chiPath).copySync(chiLink.path);
      }
      if (engLink.existsSync() == false && File(engPath).existsSync()) {
        File(engPath).copySync(engLink.path);
      }

      final text = await FlutterTesseractOcr.extractText(
        imagePath,
        language: languages,
        args: {
          "psm": "4",
          "preserve_interword_spaces": "1",
          "tessdata-dir": dir.parent.path, // Tesseract often takes the parent of tessdata or tessdata itself depending on wrapper
        }
      );

      return text;
    } catch (e) {
      UnifiedLogService.instance.log(
        UnifiedLogLevel.error,
        'OCR failed: $e',
        source: 'OCRService',
        error: e,
      );
      return '';
    }
  }

  /// Recognize text with regions (simulated or if supported).
  ///
  /// flutter_tesseract_ocr mostly returns string.
  /// We might need to parse HOCR if we want regions, but standard extractText returns raw text.
  /// For this task, we'll return the full text wrapped or basic blocks if we parse.
  Future<List<String>> recognizeLines(String imagePath) async {
     try {
      final text = await recognizeFromFile(imagePath);
      return text.split('\n').where((line) => line.trim().isNotEmpty).toList();
    } catch (e) {
      return [];
    }
  }
}
