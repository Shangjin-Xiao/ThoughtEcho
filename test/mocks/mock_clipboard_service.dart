/// Mock ClipboardService for testing
import 'package:flutter/foundation.dart';
import 'dart:async';

class MockClipboardService extends ChangeNotifier {
  bool _enableClipboardMonitoring = false;
  String _lastProcessedContent = '';
  String? _currentClipboardContent;
  bool _isInitialized = false;
  bool _isMonitoring = false;
  String? _lastError;

  final StreamController<String> _clipboardController = StreamController<String>.broadcast();

  // Getters
  bool get enableClipboardMonitoring => _enableClipboardMonitoring;
  String get lastProcessedContent => _lastProcessedContent;
  String? get currentClipboardContent => _currentClipboardContent;
  bool get isInitialized => _isInitialized;
  bool get isMonitoring => _isMonitoring;
  String? get lastError => _lastError;
  Stream<String> get clipboardStream => _clipboardController.stream;

  /// Initialize mock clipboard service
  Future<void> init() async {
    await Future.delayed(const Duration(milliseconds: 100));
    _isInitialized = true;
    notifyListeners();
  }

  /// Enable clipboard monitoring
  Future<void> enableMonitoring() async {
    await Future.delayed(const Duration(milliseconds: 50));
    _enableClipboardMonitoring = true;
    _isMonitoring = true;
    notifyListeners();
  }

  /// Disable clipboard monitoring
  Future<void> disableMonitoring() async {
    await Future.delayed(const Duration(milliseconds: 50));
    _enableClipboardMonitoring = false;
    _isMonitoring = false;
    notifyListeners();
  }

  /// Set clipboard monitoring preference
  Future<void> setClipboardMonitoring(bool enabled) async {
    await Future.delayed(const Duration(milliseconds: 30));
    _enableClipboardMonitoring = enabled;
    if (enabled) {
      _isMonitoring = true;
    } else {
      _isMonitoring = false;
    }
    notifyListeners();
  }

  /// Simulate clipboard content change
  void simulateClipboardContent(String content) {
    _currentClipboardContent = content;
    if (_isMonitoring && content != _lastProcessedContent) {
      _lastProcessedContent = content;
      _clipboardController.add(content);
      notifyListeners();
    }
  }

  /// Get current clipboard content
  Future<String?> getCurrentClipboardContent() async {
    await Future.delayed(const Duration(milliseconds: 30));
    return _currentClipboardContent;
  }

  /// Process clipboard content
  Future<Map<String, String?>> processClipboardContent(String content) async {
    await Future.delayed(const Duration(milliseconds: 100));
    
    if (content.trim().isEmpty) {
      return {
        'content': content,
        'source': null,
        'author': null,
        'work': null,
      };
    }

    // Mock content processing
    String? source;
    String? author;
    String? work;

    // Simulate quote detection
    if (content.contains('——') || content.contains('—')) {
      final parts = content.split(RegExp(r'[———]'));
      if (parts.length >= 2) {
        author = parts.last.trim();
        content = parts.first.trim();
      }
    }

    // Simulate source detection
    if (content.contains('《') && content.contains('》')) {
      final match = RegExp(r'《(.+?)》').firstMatch(content);
      if (match != null) {
        work = match.group(1);
      }
    }

    // Simulate source format detection
    if (content.contains('摘自') || content.contains('选自') || content.contains('出自')) {
      final match = RegExp(r'[摘选出]自[《]?(.+?)[》]?$').firstMatch(content);
      if (match != null) {
        source = match.group(1);
      }
    }

    return {
      'content': content.trim(),
      'source': source,
      'author': author,
      'work': work,
    };
  }

  /// Check if content looks like a quote
  bool isQuoteLikeContent(String content) {
    if (content.trim().isEmpty) return false;
    
    // Mock quote detection logic
    return content.contains('——') ||
           content.contains('—') ||
           content.contains('《') ||
           content.contains('摘自') ||
           content.contains('选自') ||
           content.contains('出自') ||
           (content.length > 10 && content.length < 500);
  }

  /// Extract quote information
  Map<String, String?> extractQuoteInfo(String content) {
    final processed = processClipboardContent(content);
    return {
      'content': processed['content'] ?? content,
      'source': processed['source'],
      'author': processed['author'],
      'work': processed['work'],
    };
  }

  /// Get content type
  String getContentType(String content) {
    if (content.isEmpty) return 'empty';
    if (content.length < 10) return 'short';
    if (content.length > 500) return 'long';
    if (isQuoteLikeContent(content)) return 'quote';
    return 'text';
  }

  /// Simulate error
  void simulateError(String error) {
    _lastError = error;
    notifyListeners();
  }

  /// Clear error
  void clearError() {
    _lastError = null;
    notifyListeners();
  }

  /// Clear clipboard history
  void clearHistory() {
    _lastProcessedContent = '';
    _currentClipboardContent = null;
    notifyListeners();
  }

  /// Get processing statistics
  Map<String, dynamic> getProcessingStats() {
    return {
      'monitoring_enabled': _enableClipboardMonitoring,
      'is_monitoring': _isMonitoring,
      'last_processed_length': _lastProcessedContent.length,
      'has_current_content': _currentClipboardContent != null,
      'initialized': _isInitialized,
    };
  }

  /// Start monitoring (convenience method)
  Future<void> startMonitoring() async {
    if (!_isInitialized) {
      await init();
    }
    await enableMonitoring();
  }

  /// Stop monitoring (convenience method)
  Future<void> stopMonitoring() async {
    await disableMonitoring();
  }

  /// Test clipboard content processing
  void testProcessing() {
    final testContents = [
      '生活不止眼前的苟且，还有诗和远方。——许巍',
      '在最深的绝望里，遇见最美丽的惊喜。摘自《偷影子的人》',
      '《百年孤独》——马尔克斯',
      '简单的文本内容',
      '',
    ];

    for (final content in testContents) {
      simulateClipboardContent(content);
    }
  }

  @override
  void dispose() {
    _clipboardController.close();
    super.dispose();
  }
}