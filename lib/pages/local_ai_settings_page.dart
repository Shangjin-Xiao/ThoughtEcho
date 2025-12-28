import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../gen_l10n/app_localizations.dart';
import '../models/local_ai_settings.dart';
import '../models/local_ai_model_config.dart';
import '../services/settings_service.dart';
import '../services/local_ai/local_ai_model_manager.dart';
import '../services/local_ai/local_vector_storage_service.dart';
import '../theme/app_theme.dart';

/// 本地 AI 功能设置页面
/// 
/// 显示并管理所有设备端 AI 功能的开关设置
class LocalAISettingsPage extends StatefulWidget {
  const LocalAISettingsPage({super.key});

  @override
  State<LocalAISettingsPage> createState() => _LocalAISettingsPageState();
}

class _LocalAISettingsPageState extends State<LocalAISettingsPage> {
  final LocalAIModelManager _modelManager = LocalAIModelManager();
  final LocalVectorStorageService _vectorStorage = LocalVectorStorageService();
  
  Map<String, int>? _storageUsage;
  int? _embeddingCount;
  bool _isLoadingStats = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _isLoadingStats = true);
    try {
      final usage = await _modelManager.getStorageUsage();
      await _vectorStorage.initialize();
      final count = await _vectorStorage.getEmbeddingCount();
      if (mounted) {
        setState(() {
          _storageUsage = usage;
          _embeddingCount = count;
          _isLoadingStats = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingStats = false);
      }
    }
  }

  @override
  void dispose() {
    _modelManager.dispose();
    _vectorStorage.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settingsService = Provider.of<SettingsService>(context);
    final localAISettings = settingsService.localAISettings;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 1,
        backgroundColor: theme.colorScheme.surface,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.localAiFeatures),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.primaryContainer,
                    theme.colorScheme.secondaryContainer,
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.science_rounded,
                    size: 12,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    l10n.localAiFeaturesPreview,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onPrimaryContainer,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          // 顶部说明卡片
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
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
                  width: 1.5,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.info_rounded,
                        color: theme.colorScheme.primary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.localAiPreviewNote,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurface,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 主开关卡片
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                side: BorderSide(
                  color: theme.colorScheme.outline.withOpacity(0.2),
                ),
              ),
              child: Container(
                decoration: BoxDecoration(
                  gradient: localAISettings.enabled
                      ? LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            theme.colorScheme.primaryContainer.withOpacity(0.5),
                            theme.colorScheme.surface,
                          ],
                        )
                      : null,
                  borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                ),
                child: SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  secondary: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: localAISettings.enabled
                          ? theme.colorScheme.primary.withOpacity(0.15)
                          : theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      localAISettings.enabled
                          ? Icons.psychology_rounded
                          : Icons.psychology_outlined,
                      color: localAISettings.enabled
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                      size: 28,
                    ),
                  ),
                  title: Text(
                    l10n.enableLocalAi,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      l10n.enableLocalAiDesc,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ),
                  value: localAISettings.enabled,
                  onChanged: (value) {
                    _updateSettings(
                      settingsService,
                      localAISettings.copyWith(enabled: value),
                    );
                  },
                ),
              ),
            ),
          ),

          // 功能分组
          if (localAISettings.enabled) ...[
            const SizedBox(height: 16),
            
            // 输入增强组
            _buildFeatureGroup(
              context: context,
              theme: theme,
              title: l10n.localAIInputEnhancement,
              icon: Icons.input_rounded,
              iconColor: Colors.blue,
              children: [
                _buildFeatureTile(
                  context: context,
                  theme: theme,
                  icon: Icons.mic_rounded,
                  title: l10n.localAISpeechToText,
                  subtitle: l10n.localAISpeechToTextDesc,
                  value: localAISettings.speechToTextEnabled,
                  onChanged: (value) => _updateSettings(
                    settingsService,
                    localAISettings.copyWith(speechToTextEnabled: value),
                  ),
                ),
                _buildFeatureTile(
                  context: context,
                  theme: theme,
                  icon: Icons.document_scanner_rounded,
                  title: l10n.ocrRecognition,
                  subtitle: l10n.ocrRecognitionDesc,
                  value: localAISettings.ocrEnabled,
                  onChanged: (value) => _updateSettings(
                    settingsService,
                    localAISettings.copyWith(ocrEnabled: value),
                  ),
                ),
                _buildFeatureTile(
                  context: context,
                  theme: theme,
                  icon: Icons.auto_fix_high_rounded,
                  title: l10n.aiCorrection,
                  subtitle: l10n.aiCorrectionDesc,
                  value: localAISettings.aiCorrectionEnabled,
                  onChanged: (value) => _updateSettings(
                    settingsService,
                    localAISettings.copyWith(aiCorrectionEnabled: value),
                  ),
                ),
                _buildFeatureTile(
                  context: context,
                  theme: theme,
                  icon: Icons.source_rounded,
                  title: l10n.localAISourceRecognition,
                  subtitle: l10n.localAISourceRecognitionDesc,
                  value: localAISettings.sourceRecognitionEnabled,
                  onChanged: (value) => _updateSettings(
                    settingsService,
                    localAISettings.copyWith(sourceRecognitionEnabled: value),
                  ),
                  isLast: true,
                ),
              ],
            ),

            const SizedBox(height: 12),

            // 搜索与发现组
            _buildFeatureGroup(
              context: context,
              theme: theme,
              title: l10n.localAISearchDiscovery,
              icon: Icons.explore_rounded,
              iconColor: Colors.purple,
              children: [
                _buildFeatureTile(
                  context: context,
                  theme: theme,
                  icon: Icons.search_rounded,
                  title: l10n.aiSearch,
                  subtitle: l10n.aiSearchDesc,
                  value: localAISettings.aiSearchEnabled,
                  onChanged: (value) => _updateSettings(
                    settingsService,
                    localAISettings.copyWith(aiSearchEnabled: value),
                  ),
                ),
                _buildFeatureTile(
                  context: context,
                  theme: theme,
                  icon: Icons.link_rounded,
                  title: l10n.localAIRelatedNotes,
                  subtitle: l10n.localAIRelatedNotesDesc,
                  value: localAISettings.relatedNotesEnabled,
                  onChanged: (value) => _updateSettings(
                    settingsService,
                    localAISettings.copyWith(relatedNotesEnabled: value),
                  ),
                  isLast: true,
                ),
              ],
            ),

            const SizedBox(height: 12),

            // 内容分析组
            _buildFeatureGroup(
              context: context,
              theme: theme,
              title: l10n.localAIContentAnalysis,
              icon: Icons.analytics_rounded,
              iconColor: Colors.orange,
              children: [
                _buildFeatureTile(
                  context: context,
                  theme: theme,
                  icon: Icons.label_rounded,
                  title: l10n.smartTags,
                  subtitle: l10n.smartTagsDesc,
                  value: localAISettings.smartTagsEnabled,
                  onChanged: (value) => _updateSettings(
                    settingsService,
                    localAISettings.copyWith(smartTagsEnabled: value),
                  ),
                ),
                _buildFeatureTile(
                  context: context,
                  theme: theme,
                  icon: Icons.category_rounded,
                  title: l10n.localAINoteClassification,
                  subtitle: l10n.localAINoteClassificationDesc,
                  value: localAISettings.noteClassificationEnabled,
                  onChanged: (value) => _updateSettings(
                    settingsService,
                    localAISettings.copyWith(noteClassificationEnabled: value),
                  ),
                ),
                _buildFeatureTile(
                  context: context,
                  theme: theme,
                  icon: Icons.sentiment_satisfied_rounded,
                  title: l10n.localAIEmotionDetection,
                  subtitle: l10n.localAIEmotionDetectionDesc,
                  value: localAISettings.emotionDetectionEnabled,
                  onChanged: (value) => _updateSettings(
                    settingsService,
                    localAISettings.copyWith(emotionDetectionEnabled: value),
                  ),
                  isLast: true,
                ),
              ],
            ),

            const SizedBox(height: 24),

            // 模型管理组
            _buildModelManagementSection(
              context: context,
              theme: theme,
              l10n: l10n,
              settingsService: settingsService,
              localAISettings: localAISettings,
            ),

            const SizedBox(height: 24),
          ],
        ],
      ),
    );
  }

  /// 构建模型管理部分
  Widget _buildModelManagementSection({
    required BuildContext context,
    required ThemeData theme,
    required AppLocalizations l10n,
    required SettingsService settingsService,
    required LocalAISettings localAISettings,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.teal.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.model_training_rounded,
                    size: 18,
                    color: Colors.teal,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  l10n.localAiModelManagement,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          
          // 模型卡片
          Card(
            elevation: 0,
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.cardRadius),
              side: BorderSide(
                color: theme.colorScheme.outline.withOpacity(0.2),
              ),
            ),
            child: Column(
              children: [
                // 嵌入模型
                _buildModelTile(
                  context: context,
                  theme: theme,
                  l10n: l10n,
                  icon: Icons.hub_rounded,
                  title: l10n.embeddingModel,
                  subtitle: l10n.embeddingModelDesc,
                  recommendation: l10n.embeddingModelRecommendation,
                  modelInfo: localAISettings.modelConfig.embeddingModel,
                  onImport: () => _importEmbeddingModel(settingsService, localAISettings),
                  onDelete: localAISettings.modelConfig.embeddingModel != null
                      ? () => _deleteModel(settingsService, localAISettings, LocalAIModelType.embedding)
                      : null,
                ),
                Divider(height: 1, indent: 72, endIndent: 16, color: theme.colorScheme.outline.withOpacity(0.1)),
                
                // ASR 模型
                _buildModelTile(
                  context: context,
                  theme: theme,
                  l10n: l10n,
                  icon: Icons.mic_rounded,
                  title: l10n.asrModel,
                  subtitle: l10n.asrModelDesc,
                  recommendation: l10n.asrModelRecommendation,
                  modelInfo: localAISettings.modelConfig.asrModel,
                  onImport: () => _importASRModel(settingsService, localAISettings),
                  onDelete: localAISettings.modelConfig.asrModel != null
                      ? () => _deleteModel(settingsService, localAISettings, LocalAIModelType.asr)
                      : null,
                ),
                Divider(height: 1, indent: 72, endIndent: 16, color: theme.colorScheme.outline.withOpacity(0.1)),
                
                // OCR 模型
                _buildModelTile(
                  context: context,
                  theme: theme,
                  l10n: l10n,
                  icon: Icons.document_scanner_rounded,
                  title: l10n.ocrModel,
                  subtitle: l10n.ocrModelDesc,
                  recommendation: l10n.ocrModelRecommendation,
                  modelInfo: localAISettings.modelConfig.ocrModel,
                  onImport: () => _showOCRImportDialog(context, settingsService, localAISettings),
                  onDelete: localAISettings.modelConfig.ocrModel != null
                      ? () => _deleteModel(settingsService, localAISettings, LocalAIModelType.ocr)
                      : null,
                  isLast: true,
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // 存储统计
          _buildStorageStatsCard(context, theme, l10n),
        ],
      ),
    );
  }

  /// 构建模型项
  Widget _buildModelTile({
    required BuildContext context,
    required ThemeData theme,
    required AppLocalizations l10n,
    required IconData icon,
    required String title,
    required String subtitle,
    required String recommendation,
    LocalAIModelInfo? modelInfo,
    required VoidCallback onImport,
    VoidCallback? onDelete,
    bool isLast = false,
  }) {
    final isInstalled = modelInfo?.isReady ?? false;
    final statusText = isInstalled ? l10n.modelReady : l10n.modelNotInstalled;
    final statusColor = isInstalled ? Colors.green : theme.colorScheme.onSurfaceVariant;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isInstalled
              ? Colors.green.withOpacity(0.15)
              : theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          color: isInstalled ? Colors.green : theme.colorScheme.onSurfaceVariant,
          size: 22,
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              statusText,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: statusColor,
              ),
            ),
          ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.3,
            ),
          ),
          if (modelInfo != null && modelInfo.fileSize != null) ...[
            const SizedBox(height: 4),
            Text(
              l10n.modelFileSize(LocalAIModelManager.formatFileSize(modelInfo.fileSize!)),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 帮助按钮
          IconButton(
            icon: Icon(
              Icons.help_outline_rounded,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            tooltip: l10n.recommendedModels,
            onPressed: () => _showRecommendationDialog(context, title, recommendation),
          ),
          // 导入/删除按钮
          if (isInstalled && onDelete != null)
            IconButton(
              icon: Icon(
                Icons.delete_outline_rounded,
                size: 20,
                color: theme.colorScheme.error,
              ),
              tooltip: l10n.deleteModel,
              onPressed: () => _confirmDeleteModel(context, l10n, onDelete),
            )
          else
            IconButton(
              icon: Icon(
                Icons.add_circle_outline_rounded,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              tooltip: l10n.importModel,
              onPressed: onImport,
            ),
        ],
      ),
    );
  }

  /// 构建存储统计卡片
  Widget _buildStorageStatsCard(BuildContext context, ThemeData theme, AppLocalizations l10n) {
    if (_isLoadingStats) {
      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          side: BorderSide(color: theme.colorScheme.outline.withOpacity(0.2)),
        ),
        child: const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }

    int totalSize = 0;
    if (_storageUsage != null) {
      for (final size in _storageUsage!.values) {
        totalSize += size;
      }
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        side: BorderSide(color: theme.colorScheme.outline.withOpacity(0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.storage_rounded,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.modelStorageUsage,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  l10n.totalModelSize(LocalAIModelManager.formatFileSize(totalSize)),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            if (_embeddingCount != null && _embeddingCount! > 0) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    Icons.data_array_rounded,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    l10n.embeddingCount(_embeddingCount!),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 导入嵌入模型
  Future<void> _importEmbeddingModel(
    SettingsService settingsService,
    LocalAISettings currentSettings,
  ) async {
    final l10n = AppLocalizations.of(context);
    
    _showLoadingDialog(context, l10n.importingModel);
    
    try {
      final modelInfo = await _modelManager.importEmbeddingModel();
      Navigator.of(context).pop(); // 关闭加载对话框
      
      if (modelInfo != null) {
        final newConfig = currentSettings.modelConfig.copyWith(
          embeddingModel: modelInfo,
        );
        await settingsService.updateLocalAISettings(
          currentSettings.copyWith(modelConfig: newConfig),
        );
        _loadStats();
        _showSnackBar(l10n.modelImported, isSuccess: true);
      } else if (_modelManager.error != null) {
        _showSnackBar(l10n.modelImportFailed(_modelManager.error!), isError: true);
      } else {
        _showSnackBar(l10n.modelImportCancelled);
      }
    } catch (e) {
      Navigator.of(context).pop();
      _showSnackBar(l10n.modelImportFailed(e.toString()), isError: true);
    }
  }

  /// 导入 ASR 模型
  Future<void> _importASRModel(
    SettingsService settingsService,
    LocalAISettings currentSettings,
  ) async {
    final l10n = AppLocalizations.of(context);
    
    _showLoadingDialog(context, l10n.importingModel);
    
    try {
      final modelInfo = await _modelManager.importASRModel();
      Navigator.of(context).pop();
      
      if (modelInfo != null) {
        final newConfig = currentSettings.modelConfig.copyWith(
          asrModel: modelInfo,
        );
        await settingsService.updateLocalAISettings(
          currentSettings.copyWith(modelConfig: newConfig),
        );
        _loadStats();
        _showSnackBar(l10n.modelImported, isSuccess: true);
      } else if (_modelManager.error != null) {
        _showSnackBar(l10n.modelImportFailed(_modelManager.error!), isError: true);
      } else {
        _showSnackBar(l10n.modelImportCancelled);
      }
    } catch (e) {
      Navigator.of(context).pop();
      _showSnackBar(l10n.modelImportFailed(e.toString()), isError: true);
    }
  }

  /// 显示 OCR 导入选择对话框
  Future<void> _showOCRImportDialog(
    BuildContext context,
    SettingsService settingsService,
    LocalAISettings currentSettings,
  ) async {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.ocrEngineType),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.text_fields_rounded),
              title: Text(l10n.useTesseract),
              subtitle: const Text('chi_sim + eng'),
              onTap: () => Navigator.of(context).pop(false),
            ),
            ListTile(
              leading: const Icon(Icons.translate_rounded),
              title: Text(l10n.usePaddleOCR),
              subtitle: const Text('PaddleOCR Lite'),
              onTap: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancel),
          ),
        ],
      ),
    );
    
    if (result != null) {
      await _importOCRModel(settingsService, currentSettings, usePaddleOCR: result);
    }
  }

  /// 导入 OCR 模型
  Future<void> _importOCRModel(
    SettingsService settingsService,
    LocalAISettings currentSettings, {
    required bool usePaddleOCR,
  }) async {
    final l10n = AppLocalizations.of(context);
    
    _showLoadingDialog(context, l10n.importingModel);
    
    try {
      final modelInfo = await _modelManager.importOCRModel(usePaddleOCR: usePaddleOCR);
      Navigator.of(context).pop();
      
      if (modelInfo != null) {
        final newConfig = currentSettings.modelConfig.copyWith(
          ocrModel: modelInfo,
        );
        await settingsService.updateLocalAISettings(
          currentSettings.copyWith(modelConfig: newConfig),
        );
        _loadStats();
        _showSnackBar(l10n.modelImported, isSuccess: true);
      } else if (_modelManager.error != null) {
        _showSnackBar(l10n.modelImportFailed(_modelManager.error!), isError: true);
      } else {
        _showSnackBar(l10n.modelImportCancelled);
      }
    } catch (e) {
      Navigator.of(context).pop();
      _showSnackBar(l10n.modelImportFailed(e.toString()), isError: true);
    }
  }

  /// 删除模型
  Future<void> _deleteModel(
    SettingsService settingsService,
    LocalAISettings currentSettings,
    LocalAIModelType type,
  ) async {
    final l10n = AppLocalizations.of(context);
    
    final success = await _modelManager.deleteModel(type);
    
    if (success) {
      LocalAIModelConfig newConfig;
      switch (type) {
        case LocalAIModelType.embedding:
          newConfig = currentSettings.modelConfig.copyWith(clearEmbeddingModel: true);
          break;
        case LocalAIModelType.asr:
          newConfig = currentSettings.modelConfig.copyWith(clearAsrModel: true);
          break;
        case LocalAIModelType.ocr:
          newConfig = currentSettings.modelConfig.copyWith(clearOcrModel: true);
          break;
      }
      
      await settingsService.updateLocalAISettings(
        currentSettings.copyWith(modelConfig: newConfig),
      );
      _loadStats();
      _showSnackBar(l10n.modelDeleted, isSuccess: true);
    } else {
      _showSnackBar(l10n.modelDeleteFailed('Unknown error'), isError: true);
    }
  }

  /// 确认删除模型
  Future<void> _confirmDeleteModel(
    BuildContext context,
    AppLocalizations l10n,
    VoidCallback onConfirm,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteModel),
        content: Text(l10n.deleteModelConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      onConfirm();
    }
  }

  /// 显示推荐模型对话框
  void _showRecommendationDialog(
    BuildContext context,
    String title,
    String recommendation,
  ) {
    final l10n = AppLocalizations.of(context);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.recommendedModels,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(recommendation),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: Text(l10n.viewDownloadLinks),
              onPressed: () {
                // 复制下载链接到剪贴板
                final recommendations = LocalAIModelRecommendations.embeddingModels;
                if (recommendations.isNotEmpty) {
                  Clipboard.setData(ClipboardData(text: recommendations.first['url'] ?? ''));
                  _showSnackBar(l10n.downloadLinkCopied);
                }
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.close),
          ),
        ],
      ),
    );
  }

  /// 显示加载对话框
  void _showLoadingDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(strokeWidth: 2),
            const SizedBox(width: 24),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }

  /// 显示 SnackBar
  void _showSnackBar(String message, {bool isSuccess = false, bool isError = false}) {
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError 
            ? Theme.of(context).colorScheme.error
            : isSuccess 
                ? Colors.green 
                : null,
      ),
    );
  }

  /// 构建功能分组
  Widget _buildFeatureGroup({
    required BuildContext context,
    required ThemeData theme,
    required String title,
    required IconData icon,
    required Color iconColor,
    required List<Widget> children,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    icon,
                    size: 18,
                    color: iconColor,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          Card(
            elevation: 0,
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.cardRadius),
              side: BorderSide(
                color: theme.colorScheme.outline.withOpacity(0.2),
              ),
            ),
            child: Column(
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建功能开关项
  Widget _buildFeatureTile({
    required BuildContext context,
    required ThemeData theme,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool isLast = false,
  }) {
    return Column(
      children: [
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 4,
          ),
          secondary: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: value
                  ? theme.colorScheme.primaryContainer.withOpacity(0.5)
                  : theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: value
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
              size: 22,
            ),
          ),
          title: Text(
            title,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.3,
              ),
            ),
          ),
          value: value,
          onChanged: onChanged,
        ),
        if (!isLast)
          Divider(
            height: 1,
            indent: 72,
            endIndent: 16,
            color: theme.colorScheme.outline.withOpacity(0.1),
          ),
      ],
    );
  }

  /// 更新设置
  Future<void> _updateSettings(
    SettingsService service,
    LocalAISettings settings,
  ) async {
    await service.updateLocalAISettings(settings);
  }
}
