import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../gen_l10n/app_localizations.dart';
import '../models/local_ai_model.dart';
import '../services/local_ai/embedding_service.dart';
import '../services/local_ai/model_manager.dart';
// import '../services/local_ai/ocr_service.dart'; // Tesseract 已移除
import '../services/local_ai/speech_recognition_service.dart';
import '../services/local_ai/text_processing_service.dart';
import '../theme/app_theme.dart';

/// 模型管理页面
///
/// 用于下载、管理本地 AI 模型
class ModelManagementPage extends StatefulWidget {
  const ModelManagementPage({super.key});

  @override
  State<ModelManagementPage> createState() => _ModelManagementPageState();
}

class _ModelManagementPageState extends State<ModelManagementPage> {
  // 预置链接用于减少用户首次配置成本；版本升级时需同步更新这里的 URL。
  static const Map<String, String> _managedModelUrlPresets = {
    'gemma-2b':
        'https://storage.googleapis.com/mediapipe-models/llm_inference/gemma2-2b-it-int4/1/gemma2-2b-it-int4.bin',
    'gecko-384':
        'https://storage.googleapis.com/mediapipe-models/text_embedder/gecko/float32/latest/gecko.tflite',
    'paligemma-3b':
        'https://storage.googleapis.com/mediapipe-models/image_generator/paligemma-3b-mix-224/float16/latest/paligemma-3b-mix-224.task',
  };

  late ModelManager _modelManager;
  bool _isInitialized = false;
  String? _initError;

  bool _isPreparing = false;

  @override
  void initState() {
    super.initState();
    _initializeManager();
  }

  Future<void> _initializeManager() async {
    try {
      _modelManager = ModelManager.instance;
      if (!_modelManager.isInitialized) {
        await _modelManager.initialize();
      }
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _initError = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 1,
        backgroundColor: theme.colorScheme.surface,
        title: Text(l10n.modelManagement),
        actions: [
          if (_isInitialized)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: l10n.modelClearAll,
              onPressed: _showClearAllDialog,
            ),
        ],
      ),
      body: _buildBody(context, l10n, theme),
    );
  }

  Widget _buildBody(
      BuildContext context, AppLocalizations l10n, ThemeData theme) {
    if (_initError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                _initError!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () {
                  setState(() {
                    _initError = null;
                  });
                  _initializeManager();
                },
                icon: const Icon(Icons.refresh),
                label: Text(l10n.retry),
              ),
            ],
          ),
        ),
      );
    }

    if (!_isInitialized) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return ListenableBuilder(
      listenable: _modelManager,
      builder: (context, _) {
        final models = _modelManager.models;
        final groupedModels = _groupModelsByType(models);

        return RefreshIndicator(
          onRefresh: () async {
            await _modelManager.refreshModelStatuses();
            if (mounted) setState(() {});
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              // 存储信息卡片
              _buildStorageCard(context, l10n, theme),
              const SizedBox(height: 16),

              // 按类型分组显示模型
              for (final entry in groupedModels.entries) ...[
                _buildModelTypeHeader(context, l10n, theme, entry.key),
                ...entry.value.asMap().entries.map(
                  (e) => _buildModelCard(context, l10n, theme, e.value, animationIndex: e.key),
                ),
                const SizedBox(height: 8),
              ],

              // 底部提示
              _buildInfoCard(context, l10n, theme),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  Map<LocalAIModelType, List<LocalAIModelInfo>> _groupModelsByType(
    List<LocalAIModelInfo> models,
  ) {
    final grouped = <LocalAIModelType, List<LocalAIModelInfo>>{};
    for (final model in models) {
      grouped.putIfAbsent(model.type, () => []).add(model);
    }
    return grouped;
  }

  Widget _buildStorageCard(
      BuildContext context, AppLocalizations l10n, ThemeData theme) {
    return FutureBuilder<int>(
      future: _modelManager.getTotalStorageUsage(),
      builder: (context, snapshot) {
        final size = snapshot.data ?? 0;
        final sizeStr = _formatSize(size);

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  theme.colorScheme.primaryContainer.withOpacity(0.3),
                  theme.colorScheme.secondaryContainer.withOpacity(0.3),
                ],
              ),
              borderRadius: BorderRadius.circular(AppTheme.cardRadius),
              border: Border.all(
                color: theme.colorScheme.primary.withOpacity(0.2),
                width: 1,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.storage_rounded,
                      color: theme.colorScheme.primary,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.modelStorageUsage(sizeStr),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          l10n.modelDownloadedCount(_modelManager.downloadedModels.length),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildModelTypeHeader(
    BuildContext context,
    AppLocalizations l10n,
    ThemeData theme,
    LocalAIModelType type,
  ) {
    final typeInfo = _getModelTypeInfo(l10n, type);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: typeInfo.color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              typeInfo.icon,
              size: 18,
              color: typeInfo.color,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            typeInfo.name,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModelCard(
    BuildContext context,
    AppLocalizations l10n,
    ThemeData theme,
    LocalAIModelInfo model, {
    int animationIndex = 0,
  }) {
    final statusInfo = _getStatusInfo(l10n, model.status);
    final needsPreparation = _needsPreparation(model);
    final tags = _getModelTags(l10n, model);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          side: BorderSide(
            color: model.status == LocalAIModelStatus.loaded
                ? theme.colorScheme.primary.withAlpha(80)
                : theme.colorScheme.outline.withAlpha(50),
            width: model.status == LocalAIModelStatus.loaded ? 1.5 : 1,
          ),
        ),
        child: InkWell(
          onTap: () => _showModelActions(context, l10n, model),
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  model.name,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              // 推荐标签
                              ...tags.map((tag) => Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: _buildTag(theme, tag),
                              )),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            model.description,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    _buildStatusBadge(theme, statusInfo),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    _buildInfoChip(
                      theme,
                      Icons.storage_outlined,
                      model.formattedSize,
                    ),
                    _buildInfoChip(
                      theme,
                      Icons.tag,
                      'v${model.version}',
                    ),
                    if (needsPreparation)
                      _buildInfoChip(
                        theme,
                        Icons.unarchive_outlined,
                        l10n.modelPrepare,
                      ),
                    if (_isManagedModel(model))
                      _buildInfoChip(
                        theme,
                        Icons.extension_outlined,
                        'flutter_gemma',
                      ),
                  ],
                ),
                // 下载进度
                if (model.status == LocalAIModelStatus.downloading) ...[
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: model.downloadProgress,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.modelDownloadProgress(
                        (model.downloadProgress * 100).toInt()),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
                // 错误信息
                if (model.status == LocalAIModelStatus.error &&
                    model.errorMessage != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 16,
                          color: theme.colorScheme.error,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _localizeModelError(l10n, model.errorMessage!),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.error,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(ThemeData theme, _StatusInfo info) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: info.color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            info.icon,
            size: 14,
            color: info.color,
          ),
          const SizedBox(width: 4),
          Text(
            info.text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: info.color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip(ThemeData theme, IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(
      BuildContext context, AppLocalizations l10n, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.modelDownloadSource,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              l10n.modelDownloadSourceHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showModelActions(
      BuildContext context, AppLocalizations l10n, LocalAIModelInfo model) {
    final theme = Theme.of(context);
    final isManaged = _isManagedModel(model);
    final canPrepare = isManaged ||
        model.status == LocalAIModelStatus.downloaded ||
        model.status == LocalAIModelStatus.loaded;

    showModalBottomSheet(
      context: context,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  model.name,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Divider(height: 1),
              if (canPrepare)
                ListTile(
                  leading: const Icon(Icons.play_circle_outline),
                  title: Text(l10n.modelPrepare),
                  subtitle: Text(l10n.modelPrepareHint),
                  enabled: !_isPreparing,
                  onTap: () {
                    Navigator.pop(context);
                    _prepareModel(model);
                  },
                ),
              if (model.status == LocalAIModelStatus.notDownloaded ||
                  model.status == LocalAIModelStatus.error)
                ListTile(
                  leading: const Icon(Icons.download),
                  title: Text(l10n.modelDownload),
                  enabled: !isManaged,
                  subtitle: isManaged ? Text(l10n.modelManagedByPackage) : null,
                  onTap: () {
                    Navigator.pop(context);
                    if (isManaged) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.modelManagedByPackage)),
                      );
                      return;
                    }
                    _downloadModel(model);
                  },
                ),
              if (model.status == LocalAIModelStatus.downloading)
                ListTile(
                  leading: const Icon(Icons.cancel),
                  title: Text(l10n.cancel),
                  onTap: () {
                    Navigator.pop(context);
                    _modelManager.cancelDownload(model.id);
                  },
                ),
              if (model.supportsManualImport)
                ListTile(
                  leading: const Icon(Icons.file_upload_outlined),
                  title: Text(l10n.modelImport),
                  subtitle: Text(l10n.modelImportHint),
                  onTap: () {
                    Navigator.pop(context);
                    _importModel(model);
                  },
                ),
              if (model.status == LocalAIModelStatus.downloaded ||
                  model.status == LocalAIModelStatus.loaded)
                ListTile(
                  leading: Icon(Icons.delete_outline,
                      color: theme.colorScheme.error),
                  title: Text(l10n.modelDelete,
                      style: TextStyle(color: theme.colorScheme.error)),
                  onTap: () {
                    Navigator.pop(context);
                    _showDeleteConfirmDialog(model);
                  },
                ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Future<void> _downloadModel(LocalAIModelInfo model) async {
    // flutter_gemma 托管模型：需要先配置真实下载地址
    if (_isManagedModel(model) &&
        model.downloadUrl.startsWith('managed://flutter_gemma/')) {
      final existingUrl =
          await _modelManager.getFlutterGemmaManagedModelUrl(model.id);
      if (existingUrl == null || existingUrl.trim().isEmpty) {
        final configured = await _promptAndSaveManagedModelUrl(model);
        if (!configured) {
          return;
        }
      }
    }

    _modelManager.downloadModel(
      model.id,
      onProgress: (progress) {
        // 进度更新由 ModelManager 通过 notifyListeners 处理
      },
      onComplete: () {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).modelDownloadComplete),
            ),
          );
        }

        // OCR 模型下载完成后同步到 tessdata，避免“下载完仍不可用”。
        // if (model.type == LocalAIModelType.ocr) {
        //   OCRService.instance.refreshModels();
        // }
      },
      onError: (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(context).modelDownloadFailed(
                  _localizeModelError(AppLocalizations.of(context), error),
                ),
              ),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      },
    );
  }

  Future<bool> _promptAndSaveManagedModelUrl(LocalAIModelInfo model) async {
    final existingUrl = await _modelManager.getFlutterGemmaManagedModelUrl(
          model.id,
        ) ??
        _getSuggestedManagedModelUrl(model.id);
    if (!mounted) return false;
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController(text: existingUrl);

    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(l10n.modelDownload),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: l10n.apiUrlField,
              hintText: l10n.apiUrlHint,
              helperText: l10n.apiUrlHelper,
            ),
            keyboardType: TextInputType.url,
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: Text(l10n.save),
            ),
          ],
        );
      },
    );

    if (result == null) return false;

    final uri = Uri.tryParse(result);
    final isValid =
        uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
    if (!isValid) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.invalidUrl),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
      return false;
    }

    await _modelManager.setFlutterGemmaManagedModelUrl(model.id, result);
    return true;
  }

  Future<void> _prepareModel(LocalAIModelInfo model) async {
    final l10n = AppLocalizations.of(context);

    if (_isPreparing) return;

    setState(() {
      _isPreparing = true;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 16),
              Text(l10n.modelPreparing),
            ],
          ),
          duration: const Duration(seconds: 30),
        ),
      );
    }

    try {
      switch (model.type) {
        case LocalAIModelType.asr:
          await SpeechRecognitionService.instance
              .initialize(eagerLoadModel: false);
          await SpeechRecognitionService.instance.prepareModel();
          break;
        case LocalAIModelType.ocr:
          // await OCRService.instance.refreshModels();
          break;
        case LocalAIModelType.llm:
          await TextProcessingService.instance.initialize();
          await TextProcessingService.instance.loadModel();
          break;
        case LocalAIModelType.embedding:
          await EmbeddingService.instance.initialize();
          await EmbeddingService.instance.loadModel();
          break;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.modelPrepareSuccess),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n
                .modelPrepareFailed(_localizeModelError(l10n, e.toString()))),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isPreparing = false;
        });
      }
    }
  }

  Future<void> _importModel(LocalAIModelInfo model) async {
    final l10n = AppLocalizations.of(context);

    // 根据模型类型确定允许的文件扩展名
    List<String> allowedExtensions;
    String dialogTitle;

    switch (model.type) {
      case LocalAIModelType.asr:
        // Whisper 模型是 tar.bz2 压缩包
        allowedExtensions = ['bz2', 'gz', 'tar'];
        dialogTitle = l10n.modelImportASR;
        break;
      case LocalAIModelType.ocr:
        // Tesseract 模型是 traineddata 文件
        allowedExtensions = ['traineddata'];
        dialogTitle = l10n.modelImportOCR;
        break;
      case LocalAIModelType.llm:
      case LocalAIModelType.embedding:
        // flutter_gemma 托管模型：允许导入本地 .task（或 .bin）模型文件
        allowedExtensions = ['task', 'bin'];
        dialogTitle = l10n.modelImport;
        break;
    }

    try {
      // 使用 file_picker 选择文件
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: allowedExtensions,
        dialogTitle: dialogTitle,
      );

      if (result == null || result.files.isEmpty) {
        return; // 用户取消
      }

      final filePath = result.files.single.path;
      if (filePath == null) {
        throw Exception('file_path_not_available');
      }

      // 显示导入进度
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 16),
                Text(l10n.modelImporting),
              ],
            ),
            duration: const Duration(seconds: 30),
          ),
        );
      }

      // 导入模型
      await _modelManager.importModel(model.id, filePath);

      // OCR 导入后同步 tessdata
      // if (model.type == LocalAIModelType.ocr) {
      //   await OCRService.instance.refreshModels();
      // }

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.modelImportSuccess),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.modelImportFailed(e.toString())),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  void _showDeleteConfirmDialog(LocalAIModelInfo model) {
    final l10n = AppLocalizations.of(context);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.modelDelete),
        content: Text(l10n.modelDeleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _modelManager.deleteModel(model.id);
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
  }

  void _showClearAllDialog() {
    final l10n = AppLocalizations.of(context);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.modelClearAll),
        content: Text(l10n.modelClearAllConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _modelManager.clearAllModels();
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
  }

  _ModelTypeInfo _getModelTypeInfo(
      AppLocalizations l10n, LocalAIModelType type) {
    switch (type) {
      case LocalAIModelType.llm:
        return _ModelTypeInfo(
          name: l10n.modelTypeLLM,
          icon: Icons.psychology_rounded,
          color: Colors.purple,
        );
      case LocalAIModelType.embedding:
        return _ModelTypeInfo(
          name: l10n.modelTypeEmbedding,
          icon: Icons.hub_rounded,
          color: Colors.blue,
        );
      case LocalAIModelType.asr:
        return _ModelTypeInfo(
          name: l10n.modelTypeASR,
          icon: Icons.mic_rounded,
          color: Colors.green,
        );
      case LocalAIModelType.ocr:
        return _ModelTypeInfo(
          name: l10n.modelTypeOCR,
          icon: Icons.document_scanner_rounded,
          color: Colors.orange,
        );
    }
  }

  _StatusInfo _getStatusInfo(AppLocalizations l10n, LocalAIModelStatus status) {
    switch (status) {
      case LocalAIModelStatus.notDownloaded:
        return _StatusInfo(
          text: l10n.modelNotDownloaded,
          icon: Icons.cloud_download_outlined,
          color: Colors.grey,
        );
      case LocalAIModelStatus.downloading:
        return _StatusInfo(
          text: l10n.modelDownloading,
          icon: Icons.downloading,
          color: Colors.blue,
        );
      case LocalAIModelStatus.downloaded:
        return _StatusInfo(
          text: l10n.modelDownloaded,
          icon: Icons.check_circle_outline,
          color: Colors.green,
        );
      case LocalAIModelStatus.loading:
        return _StatusInfo(
          text: l10n.modelLoading,
          icon: Icons.hourglass_empty,
          color: Colors.orange,
        );
      case LocalAIModelStatus.loaded:
        return _StatusInfo(
          text: l10n.modelLoaded,
          icon: Icons.check_circle,
          color: Colors.green,
        );
      case LocalAIModelStatus.error:
        return _StatusInfo(
          text: l10n.modelError,
          icon: Icons.error_outline,
          color: Colors.red,
        );
    }
  }

  bool _isManagedModel(LocalAIModelInfo model) {
    return model.downloadUrl.startsWith('managed://');
  }

  /// 为 flutter_gemma 托管模型提供预置下载链接。
  ///
  /// 返回值用于在用户尚未配置地址时预填输入框；
  /// 若模型不在预置列表中，则返回空字符串。
  String _getSuggestedManagedModelUrl(String modelId) {
    return _managedModelUrlPresets[modelId] ?? '';
  }

  bool _needsPreparation(LocalAIModelInfo model) {
    if (model.status != LocalAIModelStatus.downloaded) return false;
    if (model.fileName.endsWith('.tar.bz2') ||
        model.fileName.endsWith('.tar.gz')) {
      return _modelManager.getExtractedModelPath(model.id) == null;
    }
    // LLM/Embedding 由运行时加载；下载完成不代表已加载。
    if (model.type == LocalAIModelType.llm) {
      return !TextProcessingService.instance.isModelLoaded;
    }
    if (model.type == LocalAIModelType.embedding) {
      return !EmbeddingService.instance.isModelLoaded;
    }
    return false;
  }

  String _localizeModelError(AppLocalizations l10n, String raw) {
    // 统一把 error code 映射为用户可理解的本地化文案。
    if (raw.contains(ModelManager.errorManagedModel)) {
      return l10n.modelManagedByPackage;
    }
    if (raw.contains(ModelManager.errorManagedModelUrlMissing)) {
      return l10n.modelManagedByPackage;
    }
    if (raw.contains(ModelManager.errorExtractFailed) ||
        raw.contains('extract_failed')) {
      return l10n.modelExtractFailed;
    }
    if (raw.contains('asr_model_required')) {
      return l10n.pleaseSwitchToAsrModel;
    }
    if (raw.contains('ocr_model_required')) {
      return l10n.pleaseSwitchToOcrModel;
    }
    if (raw.contains('embedding_model_required')) {
      return l10n.modelRequiresDownload;
    }
    if (raw.contains('gemma_model_required')) {
      return l10n.modelRequiresDownload;
    }
    if (raw.contains('service_not_initialized')) {
      return l10n.featureNotAvailable;
    }
    if (raw.contains('feature_not_enabled')) {
      return l10n.featureNotEnabled;
    }
    if (raw.contains('file_path_not_available')) {
      return l10n.filePathNotAvailable;
    }
    if (raw.contains('mlkit_not_initialized') ||
        raw.contains('mlkit_not_available')) {
      return l10n.featureNotAvailable;
    }
    return raw;
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
  }

  /// 获取模型推荐标签
  List<_TagInfo> _getModelTags(AppLocalizations l10n, LocalAIModelInfo model) {
    final tags = <_TagInfo>[];
    switch (model.id) {
      case 'whisper-tiny':
        tags.add(_TagInfo(text: l10n.modelLightweight, color: Colors.teal));
        tags.add(_TagInfo(text: l10n.modelRecommended, color: Colors.amber.shade700));
        break;
      case 'whisper-base':
        tags.add(_TagInfo(text: l10n.modelHighAccuracy, color: Colors.indigo));
        break;
      case 'gemma-2b':
        tags.add(_TagInfo(text: l10n.modelRecommended, color: Colors.amber.shade700));
        break;
      case 'paligemma-3b':
        tags.add(_TagInfo(text: l10n.modelHighAccuracy, color: Colors.indigo));
        break;
      default:
        break;
    }
    return tags;
  }

  /// 构建推荐标签组件
  Widget _buildTag(ThemeData theme, _TagInfo tag) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: tag.color.withAlpha(25),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: tag.color.withAlpha(80), width: 0.5),
      ),
      child: Text(
        tag.text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: tag.color,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _TagInfo {
  final String text;
  final Color color;
  const _TagInfo({required this.text, required this.color});
}

class _ModelTypeInfo {
  final String name;
  final IconData icon;
  final Color color;

  const _ModelTypeInfo({
    required this.name,
    required this.icon,
    required this.color,
  });
}

class _StatusInfo {
  final String text;
  final IconData icon;
  final Color color;

  const _StatusInfo({
    required this.text,
    required this.icon,
    required this.color,
  });
}
