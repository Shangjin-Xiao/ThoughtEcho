part of '../note_full_editor_page.dart';

/// Document initialization, content processing, and memory-safe content
/// retrieval for the rich text editor.
extension _NoteEditorDocumentInit on _NoteFullEditorPageState {
  /// 异步获取完整笔记数据
  Future<void> _fetchFullQuote() async {
    if (!mounted || widget.initialQuote?.id == null) return;

    try {
      final db = Provider.of<DatabaseService>(context, listen: false);
      final fullQuote = await db.getQuoteById(widget.initialQuote!.id!);
      if (fullQuote != null && mounted) {
        _updateState(() {
          _fullInitialQuote = fullQuote;
          // 初始化 AI 分析结果
          _currentAiAnalysis ??= fullQuote.aiAnalysis;
        });
        logDebug('已获取完整笔记数据，ID: ${fullQuote.id}');
      }
    } catch (e) {
      logDebug('获取完整笔记数据失败: $e');
    } finally {
      if (mounted) {
        _updateState(() {
          _isLoadingFullQuote = false;
        });
      }
    }
  }

  /// 显示编辑器功能引导
  void _showEditorGuide() {
    FeatureGuideHelper.show(
      context: context,
      guideId: 'editor_metadata',
      targetKey: _metadataButtonKey,
    );
  }

  /// 新增：显示工具栏操作气泡引导
  void _showToolbarGuide() {
    FeatureGuideHelper.show(
      context: context,
      guideId: 'editor_toolbar_usage',
      targetKey: _toolbarGuideKey,
      autoDismissDuration: const Duration(milliseconds: 3200),
    );
  }

  /// 异步初始化文档内容
  Future<void> _initializeDocumentAsync() async {
    try {
      if (widget.initialQuote?.deltaContent != null) {
        // 如果有富文本内容，使用后台处理避免阻塞UI
        logDebug('开始异步解析富文本内容...');

        final deltaContent = widget.initialQuote!.deltaContent!;

        // 使用内存安全的处理策略
        await _initializeRichTextContentSafely(deltaContent);
      } else {
        logDebug('使用纯文本初始化编辑器');
        _initializeAsPlainText();
      }
    } catch (e) {
      logDebug('文档初始化失败: $e');
      _initializeAsPlainText();
    } finally {
      _draftLoaded = true;
    }
  }

  /// 内存安全的富文本内容初始化
  Future<void> _initializeRichTextContentSafely(String deltaContent) async {
    try {
      final memoryManager = DeviceMemoryManager();
      final contentSize = deltaContent.length;

      logDebug(
        '开始内存安全的富文本初始化，内容大小: ${(contentSize / 1024).toStringAsFixed(1)}KB',
      );

      // 检查内存压力
      final memoryPressure = await memoryManager.getMemoryPressureLevel();

      if (memoryPressure >= 3) {
        // 临界状态
        logDebug('内存不足，回退到纯文本模式');
        _initializeAsPlainText();
        return;
      }

      // 根据内容大小和内存压力选择处理策略
      if (contentSize > 10 * 1024 * 1024) {
        // 10MB以上
        logDebug('超大富文本内容，使用分段加载');
        await _initializeWithChunkedLoading(deltaContent);
      } else if (contentSize > 2 * 1024 * 1024 || memoryPressure >= 2) {
        // 2MB以上或高内存压力
        logDebug('大富文本内容，使用后台处理');
        await _initializeWithIsolate(deltaContent);
      } else {
        logDebug('普通富文本内容，直接处理');
        await _initializeDirectly(deltaContent);
      }
    } catch (e) {
      logDebug('富文本初始化失败: $e，回退到纯文本');
      _initializeAsPlainText();
    }
  }

  /// 修复：直接初始化富文本内容，增加Delta格式验证
  Future<void> _initializeDirectly(String deltaContent) async {
    try {
      // 修复：验证Delta格式的完整性
      if (!_isValidDeltaFormat(deltaContent)) {
        throw const FormatException('Delta格式无效');
      }

      final deltaJson = jsonDecode(deltaContent);

      // 修复：验证解析后的JSON结构
      if (!_isValidDeltaJson(deltaJson)) {
        throw const FormatException('Delta JSON结构无效');
      }

      final document = quill.Document.fromJson(deltaJson);

      if (mounted) {
        _updateState(() {
          _controller.dispose();
          _controller = quill.QuillController(
            document: document,
            selection: const TextSelection.collapsed(offset: 0),
          );
          _attachDraftListener();
        });
        logDebug('富文本内容直接初始化完成');
      }
    } catch (e) {
      logDebug('直接初始化失败: $e');
      rethrow;
    }
  }

  /// 修复：验证Delta格式的基本有效性
  bool _isValidDeltaFormat(String deltaContent) {
    try {
      if (deltaContent.trim().isEmpty) return false;

      // 基本JSON格式检查
      final decoded = jsonDecode(deltaContent);
      return decoded is List || decoded is Map;
    } catch (e) {
      return false;
    }
  }

  /// 修复：验证Delta JSON结构的有效性
  bool _isValidDeltaJson(dynamic deltaJson) {
    try {
      if (deltaJson is List) {
        // 验证Delta操作数组
        for (final op in deltaJson) {
          if (op is! Map<String, dynamic>) return false;
          if (!op.containsKey('insert') &&
              !op.containsKey('retain') &&
              !op.containsKey('delete')) {
            return false;
          }
        }
        return true;
      } else if (deltaJson is Map<String, dynamic>) {
        // 验证Document格式
        return deltaJson.containsKey('ops') && deltaJson['ops'] is List;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// 使用Isolate初始化富文本内容
  Future<void> _initializeWithIsolate(String deltaContent) async {
    try {
      final deltaJson = await compute(
        _NoteFullEditorPageState._parseJsonInIsolate,
        deltaContent,
      );
      final document = quill.Document.fromJson(deltaJson);

      if (mounted) {
        _updateState(() {
          _controller.dispose();
          _controller = quill.QuillController(
            document: document,
            selection: const TextSelection.collapsed(offset: 0),
          );
          _attachDraftListener();
        });
        logDebug('富文本内容后台初始化完成');
      }
    } catch (e) {
      logDebug('后台初始化失败: $e');
      rethrow;
    }
  }

  /// 修复：使用分段加载初始化超大富文本内容，优化内存管理
  Future<void> _initializeWithChunkedLoading(String deltaContent) async {
    try {
      // 对于超大内容，先创建一个空文档，然后逐步加载内容
      logDebug('开始分段加载超大富文本内容，大小: ${deltaContent.length} 字符');

      // 首先创建一个简单的占位符文档
      if (!mounted) return;
      final loadingMessage = AppLocalizations.of(context).loadingLargeDocument;
      final placeholderDocument = quill.Document()..insert(0, loadingMessage);

      if (mounted) {
        _updateState(() {
          _controller.dispose();
          _controller = quill.QuillController(
            document: placeholderDocument,
            selection: const TextSelection.collapsed(offset: 0),
          );
          _attachDraftListener();
        });
      }

      // 修复：分批处理超大内容，避免内存峰值
      final deltaJson = await _processLargeContentSafely(deltaContent);

      if (deltaJson == null) {
        throw Exception('大型内容处理失败');
      }

      final document = quill.Document.fromJson(deltaJson);

      // 替换为实际文档
      if (mounted) {
        _updateState(() {
          _controller.dispose();
          _controller = quill.QuillController(
            document: document,
            selection: const TextSelection.collapsed(offset: 0),
          );
          _attachDraftListener();
        });
        logDebug('超大富文本内容分段加载完成');
      }
    } catch (e) {
      logDebug('分段加载失败: $e');
      rethrow;
    }
  }

  /// 获取针对当前设备优化的块大小
  Future<int> _getOptimalChunkSize() async {
    try {
      final memoryManager = DeviceMemoryManager();
      final memoryPressure = await memoryManager.getMemoryPressureLevel();

      // 根据内存压力级别调整块大小
      switch (memoryPressure) {
        case 0: // 内存充足
          return 4 * 1024 * 1024; // 4MB
        case 1: // 内存正常
          return 2 * 1024 * 1024; // 2MB
        case 2: // 内存紧张
          return 1 * 1024 * 1024; // 1MB
        case 3: // 内存临界
          return 512 * 1024; // 512KB
        default: // 内存不足或未知状态
          return 256 * 1024; // 256KB（最保守）
      }
    } catch (e) {
      logDebug('获取设备内存状况失败，使用默认块大小: $e');
      return 1024 * 1024; // 回退到1MB
    }
  }

  /// 修复：安全处理大型内容，分批加载避免内存峰值
  Future<dynamic> _processLargeContentSafely(String deltaContent) async {
    try {
      // 动态获取适合当前设备的块大小
      final chunkSize = await _getOptimalChunkSize();
      logDebug('使用动态块大小: ${(chunkSize / 1024).toStringAsFixed(1)}KB');

      if (deltaContent.length > chunkSize) {
        logDebug('内容过大，使用分批处理策略');

        // 尝试简化内容
        final simplifiedContent = _simplifyLargeContent(deltaContent);
        return await compute(
          _NoteFullEditorPageState._parseJsonInIsolate,
          simplifiedContent,
        );
      } else {
        // 正常处理
        return await compute(
          _NoteFullEditorPageState._parseJsonInIsolate,
          deltaContent,
        );
      }
    } catch (e) {
      logDebug('大型内容处理失败: $e');
      return null;
    }
  }

  /// 修复：简化大型内容，移除非必要元素
  String _simplifyLargeContent(String deltaContent) {
    try {
      final deltaJson = jsonDecode(deltaContent);
      final simplified = _simplifyDeltaData(deltaJson);
      return jsonEncode(simplified);
    } catch (e) {
      logDebug('简化大型内容失败: $e');
      return deltaContent;
    }
  }

  Future<String> _getDocumentContentSafely() async {
    try {
      final memoryManager = DeviceMemoryManager();
      final delta = _controller.document.toDelta();
      final deltaData = delta.toJson();

      // 估算内容大小
      final estimatedSize = deltaData.toString().length * 2;
      logDebug('文档内容估算大小: ${(estimatedSize / 1024).toStringAsFixed(1)}KB');

      // 检查内存压力
      final memoryPressure = await memoryManager.getMemoryPressureLevel();

      if (memoryPressure >= 3) {
        // 临界状态
        logDebug('内存不足，使用最小化处理');
        return _getMinimalDocumentContent();
      }

      // 根据内容大小和内存压力选择处理策略
      if (estimatedSize > 5 * 1024 * 1024) {
        // 5MB以上
        logDebug('超大文档，使用分段处理');
        return await _getDocumentContentWithChunking(deltaData);
      } else if (estimatedSize > 1 * 1024 * 1024 || memoryPressure >= 2) {
        // 1MB以上或高内存压力
        logDebug('大文档，使用后台处理');
        return await _getDocumentContentWithIsolate(deltaData);
      } else {
        logDebug('普通文档，直接处理');
        return jsonEncode(deltaData);
      }
    } catch (e) {
      logDebug('获取文档内容失败: $e');
      return _getMinimalDocumentContent();
    }
  }

  /// 获取最小化文档内容（仅纯文本）
  String _getMinimalDocumentContent() {
    try {
      // 在内存不足时，只保存纯文本内容作为简单的Delta格式
      final plainText = _controller.document.toPlainText();
      final minimalDelta = [
        {"insert": plainText},
        {"insert": "\n"},
      ];
      return jsonEncode(minimalDelta);
    } catch (e) {
      logDebug('获取最小化内容失败: $e');
      return '[]'; // 返回空的Delta
    }
  }

  /// 使用Isolate处理文档内容
  Future<String> _getDocumentContentWithIsolate(dynamic deltaData) async {
    try {
      return await compute(
        _NoteFullEditorPageState._encodeJsonInIsolate,
        deltaData,
      );
    } catch (e) {
      logDebug('后台处理失败: $e');
      return _getMinimalDocumentContent();
    }
  }

  /// 使用分段处理超大文档内容
  Future<String> _getDocumentContentWithChunking(dynamic deltaData) async {
    try {
      // 对于超大文档，尝试简化内容
      logDebug('开始分段处理超大文档');

      // 首先尝试移除一些可能占用大量空间的元素
      final simplifiedData = _simplifyDeltaData(deltaData);

      // 然后使用Isolate处理简化后的数据
      return await compute(
        _NoteFullEditorPageState._encodeJsonInIsolate,
        simplifiedData,
      );
    } catch (e) {
      logDebug('分段处理失败: $e');
      return _getMinimalDocumentContent();
    }
  }

  /// 简化Delta数据，移除可能占用大量内存的元素
  dynamic _simplifyDeltaData(dynamic deltaData) {
    try {
      if (deltaData is List) {
        return deltaData.map((item) {
          if (item is Map<String, dynamic>) {
            final simplified = Map<String, dynamic>.from(item);

            // 移除大型嵌入内容，保留引用
            if (simplified.containsKey('insert') &&
                simplified['insert'] is Map) {
              final insert = simplified['insert'] as Map;
              if (insert.containsKey('image') || insert.containsKey('video')) {
                // 保留类型信息但移除实际数据
                simplified['insert'] = {
                  'type': insert.keys.first,
                  'simplified': true,
                };
              }
            }

            return simplified;
          }
          return item;
        }).toList();
      }
      return deltaData;
    } catch (e) {
      logDebug('简化Delta数据失败: $e');
      return deltaData;
    }
  }

  dynamic _deepCopy(dynamic original) {
    if (original == null) {
      return null;
    } else if (original is Map) {
      return Map<String, dynamic>.from(
        original.map((key, value) => MapEntry(key, _deepCopy(value))),
      );
    } else if (original is List) {
      return original.map((item) => _deepCopy(item)).toList();
    } else {
      // 基本类型（String, int, double, bool等）直接返回
      return original;
    }
  }
}
