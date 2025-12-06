import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_quill_extensions/flutter_quill_extensions.dart';
import 'dart:convert';
import 'package:provider/provider.dart';
import '../gen_l10n/app_localizations.dart';
import 'package:uuid/uuid.dart';
import '../services/database_service.dart';
import '../models/quote_model.dart';
import '../models/note_category.dart';
import '../services/location_service.dart';
import '../services/local_geocoding_service.dart';
import '../services/weather_service.dart';
import '../services/ai_service.dart'; // 导入AI服务
import '../utils/time_utils.dart'; // 导入时间工具类
import 'package:flex_color_picker/flex_color_picker.dart';
import '../utils/icon_utils.dart';
import '../utils/color_utils.dart'; // Import color_utils
import 'dart:math' show min; // 添加math包导入
import '../widgets/streaming_text_dialog.dart'; // 导入 StreamingTextDialog
import 'package:flutter/services.dart';
import '../utils/app_logger.dart';
import 'note_qa_chat_page.dart'; // 添加问笔记聊天页面导入
import 'package:flutter/foundation.dart' show kIsWeb, compute;
import '../utils/device_memory_manager.dart';
import '../widgets/quill_enhanced_toolbar_unified.dart';
import '../utils/quill_editor_extensions.dart'; // 导入自定义embedBuilders
import '../services/temporary_media_service.dart';
import '../widgets/media_player_widget.dart';
import '../constants/app_constants.dart';
import '../services/media_file_service.dart';
import '../services/media_reference_service.dart';
import '../utils/feature_guide_helper.dart';

class NoteFullEditorPage extends StatefulWidget {
  final String initialContent;
  final Quote? initialQuote;
  final List<NoteCategory>? allTags;
  const NoteFullEditorPage({
    super.key,
    required this.initialContent,
    this.initialQuote,
    this.allTags,
  });

  @override
  State<NoteFullEditorPage> createState() => _NoteFullEditorPageState();
}

class _NoteFullEditorPageState extends State<NoteFullEditorPage> {
  late quill.QuillController _controller;
  late TextEditingController _authorController;
  late TextEditingController _workController;
  late List<String> _selectedTagIds; // 选中标签ID列表
  String? _selectedColorHex;
  String? _location;
  double? _latitude; // 位置纬度
  double? _longitude; // 位置经度
  String? _weather;
  String? _temperature; // 分离位置和天气控制
  bool _showLocation = false;
  bool _showWeather = false;

  // 保存原始笔记的位置和天气信息（用于编辑模式判断）
  String? _originalLocation;
  double? _originalLatitude;
  double? _originalLongitude;
  String? _originalWeather;

  // 会话级媒体追踪：记录本编辑会话中通过导入对话框新增的媒体文件
  final Set<String> _sessionImportedMedia = <String>{};
  bool _didSaveSuccessfully = false; // 成功保存后不进行会话级清理

  // 保存进度状态
  bool _isSaving = false; // 是否显示保存遮罩
  double _saveProgress = 0.0; // 整体进度 (媒体文件处理进度主导)
  String? _saveStatus; // 当前状态描述

  // 标签搜索控制器和过滤状态
  final TextEditingController _tagSearchController = TextEditingController();
  String _tagSearchQuery = '';

  // 功能引导：元数据编辑按钮的 Key
  final GlobalKey _metadataButtonKey = GlobalKey();
  // 新增：工具栏气泡引导 Key
  final GlobalKey _toolbarGuideKey = GlobalKey();

  // 用于检测未保存内容的初始状态
  late String _initialPlainText;
  late String _initialDeltaContent;
  late String _initialAuthor;
  late String _initialWork;
  late List<String> _initialTagIds;
  late String? _initialColorHex;
  late String? _initialLocation;
  late double? _initialLatitude;
  late double? _initialLongitude;
  late String? _initialWeather;
  late String? _initialTemperature;

  @override
  void initState() {
    super.initState();

    // 先初始化为基本控制器，避免阻塞UI
    _controller = quill.QuillController.basic();

    // 异步初始化文档内容
    _initializeDocumentAsync();

    // 作者/作品
    _authorController = TextEditingController(
      text: widget.initialQuote?.sourceAuthor ?? '',
    );
    _workController = TextEditingController(
      text: widget.initialQuote?.sourceWork ?? '',
    );
    _selectedTagIds = widget.initialQuote?.tagIds ?? [];
    // 颜色
    _selectedColorHex = widget.initialQuote?.colorHex;
    // 位置/天气 - 分别设置状态
    _location = widget.initialQuote?.location;
    _latitude = widget.initialQuote?.latitude;
    _longitude = widget.initialQuote?.longitude;
    _weather = widget.initialQuote?.weather;
    _temperature = widget.initialQuote?.temperature;

    // 保存原始的位置和天气信息（用于编辑模式判断）
    _originalLocation = widget.initialQuote?.location;
    _originalLatitude = widget.initialQuote?.latitude;
    _originalLongitude = widget.initialQuote?.longitude;
    _originalWeather = widget.initialQuote?.weather;

    // 分别检查并设置位置和天气状态
    // 有地址字符串或有坐标都算有位置
    _showLocation =
        _location != null || (_latitude != null && _longitude != null);
    _showWeather = _weather != null;

    // 初始化用于检测未保存内容的初始状态
    _initialPlainText = widget.initialContent;
    _initialDeltaContent = widget.initialQuote?.deltaContent ?? '';
    _initialAuthor = widget.initialQuote?.sourceAuthor ?? '';
    _initialWork = widget.initialQuote?.sourceWork ?? '';
    _initialTagIds = List.from(widget.initialQuote?.tagIds ?? []);
    _initialColorHex = widget.initialQuote?.colorHex;
    _initialLocation = widget.initialQuote?.location;
    _initialLatitude = widget.initialQuote?.latitude;
    _initialLongitude = widget.initialQuote?.longitude;
    _initialWeather = widget.initialQuote?.weather;
    _initialTemperature = widget.initialQuote?.temperature;

    // 显示功能引导（首帧后立即触发）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _showEditorGuide();
        _showToolbarGuide();
      }
    });
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
        setState(() {
          _controller.dispose();
          _controller = quill.QuillController(
            document: document,
            selection: const TextSelection.collapsed(offset: 0),
          );
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
      final deltaJson = await compute(_parseJsonInIsolate, deltaContent);
      final document = quill.Document.fromJson(deltaJson);

      if (mounted) {
        setState(() {
          _controller.dispose();
          _controller = quill.QuillController(
            document: document,
            selection: const TextSelection.collapsed(offset: 0),
          );
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
      final placeholderDocument = quill.Document()..insert(0, '正在加载大型文档...');

      if (mounted) {
        setState(() {
          _controller.dispose();
          _controller = quill.QuillController(
            document: placeholderDocument,
            selection: const TextSelection.collapsed(offset: 0),
          );
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
        setState(() {
          _controller.dispose();
          _controller = quill.QuillController(
            document: document,
            selection: const TextSelection.collapsed(offset: 0),
          );
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
        return await compute(_parseJsonInIsolate, simplifiedContent);
      } else {
        // 正常处理
        return await compute(_parseJsonInIsolate, deltaContent);
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

  /// 在Isolate中解析JSON
  static dynamic _parseJsonInIsolate(String jsonString) {
    return jsonDecode(jsonString);
  }

  /// 内存安全的文档内容获取
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
      return await compute(_encodeJsonInIsolate, deltaData);
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
      return await compute(_encodeJsonInIsolate, simplifiedData);
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

  /// 在Isolate中编码JSON
  static String _encodeJsonInIsolate(dynamic data) {
    return jsonEncode(data);
  }

  /// 深拷贝List或Map，递归处理嵌套对象
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

  /// 修复：初始化为纯文本的辅助方法，增强错误恢复
  void _initializeAsPlainText() {
    try {
      if (mounted) {
        setState(() {
          _controller.dispose(); // 释放旧控制器
          _controller = quill.QuillController(
            document: quill.Document()..insert(0, widget.initialContent),
            selection: const TextSelection.collapsed(offset: 0),
          );
        });
      }
    } catch (e) {
      // 如果即使初始化纯文本也失败，使用空文档
      logDebug('初始化编辑器为纯文本失败: $e');
      _initializeEmptyDocument();
    }
  }

  /// 修复：初始化空文档作为最后的错误恢复手段
  void _initializeEmptyDocument() {
    try {
      if (mounted) {
        setState(() {
          _controller.dispose(); // 释放旧控制器
          _controller = quill.QuillController.basic();

          // 尝试安全地添加内容
          try {
            if (widget.initialContent.isNotEmpty) {
              // 修复：分批添加内容，避免一次性插入大量文本，并正确跟踪插入位置
              final content = widget.initialContent;
              const chunkSize = 1000; // 每次插入1000字符
              int currentInsertPosition = 0; // 跟踪当前插入位置

              for (int i = 0; i < content.length; i += chunkSize) {
                final end = (i + chunkSize < content.length)
                    ? i + chunkSize
                    : content.length;
                final chunk = content.substring(i, end);

                // 确保插入位置在有效范围内
                final docLength = _controller.document.length;
                final safeInsertPosition = currentInsertPosition.clamp(
                  0,
                  docLength - 1,
                );

                _controller.document.insert(safeInsertPosition, chunk);

                // 更新插入位置：当前位置 + 插入的文本长度
                currentInsertPosition = safeInsertPosition + chunk.length;
              }
            }
          } catch (insertError) {
            logDebug('插入内容失败: $insertError');
            // 最后的兜底：创建一个包含错误信息的文档
            try {
              _controller.document.insert(0, '文档加载失败，请重新打开编辑器');
            } catch (_) {
              // 完全失败，保持空文档
            }
          }
        });
      }
    } catch (e) {
      logDebug('初始化空文档也失败: $e');
      // 这种情况下，保持现有控制器状态
    }
  }

  // 天气图标映射方法
  IconData _getWeatherIcon(String weatherKey) {
    return WeatherService.getWeatherIconDataByKey(weatherKey);
  }

  /// 编辑模式下的位置对话框
  Future<void> _showLocationDialogInEditor(
    BuildContext context,
    ThemeData theme,
  ) async {
    final l10n = AppLocalizations.of(context);
    final hasLocationData = _originalLocation != null ||
        (_originalLatitude != null && _originalLongitude != null);
    final hasCoordinates =
        _originalLatitude != null && _originalLongitude != null;
    final hasOnlyCoordinates = _originalLocation == null && hasCoordinates;

    String title;
    String content;
    List<Widget> actions = [];

    if (!hasLocationData) {
      // 没有位置数据
      title = l10n.cannotAddLocation;
      content = l10n.cannotAddLocationDesc;
      actions = [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.iKnow),
        ),
      ];
    } else {
      // 有位置数据
      title = l10n.locationInfo;
      content = hasOnlyCoordinates
          ? l10n.locationUpdateHint(
              LocationService.formatCoordinates(
                _originalLatitude,
                _originalLongitude,
              ),
            )
          : l10n.locationRemoveHint(_originalLocation ?? _location ?? "");
      actions = [
        if (_showLocation)
          TextButton(
            onPressed: () => Navigator.pop(context, 'remove'),
            child: Text(l10n.remove),
          ),
        if (hasOnlyCoordinates)
          TextButton(
            onPressed: () => Navigator.pop(context, 'update'),
            child: Text(l10n.updateLocation),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context, 'cancel'),
          child: Text(l10n.cancel),
        ),
      ];
    }

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: actions,
      ),
    );

    if (!mounted) {
      return; // Ensure the widget is still in the tree before using context
    }

    if (result == 'update' && hasCoordinates) {
      // 尝试用坐标更新地址
      try {
        // 获取当前语言设置（在异步操作前获取，避免context跨越异步间隙）
        if (!context.mounted) return;
        final locationService =
            Provider.of<LocationService>(context, listen: false);
        final localeCode = locationService.currentLocaleCode;
        final addressInfo =
            await LocalGeocodingService.getAddressFromCoordinates(
          _originalLatitude!,
          _originalLongitude!,
          localeCode: localeCode,
        );
        if (addressInfo != null && mounted) {
          final formattedAddress = addressInfo['formatted_address'];
          if (formattedAddress != null && formattedAddress.isNotEmpty) {
            setState(() {
              _location = formattedAddress;
              _originalLocation = formattedAddress;
            });
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(l10n.locationUpdatedTo(formattedAddress)),
                ),
              );
            }
          } else if (context.mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(l10n.cannotGetAddress)));
          }
        } else if (mounted && context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(l10n.cannotGetAddress)));
        }
      } catch (e) {
        if (mounted && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.updateFailed(e.toString()))),
          );
        }
      }
    } else if (result == 'remove') {
      setState(() {
        _showLocation = false;
      });
    }
  }

  /// 编辑模式下的天气对话框
  Future<void> _showWeatherDialogInEditor(
    BuildContext context,
    ThemeData theme,
  ) async {
    final l10n = AppLocalizations.of(context);
    final hasWeatherData = _originalWeather != null;

    String title;
    String content;
    List<Widget> actions = [];

    if (!hasWeatherData) {
      // 没有天气数据
      title = l10n.cannotAddWeather;
      content = l10n.cannotAddWeatherDesc;
      actions = [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.iKnow),
        ),
      ];
    } else {
      // 有天气数据
      final weatherDesc = WeatherService.getLocalizedWeatherDescription(
        AppLocalizations.of(context),
        _originalWeather!,
      );
      title = l10n.weatherInfo2;
      content = l10n.weatherRemoveHint(
        '$weatherDesc${_temperature != null ? " $_temperature" : ""}',
      );
      actions = [
        if (_showWeather)
          TextButton(
            onPressed: () => Navigator.pop(context, 'remove'),
            child: Text(l10n.remove),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context, 'cancel'),
          child: Text(l10n.cancel),
        ),
      ];
    }

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: actions,
      ),
    );

    if (result == 'remove') {
      setState(() {
        _showWeather = false;
      });
    }
  }

  Future<void> _fetchLocationWeather() async {
    final locationService = Provider.of<LocationService>(
      context,
      listen: false,
    );
    final weatherService = Provider.of<WeatherService>(context, listen: false);

    // 检查并请求权限
    if (!locationService.hasLocationPermission) {
      bool permissionGranted =
          await locationService.requestLocationPermission();
      if (!permissionGranted) {
        if (mounted && context.mounted) {
          final l10n = AppLocalizations.of(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.cannotGetLocationPermissionShort),
              duration: AppConstants.snackBarDurationError,
            ),
          );
        }
        return;
      }
    }

    final position = await locationService.getCurrentLocation();
    if (position != null && mounted) {
      final location = locationService.getFormattedLocation();

      // 优化：将网络请求包装为 Future，避免阻塞主线程
      try {
        // 更新位置信息（包括经纬度）
        setState(() {
          _location = location.isNotEmpty ? location : null;
          _latitude = position.latitude;
          _longitude = position.longitude;
        });

        // 异步获取天气数据，不阻塞UI
        _fetchWeatherAsync(
          weatherService,
          position.latitude,
          position.longitude,
        );
      } catch (e) {
        logError('获取位置天气失败', error: e, source: 'NoteFullEditorPage');
      }
    } else if (mounted && context.mounted) {
      // 获取位置失败，给出提示
      final l10n = AppLocalizations.of(context);
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.cannotGetLocationTitle),
          content: Text(l10n.cannotGetLocationDesc),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.iKnow),
            ),
          ],
        ),
      );
    }
  }

  // 异步获取天气数据的辅助方法
  Future<void> _fetchWeatherAsync(
    WeatherService weatherService,
    double latitude,
    double longitude,
  ) async {
    try {
      await weatherService.getWeatherData(latitude, longitude);

      // 优化：仅在组件仍然挂载时更新状态
      if (mounted) {
        setState(() {
          _weather = weatherService.currentWeather;
          _temperature = weatherService.temperature;
        });
      }
    } catch (e) {
      logError('获取天气数据失败', error: e, source: 'NoteFullEditorPage');
    }
  }

  /// 检测是否有未保存的内容变化
  bool _hasUnsavedChanges() {
    // 检查主要内容
    final currentPlainText = _controller.document.toPlainText().trim();
    if (currentPlainText != _initialPlainText.trim()) {
      return true;
    }

    // 检查元数据
    if (_authorController.text != _initialAuthor) {
      return true;
    }
    if (_workController.text != _initialWork) {
      return true;
    }

    // 检查标签
    final selectedTagSet = Set.from(_selectedTagIds);
    final initialTagSet = Set.from(_initialTagIds);
    if (!selectedTagSet.containsAll(initialTagSet) ||
        !initialTagSet.containsAll(selectedTagSet)) {
      return true;
    }

    // 检查颜色
    if (_selectedColorHex != _initialColorHex) {
      return true;
    }

    // 检查位置
    if (_location != _initialLocation) {
      return true;
    }
    if (_latitude != _initialLatitude) {
      return true;
    }
    if (_longitude != _initialLongitude) {
      return true;
    }

    // 检查天气
    if (_weather != _initialWeather) {
      return true;
    }
    if (_temperature != _initialTemperature) {
      return true;
    }

    // 使用 _initialDeltaContent 避免编译器警告
    // 富文本内容如果被修改，纯文本内容通常也会反映这个变化
    // 所以这里仅用于记录初始状态，实际比对通过纯文本进行
    // ignore: unused_local_variable
    final _ = _initialDeltaContent;

    return false;
  }

  Future<void> _saveContent() async {
    final db = Provider.of<DatabaseService>(context, listen: false);

    logDebug('开始保存笔记内容...');
    if (mounted) {
      setState(() {
        _isSaving = true;
        _saveProgress = 0.0;
        _saveStatus = '准备处理中...';
      });
    }

    // 处理临时媒体文件，带进度
    // 为了在保存失败时回滚，记录本次从临时目录移动到永久目录的文件
    final List<String> movedToPermanentForThisSave = [];
    try {
      await _processTemporaryMediaFiles(
        onProgress: (p, status) {
          if (mounted) {
            setState(() {
              _saveProgress = p.clamp(0.0, 1.0);
              if (status != null) _saveStatus = status;
            });
          }
        },
        onFileMoved: (permanentPath) {
          // 仅记录位于应用永久媒体目录下的路径
          if (permanentPath.isNotEmpty) {
            movedToPermanentForThisSave.add(permanentPath);
          }
        },
      );
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.mediaProcessFailed(e.toString())),
            backgroundColor: Colors.orange,
            duration: AppConstants.snackBarDurationError,
          ),
        );
      }
    }

    // 获取纯文本内容
    String plainTextContent = '';
    String deltaJson = '';

    try {
      plainTextContent = _controller.document.toPlainText().trim();
      logDebug('获取到纯文本内容: ${plainTextContent.length} 字符');

      // 使用内存安全的方法获取富文本内容
      deltaJson = await _getDocumentContentSafely();

      logDebug('富文本JSON长度: ${deltaJson.length}');
      logDebug(
        '富文本JSON内容示例: ${deltaJson.substring(0, min(100, deltaJson.length))}...',
      );
    } catch (e) {
      logDebug('获取文档内容失败: $e');
      // 显示错误但继续尝试保存
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.documentLoadFailed),
            backgroundColor: Colors.orange,
            duration: AppConstants.snackBarDurationError,
          ),
        );
      }

      // 尝试获取内容
      try {
        plainTextContent = _controller.document.toPlainText().trim();
        if (plainTextContent.isEmpty) {
          plainTextContent = widget.initialContent; // 回退到初始内容
        }
        // 不设置deltaJson，这样将不会保存富文本格式
      } catch (_) {
        plainTextContent = widget.initialContent; // 回退到初始内容
      }
    }

    final now = DateTime.now().toIso8601String();

    // 获取当前时间段
    final String currentDayPeriodKey =
        TimeUtils.getCurrentDayPeriodKey(); // 使用 Key

    // 构建笔记对象
    final quote = Quote(
      id: widget.initialQuote?.id ?? const Uuid().v4(),
      content: plainTextContent,
      date: widget.initialQuote?.date ?? now,
      aiAnalysis: widget.initialQuote?.aiAnalysis,
      source: _formatSource(_authorController.text, _workController.text),
      sourceAuthor: _authorController.text,
      sourceWork: _workController.text,
      tagIds: _selectedTagIds,
      sentiment: widget.initialQuote?.sentiment,
      keywords: widget.initialQuote?.keywords,
      summary: widget.initialQuote?.summary,
      categoryId: widget.initialQuote?.categoryId,
      colorHex: _selectedColorHex,
      location: _showLocation ? _location : null,
      latitude: _showLocation ? _latitude : null,
      longitude: _showLocation ? _longitude : null,
      weather: _showWeather ? _weather : null,
      temperature: _showWeather ? _temperature : null,
      deltaContent: deltaJson,
      editSource: 'fullscreen',
      dayPeriod:
          widget.initialQuote?.dayPeriod ?? currentDayPeriodKey, // 保存 Key
    );

    try {
      logDebug('保存笔记: ID=${quote.id}, 是否为更新模式=${widget.initialQuote != null}');
      logDebug(
        '笔记内容长度: ${quote.content.length}, 富文本长度: ${quote.deltaContent?.length ?? 0}',
      );

      if (mounted) {
        setState(() {
          _saveStatus = '写入数据库...';
          _saveProgress = _saveProgress < 0.9 ? 0.9 : _saveProgress;
        });
      }

      if (widget.initialQuote != null && widget.initialQuote?.id != null) {
        // 只有当initialQuote存在且有ID时，才更新现有笔记
        logDebug('更新现有笔记，ID: ${quote.id}');
        await db.updateQuote(quote);
        _didSaveSuccessfully = true; // 标记保存成功，避免会话级清理
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).noteSaved),
              duration: AppConstants.snackBarDurationImportant,
            ),
          );
          // 成功更新后，关闭页面并返回
          Navigator.of(context).pop(true); // 返回true表示更新成功
        }
      } else {
        // 添加新笔记（初始Quote为null或无ID时）
        logDebug('添加新笔记');
        await db.addQuote(quote);
        _didSaveSuccessfully = true; // 标记保存成功，避免会话级清理
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).noteSaved),
              duration: AppConstants.snackBarDurationImportant,
            ),
          );
          // 成功添加后，关闭页面并返回
          Navigator.of(context).pop(true); // 返回true表示保存成功
        }
      }
    } catch (e) {
      // 数据库保存失败，回滚本次移动到永久目录的媒体文件，避免产生孤儿
      try {
        for (final p in movedToPermanentForThisSave) {
          final f = File(p);
          if (await f.exists()) {
            await f.delete();
            logDebug('因保存失败，回滚删除永久媒体文件: $p');
          }
        }
      } catch (rollbackErr) {
        logDebug('保存失败后的媒体回滚删除出错: $rollbackErr');
      }
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.saveFailed(e.toString())),
            backgroundColor: Colors.red,
            duration: AppConstants.snackBarDurationError,
          ),
        );
      }
    } finally {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        setState(() {
          _saveProgress = 1.0;
          _saveStatus = l10n.saveComplete;
        });
        Future.delayed(const Duration(milliseconds: 320), () {
          if (mounted) {
            setState(() {
              _isSaving = false;
            });
          }
        });
      }
    }
  }

  // 格式化来源（从作者和作品）
  String _formatSource(String author, String work) {
    if (author.isEmpty && work.isEmpty) {
      return '';
    }

    String result = '';
    if (author.isNotEmpty) {
      result += '——$author';
    }

    if (work.isNotEmpty) {
      if (result.isNotEmpty) {
        result += ' ';
      } else {
        result += '——';
      }
      result += '《$work》';
    }

    return result;
  }

  // 统一使用 IconUtils 渲染标签图标，确保 Emoji 与系统图标显示一致
  Widget _tagAvatarSmall(String? iconName) {
    if (IconUtils.isEmoji(iconName)) {
      return Text(
        IconUtils.getDisplayIcon(iconName),
        style: const TextStyle(fontSize: 16),
      );
    }
    return Icon(IconUtils.getIconData(iconName), size: 16);
  }

  // 自定义颜色选择器
  Future<void> _showCustomColorPicker(BuildContext context) async {
    final Color initialColor = _selectedColorHex != null
        ? Color(
            int.parse(_selectedColorHex!.substring(1), radix: 16) | 0xFF000000,
          )
        : Colors.transparent;

    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    // 预设颜色列表 - 更现代的轻柔色调
    final List<Color> presetColors = [
      Colors.transparent, // 透明/无
      const Color(0xFFF9E4E4), // 轻红色
      const Color(0xFFFFF0E1), // 轻橙色
      const Color(0xFFFFFBE5), // 轻黄色
      const Color(0xFFE8F5E9), // 轻绿色
      const Color(0xFFE1F5FE), // 轻蓝色
      const Color(0xFFF3E5F5), // 轻紫色
      const Color(0xFFFCE4EC), // 轻粉色

      const Color(0xFFEF9A9A), // 红色
      const Color(0xFFFFE0B2), // 橙色
      const Color(0xFFFFF9C4), // 黄色
      const Color(0xFFC8E6C9), // 绿色
      const Color(0xFFBBDEFB), // 蓝色
      const Color(0xFFE1BEE7), // 紫色
      const Color(0xFFF8BBD0), // 粉色

      const Color(0xFFEF9A9A), // 深红色
      const Color(0xFFFFCC80), // 深橙色
      const Color(0xFFFFF59D), // 深黄色
      const Color(0xFFA5D6A7), // 深绿色
      const Color(0xFF90CAF9), // 深蓝色
      const Color(0xFFCE93D8), // 深紫色
      const Color(0xFFF48FB1), // 深粉色
    ];

    final Color? result = await showDialog<Color>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context).selectCardColor),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 预设颜色网格
              Container(
                width: 280,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 8),
                      child: Text(
                        AppLocalizations.of(context).presetColors,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      alignment: WrapAlignment.start,
                      children: presetColors.map((color) {
                        String? colorHex;
                        if (color != Colors.transparent) {
                          colorHex =
                              '#${color.toARGB32().toRadixString(16).substring(2)}';
                        }

                        final bool isSelected = color == Colors.transparent
                            ? _selectedColorHex == null
                            : _selectedColorHex == colorHex;

                        return GestureDetector(
                          onTap: () {
                            Navigator.of(context).pop(color);
                          },
                          child: Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(21),
                              border: Border.all(
                                color: isSelected
                                    ? colorScheme.primary
                                    : color == Colors.transparent
                                        ? Colors.grey
                                            .applyOpacity(0.5) // MODIFIED
                                        : Colors.transparent,
                                width: 2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.applyOpacity(
                                    0.05,
                                  ), // MODIFIED
                                  spreadRadius: 1,
                                  blurRadius: 3,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                            child: Center(
                              child: isSelected
                                  ? Icon(
                                      Icons.check_circle,
                                      color: color == Colors.transparent ||
                                              color.computeLuminance() > 0.7
                                          ? colorScheme.primary
                                          : Colors.white,
                                      size: 24,
                                    )
                                  : color == Colors.transparent
                                      ? const Icon(
                                          Icons.block,
                                          color: Colors.grey,
                                          size: 18,
                                        )
                                      : null,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // 高级颜色选择按钮
              OutlinedButton.icon(
                icon: const Icon(Icons.color_lens),
                label: Text(AppLocalizations.of(context).customColor),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () async {
                  Navigator.pop(context); // 关闭当前对话框

                  // 打开高级颜色选择器
                  final Color? advancedColor = await showDialog<Color>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text(AppLocalizations.of(context).customColor),
                      content: SingleChildScrollView(
                        child: ColorPicker(
                          color: initialColor != Colors.transparent
                              ? initialColor
                              : const Color(0xFFE1F5FE), // 默认蓝色
                          onColorChanged: (color) {},
                          width: 40,
                          height: 40,
                          spacing: 10,
                          runSpacing: 10,
                          borderRadius: 20,
                          wheelDiameter: 200,
                          enableShadesSelection: true,
                          pickersEnabled: const {
                            ColorPickerType.primary: true,
                            ColorPickerType.accent: false,
                            ColorPickerType.wheel: true,
                          },
                        ),
                      ),
                      actions: <Widget>[
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text(AppLocalizations.of(context).cancel),
                        ),
                        FilledButton(
                          onPressed: () =>
                              Navigator.of(context).pop(initialColor),
                          child: Text(AppLocalizations.of(context).select),
                        ),
                      ],
                    ),
                  );

                  if (advancedColor != null && mounted) {
                    // 优化：合并所有状态更新为单次 setState 调用
                    setState(() {
                      _selectedColorHex = advancedColor == Colors.transparent
                          ? null
                          : '#${advancedColor.toARGB32().toRadixString(16).substring(2)}';
                    });
                  }
                },
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(AppLocalizations.of(context).cancel),
          ),
        ],
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );

    if (result != null) {
      // 优化：合并所有状态更新为单次 setState 调用
      setState(() {
        _selectedColorHex = result == Colors.transparent
            ? null
            : '#${result.toARGB32().toRadixString(16).substring(2)}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) {
          return;
        }
        // 有未保存的内容，提示用户
        final hasUnsavedChanges = _hasUnsavedChanges();
        if (!hasUnsavedChanges) {
          if (context.mounted) {
            Navigator.pop(context);
          }
          return;
        }

        final shouldDiscard = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(l10n.unsavedChangesTitle),
            content: Text(l10n.unsavedChangesDesc),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l10n.continueEditing),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(
                  l10n.discardChanges,
                  style: TextStyle(color: Colors.red.shade400),
                ),
              ),
            ],
          ),
        );

        if (shouldDiscard ?? false) {
          if (context.mounted) {
            Navigator.pop(context);
          }
        }
      },
      child: Scaffold(
        backgroundColor: theme.colorScheme.surface,
        appBar: AppBar(
          title: const SizedBox.shrink(),
          actions: [
            IconButton(
              key: _metadataButtonKey, // 功能引导 key
              icon: const Icon(Icons.edit_note),
              tooltip: l10n.editMetadataShort,
              onPressed: () => _showMetadataDialog(context),
            ),
            IconButton(
              icon: const Icon(Icons.auto_awesome),
              tooltip: l10n.aiAssistantLabel,
              onPressed: () => _showAIOptions(context),
            ),
            IconButton(
              icon: const Icon(Icons.save),
              tooltip: l10n.save,
              onPressed: () async {
                try {
                  await pauseAllMediaPlayers();
                } catch (_) {}
                await _saveContent();
              },
            ),
          ],
          automaticallyImplyLeading: true,
        ),
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  UnifiedQuillToolbar(
                    key: _toolbarGuideKey, // 新增：用于气泡定位
                    controller: _controller,
                    onMediaImported: (String filePath) {
                      _sessionImportedMedia.add(filePath);
                    },
                  ),
                  if (_selectedTagIds.isNotEmpty ||
                      _selectedColorHex != null ||
                      _showLocation ||
                      _showWeather)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        border: Border(
                          bottom: BorderSide(
                            color:
                                theme.colorScheme.outlineVariant.applyOpacity(
                              0.1,
                            ),
                            width: 1,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          if (_selectedTagIds.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: Chip(
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                label: Text(
                                  l10n.tagsCount(_selectedTagIds.length),
                                ),
                                avatar: const Icon(Icons.tag, size: 16),
                              ),
                            ),
                          if (_selectedColorHex != null)
                            Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: Container(
                                width: 16,
                                height: 16,
                                decoration: BoxDecoration(
                                  color: Color(
                                    int.parse(
                                          _selectedColorHex!.substring(1),
                                          radix: 16,
                                        ) |
                                        0xFF000000,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color:
                                        theme.colorScheme.outline.applyOpacity(
                                      0.2,
                                    ),
                                    width: 1,
                                  ),
                                ),
                                key: ValueKey(
                                  'color-indicator-$_selectedColorHex',
                                ),
                              ),
                            ),
                          if (_showLocation &&
                              (_location != null ||
                                  (_latitude != null && _longitude != null)))
                            Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: Icon(
                                Icons.location_on,
                                size: 16,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          if (_showWeather && _weather != null)
                            Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: Icon(
                                _getWeatherIcon(_weather!),
                                size: 16,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          const Spacer(),
                          TextButton(
                            onPressed: () => _showMetadataDialog(context),
                            child: const Text(
                              '编辑元数据',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: Container(
                      color: theme.colorScheme.surface,
                      padding: const EdgeInsets.all(16),
                      child: quill.QuillEditor(
                        controller: _controller,
                        scrollController: ScrollController(),
                        focusNode: FocusNode(),
                        config: quill.QuillEditorConfig(
                          embedBuilders: kIsWeb
                              ? FlutterQuillEmbeds.editorWebBuilders()
                              : QuillEditorExtensions.getEmbedBuilders(
                                  optimizedImages: false,
                                ),
                          placeholder: AppLocalizations.of(context)
                              .fullscreenEditorPlaceholder,
                          padding: const EdgeInsets.all(16),
                          autoFocus: false,
                          expands: false,
                          scrollable: true,
                          enableInteractiveSelection: true,
                          enableSelectionToolbar: true,
                          showCursor: true,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (_isSaving)
                Positioned.fill(
                  child: Container(
                    color: theme.colorScheme.surface.withValues(alpha: 0.72),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 300),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 24,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surface,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.08),
                                blurRadius: 18,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      value: _saveProgress >= 0.99
                                          ? 1.0
                                          : (_saveProgress <= 0
                                              ? null
                                              : _saveProgress),
                                      strokeWidth: 3,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    _saveProgress < 1.0 ? '正在保存' : '完成',
                                    style: theme.textTheme.titleMedium,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              LinearProgressIndicator(
                                value: _saveProgress.clamp(0.0, 1.0),
                                minHeight: 6,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              const SizedBox(height: 12),
                              if (_saveStatus != null)
                                Text(
                                  _saveStatus!,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              const SizedBox(height: 8),
                              Text(
                                '${(_saveProgress * 100).clamp(0, 100).toStringAsFixed(0)}%',
                                style: theme.textTheme.labelMedium,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // 显示元数据编辑弹窗
  Future<void> _showMetadataDialog(BuildContext context) async {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.6,
              minChildSize: 0.4,
              maxChildSize: 0.95,
              expand: false,
              builder: (context, scrollController) {
                return Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color:
                              theme.colorScheme.onSurfaceVariant.applyOpacity(
                            // MODIFIED
                            0.4,
                          ),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                      child: Row(
                        children: [
                          Text(
                            AppLocalizations.of(context).editMetadata,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            icon: const Icon(Icons.check),
                            label: Text(AppLocalizations.of(context).done),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        children: [
                          // 作者/作品输入
                          Text(
                            l10n.sourceInfo,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _authorController,
                                  decoration: InputDecoration(
                                    hintText: AppLocalizations.of(
                                      context,
                                    ).authorPerson,
                                    prefixIcon: const Icon(
                                      Icons.person_outline,
                                    ),
                                    border: const OutlineInputBorder(),
                                    contentPadding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                      horizontal: 12,
                                    ),
                                    isDense: true,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: _workController,
                                  decoration: InputDecoration(
                                    hintText: AppLocalizations.of(
                                      context,
                                    ).workSource,
                                    prefixIcon: const Icon(
                                      Icons.menu_book_outlined,
                                    ),
                                    border: const OutlineInputBorder(),
                                    contentPadding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                      horizontal: 12,
                                    ),
                                    isDense: true,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),

                          // 标签选择
                          Row(
                            children: [
                              Text(
                                l10n.tagsLabel,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                l10n.selectedTagsCount(_selectedTagIds.length),
                                style: TextStyle(
                                  fontSize: 14,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Container(
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: theme.colorScheme.outlineVariant,
                              ),
                            ),
                            child: ExpansionTile(
                              title: Text(
                                AppLocalizations.of(context).selectTags,
                              ),
                              leading: const Icon(Icons.sell_outlined),
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.all(
                                  Radius.circular(12),
                                ),
                              ),
                              tilePadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 0,
                              ),
                              childrenPadding: const EdgeInsets.fromLTRB(
                                16,
                                0,
                                16,
                                16,
                              ),
                              children: [
                                // 搜索框
                                TextField(
                                  controller: _tagSearchController,
                                  decoration: InputDecoration(
                                    hintText: AppLocalizations.of(
                                      context,
                                    ).searchTags,
                                    prefixIcon: const Icon(Icons.search),
                                    border: const OutlineInputBorder(),
                                    contentPadding: const EdgeInsets.symmetric(
                                      vertical: 8.0,
                                      horizontal: 12.0,
                                    ),
                                  ),
                                  onChanged: (value) {
                                    setState(() {
                                      _tagSearchQuery = value.toLowerCase();
                                    });
                                  },
                                ),
                                const SizedBox(height: 8), // 标签列表
                                Container(
                                  constraints: const BoxConstraints(
                                    maxHeight: 200,
                                  ),
                                  child: SingleChildScrollView(
                                    child: Builder(
                                      builder: (context) {
                                        // 过滤标签
                                        final filteredTags =
                                            widget.allTags!.where((tag) {
                                          return _tagSearchQuery.isEmpty ||
                                              tag.name.toLowerCase().contains(
                                                    _tagSearchQuery,
                                                  );
                                        }).toList();

                                        if (filteredTags.isEmpty) {
                                          return Center(
                                            child: Padding(
                                              padding: const EdgeInsets.all(
                                                16.0,
                                              ),
                                              child: Text(
                                                AppLocalizations.of(
                                                  context,
                                                ).noMatchingTags,
                                              ),
                                            ),
                                          );
                                        }

                                        return Wrap(
                                          spacing: 8.0,
                                          runSpacing: 8.0,
                                          children: filteredTags.map((tag) {
                                            final selected = _selectedTagIds
                                                .contains(tag.id);
                                            return FilterChip(
                                              selected: selected,
                                              label: Text(tag.name),
                                              avatar: _tagAvatarSmall(
                                                tag.iconName,
                                              ),
                                              onSelected: (bool value) {
                                                setState(() {
                                                  if (value) {
                                                    _selectedTagIds.add(tag.id);
                                                  } else {
                                                    _selectedTagIds.remove(
                                                      tag.id,
                                                    );
                                                  }
                                                });
                                              },
                                              selectedColor: theme
                                                  .colorScheme.primaryContainer,
                                              checkmarkColor:
                                                  theme.colorScheme.primary,
                                            );
                                          }).toList(),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // 显示已选标签
                          if (_selectedTagIds.isNotEmpty)
                            Container(
                              margin: const EdgeInsets.only(top: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color:
                                    theme.colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    l10n.selectedTags,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8.0,
                                    runSpacing: 4.0,
                                    children: _selectedTagIds.map((tagId) {
                                      final tag = widget.allTags!.firstWhere(
                                        (t) => t.id == tagId,
                                        orElse: () => NoteCategory(
                                          id: tagId,
                                          name: l10n.unknownTagWithId(
                                            tagId.substring(
                                              0,
                                              min(4, tagId.length),
                                            ),
                                          ),
                                          iconName: 'help_outline',
                                        ),
                                      );
                                      return Chip(
                                        label: Text(tag.name),
                                        avatar: _buildTagIcon(tag),
                                        onDeleted: () {
                                          setState(() {
                                            _selectedTagIds.remove(tagId);
                                          });
                                        },
                                      );
                                    }).toList(),
                                  ),
                                ],
                              ),
                            ),
                          const SizedBox(height: 24),

                          // 颜色选择
                          Text(
                            l10n.colorLabel,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: theme.colorScheme.outlineVariant,
                              ),
                            ),
                            child: ListTile(
                              title: Text(l10n.selectCardColorLabel),
                              subtitle: Text(
                                _selectedColorHex == null
                                    ? l10n.noColor
                                    : l10n.colorSet,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              leading: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: _selectedColorHex != null
                                      ? Color(
                                          int.parse(
                                                _selectedColorHex!.substring(1),
                                                radix: 16,
                                              ) |
                                              0xFF000000,
                                        )
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: _selectedColorHex == null
                                        ? theme.colorScheme.outline
                                        : Colors.transparent,
                                  ),
                                ),
                                child: _selectedColorHex == null
                                    ? Icon(
                                        Icons.block,
                                        size: 16,
                                        color: theme.colorScheme.outline,
                                      )
                                    : null,
                              ),
                              trailing: const Icon(
                                Icons.arrow_forward_ios,
                                size: 16,
                              ),
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.all(
                                  Radius.circular(12),
                                ),
                              ),
                              onTap: () async {
                                // 使用async/await确保颜色选择完成后刷新UI
                                if (!context.mounted) return;
                                await _showCustomColorPicker(context);
                                // 强制刷新对话框UI以显示新选的颜色
                                if (mounted) {
                                  setState(() {});
                                }
                              },
                            ),
                          ),
                          const SizedBox(height: 24),

                          // 位置和天气
                          Row(
                            children: [
                              Text(
                                l10n.locationAndWeather,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Spacer(),
                              // 编辑模式提示
                              if (widget.initialQuote != null)
                                Text(
                                  l10n.recordedOnFirstSave,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // 位置和天气选择容器
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: theme.colorScheme.outlineVariant,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // 位置和天气开关
                                Row(
                                  children: [
                                    // 位置信息按钮
                                    Expanded(
                                      child: Stack(
                                        children: [
                                          FilterChip(
                                            avatar: Icon(
                                              Icons.location_on,
                                              color: _showLocation
                                                  ? theme.colorScheme.primary
                                                  : Colors.grey,
                                              size: 18,
                                            ),
                                            label: Text(l10n.locationLabel),
                                            selected: _showLocation,
                                            onSelected: (value) async {
                                              // 编辑模式下统一弹对话框（只有已保存的笔记才是编辑模式）
                                              if (widget.initialQuote?.id !=
                                                  null) {
                                                await _showLocationDialogInEditor(
                                                  context,
                                                  theme,
                                                );
                                                return;
                                              }
                                              // 新建模式
                                              if (value &&
                                                  _location == null &&
                                                  _latitude == null) {
                                                _fetchLocationWeather();
                                              }
                                              setState(() {
                                                _showLocation = value;
                                              });
                                            },
                                            selectedColor: theme
                                                .colorScheme.primaryContainer,
                                          ),
                                          // 小红点：有坐标但没地址时提示可更新（仅已保存笔记）
                                          if (widget.initialQuote?.id != null &&
                                              _originalLocation == null &&
                                              _originalLatitude != null &&
                                              _originalLongitude != null)
                                            Positioned(
                                              right: 0,
                                              top: 0,
                                              child: Container(
                                                width: 8,
                                                height: 8,
                                                decoration: BoxDecoration(
                                                  color:
                                                      theme.colorScheme.error,
                                                  shape: BoxShape.circle,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    // 天气信息按钮
                                    Expanded(
                                      child: FilterChip(
                                        avatar: Icon(
                                          _weather != null
                                              ? _getWeatherIcon(_weather!)
                                              : Icons.cloud,
                                          color: _showWeather
                                              ? theme.colorScheme.primary
                                              : Colors.grey,
                                          size: 18,
                                        ),
                                        label: Text(l10n.weatherLabel),
                                        selected: _showWeather,
                                        onSelected: (value) async {
                                          // 编辑模式下统一弹对话框（只有已保存的笔记才是编辑模式）
                                          if (widget.initialQuote?.id != null) {
                                            await _showWeatherDialogInEditor(
                                              context,
                                              theme,
                                            );
                                            return;
                                          }
                                          // 新建模式
                                          if (value && _weather == null) {
                                            _fetchLocationWeather();
                                          }
                                          setState(() {
                                            _showWeather = value;
                                          });
                                        },
                                        selectedColor:
                                            theme.colorScheme.primaryContainer,
                                      ),
                                    ),
                                    // 刷新按钮 - 仅新建模式显示（未保存的笔记）
                                    if (widget.initialQuote?.id == null)
                                      IconButton(
                                        icon: const Icon(
                                          Icons.refresh,
                                          size: 20,
                                        ),
                                        tooltip: l10n.refreshLocationWeather,
                                        onPressed: () {
                                          _fetchLocationWeather();
                                          setState(() {});
                                        },
                                      ),
                                  ],
                                ),

                                // 显示位置和天气信息
                                if (_location != null ||
                                    _latitude != null ||
                                    _weather != null) ...[
                                  const SizedBox(height: 12),
                                  const Divider(height: 1),
                                  const SizedBox(height: 12),
                                  if (_location != null || _latitude != null)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.location_on,
                                            size: 16,
                                            color: theme.colorScheme.primary,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              // 优先显示地址，没有地址时显示坐标
                                              _location ??
                                                  ((_latitude != null &&
                                                          _longitude != null)
                                                      ? '📍 ${LocationService.formatCoordinates(_latitude, _longitude)}'
                                                      : l10n
                                                          .gettingLocationHint),
                                              style: TextStyle(
                                                fontSize: 14,
                                                color: theme.colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  if (_weather != null)
                                    Row(
                                      children: [
                                        Icon(
                                          _getWeatherIcon(_weather!),
                                          size: 16,
                                          color: theme.colorScheme.primary,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          WeatherService
                                              .getLocalizedWeatherDescription(
                                            AppLocalizations.of(context),
                                            _weather!,
                                          ),
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: theme
                                                .colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                        if (_temperature != null)
                                          Text(
                                            ' $_temperature',
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: theme
                                                  .colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                      ],
                                    ),
                                ],

                                // 编辑模式下无数据时的提示（只有真正编辑已保存的笔记时才显示）
                                // initialQuote.id 不为空表示是已保存的笔记
                                if (widget.initialQuote?.id != null &&
                                    _originalLocation == null &&
                                    _originalLatitude == null &&
                                    _originalWeather == null) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    '此笔记首次保存时未记录位置和天气信息',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: theme.colorScheme.onSurfaceVariant,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );

    // 优化：对话框关闭后使用单次 setState 更新UI
    if (mounted) {
      setState(() {
        // 强制刷新所有状态
      });
    }
  }

  Widget _buildTagIcon(NoteCategory tag) {
    return _tagAvatarSmall(tag.iconName);
  }

  // 显示AI选项菜单
  void _showAIOptions(BuildContext context) {
    final theme = Theme.of(context);

    showModalBottomSheet(
      context: context,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(12), // 使用圆角
        ),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: SingleChildScrollView(
            child: IntrinsicHeight(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        Icon(
                          Icons.auto_awesome,
                          size: 20,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'AI助手',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: theme.colorScheme.outline),
                  ListTile(
                    leading: const Icon(Icons.text_fields),
                    title: Text(
                      AppLocalizations.of(context).smartAnalyzeSource,
                    ),
                    subtitle: Text(
                      AppLocalizations.of(context).smartAnalyzeSourceDesc,
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _analyzeSource();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.brush),
                    title: Text(AppLocalizations.of(context).polishText),
                    subtitle: Text(AppLocalizations.of(context).polishTextDesc),
                    onTap: () {
                      Navigator.pop(context);
                      _polishText();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.add_circle_outline),
                    title: Text(AppLocalizations.of(context).continueWriting),
                    subtitle: Text(
                      AppLocalizations.of(context).continueWritingDesc,
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _continueText();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.analytics),
                    title: Text(AppLocalizations.of(context).deepAnalysis),
                    subtitle: Text(
                      AppLocalizations.of(context).deepAnalysisDesc,
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _analyzeContent();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.chat),
                    title: Text(AppLocalizations.of(context).askNote),
                    subtitle: Text(AppLocalizations.of(context).askNoteDesc),
                    onTap: () {
                      Navigator.pop(context);
                      _askNoteQuestion();
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // 分析来源
  Future<void> _analyzeSource() async {
    final plainText = _controller.document.toPlainText().trim();
    if (plainText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).pleaseEnterContent),
          duration: AppConstants.snackBarDurationError,
        ),
      );
      return;
    }

    final aiService = Provider.of<AIService>(context, listen: false);

    try {
      // 显示加载对话框
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(AppLocalizations.of(context).analyzing),
              ],
            ),
          );
        },
      );

      // 调用AI分析来源
      final result = await aiService.analyzeSource(plainText);

      // 确保组件仍然挂载在widget树上
      if (!mounted) return;

      // 关闭加载对话框
      Navigator.of(context).pop();

      // 解析JSON结果
      try {
        final Map<String, dynamic> sourceData = json.decode(result);

        String? author = sourceData['author'] as String?;
        String? work = sourceData['work'] as String?;
        String confidence = sourceData['confidence'] as String? ?? '低';
        String explanation = sourceData['explanation'] as String? ?? '';

        // 显示结果对话框
        if (mounted) {
          final l10n = AppLocalizations.of(context);
          showDialog(
            context: context,
            builder: (dialogContext) {
              return AlertDialog(
                title: Text(l10n.analysisResultWithConfidence(confidence)),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (author != null && author.isNotEmpty) ...[
                      Text(
                        l10n.possibleAuthor,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(author),
                      const SizedBox(height: 8),
                    ],
                    if (work != null && work.isNotEmpty) ...[
                      Text(
                        l10n.possibleWork,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(work),
                      const SizedBox(height: 8),
                    ],
                    if (explanation.isNotEmpty) ...[
                      Text(
                        l10n.analysisExplanation,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(explanation, style: const TextStyle(fontSize: 13)),
                    ],
                    if ((author == null || author.isEmpty) &&
                        (work == null || work.isEmpty))
                      Text(l10n.noAuthorWorkIdentified),
                  ],
                ),
                actions: [
                  if ((author != null && author.isNotEmpty) ||
                      (work != null && work.isNotEmpty))
                    TextButton(
                      child: Text(l10n.applyAnalysisResult),
                      onPressed: () {
                        setState(() {
                          if (author != null && author.isNotEmpty) {
                            _authorController.text = author;
                          }
                          if (work != null && work.isNotEmpty) {
                            _workController.text = work;
                          }
                        });
                        Navigator.of(dialogContext).pop();
                      },
                    ),
                  TextButton(
                    child: Text(l10n.close),
                    onPressed: () {
                      Navigator.of(dialogContext).pop();
                    },
                  ),
                ],
              );
            },
          );
        }
      } catch (e) {
        if (mounted) {
          final l10n = AppLocalizations.of(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.parseResultFailedWithError(e.toString())),
              duration: AppConstants.snackBarDurationError,
            ),
          );
        }
      }
    } catch (e) {
      // 确保组件仍然挂载在widget树上
      if (!mounted) return;

      // 关闭加载对话框
      Navigator.of(context).pop();

      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.analysisFailedWithError(e.toString())),
            duration: AppConstants.snackBarDurationError,
          ),
        );
      }
    }
  }

  // 润色文本 (使用流式传输)
  Future<void> _polishText() async {
    final plainText = _controller.document.toPlainText().trim();
    if (plainText.isEmpty) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.pleaseInputContent),
            duration: AppConstants.snackBarDurationError,
          ),
        );
      }
      return;
    }

    final aiService = Provider.of<AIService>(context, listen: false);

    // 显示流式文本对话框
    // 注意：这里await showDialog会等待对话框关闭并返回结果
    final l10n = AppLocalizations.of(context);
    String? finalResult = await showDialog<String?>(
      context: context,
      barrierDismissible: false, // 不允许点击外部关闭
      builder: (dialogContext) {
        return StreamingTextDialog(
          title: l10n.polishingText,
          textStream: aiService.streamPolishText(plainText), // 调用流式方法，使用正确的参数名
          applyButtonText: '应用更改', // 应用按钮文本
          onApply: (fullText) {
            // 用户点击"应用更改"时调用
            // 返回结果给showDialog的await调用
            Navigator.of(dialogContext).pop(fullText); // 通过pop将结果返回
          },
          onCancel: () {
            // 用户点击"取消"时调用
            Navigator.of(dialogContext).pop(null); // 返回null表示取消
          },
          // StreamingTextDialog 内部处理 onError 和 onComplete
        );
      },
    );

    // 如果showDialog返回了结果 (用户点击了应用)，更新编辑器内容
    if (finalResult != null && mounted) {
      setState(() {
        _controller.document = quill.Document.fromJson([
          {"insert": finalResult},
        ]);
      });
    }
  }

  // 续写文本 (使用流式传输)
  Future<void> _continueText() async {
    final plainText = _controller.document.toPlainText().trim();
    if (plainText.isEmpty) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.pleaseInputContent),
            duration: AppConstants.snackBarDurationError,
          ),
        );
      }
      return;
    }

    final aiService = Provider.of<AIService>(context, listen: false);

    // 显示流式文本对话框
    final l10n = AppLocalizations.of(context);
    String? finalResult = await showDialog<String?>(
      context: context,
      barrierDismissible: false, // 不允许点击外部关闭
      builder: (dialogContext) {
        return StreamingTextDialog(
          title: l10n.continuingText,
          textStream: aiService.streamContinueText(
            plainText,
          ), // 调用流式方法，使用正确的参数名
          applyButtonText: '附加到原文', // 应用按钮文本
          onApply: (fullText) {
            // 用户点击"附加到原文"时调用
            // 返回结果给showDialog的await调用
            Navigator.of(dialogContext).pop(fullText); // 通过pop将结果返回
          },
          onCancel: () {
            // 用户点击"取消"时调用
            Navigator.of(dialogContext).pop(null); // 返回null表示取消
          },
          // StreamingTextDialog 内部处理 onError 和 onComplete
        );
      },
    );

    // 如果showDialog返回了结果 (用户点击了应用)，附加到编辑器内容
    if (finalResult != null && mounted) {
      final int length = _controller.document.length;
      // 在文档末尾插入续写内容，确保在最后一行
      _controller.document.insert(length, '\n\n$finalResult');
      // 移动光标到文档末尾
      _controller.updateSelection(
        TextSelection.collapsed(offset: _controller.document.length),
        quill.ChangeSource.local,
      );
    }
  }

  // 深度分析内容 (使用流式传输)
  Future<void> _analyzeContent() async {
    final plainText = _controller.document.toPlainText().trim();
    if (plainText.isEmpty) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.pleaseInputContent),
            duration: AppConstants.snackBarDurationError,
          ),
        );
      }
      return;
    }

    final aiService = Provider.of<AIService>(context, listen: false);

    // 显示流式文本对话框
    // 对于分析功能，我们只关心对话框的显示，不需要await返回值来更新编辑器
    final l10n = AppLocalizations.of(context);
    await showDialog<void>(
      context: context,
      barrierDismissible: false, // 不允许点击外部关闭
      builder: (dialogContext) {
        // 创建临时Quote对象进行分析
        final quote = Quote(
          id: widget.initialQuote?.id ?? const Uuid().v4(),
          content: plainText,
          date: widget.initialQuote?.date ?? DateTime.now().toIso8601String(),
          location: _showLocation ? _location : null,
          weather: _showWeather ? _weather : null,
          temperature: _showWeather ? _temperature : null,
        );

        return StreamingTextDialog(
          title: l10n.analyzingNote,
          textStream: aiService.streamSummarizeNote(quote), // 调用流式方法，使用正确的参数名
          applyButtonText: l10n.copyResult, // 分析结果的应用按钮可以是复制
          onApply: (fullText) {
            // 用户点击"复制结果"时调用
            Clipboard.setData(ClipboardData(text: fullText)).then((_) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(l10n.analysisResultCopied),
                    duration: AppConstants.snackBarDurationImportant,
                  ),
                );
              }
            });
            Navigator.of(dialogContext).pop(); // 关闭对话框
          },
          onCancel: () {
            // 用户点击"关闭"时调用
            Navigator.of(dialogContext).pop();
          },
          isMarkdown: true, // 分析结果通常是Markdown格式
          // StreamingTextDialog 内部处理 onError 和 onComplete
        );
      },
    );
    // showDialog 返回后，如果用户点击了应用按钮，复制逻辑已经在onApply中处理了
    // 如果用户点击了取消或关闭对话框，这里不需要做额外处理
  }

  // 问笔记功能
  Future<void> _askNoteQuestion() async {
    final plainText = _controller.document.toPlainText().trim();
    if (plainText.isEmpty) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.pleaseInputContent),
          duration: AppConstants.snackBarDurationError,
        ),
      );
      return;
    }

    // 创建临时Quote对象用于问答
    final tempQuote = Quote(
      id: widget.initialQuote?.id ?? '',
      content: plainText,
      date: DateTime.now().toIso8601String(),
    );

    // 导航到聊天页面
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => NoteQAChatPage(quote: tempQuote)),
    );
  }

  /// 修复：处理临时媒体文件，增加事务安全性和错误恢复
  Future<void> _processTemporaryMediaFiles({
    void Function(double progress, String? status)? onProgress,
    void Function(String permanentPath)? onFileMoved,
  }) async {
    try {
      logDebug('开始处理临时媒体文件...');

      // 获取当前文档的Delta内容
      final deltaData = _controller.document.toDelta().toJson();
      // 修复：使用深拷贝确保备份数据完全独立，避免嵌套对象的意外修改
      final originalDeltaData = _deepCopy(deltaData) as List;
      bool hasChanges = false;
      final processedFiles = <String, String>{}; // 记录已处理的文件映射

      // 预扫描：统计需要处理的临时媒体文件
      final mediaEntries = <Map<String, dynamic>>[];
      for (final op in deltaData) {
        if (op.containsKey('insert')) {
          final insert = op['insert'];
          if (insert is Map) {
            if (insert.containsKey('image')) {
              mediaEntries.add({'ref': insert, 'key': 'image', 'type': '图片'});
            }
            if (insert.containsKey('video')) {
              mediaEntries.add({'ref': insert, 'key': 'video', 'type': '视频'});
            }
            if (insert.containsKey('custom')) {
              final custom = insert['custom'];
              if (custom is Map && custom.containsKey('audio')) {
                mediaEntries.add({'ref': custom, 'key': 'audio', 'type': '音频'});
              }
            }
          }
        }
      }
      final total = mediaEntries.length;
      var done = 0;
      if (total == 0) {
        onProgress?.call(1.0, '无需处理媒体文件');
      } else {
        onProgress?.call(0.0, '发现 $total 个媒体文件');
      }

      for (final entry in mediaEntries) {
        final ref = entry['ref'] as Map;
        final key = entry['key'] as String;
        final typeLabel = entry['type'] as String;
        final pathVal = ref[key] as String?;
        if (pathVal != null &&
            await TemporaryMediaService.isTemporaryFile(pathVal)) {
          final newPath = await _moveMediaFileSafely(
            pathVal,
            processedFiles,
            onFileProgress: (fileProg) {
              if (total > 0) {
                final overall = (done + fileProg) / total;
                onProgress?.call(overall, '复制$typeLabel ${done + 1}/$total');
              }
            },
          );
          if (newPath != null) {
            ref[key] = newPath;
            hasChanges = true;
            onFileMoved?.call(newPath);
          }
        }
        done++;
        if (total > 0) {
          onProgress?.call(done / total, '已处理 $done / $total');
        }
      }

      // 遍历Delta内容，查找临时媒体文件
      for (final op in deltaData) {
        if (op.containsKey('insert')) {
          final insert = op['insert'];
          if (insert is Map) {
            // 处理图片
            if (insert.containsKey('image')) {
              final imagePath = insert['image'] as String?;
              if (imagePath != null &&
                  await TemporaryMediaService.isTemporaryFile(imagePath)) {
                final permanentPath = await _moveMediaFileSafely(
                  imagePath,
                  processedFiles,
                );
                if (permanentPath != null) {
                  insert['image'] = permanentPath;
                  hasChanges = true;
                  logDebug('临时图片已移动: $imagePath -> $permanentPath');
                  onFileMoved?.call(permanentPath);
                }
              }
            }

            // 处理视频
            if (insert.containsKey('video')) {
              final videoPath = insert['video'] as String?;
              if (videoPath != null &&
                  await TemporaryMediaService.isTemporaryFile(videoPath)) {
                final permanentPath = await _moveMediaFileSafely(
                  videoPath,
                  processedFiles,
                );
                if (permanentPath != null) {
                  insert['video'] = permanentPath;
                  hasChanges = true;
                  logDebug('临时视频已移动: $videoPath -> $permanentPath');
                  onFileMoved?.call(permanentPath);
                }
              }
            }

            // 处理自定义嵌入（如音频）
            if (insert.containsKey('custom')) {
              final custom = insert['custom'];
              if (custom is Map && custom.containsKey('audio')) {
                final audioPath = custom['audio'] as String?;
                if (audioPath != null &&
                    await TemporaryMediaService.isTemporaryFile(audioPath)) {
                  final permanentPath = await _moveMediaFileSafely(
                    audioPath,
                    processedFiles,
                  );
                  if (permanentPath != null) {
                    custom['audio'] = permanentPath;
                    hasChanges = true;
                    logDebug('临时音频已移动: $audioPath -> $permanentPath');
                    onFileMoved?.call(permanentPath);
                  }
                }
              }
            }
          }
        }
      }

      // 只有在有变更时才更新编辑器内容
      if (hasChanges) {
        try {
          final newDocument = quill.Document.fromJson(deltaData);
          _controller.document = newDocument;
          logDebug('临时媒体文件处理完成，共处理 ${processedFiles.length} 个文件');
        } catch (e) {
          logDebug('更新编辑器内容失败，回滚到原始状态: $e');
          // 回滚到原始状态
          final rollbackDocument = quill.Document.fromJson(originalDeltaData);
          _controller.document = rollbackDocument;
          rethrow;
        }
      } else {
        logDebug('没有临时媒体文件需要处理');
      }
    } catch (e) {
      logDebug('处理临时媒体文件失败: $e');
      rethrow;
    }
  }

  /// 修复：安全移动媒体文件，避免重复处理
  Future<String?> _moveMediaFileSafely(
    String sourcePath,
    Map<String, String> processedFiles, {
    Function(double progress)? onFileProgress,
  }) async {
    try {
      // 检查是否已经处理过这个文件
      if (processedFiles.containsKey(sourcePath)) {
        return processedFiles[sourcePath];
      }

      final permanentPath = await TemporaryMediaService.moveToPermament(
        sourcePath,
        onProgress: onFileProgress,
        deleteSource: false,
      );
      if (permanentPath != null) {
        processedFiles[sourcePath] = permanentPath;
      }
      return permanentPath;
    } catch (e) {
      logDebug('移动媒体文件失败: $sourcePath, 错误: $e');
      return null;
    }
  }

  @override
  void dispose() {
    // 未保存退出时，清理本会话导入而未被引用的媒体文件
    _cleanupSessionImportedMediaIfUnsaved();
    // 清理临时媒体文件（异步执行，不阻塞dispose）
    _cleanupTemporaryMedia();

    // 释放QuillController
    _controller.dispose();

    // 释放TextEditingController
    _authorController.dispose();
    _workController.dispose();
    _tagSearchController.dispose();

    super.dispose();
  }

  /// 清理临时媒体文件
  Future<void> _cleanupTemporaryMedia() async {
    try {
      await TemporaryMediaService.cleanupAllTemporaryFiles();
      logDebug('临时媒体文件清理完成');
    } catch (e) {
      logDebug('清理临时媒体文件失败: $e');
    }
  }

  /// 会话级清理：未保存退出时删除本次导入且未被任何笔记引用的媒体
  Future<void> _cleanupSessionImportedMediaIfUnsaved() async {
    try {
      if (_didSaveSuccessfully || _sessionImportedMedia.isEmpty) return;
      for (final p in _sessionImportedMedia) {
        try {
          final refCount = await MediaReferenceService.getReferenceCount(p);
          if (refCount <= 0) {
            final deleted = await MediaFileService.deleteMediaFile(p);
            if (deleted) {
              logDebug('未保存退出，已删除未引用媒体文件: $p');
            }
          }
        } catch (e) {
          logDebug('清理会话媒体失败: $p, 错误: $e');
        }
      }
    } catch (e) {
      logDebug('执行会话级媒体清理出错: $e');
    }
  }
}
