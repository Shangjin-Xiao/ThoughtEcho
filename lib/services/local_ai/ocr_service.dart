import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../../utils/app_logger.dart';

/// OCR 识别结果
class OCRResult {
  /// 识别的完整文本
  final String text;
  
  /// 文本块列表
  final List<OCRTextBlock> blocks;
  
  /// 处理时间 (毫秒)
  final int processingTimeMs;
  
  /// 检测到的语言 (如果可用)
  final String? detectedLanguage;
  
  /// 置信度 (0-1, 如果可用)
  final double? confidence;

  const OCRResult({
    required this.text,
    required this.blocks,
    this.processingTimeMs = 0,
    this.detectedLanguage,
    this.confidence,
  });

  /// 检查是否有内容
  bool get isEmpty => text.trim().isEmpty;
  bool get isNotEmpty => !isEmpty;

  /// 获取所有行
  List<String> get lines => blocks.expand((b) => b.lines).toList();

  @override
  String toString() => 'OCRResult(text: "${text.substring(0, text.length.clamp(0, 50))}...")';
}

/// OCR 文本块
class OCRTextBlock {
  /// 文本内容
  final String text;
  
  /// 行列表
  final List<String> lines;
  
  /// 边界框 (如果可用)
  final Rect? boundingBox;
  
  /// 置信度 (0-1)
  final double? confidence;

  const OCRTextBlock({
    required this.text,
    required this.lines,
    this.boundingBox,
    this.confidence,
  });
}

/// 引文信息提取结果
class QuoteInfo {
  /// 引文内容
  final String? content;
  
  /// 作者
  final String? author;
  
  /// 出处/来源
  final String? source;

  const QuoteInfo({
    this.content,
    this.author,
    this.source,
  });

  /// 检查是否提取到任何信息
  bool get hasAnyInfo => content != null || author != null || source != null;

  /// 转换为 Map
  Map<String, String?> toMap() => {
    'content': content,
    'author': author,
    'source': source,
  };

  @override
  String toString() => 'QuoteInfo(author: $author, source: $source)';
}

/// OCR 识别语言脚本
enum OCRScript {
  /// 拉丁字母 (英语、法语等)
  latin,
  
  /// 中文
  chinese,
  
  /// 日语
  japanese,
  
  /// 韩语
  korean,
  
  /// 梵文 (印度语系)
  devanagari,
}

/// OCR 服务
/// 
/// 使用 Google ML Kit 进行文字识别
class OCRService extends ChangeNotifier {
  static final OCRService _instance = OCRService._internal();
  factory OCRService() => _instance;
  OCRService._internal();

  /// 文字识别器缓存
  final Map<OCRScript, TextRecognizer> _recognizers = {};

  /// 默认脚本
  OCRScript _defaultScript = OCRScript.chinese;
  OCRScript get defaultScript => _defaultScript;

  /// 是否已初始化
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  /// 初始化 OCR 服务
  Future<void> initialize({OCRScript defaultScript = OCRScript.chinese}) async {
    if (_isInitialized) return;

    _defaultScript = defaultScript;
    
    // 预加载默认识别器
    _getRecognizer(defaultScript);
    
    _isInitialized = true;
    logInfo('OCR 服务初始化成功', source: 'OCRService');
    notifyListeners();
  }

  /// 获取或创建文字识别器
  TextRecognizer _getRecognizer(OCRScript script) {
    if (_recognizers.containsKey(script)) {
      return _recognizers[script]!;
    }

    final TextRecognizerScript mlScript;
    switch (script) {
      case OCRScript.latin:
        mlScript = TextRecognizerScript.latin;
        break;
      case OCRScript.chinese:
        mlScript = TextRecognizerScript.chinese;
        break;
      case OCRScript.japanese:
        mlScript = TextRecognizerScript.japanese;
        break;
      case OCRScript.korean:
        mlScript = TextRecognizerScript.korean;
        break;
      case OCRScript.devanagari:
        mlScript = TextRecognizerScript.devanagari;
        break;
    }

    final recognizer = TextRecognizer(script: mlScript);
    _recognizers[script] = recognizer;
    
    logDebug('创建 OCR 识别器: $script', source: 'OCRService');
    return recognizer;
  }

  /// 从图片文件识别文字
  /// 
  /// [imagePath] 图片文件路径
  /// [script] OCR 脚本类型，默认使用中文
  Future<OCRResult> recognizeFromFile(
    String imagePath, {
    OCRScript? script,
  }) async {
    final file = File(imagePath);
    if (!await file.exists()) {
      throw FileSystemException('图片文件不存在', imagePath);
    }

    final inputImage = InputImage.fromFilePath(imagePath);
    return recognizeFromInputImage(inputImage, script: script);
  }

  /// 从字节数据识别文字
  Future<OCRResult> recognizeFromBytes(
    Uint8List bytes, {
    required int width,
    required int height,
    required InputImageFormat format,
    int rotation = 0,
    OCRScript? script,
  }) async {
    final inputImageMetadata = InputImageMetadata(
      size: Size(width.toDouble(), height.toDouble()),
      rotation: InputImageRotation.values.firstWhere(
        (r) => r.rawValue == rotation,
        orElse: () => InputImageRotation.rotation0deg,
      ),
      format: format,
      bytesPerRow: width,
    );

    final inputImage = InputImage.fromBytes(
      bytes: bytes,
      metadata: inputImageMetadata,
    );

    return recognizeFromInputImage(inputImage, script: script);
  }

  /// 从 InputImage 识别文字
  Future<OCRResult> recognizeFromInputImage(
    InputImage inputImage, {
    OCRScript? script,
  }) async {
    final targetScript = script ?? _defaultScript;
    final recognizer = _getRecognizer(targetScript);

    final stopwatch = Stopwatch()..start();

    try {
      final recognizedText = await recognizer.processImage(inputImage);
      stopwatch.stop();

      // 转换为 OCRResult
      final blocks = <OCRTextBlock>[];
      for (final block in recognizedText.blocks) {
        final lines = block.lines.map((l) => l.text).toList();
        blocks.add(OCRTextBlock(
          text: block.text,
          lines: lines,
          boundingBox: block.boundingBox,
        ));
      }

      final result = OCRResult(
        text: recognizedText.text,
        blocks: blocks,
        processingTimeMs: stopwatch.elapsedMilliseconds,
      );

      logDebug(
        'OCR 识别完成: ${result.text.length} 字符, ${stopwatch.elapsedMilliseconds}ms',
        source: 'OCRService',
      );

      return result;
    } catch (e, stackTrace) {
      stopwatch.stop();
      logError(
        'OCR 识别失败: $e',
        error: e,
        stackTrace: stackTrace,
        source: 'OCRService',
      );
      rethrow;
    }
  }

  /// 多脚本自动识别
  /// 
  /// 尝试使用多种脚本进行识别，返回结果最好的
  Future<OCRResult> recognizeMultiScript(
    String imagePath, {
    List<OCRScript> scripts = const [OCRScript.chinese, OCRScript.latin],
  }) async {
    OCRResult? bestResult;
    
    for (final script in scripts) {
      try {
        final result = await recognizeFromFile(imagePath, script: script);
        
        // 简单策略：选择文本最长的结果
        if (bestResult == null || result.text.length > bestResult.text.length) {
          bestResult = result;
        }
      } catch (e) {
        logWarning(
          '脚本 $script 识别失败: $e',
          source: 'OCRService',
        );
      }
    }

    return bestResult ?? const OCRResult(text: '', blocks: []);
  }

  /// 后处理识别文本
  /// 
  /// 清理和格式化 OCR 输出
  String postProcessText(String text) {
    return text
        // 合并多余的空白
        .replaceAll(RegExp(r'\s+'), ' ')
        // 移除无意义的单字符行
        .split('\n')
        .where((line) => line.trim().length > 1)
        .join('\n')
        .trim();
  }

  /// 智能提取引文信息
  /// 
  /// 尝试从 OCR 文本中提取作者、作品等信息
  /// 返回结构化的 [QuoteInfo] 对象
  QuoteInfo extractQuoteInfo(String text) {
    String? author;
    String? source;

    // 尝试提取作者 (常见格式: "—— 作者名" 或 "-- 作者名")
    final authorPatterns = [
      RegExp(r'[—–-]{1,2}\s*([^\n,，。.]{2,20})\s*$'),
      RegExp(r'^\s*作者[：:]\s*(.+)$', multiLine: true),
      RegExp(r'摘自.*?[《「【]([^》」】]+)[》」】]'),
    ];

    for (final pattern in authorPatterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        author = match.group(1)?.trim();
        break;
      }
    }

    // 尝试提取出处 (书名号内容)
    final sourcePattern = RegExp(r'[《「【]([^》」】]+)[》」】]');
    final sourceMatch = sourcePattern.firstMatch(text);
    if (sourceMatch != null) {
      source = sourceMatch.group(1);
    }

    // 提取引文内容 (去除作者和出处后的主体文本)
    var content = text;
    if (author != null) {
      content = content.replaceAll(
        RegExp(r'[—–-]{1,2}\s*' + RegExp.escape(author)),
        '',
      );
    }

    return QuoteInfo(
      content: content.trim().isNotEmpty ? content.trim() : null,
      author: author,
      source: source,
    );
  }

  /// 设置默认脚本
  void setDefaultScript(OCRScript script) {
    _defaultScript = script;
    notifyListeners();
  }

  /// 释放资源
  @override
  void dispose() {
    for (final recognizer in _recognizers.values) {
      recognizer.close();
    }
    _recognizers.clear();
    _isInitialized = false;
    super.dispose();
  }
}
