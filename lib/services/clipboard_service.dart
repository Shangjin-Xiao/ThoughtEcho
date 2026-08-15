import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../gen_l10n/app_localizations.dart';
import '../theme/theme_style.dart';
import '../utils/app_logger.dart';
import '../utils/mmkv_ffi_fix.dart'; // 导入安全包装类

/// 用户接受剪贴板摘录后的回调：交给页面用它自己的新增笔记入口打开编辑器，
/// 服务本身不负责建编辑器、也不负责存库。
typedef ClipboardCaptureAccepted = void Function(
  String content,
  String? author,
  String? source,
);

class ClipboardService extends ChangeNotifier {
  static const String _keyEnableClipboardMonitoring =
      'enable_clipboard_monitoring';

  // 是否启用剪贴板监控
  bool _enableClipboardMonitoring = false;
  bool get enableClipboardMonitoring => _enableClipboardMonitoring;

  // 剪贴板上次处理的内容缓存（仅内存中，不需要持久化）
  String _lastProcessedContent = '';
  static bool _skipNextClipboardCheck = false;

  @visibleForTesting
  bool get shouldSkipNextClipboardCheck => _skipNextClipboardCheck;

  // 使用安全包装类替代直接的MMKV
  SafeMMKV? _storage;

  // 构造函数
  ClipboardService();

  static void suppressNextCheckForNotificationNavigation() {
    _skipNextClipboardCheck = true;
    logDebug('通知笔记导航后跳过下一次剪贴板检查');
  }

  /// 初始化服务（需要在应用启动时显式调用）
  Future<void> init() async {
    await _initPreferences();
  }

  // 初始化首选项
  Future<void> _initPreferences() async {
    try {
      _storage = SafeMMKV();
      await _storage!.initialize();
      _loadPreferences();
      logDebug('剪贴板服务初始化完成，监控状态: $_enableClipboardMonitoring');
    } catch (e) {
      logDebug('初始化剪贴板服务首选项时出错: $e');
    }
  }

  // 从存储加载首选项
  void _loadPreferences() {
    _enableClipboardMonitoring =
        _storage?.getBool(_keyEnableClipboardMonitoring) ?? false;
    logDebug('加载剪贴板监控设置: $_enableClipboardMonitoring');
    notifyListeners();
  }

  // 设置是否启用剪贴板监控
  void setEnableClipboardMonitoring(bool value) {
    _enableClipboardMonitoring = value;
    _storage?.setBool(_keyEnableClipboardMonitoring, value);
    logDebug('剪贴板监控设置已更新: $value');
    notifyListeners();
  }

  // 检查剪贴板内容（应用启动或从后台恢复时调用）
  Future<Map<String, dynamic>?> checkClipboard() async {
    if (_skipNextClipboardCheck) {
      _skipNextClipboardCheck = false;
      logDebug('已跳过通知笔记导航后的剪贴板检查');
      return null;
    }

    if (!_enableClipboardMonitoring) {
      logDebug('剪贴板监控已禁用，跳过检查');
      return null;
    }

    try {
      // 获取剪贴板数据
      final data = await Clipboard.getData(Clipboard.kTextPlain);

      // 没有数据或数据与上次处理的相同，返回null
      if (data == null ||
          data.text == null ||
          data.text!.isEmpty ||
          data.text == _lastProcessedContent) {
        logDebug('剪贴板为空或内容未变化');
        return null;
      }

      final content = data.text!;
      if (kDebugMode) {
        logDebug(
          '检测到新的剪贴板内容: ${content.length > 20 ? '${content.substring(0, 20)}...' : content} (已脱敏)',
        );
      }

      // 内容过长或过短不处理
      if (content.length > 5000 || content.length < 5) {
        logDebug('剪贴板内容长度不适合处理: ${content.length}字符');
        return null;
      }

      // 更新最近处理的内容（仅在内存中记住，不需要持久化）
      _lastProcessedContent = content;

      // 提取作者和出处（如果有）
      final attribution = _extractAttribution(content);

      logDebug(
        '从剪贴板提取信息 - 作者: ${attribution.author}, 出处: ${attribution.source}',
      );

      return {
        'content': attribution.content,
        'author': attribution.author,
        'source': attribution.source,
      };
    } catch (e) {
      logDebug('检查剪贴板时出错: $e');
      return null;
    }
  }

  /// 归属分隔符（破折号/连字号）。
  ///
  /// 单个 ASCII `-` 只有同一行内前面带空格才算分隔符（"正文 - 作者"）。否则
  /// `2026-08-15`、`foo-bar`、`https://x.com/a-b` 这类普通文本的尾巴都会被
  /// 当成"——作者"切走，这是旧实现最常见的误判来源。
  /// 破折号 `—` `–` 和 `--` 允许跨行，署名单独占一行是常见排版。
  static const String _dash = r'(?:\s*[—–]+|\s*-{2,}|[ \t]+-)\s*';

  /// 兜底提取作者时的候选名。排除句读、书名号和 URL 里的 `:` `/`，
  /// 长度限制在 2~20，避免把整句话当成作者。
  static const String _fallbackAuthor =
      r'[^，。,、\.\n《（\(：:/\\]{2,20}';

  /// 已被书名号锚定的位置，作者名可以放宽一些。
  static const String _anchoredAuthor = r'[^，。,、\.\n]{1,30}';

  /// 书名号包裹的出处。兜底提取出处时**只认书名号**：
  /// 中英文圆括号在普通文本里太常见（"今天很开心（真的）"），
  /// 当出处切走会把正文改坏。
  static final RegExp _bookTitleSource = RegExp(r'[《〈]([^》〉]+?)[》〉]\s*$');

  // 1. 正文 ——作者《出处》
  static final RegExp _dashAuthorThenSource = RegExp(
    '$_dash' r'([^《（\(]+?)?\s*[《（\(]([^》）\)]+?)[》）\)]\s*$',
  );

  // 2. 正文《出处》——作者
  static final RegExp _sourceThenDashAuthor = RegExp(
    r'[《（\(]([^》）\)]+?)[》）\)]' '$_dash' '($_anchoredAuthor)' r'\s*$',
  );

  // 3. 兜底：正文 ——作者
  //
  // “引文”——作者 也走这条：切点是分隔符，引文整体留在正文里，
  // 不需要单独为引号写一条规则。
  static final RegExp _dashAuthorOnly = RegExp(
    '$_dash' '($_fallbackAuthor)' r'\s*$',
  );

  static final RegExp _cleanPattern = RegExp(r'^[—–\-\s]+|[—–\-\s]+$');

  /// 从文本尾部提取作者和出处（一言式署名），并返回去掉署名后的正文。
  ///
  /// 只在**尾部有明确署名标记**（破折号、书名号）时才切；宁可漏判也不误切——
  /// 切错等于悄悄改用户的笔记正文，比不提取难受得多。
  _ClipboardAttribution _extractAttribution(String content) {
    final text = content.trim();

    String? clean(String? input) {
      final cleaned = input?.trim().replaceAll(_cleanPattern, '').trim();
      return (cleaned == null || cleaned.isEmpty) ? null : cleaned;
    }

    // 署名从 matchStart 开始，前面剩下的才是正文。正文被切空说明整段都是
    // 署名（比如只复制了一个书名），这种情况保留原文、不做提取。
    _ClipboardAttribution? cut(int matchStart, String? author, String? source) {
      final body = text.substring(0, matchStart).trim();
      if (body.isEmpty) return null;
      if (author == null && source == null) return null;
      return _ClipboardAttribution(
        content: body,
        author: author,
        source: source,
      );
    }

    // 1. 正文 ——作者《出处》
    final m1 = _dashAuthorThenSource.firstMatch(text);
    if (m1 != null) {
      final result = cut(m1.start, clean(m1.group(1)), clean(m1.group(2)));
      if (result != null) return result;
    }

    // 2. 正文《出处》——作者
    final m2 = _sourceThenDashAuthor.firstMatch(text);
    if (m2 != null) {
      final result = cut(m2.start, clean(m2.group(2)), clean(m2.group(1)));
      if (result != null) return result;
    }

    // 3. 兜底：正文 ——作者（作者前面可能还有一个书名号出处）
    final m3 = _dashAuthorOnly.firstMatch(text);
    if (m3 != null && _hasInlineBody(text, m3.start)) {
      final author = clean(m3.group(1));
      final beforeAuthor = text.substring(0, m3.start);
      final sourceMatch = _bookTitleSource.firstMatch(beforeAuthor);
      if (sourceMatch != null) {
        final result = cut(
          sourceMatch.start,
          author,
          clean(sourceMatch.group(1)),
        );
        if (result != null) return result;
      }
      final result = cut(m3.start, author, null);
      if (result != null) return result;
    }

    // 4. 兜底：正文《出处》（出处前面可能还有一个 ——作者）
    final m4 = _bookTitleSource.firstMatch(text);
    if (m4 != null) {
      final source = clean(m4.group(1));
      final beforeSource = text.substring(0, m4.start);
      final authorMatch = _dashAuthorOnly.firstMatch(beforeSource);
      if (authorMatch != null &&
          _hasInlineBody(beforeSource, authorMatch.start)) {
        final result = cut(
          authorMatch.start,
          clean(authorMatch.group(1)),
          source,
        );
        if (result != null) return result;
      }
      final result = cut(m4.start, null, source);
      if (result != null) return result;
    }

    return _ClipboardAttribution(content: content);
  }

  /// 分隔符所在行前面是否还有正文。
  ///
  /// 缩进后的 markdown 列表项（`  - 香蕉`）会命中"空格 + 连字号"的分隔符规则，
  /// 但它整行都是列表项，前面只有换行和缩进——这种不是署名。
  bool _hasInlineBody(String text, int separatorStart) =>
      separatorStart > 0 && !text.substring(0, separatorStart).endsWith('\n');

  /// 弹出"发现剪贴板内容"提示；用户点提示后由 [onAccept] 打开新增笔记入口。
  ///
  /// 服务只负责提示和解析，编辑器怎么开、笔记怎么存都交回页面：页面那条路径
  /// 已经处理了标签加载、"跳过非全屏编辑器"偏好和统一的保存反馈。
  void showClipboardCapturePrompt(
    BuildContext context,
    Map<String, dynamic> clipboardData, {
    required ClipboardCaptureAccepted onAccept,
  }) {
    final content = clipboardData['content'] as String;
    final author = clipboardData['author'] as String?;
    final source = clipboardData['source'] as String?;

    OverlayEntry? backgroundEntry;
    OverlayEntry? cardEntry;
    var handled = false;

    void dismiss({bool accepted = false}) {
      if (handled) return;
      handled = true;
      if (backgroundEntry?.mounted ?? false) backgroundEntry!.remove();
      if (cardEntry?.mounted ?? false) cardEntry!.remove();
      if (accepted && context.mounted) {
        onAccept(content, author, source);
      }
    }

    // 背景层：全屏透明，监听任意触摸即关闭通知
    backgroundEntry = OverlayEntry(
      builder: (overlayContext) => Positioned.fill(
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => dismiss(),
        ),
      ),
    );

    // 通知卡片层
    cardEntry = OverlayEntry(
      builder: (overlayContext) => Positioned(
        top: MediaQuery.of(overlayContext).size.height * 0.15,
        left: 0,
        right: 0,
        child: Material(
          color: Colors.transparent,
          child: GestureDetector(
            // 点卡片本身 → 打开新增笔记
            onTap: () => dismiss(accepted: true),
            // 拦截事件冒泡，防止触发背景层（卡片范围内的事件由此处处理）
            behavior: HitTestBehavior.opaque,
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 320),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(overlayContext).colorScheme.surface,
                  borderRadius: BorderRadius.circular(
                      AppShapeTokens.of(overlayContext).dialogRadius),
                  boxShadow: AppShapeTokens.of(overlayContext).restShadow,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.content_paste,
                      color: Theme.of(overlayContext).colorScheme.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        AppLocalizations.of(overlayContext).clipboardFoundHint,
                        style: Theme.of(overlayContext).textTheme.titleSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    logDebug('显示剪贴板通知弹窗');
    // 先插入背景层（z-order 靠下），再插入卡片层（z-order 靠上）
    Overlay.of(context).insert(backgroundEntry);
    Overlay.of(context).insert(cardEntry);

    // 6 秒自动消失
    Future.delayed(const Duration(seconds: 6), () => dismiss());
  }
}

/// 剪贴板文本解析结果：去掉署名后的正文，以及识别出的作者/出处。
class _ClipboardAttribution {
  const _ClipboardAttribution({
    required this.content,
    this.author,
    this.source,
  });

  final String content;
  final String? author;
  final String? source;
}
