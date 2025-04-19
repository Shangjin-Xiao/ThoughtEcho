// filepath: /workspaces/ThoughtEcho/lib/services/clipboard_service.dart
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import '../models/quote_model.dart';
import 'package:uuid/uuid.dart';

/// 剪贴板服务，用于监听和处理剪贴板内容
class ClipboardService extends ChangeNotifier {
  // 用于监听剪贴板的定时器
  Timer? _clipboardTimer;
  // 上一次检测到的剪贴板内容
  String _lastClipboardContent = '';
  // 是否启用剪贴板监听
  bool _isMonitoringEnabled = false;
  // 回调函数，当检测到新的有效文本时调用
  Function(String)? onNewTextDetected;

  // 获取监听状态
  bool get isMonitoringEnabled => _isMonitoringEnabled;

  // 设置监听状态并通知监听器
  set isMonitoringEnabled(bool value) {
    if (_isMonitoringEnabled == value) return;
    _isMonitoringEnabled = value;
    if (_isMonitoringEnabled) {
      _startMonitoring();
    } else {
      _stopMonitoring();
    }
    notifyListeners();
  }

  ClipboardService() {
    // 构造函数中初始化，但默认不开启监听
  }

  /// 开始监听剪贴板变化
  void _startMonitoring() {
    if (kIsWeb) {
      debugPrint('Web平台不支持剪贴板监听');
      return;
    }

    // 先检查当前剪贴板内容
    _checkClipboard();

    // 设置定时器，每2秒检查一次剪贴板
    _clipboardTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      _checkClipboard();
    });

    debugPrint('剪贴板监听已启动');
  }

  /// 停止监听剪贴板变化
  void _stopMonitoring() {
    _clipboardTimer?.cancel();
    _clipboardTimer = null;
    debugPrint('剪贴板监听已停止');
  }

  /// 检查剪贴板内容是否变化
  Future<void> _checkClipboard() async {
    try {
      // 获取当前剪贴板内容
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      final text = clipboardData?.text ?? '';

      // 如果内容有变化且不为空
      if (text.isNotEmpty && text != _lastClipboardContent) {
        debugPrint('检测到剪贴板内容变化');
        _lastClipboardContent = text;

        // 判断内容是否适合作为引用保存（排除太短的内容或URL等）
        if (_isValidQuoteContent(text)) {
          // 调用回调函数
          if (onNewTextDetected != null) {
            onNewTextDetected!(text);
          }
        }
      }
    } catch (e) {
      debugPrint('检查剪贴板内容出错: $e');
    }
  }

  /// 判断内容是否适合作为引用保存
  bool _isValidQuoteContent(String text) {
    // 过滤掉太短的内容
    if (text.length < 5) return false;

    // 过滤掉看起来像URL的内容
    if (text.startsWith('http://') ||
        text.startsWith('https://') ||
        text.startsWith('www.')) {
      return false;
    }

    // 过滤掉可能是代码的内容
    if (text.contains('{') &&
        text.contains('}') &&
        (text.contains('function') ||
            text.contains('class') ||
            text.contains('var ') ||
            text.contains('let '))) {
      return false;
    }

    return true;
  }

  /// 手动检查剪贴板内容
  Future<String?> getClipboardText() async {
    try {
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      return clipboardData?.text;
    } catch (e) {
      debugPrint('获取剪贴板内容出错: $e');
      return null;
    }
  }

  /// 将文本复制到剪贴板
  Future<bool> copyToClipboard(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      return true;
    } catch (e) {
      debugPrint('复制到剪贴板失败: $e');
      return false;
    }
  }

  /// 从剪贴板内容创建引用
  Quote? createQuoteFromClipboard(String? text) {
    if (text == null || text.isEmpty) return null;

    return Quote(
      id: const Uuid().v4(),
      content: text,
      date: DateTime.now().toIso8601String(),
      source: '',
    );
  }

  @override
  void dispose() {
    _stopMonitoring();
    super.dispose();
  }
}
