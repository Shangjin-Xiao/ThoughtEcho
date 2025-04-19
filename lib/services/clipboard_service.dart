// filepath: /workspaces/ThoughtEcho/lib/services/clipboard_service.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mind_trace/models/note_category.dart';
import 'package:mind_trace/services/database_service.dart';
import 'package:mind_trace/widgets/add_note_dialog.dart'; // 导入AddNoteDialog
import 'package:provider/provider.dart';
import '../utils/mmkv_ffi_fix.dart'; // 导入安全包装类

class ClipboardService extends ChangeNotifier {
  static const String _keyEnableClipboardMonitoring = 'enable_clipboard_monitoring';
  static const String _keyLastClipboardContent = 'last_clipboard_content';
  
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
  
  // 剪贴板上次处理的内容缓存
  String _lastProcessedContent = '';
  
  // 使用安全包装类替代直接的MMKV
  late final SafeMMKV _storage;
  
  // 构造函数
  ClipboardService() {
    _initPreferences();
  }
  
  // 初始化首选项
  Future<void> _initPreferences() async {
    try {
      _storage = SafeMMKV();
      await _storage.initialize();
      _loadPreferences();
    } catch (e) {
      debugPrint('初始化剪贴板服务首选项时出错: $e');
    }
  }
  
  // 从存储加载首选项
  void _loadPreferences() {
    _enableClipboardMonitoring = _storage.getBool(_keyEnableClipboardMonitoring) ?? false;
    _lastProcessedContent = _storage.getString(_keyLastClipboardContent) ?? '';
    notifyListeners();
  }
  
  // 设置是否启用剪贴板监控
  void setEnableClipboardMonitoring(bool value) {
    _enableClipboardMonitoring = value;
    _storage.setBool(_keyEnableClipboardMonitoring, value);
    notifyListeners();
  }
  
  // 检查剪贴板内容
  Future<Map<String, dynamic>?> checkClipboard() async {
    if (!_enableClipboardMonitoring) {
      return null;
    }
    
    try {
      // 获取剪贴板数据
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      
      // 没有数据或数据与上次处理的相同，返回null
      if (data == null || data.text == null || data.text!.isEmpty || 
          data.text == _lastProcessedContent) {
        return null;
      }
      
      final content = data.text!;
      
      // 内容过长或过短不处理
      if (content.length > 5000 || content.length < 5) {
        return null;
      }
      
      // 更新最近处理的内容
      _lastProcessedContent = content;
      _storage.setString(_keyLastClipboardContent, content);  // 修正变量名
      
      // 提取作者和出处（如果有）
      final extractedInfo = _extractAuthorAndSource(content);
      String? author = extractedInfo['author'];
      String? source = extractedInfo['source'];
      
      // 返回提取的信息
      return {
        'content': content,
        'author': author,
        'source': source,
      };
    } catch (e) {
      debugPrint('检查剪贴板时出错: $e');
      return null;
    }
  }
  
  // 从文本中提取作者和出处信息（类似一言格式）
  Map<String, String?> _extractAuthorAndSource(String content) {
    String? author;
    String? source;
    
    // 尝试提取作者信息（如常见的"—— 作者"格式）
    final authorMatches = _quoteAuthorPattern.allMatches(content);
    if (authorMatches.isNotEmpty) {
      for (var match in authorMatches) {
        // 按优先级尝试不同的匹配组
        author = match.group(1) ?? match.group(3) ?? match.group(5);
        if (author != null && author.isNotEmpty) {
          break;
        }
      }
    }
    
    // 尝试提取出处信息（如书名或文章名）
    final sourceMatches = _sourcePattern.allMatches(content);
    if (sourceMatches.isNotEmpty) {
      for (var match in sourceMatches) {
        // 尝试不同的匹配组
        source = match.group(1) ?? match.group(2) ?? match.group(3) ?? match.group(4);
        if (source != null && source.isNotEmpty) {
          break;
        }
      }
    }
    
    return {
      'author': author,
      'source': source,
    };
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
    // 构建一个OverlayEntry
    OverlayEntry? overlayEntry;
    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 20,
        right: 20,
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 280,
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha((0.15 * 255).round()),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    children: [
                      Icon(
                        Icons.content_paste,
                        color: Theme.of(context).colorScheme.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        '发现剪贴板内容',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () {
                          overlayEntry?.remove();
                        },
                        child: const Icon(
                          Icons.close,
                          size: 16,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Text(
                    content.length > 60 ? '${content.substring(0, 60)}...' : content,
                    style: const TextStyle(fontSize: 13),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (author != null || source != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0),
                    child: Text(
                      '已识别: ${author ?? ''}${source != null ? ' 《$source》' : ''}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.grey,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                OverflowBar(
                  spacing: 8.0,
                  children: [
                    TextButton(
                      onPressed: () {
                        overlayEntry?.remove();
                      },
                      child: const Text('忽略'),
                    ),
                    TextButton(
                      onPressed: () {
                        overlayEntry?.remove();
                        _openEditPage(context, content, author, source);
                      },
                      child: const Text('添加为笔记'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // 添加到Overlay
    Overlay.of(context).insert(overlayEntry);
    
    // 10秒后自动移除通知
    Future.delayed(const Duration(seconds: 10), () {
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
    String? source
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
        builder: (context) => AddNoteDialog(
          prefilledContent: content,
          prefilledAuthor: author,
          prefilledWork: source,
          tags: tags,
          onSave: (quote) {
            // 可以在这里添加保存后的回调
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('笔记已保存')),
              );
            }
          },
        ),
      );
    } catch (e) {
      debugPrint('打开编辑页面失败: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('操作失败: $e')),
        );
      }
    }
  }
}
