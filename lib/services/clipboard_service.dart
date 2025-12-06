// filepath: /workspaces/ThoughtEcho/lib/services/clipboard_service.dart
// ignore_for_file: unused_field
import '../constants/app_constants.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/note_category.dart';
import '../services/database_service.dart';
import '../widgets/add_note_dialog.dart'; // 导入AddNoteDialog
import 'package:provider/provider.dart';
import '../utils/mmkv_ffi_fix.dart'; // 导入安全包装类
import '../theme/app_theme.dart';
import '../utils/app_logger.dart';

class ClipboardService extends ChangeNotifier {
  static const String _keyEnableClipboardMonitoring =
      'enable_clipboard_monitoring';

  // 常见的引述格式匹配
  static final RegExp _quoteAuthorPattern = RegExp(
    r'[-—–]\s*([^，。,\.、\n]{2,20})$|《([^》]+)》\s*[-—–]\s*([^，。,\.、\n]{2,20})|"(.+)"\s*[-—–]\s*([^，。,\.、\n]{2,20})',
    multiLine: true,
  );

  // 可能的出处标识
  static final RegExp _sourcePattern = RegExp(
    r'[（\(](.{2,30}?)[）\)]$|《(.{2,30}?)》$|摘自[《]?(.{2,30}?)[》]?$|选自[《]?(.{2,30}?)[》]?$|出自[《]?(.{2,30}?)[》]?$',
    multiLine: true,
  );

  // 是否启用剪贴板监控
  bool _enableClipboardMonitoring = false;
  bool get enableClipboardMonitoring => _enableClipboardMonitoring;

  // 剪贴板上次处理的内容缓存（仅内存中，不需要持久化）
  String _lastProcessedContent = '';

  // 使用安全包装类替代直接的MMKV
  SafeMMKV? _storage;

  // 构造函数
  ClipboardService();

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
      logDebug(
        '检测到新的剪贴板内容: ${content.length > 20 ? '${content.substring(0, 20)}...' : content}',
      );

      // 内容过长或过短不处理
      if (content.length > 5000 || content.length < 5) {
        logDebug('剪贴板内容长度不适合处理: ${content.length}字符');
        return null;
      }

      // 更新最近处理的内容（仅在内存中记住，不需要持久化）
      _lastProcessedContent = content;

      // 提取作者和出处（如果有）
      final extractedInfo = _extractAuthorAndSource(content);
      String? author = extractedInfo['author'];
      String? source = extractedInfo['source'];
      String? matchedSubstring = extractedInfo['matched_substring']; // 获取匹配到的子串

      logDebug('从剪贴板提取信息 - 作者: $author, 出处: $source, 匹配子串: $matchedSubstring');

      // 如果提取到了元数据，从原始内容中移除匹配的子串
      final displayContent = (matchedSubstring != null)
          ? content.replaceFirst(matchedSubstring, '').trim()
          : content;

      // 返回提取的信息
      return {
        'content': displayContent, // 使用处理后的内容
        'author': author,
        'source': source,
      };
    } catch (e) {
      logDebug('检查剪贴板时出错: $e');
      return null;
    }
  }

  // 从文本中提取作者和出处信息（类似一言格式）
  // 返回包含 'author', 'source', 'matched_substring' 的 Map
  Map<String, String?> _extractAuthorAndSource(String content) {
    final text = content.trim();
    String? author;
    String? source;
    String? matchedSubstring; // 用于存储匹配到的完整元数据子串

    // 定义清理函数，去除前后空格和特定标点
    String? clean(String? input) {
      return input
          ?.trim()
          .replaceAll(RegExp(r'^[—–\-—\s]+|[—–\-—\s]+$'), '')
          .trim();
    }

    // 1. 匹配 ——作者《出处》 或 --作者《出处》 等
    final m1 = RegExp(
      r'[-—–]+\s*([^《（\(]+?)?\s*[《（\(]([^》）\)]+?)[》）\)]\s*$',
    ).firstMatch(text);
    if (m1 != null) {
      author = clean(m1.group(1));
      source = clean(m1.group(2));
      matchedSubstring = m1.group(0);
      return {
        'author': author,
        'source': source,
        'matched_substring': matchedSubstring,
      };
    }

    // 2. 匹配 《出处》——作者 或 《出处》--作者 等
    final m2 = RegExp(
      r'[《（\(]([^》）\)]+?)[》）\)]\s*[-—–]+\s*([^，。,、\.\n]+)\s*$',
    ).firstMatch(text);
    if (m2 != null) {
      source = clean(m2.group(1));
      author = clean(m2.group(2));
      matchedSubstring = m2.group(0);
      return {
        'author': author,
        'source': source,
        'matched_substring': matchedSubstring,
      };
    }

    // 3. 匹配 "文"——作者 或 "文"--作者 等
    final m3 = RegExp(
      r'["""](.+?)["""]\s*[-—–]+\s*([^，。,、\.\n]+)\s*$',
    ).firstMatch(text);
    if (m3 != null) {
      // 这种情况通常只提取作者，引用的内容在前面
      author = clean(m3.group(2));
      matchedSubstring = m3.group(0);
      // 注意：这里可能需要更复杂的逻辑来判断是否要提取 source，暂时只提取 author
      return {
        'author': author,
        'source': null,
        'matched_substring': matchedSubstring,
      };
    }

    // 4. 回退提取作者（匹配末尾的 ——作者 或 --作者）
    final m4 = RegExp(r'[-—–]+\s*([^，。,、\.\n《（\(]{2,20})\s*$').firstMatch(text);
    if (m4 != null) {
      author = clean(m4.group(1));
      matchedSubstring = m4.group(0);
      // 尝试在此基础上再提取出处
      final remainingText =
          text.substring(0, text.length - matchedSubstring!.length).trim();
      final m4Source = RegExp(
        r'[《（\(]([^》）\)]+?)[》）\)]\s*$',
      ).firstMatch(remainingText);
      if (m4Source != null) {
        source = clean(m4Source.group(1));
        // 更新匹配的子串以包含出处部分 (可能不精确，但尝试包含)
        matchedSubstring = text.substring(
          remainingText.length - m4Source.group(0)!.length,
        );
      }
      return {
        'author': author,
        'source': source,
        'matched_substring': matchedSubstring,
      };
    }

    // 5. 回退提取出处（匹配末尾的 《出处》 或 （出处））
    final m5 = RegExp(r'[《（\(]([^》）\)]+?)[》）\)]\s*$').firstMatch(text);
    if (m5 != null) {
      source = clean(m5.group(1));
      matchedSubstring = m5.group(0);
      // 尝试在此基础上再提取作者
      final remainingText =
          text.substring(0, text.length - matchedSubstring!.length).trim();
      final m5Author = RegExp(
        r'[-—–]+\s*([^，。,、\.\n《（\(]{2,20})\s*$',
      ).firstMatch(remainingText);
      if (m5Author != null) {
        author = clean(m5Author.group(1));
        // 更新匹配的子串以包含作者部分 (可能不精确，但尝试包含)
        matchedSubstring = text.substring(
          remainingText.length - m5Author.group(0)!.length,
        );
      }
      return {
        'author': author,
        'source': source,
        'matched_substring': matchedSubstring,
      };
    }

    // 如果都没有匹配到，返回 null
    return {'author': null, 'source': null, 'matched_substring': null};
  }

  // 显示询问对话框并打开编辑页面
  void showClipboardConfirmationDialog(
    BuildContext context,
    Map<String, dynamic> clipboardData,
  ) {
    final content = clipboardData['content'] as String;
    final author = clipboardData['author'] as String?;
    final source = clipboardData['source'] as String?;

    // 显示非阻塞式通知
    showNonBlockingClipboardNotification(context, content, author, source);
  }

  // 显示非阻塞式剪贴板通知
  void showNonBlockingClipboardNotification(
    BuildContext context,
    String content,
    String? author,
    String? source,
  ) {
    // 构建一个OverlayEntry，但不使用全屏覆盖层
    OverlayEntry? overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        // 放置在屏幕上方合适位置
        top: MediaQuery.of(context).size.height * 0.15,
        left: 0,
        right: 0,
        child: Material(
          color: Colors.transparent,
          child: GestureDetector(
            onTap: () async {
              overlayEntry?.remove();
              if (context.mounted) {
                _openEditPage(context, content, author, source);
              }
            },
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 320),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(AppTheme.dialogRadius),
                  boxShadow: AppTheme.defaultShadow,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.content_paste,
                      color: Theme.of(context).colorScheme.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    const Flexible(
                      child: Text(
                        '发现剪贴板内容，点击添加为笔记',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
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

    // 添加到Overlay
    logDebug('显示剪贴板通知弹窗');
    Overlay.of(context).insert(overlayEntry);

    // 10秒后自动移除通知
    Future.delayed(const Duration(seconds: 3), () {
      if (overlayEntry?.mounted ?? false) {
        overlayEntry?.remove();
      }
    });
  }

  // 打开编辑页面
  void _openEditPage(
    BuildContext context,
    String content,
    String? author,
    String? source,
  ) async {
    try {
      // 获取所有标签
      final databaseService = Provider.of<DatabaseService>(
        context,
        listen: false,
      );
      final List<NoteCategory> tags = await databaseService.getCategories();

      // 防止在异步操作后使用已销毁的BuildContext
      if (!context.mounted) return;

      // 打开编辑页面
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Theme.of(context).brightness == Brightness.light
            ? Colors.white
            : Theme.of(context).colorScheme.surface,
        builder: (context) => AddNoteDialog(
          prefilledContent: content,
          prefilledAuthor: author,
          prefilledWork: source,
          tags: tags,
          onSave: (quote) {
            // 可以在这里添加保存后的回调
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('笔记已保存'),
                  duration: AppConstants.snackBarDurationImportant,
                ),
              );
            }
          },
        ),
      );
    } catch (e) {
      logDebug('打开编辑页面失败: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('操作失败: $e'),
            duration: AppConstants.snackBarDurationError,
          ),
        );
      }
    }
  }
}
