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
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter/services.dart';
import '../utils/app_logger.dart';
import '../utils/string_utils.dart';
import 'ai_assistant_page.dart';
import '../models/ai_assistant_entry.dart';
import 'package:flutter/foundation.dart' show kIsWeb, compute;

import '../extensions/note_category_localization_extension.dart';
import '../utils/delta_content_serializer.dart';
import '../utils/device_memory_manager.dart';
import '../widgets/quill_enhanced_toolbar_unified.dart';
import '../widgets/ai_options_menu.dart';
import '../utils/quill_editor_extensions.dart'; // 导入自定义embedBuilders
import '../utils/quill_ai_apply_utils.dart';
import '../services/temporary_media_service.dart';
import '../widgets/media_player_widget.dart';
import '../constants/app_constants.dart';
import '../services/media_file_service.dart';
import '../services/media_reference_service.dart';
import '../services/draft_service.dart'; // 导入草稿服务
import '../utils/feature_guide_helper.dart';
import '../utils/location_weather_helper.dart';
import '../services/settings_service.dart';
import '../controllers/note_editor_states.dart';

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
  final String? initialAuthor;
  final String? initialWork;
  final bool skipDefaultMetadataAutofill;
  final bool isRestoredDraft; // 新增：标记是否为恢复的草稿
  final String? restoredDraftId; // 新增：恢复草稿的原始ID
  final bool isFromDailyQuote; // 新增：标记是否来自每日一言

  const NoteFullEditorPage({
    super.key,
    required this.initialContent,
    this.initialQuote,
    this.allTags,
    this.initialAuthor,
    this.initialWork,
    this.skipDefaultMetadataAutofill = false,
    this.isRestoredDraft = false, // 默认为 false
    this.restoredDraftId, // 恢复草稿的原始ID
    this.isFromDailyQuote = false, // 默认为 false
  });

  @override
  State<NoteFullEditorPage> createState() => _NoteFullEditorPageState();
}

class _NoteFullEditorPageState extends State<NoteFullEditorPage> {
  late final NoteEditorState _editorState;
  late final NoteEditorMetadataState _metadataState;
  final NoteEditorMediaState _mediaState = NoteEditorMediaState();

  String _createDraftStorageKey() {
    final restoredDraftId = widget.restoredDraftId;
    if (restoredDraftId != null && restoredDraftId.isNotEmpty) {
      return restoredDraftId;
    }
    final quoteId = widget.initialQuote?.id;
    if (quoteId != null && quoteId.isNotEmpty) return quoteId;
    return 'new_note_${const Uuid().v4()}';
  }

  // 功能引导：元数据编辑按钮的 Key
  final GlobalKey _metadataButtonKey = GlobalKey();
  // 新增：工具栏气泡引导 Key
  final GlobalKey _toolbarGuideKey = GlobalKey();

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
    return DeltaContentSerializer.encode(data);
  }

  @override
  void initState() {
    super.initState();
    _metadataState = NoteEditorMetadataState(
      initialQuote: widget.initialQuote,
      initialAuthor: widget.initialAuthor,
      initialWork: widget.initialWork,
      initialTagIds: widget.initialQuote?.tagIds,
    );
    _editorState = NoteEditorState(
      initialPlainText: widget.initialContent,
      initialDeltaContent: widget.initialQuote?.deltaContent,
      draftStorageKey: _createDraftStorageKey(),
      restoredFromDraft: widget.isRestoredDraft,
    );

    // 如果是编辑模式，异步获取完整笔记数据
    if (widget.initialQuote != null && widget.initialQuote!.id != null) {
      _editorState
        ..setFullQuoteLoading(true)
        ..setFullInitialQuote(widget.initialQuote); // 先使用传入的数据
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _fetchFullQuote();
      });
    }

    // 先初始化为基本控制器，避免阻塞UI
    _attachDraftListener();

    // 异步初始化文档内容
    _initializeDocumentAsync();

    // 新建笔记时，自动填充默认作者、出处和标签
    if (widget.initialQuote == null && !widget.skipDefaultMetadataAutofill) {
      try {
        final settingsService = Provider.of<SettingsService>(
          context,
          listen: false,
        );
        if (_metadataState.authorController.text.isEmpty &&
            settingsService.defaultAuthor != null &&
            settingsService.defaultAuthor!.isNotEmpty) {
          _metadataState.setAuthor(settingsService.defaultAuthor!);
        }
        if (_metadataState.workController.text.isEmpty &&
            settingsService.defaultSource != null &&
            settingsService.defaultSource!.isNotEmpty) {
          _metadataState.setWork(settingsService.defaultSource!);
        }
        if (_metadataState.selectedTagIds.isEmpty &&
            settingsService.defaultTagIds.isNotEmpty) {
          _metadataState.setSelectedTagIds(settingsService.defaultTagIds);
        }
      } catch (_) {
        // SettingsService 未注入时忽略
      }
    }
    _metadataState.captureInitialSnapshot();

    // 新建笔记时，读取用户偏好设置自动勾选位置/天气
    if (widget.initialQuote == null) {
      // 性能优化：延迟到首帧渲染后 300ms 执行，避免与页面动画竞争
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Future.delayed(const Duration(milliseconds: 300), () {
          if (!mounted) return;
          final settingsService = Provider.of<SettingsService>(
            context,
            listen: false,
          );
          final autoLocation = settingsService.autoAttachLocation;
          final autoWeather = settingsService.autoAttachWeather;

          if (autoLocation || autoWeather) {
            setState(() {
              if (autoLocation) _metadataState.setShowLocation(true);
              if (autoWeather) _metadataState.setShowWeather(true);
            });
            // 自动获取位置和天气
            _fetchLocationWeatherWithNotification();
          }
        });
      });
    }

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
    // 未保存退出时，清理本会话导入而未被引用的媒体文件
    _cleanupSessionImportedMediaIfUnsaved();
    // 清理临时媒体文件（异步执行，不阻塞dispose）
    _cleanupTemporaryMedia();

    _editorState.dispose();
    _metadataState.dispose();
    _mediaState.dispose();

    super.dispose();
  }
}
