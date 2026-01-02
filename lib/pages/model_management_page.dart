import 'package:flutter/material.dart';

import '../gen_l10n/app_localizations.dart';
import '../models/local_ai_model.dart';
import '../services/local_ai/model_manager.dart';
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
  late ModelManager _modelManager;
  bool _isInitialized = false;
  String? _initError;

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

  Widget _buildBody(BuildContext context, AppLocalizations l10n, ThemeData theme) {
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

        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            // 存储信息卡片
            _buildStorageCard(context, l10n, theme),
            const SizedBox(height: 16),

            // 按类型分组显示模型
            for (final entry in groupedModels.entries) ...[
              _buildModelTypeHeader(context, l10n, theme, entry.key),
              ...entry.value.map(
                (model) => _buildModelCard(context, l10n, theme, model),
              ),
              const SizedBox(height: 8),
            ],

            // 底部提示
            _buildInfoCard(context, l10n, theme),
            const SizedBox(height: 24),
          ],
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

  Widget _buildStorageCard(BuildContext context, AppLocalizations l10n, ThemeData theme) {
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
                          '${_modelManager.downloadedModels.length} ${l10n.modelDownloaded}',
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
    LocalAIModelInfo model,
  ) {
    final statusInfo = _getStatusInfo(l10n, model.status);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          side: BorderSide(
            color: theme.colorScheme.outline.withOpacity(0.2),
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
                          Text(
                            model.name,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
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
                Row(
                  children: [
                    _buildInfoChip(
                      theme,
                      Icons.storage_outlined,
                      model.formattedSize,
                    ),
                    const SizedBox(width: 8),
                    _buildInfoChip(
                      theme,
                      Icons.tag,
                      'v${model.version}',
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
                    l10n.modelDownloadProgress((model.downloadProgress * 100).toInt()),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
                // 错误信息
                if (model.status == LocalAIModelStatus.error && model.errorMessage != null) ...[
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
                            model.errorMessage!,
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

  Widget _buildInfoCard(BuildContext context, AppLocalizations l10n, ThemeData theme) {
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

  void _showModelActions(BuildContext context, AppLocalizations l10n, LocalAIModelInfo model) {
    final theme = Theme.of(context);

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
              if (model.status == LocalAIModelStatus.notDownloaded ||
                  model.status == LocalAIModelStatus.error)
                ListTile(
                  leading: const Icon(Icons.download),
                  title: Text(l10n.modelDownload),
                  onTap: () {
                    Navigator.pop(context);
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
              if (model.status == LocalAIModelStatus.notDownloaded ||
                  model.status == LocalAIModelStatus.error)
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
                  leading: Icon(Icons.delete_outline, color: theme.colorScheme.error),
                  title: Text(l10n.modelDelete, style: TextStyle(color: theme.colorScheme.error)),
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

  void _downloadModel(LocalAIModelInfo model) {
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
      },
      onError: (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).modelDownloadFailed(error)),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      },
    );
  }

  void _importModel(LocalAIModelInfo model) {
    // TODO: 使用 file_picker 选择文件并导入
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).featureComingSoon),
      ),
    );
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

  _ModelTypeInfo _getModelTypeInfo(AppLocalizations l10n, LocalAIModelType type) {
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
