import 'dart:io';
import 'package:flutter/material.dart';
import '../gen_l10n/app_localizations.dart';
import '../models/merge_report.dart';
import '../services/backup_service.dart';
import '../services/large_file_manager.dart';
import '../utils/app_logger.dart';
import '../utils/backup_progress_update_gate.dart';
import '../utils/stream_file_selector.dart';
import '../utils/time_utils.dart';
import '../widgets/app_snackbar.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:thoughtecho/theme/app_semantic_colors.dart';

/// 备份与还原页面
///
/// 支持新版ZIP格式备份（包含媒体文件）和旧版JSON格式兼容
class BackupRestorePage extends StatefulWidget {
  const BackupRestorePage({super.key});

  @override
  State<BackupRestorePage> createState() => _BackupRestorePageState();
}

class _BackupRestorePageState extends State<BackupRestorePage> {
  bool _isLoading = false;
  bool _includeMediaFiles = true; // 默认包含媒体文件
  AppLocalizations get l10n => AppLocalizations.of(context);
  double _progress = 0.0;
  String _progressText = '';
  CancelToken? _cancelToken;
  final BackupProgressUpdateGate _backupProgressUpdateGate =
      BackupProgressUpdateGate();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.backupAndRestore), elevation: 0),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildBackupSection(),
            const SizedBox(height: 24),
            _buildRestoreSection(),
            const SizedBox(height: 24),
            _buildInfoSection(),
          ],
        ),
      ),
    );
  }

  /// 构建备份区域
  Widget _buildBackupSection() {
    final l10n = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.backup,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.dataBackup,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 媒体文件选项
            CheckboxListTile(
              title: Text(l10n.includeMediaFiles),
              subtitle: Text(l10n.includeMediaFilesHint),
              value: _includeMediaFiles,
              onChanged: _isLoading
                  ? null
                  : (value) {
                      setState(() {
                        _includeMediaFiles = value ?? true;
                      });
                    },
            ),

            const SizedBox(height: 16),

            // 备份按钮
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _isLoading ? null : _handleBackup,
                icon: _isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_alt),
                label: Text(
                  _isLoading ? l10n.creatingBackup : l10n.createBackup,
                ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),

            // 进度显示
            if (_isLoading) ...[
              const SizedBox(height: 16),
              Column(
                children: [
                  LinearProgressIndicator(value: _progress / 100),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _progressText,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Text(
                        '${_progress.toStringAsFixed(0)}%',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () {
                      _cancelToken?.cancel();
                    },
                    child: Text(l10n.cancel),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 8),
            Text(
              _includeMediaFiles ? l10n.backupFormatZip : l10n.backupFormatJson,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建还原区域
  Widget _buildRestoreSection() {
    final l10n = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.restore,
                  color: Theme.of(context).colorScheme.secondary,
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.dataRestore,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: _isLoading ? null : _handleRestore,
                icon: const Icon(Icons.folder_open),
                label: Text(l10n.selectBackupFileToRestore),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),

            // 还原进度显示
            if (_isLoading) ...[
              const SizedBox(height: 16),
              Column(
                children: [
                  LinearProgressIndicator(value: _progress / 100),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          _progressText,
                          style: Theme.of(context).textTheme.bodySmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${_progress.toStringAsFixed(0)}%',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () {
                      _cancelToken?.cancel();
                    },
                    child: Text(l10n.cancel),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 8),
            Text(
              l10n.supportedBackupFormats,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建信息区域
  Widget _buildInfoSection() {
    final l10n = AppLocalizations.of(context);
    return Card(
      color: Theme.of(
        context,
      ).colorScheme.errorContainer.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: Theme.of(context).colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.importantNotes,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildInfoItem(l10n.dataSecurity, l10n.dataSafetyDesc),
            _buildInfoItem(l10n.backupAdvice, l10n.backupAdviceDesc),
            _buildInfoItem(l10n.formatInfo, l10n.formatInfoDesc),
            _buildInfoItem(l10n.compatibility, l10n.compatibilityDesc),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoItem(String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 4,
            height: 4,
            margin: const EdgeInsets.only(top: 8, right: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: Theme.of(context).textTheme.bodySmall,
                children: [
                  TextSpan(
                    text: '$title: ',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  TextSpan(text: content),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 处理备份操作
  Future<void> _handleBackup() async {
    if (!mounted) return;

    _backupProgressUpdateGate.reset();
    setState(() {
      _isLoading = true;
      _progress = 0.0;
      _progressText = l10n.preparingBackup;
    });

    // 创建取消令牌
    _cancelToken = CancelToken();

    try {
      final backupService = Provider.of<BackupService>(context, listen: false);
      final now = DateTime.now();
      final formattedDate = TimeUtils.formatFileTimestamp(now);
      final extension = _includeMediaFiles ? 'zip' : 'json';
      final fileName =
          '${l10n.appTitle}_${l10n.thoughtEchoBackupFile}_$formattedDate.$extension';

      String? backupPath;
      void onBackupProgress(int current, int total) {
        _handleBackupProgressUpdate(current, total);
      }

      if (Platform.isAndroid || Platform.isIOS) {
        // 移动平台：创建备份并分享
        backupPath = await backupService.exportAllData(
          includeMediaFiles: _includeMediaFiles,
          onProgress: onBackupProgress,
          cancelToken: _cancelToken,
        );

        if (mounted) {
          await SharePlus.instance.share(
            ShareParams(
              text: l10n.thoughtEchoBackupFile,
              subject: fileName,
              files: [XFile(backupPath)],
            ),
          );

          _showSuccessSnackBar(l10n.backupCompleteSelectLocation);
        }
      } else {
        // 桌面平台：选择保存位置
        final saveLocation = await getSaveLocation(
          suggestedName: fileName,
          acceptedTypeGroups: [
            XTypeGroup(
              label: _includeMediaFiles ? l10n.zipFile : l10n.jsonFile,
              extensions: [extension],
            ),
          ],
        );

        if (saveLocation != null && mounted) {
          final savedToPathMessage = l10n.backupSavedToPath(saveLocation.path);
          backupPath = await backupService.exportAllData(
            includeMediaFiles: _includeMediaFiles,
            customPath: saveLocation.path,
            onProgress: onBackupProgress,
            cancelToken: _cancelToken,
          );

          _showSuccessSnackBar(savedToPathMessage);
        }
      }

      // 导出完成后上报富文本路径转换失败（不静默降级）
      final deltaFailures = backupService.lastExportDeltaConversionFailures;
      if (backupPath != null && deltaFailures.isNotEmpty && mounted) {
        final affectedIds =
            deltaFailures.take(10).join(l10n.backupDeltaFailuresIdJoiner) +
                (deltaFailures.length > 10
                    ? l10n.backupDeltaFailuresMoreSuffix
                    : '');
        _showErrorDialog(
          l10n.backupCompleteWithWarnings,
          l10n.backupDeltaFailuresMessage(
            deltaFailures.length,
            affectedIds,
          ),
        );
      }
    } catch (e, stackTrace) {
      AppLogger.e(
        '执行备份失败: $e',
        error: e,
        stackTrace: stackTrace,
        source: 'BackupRestorePage',
      );
      if (mounted) {
        String errorMessage = l10n.backupFailedGeneric;

        // 针对不同类型的错误提供更友好的提示
        if (e.toString().contains('OutOfMemoryError') ||
            e.toString().contains('内存不足')) {
          errorMessage = l10n.backupFailedOutOfMemory;
        } else if (e.toString().contains('存储空间') ||
            e.toString().contains('No space left')) {
          errorMessage = l10n.backupFailedNoSpace;
        } else if (e.toString().contains('权限') ||
            e.toString().contains('Permission')) {
          errorMessage = l10n.backupFailedPermission;
        } else if (e.toString().contains('cancelled') ||
            e.toString().contains('取消')) {
          errorMessage = l10n.backupCancelled;
        }

        _showErrorDialog(l10n.backupFailedText, errorMessage);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      _cancelToken = null;
    }
  }

  void _handleBackupProgressUpdate(int current, int total) {
    if (!mounted) return;

    final safeTotal = total <= 0 ? 1 : total;
    final normalizedProgress =
        ((current / safeTotal) * 100).clamp(0, 100).toDouble();
    final progressPercent = normalizedProgress.round();
    final stageKey = resolveBackupStageKey(progressPercent);

    if (!_backupProgressUpdateGate.shouldUpdate(
      progressPercent: progressPercent,
      stageKey: stageKey,
    )) {
      return;
    }

    setState(() {
      _progress = progressPercent.toDouble();
      _progressText = _backupStageText(stageKey);
    });
  }

  String _backupStageText(String stageKey) {
    switch (stageKey) {
      case BackupProgressStages.collect:
        return l10n.collectingData;
      case BackupProgressStages.note:
        return l10n.processingNoteData;
      case BackupProgressStages.media:
        return l10n.processingMediaFiles;
      case BackupProgressStages.zip:
        return l10n.creatingBackupFile;
      default:
        return l10n.verifyingBackupFile;
    }
  }

  /// 处理还原操作
  Future<void> _handleRestore() async {
    if (!mounted) return;

    try {
      // 选择备份文件
      final FilePickerResult? result = await StreamFileSelector.selectFile(
        extensions: ['zip', 'json'],
        description: 'Backup Files',
      );
      if (result == null || result.files.isEmpty || !mounted) return;

      final file = result.files.first;
      if (file.path == null) {
        _showErrorDialog(l10n.selectFileError, l10n.cannotGetFilePath);
        return;
      }

      setState(() {
        _isLoading = true;
        _progress = 0;
        _progressText = '';
      });

      final backupService = Provider.of<BackupService>(context, listen: false);

      // 验证备份文件
      final isValid = await backupService.validateBackupFile(file.path!);
      if (!isValid) {
        if (mounted) {
          _showErrorDialog(l10n.invalidBackupFile, l10n.invalidBackupFileDesc);
        }
        return;
      }

      // 选择导入模式：覆盖 或 合并(LWW)
      bool useMerge = false;
      if (mounted) {
        final mode = await showDialog<String>(
          context: context,
          barrierDismissible: false,
          builder: (c) {
            String selected = 'overwrite';
            final dialogL10n = AppLocalizations.of(c);
            return StatefulBuilder(
              builder: (ctx, setLocal) {
                return AlertDialog(
                  title: Text(dialogL10n.selectImportMode),
                  content: RadioGroup<String>(
                    groupValue: selected,
                    onChanged: (v) => setLocal(() => selected = v!),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RadioListTile<String>(
                          title: Text(dialogL10n.overwriteImport),
                          subtitle: Text(dialogL10n.overwriteImportDesc),
                          value: 'overwrite',
                          dense: true,
                        ),
                        RadioListTile<String>(
                          title: Text(dialogL10n.mergeImport),
                          subtitle: Text(dialogL10n.mergeImportDesc),
                          value: 'merge',
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(null),
                      child: Text(dialogL10n.cancel),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(ctx).pop(selected),
                      child: Text(dialogL10n.continueAction),
                    ),
                  ],
                );
              },
            );
          },
        );
        if (mode == null) return; // 用户取消
        useMerge = mode == 'merge';
      }

      // 确认还原/合并操作
      if (mounted) {
        final confirmed = useMerge
            ? await _showMergeConfirmDialog()
            : await _showRestoreConfirmDialog();
        if (!confirmed) return;
      }

      // 执行导入
      _backupProgressUpdateGate.reset();
      _cancelToken = CancelToken();
      MergeReport? report;
      if (useMerge) {
        report = await backupService.importData(
          file.path!,
          clearExisting: false,
          merge: true,
          onProgress: (current, total) {
            _handleRestoreProgressUpdate(current, total, isMerge: true);
          },
          cancelToken: _cancelToken,
        );
        debugPrint('合并导入完成: ${report?.summary}');
      } else {
        report = await backupService.importData(
          file.path!,
          clearExisting: true,
          onProgress: (current, total) {
            _handleRestoreProgressUpdate(current, total);
          },
          cancelToken: _cancelToken,
        );
      }

      if (mounted) {
        final l10n = AppLocalizations.of(context);
        // 还原成功，回到主页并显示成功消息
        Navigator.of(context).popUntil((route) => route.isFirst);

        // 备份里有本应用认不出的字段值、或有正文为空进不来的笔记时，必须让用户看见
        // 一眼——这类数据只可能来自非心迹产生的文件，只写日志等于没说。
        final sanitized = report?.sanitizedFields ?? 0;
        final skippedEmpty = report?.skippedEmptyQuotes ?? 0;
        if (sanitized > 0 || skippedEmpty > 0) {
          AppSnackBar.warning(
            context,
            l10n.importCleanupNotice(sanitized, skippedEmpty),
          );
        } else {
          AppSnackBar.success(context, l10n.restoreSuccess);
        }
      }
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        String errorMessage = l10n.restoreFailedGeneric(e.toString());

        // 修复：针对不同类型的错误提供更友好的提示
        if (e.toString().contains('OutOfMemoryError') ||
            e.toString().contains('内存不足')) {
          errorMessage = l10n.restoreFailedOutOfMemory;
        } else if (e.toString().contains('存储空间') ||
            e.toString().contains('No space left')) {
          errorMessage = l10n.restoreFailedNoSpace;
        } else if (e.toString().contains('权限') ||
            e.toString().contains('Permission')) {
          errorMessage = l10n.restoreFailedPermission;
        } else if (e.toString().contains('cancelled') ||
            e.toString().contains('取消')) {
          errorMessage = l10n.restoreCancelled;
        } else if (e.toString().contains('无效') ||
            e.toString().contains('corrupt')) {
          errorMessage = l10n.restoreFailedCorrupt;
        } else if (e.toString().contains('has no column named')) {
          // 修复：专门处理字段名不匹配的错误
          final columnMatch = RegExp(
            r'has no column named (\w+)',
          ).firstMatch(e.toString());
          final columnName = columnMatch?.group(1) ?? l10n.unknownTag;

          errorMessage = '''${l10n.restoreFailedCorrupt}

Column: $columnName
Details: $e''';
        } else if (e.toString().contains('SQLITE_ERROR')) {
          errorMessage = '''${l10n.restoreFailedCorrupt}

Details: $e''';
        }

        _showErrorDialog(l10n.restoreConfirmDialogTitle, errorMessage);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      _cancelToken = null;
    }
  }

  void _handleRestoreProgressUpdate(
    int current,
    int total, {
    bool isMerge = false,
  }) {
    if (!mounted) return;

    final safeTotal = total <= 0 ? 1 : total;
    final progressPercent = ((current / safeTotal) * 100).clamp(0, 100).round();
    if (!_backupProgressUpdateGate.shouldUpdate(
      progressPercent: progressPercent,
      stageKey: isMerge ? 'merge' : 'restore',
    )) {
      return;
    }

    setState(() {
      _progress = progressPercent.toDouble();
      _progressText = isMerge
          ? '${l10n.mergingDataProgress} $current/$safeTotal'
          : l10n.restoringData(current, safeTotal);
    });
  }

  /// 显示还原确认对话框
  Future<bool> _showRestoreConfirmDialog() async {
    final l10n = AppLocalizations.of(context);
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.warning_amber,
                    color: AppSemanticColors.of(context).warning),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    l10n.restoreConfirmDialogTitle,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.restoreConfirmDialogDesc,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Text(l10n.restoreConfirmDialogItem1),
                Text(l10n.restoreConfirmDialogItem2),
                Text(l10n.restoreConfirmDialogItem3),
                const SizedBox(height: 16),
                Text(
                  l10n.restoreConfirmDialogWarning,
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                ),
                child: Text(l10n.confirmRestoreBtn),
              ),
            ],
          ),
        ) ??
        false;
  }

  /// 显示合并导入确认对话框
  Future<bool> _showMergeConfirmDialog() async {
    final l10n = AppLocalizations.of(context);
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.merge_type, color: Colors.indigo),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    l10n.mergeConfirmDialogTitle,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.mergeConfirmDialogDesc),
                const SizedBox(height: 8),
                Text(l10n.mergeConfirmDialogItem1),
                Text(l10n.mergeConfirmDialogItem2),
                Text(l10n.mergeConfirmDialogItem3),
                const SizedBox(height: 12),
                Text(l10n.mergeConfirmDialogReversible),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(l10n.startMerge),
              ),
            ],
          ),
        ) ??
        false;
  }

  /// 显示成功提示
  void _showSuccessSnackBar(String message) {
    AppSnackBar.success(context, message);
  }

  /// 显示错误对话框
  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.error, color: Theme.of(context).colorScheme.error),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                title,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );
  }
}
