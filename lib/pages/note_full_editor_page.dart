import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_quill_extensions/flutter_quill_extensions.dart';
import 'dart:convert';
import 'package:geolocator/geolocator.dart' show Position;
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
import '../widgets/source_analysis_result_dialog.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import '../utils/app_logger.dart';
import '../utils/string_utils.dart';
import 'note_qa_chat_page.dart'; // 添加问笔记聊天页面导入
import 'package:flutter/foundation.dart' show kIsWeb, compute;
import '../utils/device_memory_manager.dart';
import '../widgets/quill_enhanced_toolbar_unified.dart';
import '../widgets/ai_options_menu.dart';
import '../utils/quill_editor_extensions.dart'; // 导入自定义embedBuilders
import '../services/temporary_media_service.dart';
import '../widgets/media_player_widget.dart';
import '../constants/app_constants.dart';
import '../services/media_file_service.dart';
import '../services/media_reference_service.dart';
import '../services/draft_service.dart'; // 导入草稿服务
import '../utils/feature_guide_helper.dart';
import '../services/settings_service.dart';

part 'note_editor/editor_document_init.dart';
part 'note_editor/editor_save_and_draft.dart';
part 'note_editor/editor_location_dialogs.dart';
part 'note_editor/editor_location_fetch.dart';
part 'note_editor/editor_build.dart';
part 'note_editor/editor_color_and_media.dart';
part 'note_editor/editor_metadata_dialog.dart';
part 'note_editor/editor_metadata_location_section.dart';
part 'note_editor/editor_metadata_ai_section.dart';
part 'note_editor/editor_ai_features.dart';

class NoteFullEditorPage extends StatefulWidget {
  final String initialContent;
  final Quote? initialQuote;
  final List<NoteCategory>? allTags;
  final bool isRestoredDraft; // 新增：标记是否为恢复的草稿
  final String? restoredDraftId; // 新增：恢复草稿的原始ID

  const NoteFullEditorPage({
    super.key,
    required this.initialContent,
    this.initialQuote,
    this.allTags,
    this.isRestoredDraft = false, // 默认为 false
    this.restoredDraftId, // 恢复草稿的原始ID
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

  // 标记是否是从草稿恢复的
  late bool _isRestoredFromDraft;

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
  late String? _initialAiAnalysis;

  // 完整笔记数据（从数据库重新获取，确保字段完整）
  Quote? _fullInitialQuote;
  bool _isLoadingFullQuote = false;

  // AI 分析结果（可在元数据抽屉中查看/编辑）
  String? _currentAiAnalysis;

  // 草稿自动保存
  Timer? _draftSaveTimer;
  String? _draftStorageKey;
  bool _draftLoaded = false;

  void _updateState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  /// 在Isolate中解析JSON
  static dynamic _parseJsonInIsolate(String jsonString) {
    return jsonDecode(jsonString);
  }

  /// 在Isolate中编码JSON
  static String _encodeJsonInIsolate(dynamic data) {
    return jsonEncode(data);
  }

  @override
  void initState() {
    super.initState();

    _draftStorageKey = _buildDraftStorageKey();

    _isRestoredFromDraft = widget.isRestoredDraft;

    // 如果是编辑模式，异步获取完整笔记数据
    if (widget.initialQuote != null && widget.initialQuote!.id != null) {
      _isLoadingFullQuote = true;
      _fullInitialQuote = widget.initialQuote; // 先使用传入的数据
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _fetchFullQuote();
      });
    }

    // 先初始化为基本控制器，避免阻塞UI
    _controller = quill.QuillController.basic();
    _attachDraftListener();

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

    // AI 分析结果
    _currentAiAnalysis = widget.initialQuote?.aiAnalysis;

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

    // 新建笔记时，自动填充默认作者、出处和标签
    if (widget.initialQuote == null) {
      try {
        final settingsService =
            Provider.of<SettingsService>(context, listen: false);
        if (_authorController.text.isEmpty &&
            settingsService.defaultAuthor != null &&
            settingsService.defaultAuthor!.isNotEmpty) {
          _authorController.text = settingsService.defaultAuthor!;
        }
        if (_workController.text.isEmpty &&
            settingsService.defaultSource != null &&
            settingsService.defaultSource!.isNotEmpty) {
          _workController.text = settingsService.defaultSource!;
        }
        if (_selectedTagIds.isEmpty &&
            settingsService.defaultTagIds.isNotEmpty) {
          _selectedTagIds = List.from(settingsService.defaultTagIds);
        }
      } catch (_) {
        // SettingsService 未注入时忽略
      }
    }

    // 新建笔记时，读取用户偏好设置自动勾选位置/天气
    if (widget.initialQuote == null) {
      // 性能优化：延迟到首帧渲染后 300ms 执行，避免与页面动画竞争
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Future.delayed(const Duration(milliseconds: 300), () {
          if (!mounted) return;
          final settingsService =
              Provider.of<SettingsService>(context, listen: false);
          final autoLocation = settingsService.autoAttachLocation;
          final autoWeather = settingsService.autoAttachWeather;

          if (autoLocation || autoWeather) {
            setState(() {
              if (autoLocation) _showLocation = true;
              if (autoWeather) _showWeather = true;
            });
            // 自动获取位置和天气
            _fetchLocationWeatherWithNotification();
          }
        });
      });
    }

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
    _initialAiAnalysis = widget.initialQuote?.aiAnalysis;

    // 性能优化：延迟显示功能引导，避免与编辑器初始化竞争
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // 延迟 500ms 显示引导，确保编辑器完全初始化
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          _showEditorGuide();
          _showToolbarGuide();
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) => _buildEditorPage(context);

  @override
  void dispose() {
    _draftSaveTimer?.cancel();
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
}
