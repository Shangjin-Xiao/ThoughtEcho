import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../extensions/note_category_localization_extension.dart';
import '../gen_l10n/app_localizations.dart';
import '../models/smart_push_settings.dart';
import '../models/note_category.dart';
import '../services/smart_push_service.dart';
import '../services/database_service.dart';
import '../services/settings_service.dart';
import '../constants/app_constants.dart';

part 'smart_push_settings_page_basic_sections.dart';
part 'smart_push_settings_page_custom_sections.dart';
part 'smart_push_settings_page_misc_sections.dart';

/// 智能推送设置页面
/// 重构版：简洁现代的UI设计，智能推送为默认模式
// Refactored: settings categories split into separate part files.
class SmartPushSettingsPage extends StatefulWidget {
  const SmartPushSettingsPage({super.key});

  @override
  State<SmartPushSettingsPage> createState() => _SmartPushSettingsPageState();
}

class _SmartPushSettingsPageState extends State<SmartPushSettingsPage>
    with SingleTickerProviderStateMixin {
  SmartPushSettings _settings = SmartPushSettings.defaultSettings();
  List<NoteCategory> _availableTags = [];
  bool _isLoading = true;
  bool _isTesting = false;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
    _loadData();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final smartPushService = context.read<SmartPushService>();
      final databaseService = context.read<DatabaseService>();

      final tags = await databaseService.getCategories();

      if (mounted) {
        setState(() {
          _settings = smartPushService.settings;
          _availableTags = tags;
          _isLoading = false;
        });
        if (_settings.showAdvancedOptions) {
          _animationController.forward();
        }

        // 检查是否有精确闹钟权限（如果已启用功能但缺少权限）
        // 延迟执行以确保页面已构建完成
        if ((_settings.enabled || _settings.dailyQuotePushEnabled) && mounted) {
          Future.delayed(const Duration(milliseconds: 500), () {
            _checkPermissionAndShowDialog();
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).loadFailed(e.toString()),
            ),
            duration: AppConstants.snackBarDurationError,
          ),
        );
      }
    }
  }

  Future<void> _saveSettings() async {
    try {
      final smartPushService = context.read<SmartPushService>();
      await smartPushService.saveSettings(_settings);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).settingsSaved),
            duration: AppConstants.snackBarDurationNormal,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).saveFailed(e.toString()),
            ),
            duration: AppConstants.snackBarDurationError,
          ),
        );
      }
    }
  }

  Future<void> _testPush() async {
    setState(() => _isTesting = true);
    try {
      final smartPushService = context.read<SmartPushService>();

      final hasPermission = await smartPushService
          .requestNotificationPermission();
      if (!hasPermission) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(context).smartPushPermissionRequired,
              ),
              duration: AppConstants.snackBarDurationError,
            ),
          );
        }
        return;
      }

      final previewNote = await smartPushService.previewPush();
      if (previewNote == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(context).smartPushNoMatchingNotes,
              ),
              duration: AppConstants.snackBarDurationNormal,
            ),
          );
        }
        return;
      }

      await smartPushService.triggerPush();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).smartPushTestSent),
            duration: AppConstants.snackBarDurationNormal,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).testFailed(e.toString()),
            ),
            duration: AppConstants.snackBarDurationError,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isTesting = false);
      }
    }
  }

  Future<void> _checkPermissionAndShowDialog() async {
    if (!mounted) return;
    try {
      final smartPushService = context.read<SmartPushService>();
      final hasExactAlarmPermission = await smartPushService
          .checkExactAlarmPermission();

      if (!hasExactAlarmPermission && mounted) {
        // 直接申请精确闹钟权限（无需询问）
        final granted = await smartPushService.requestExactAlarmPermission();
        if (!granted && mounted) {
          final l10n = AppLocalizations.of(context);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(l10n.exactAlarmDeniedHint),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
        // 刷新页面状态以更新警告卡片
        if (mounted) {
          setState(() {});
        }
      }
    } catch (e) {
      // 忽略检查错误
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.smartPushTitle)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.smartPushTitle),
        actions: [
          TextButton.icon(
            onPressed: _saveSettings,
            icon: const Icon(Icons.check),
            label: Text(l10n.save),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          // 主开关卡片
          _buildMainSwitchCard(l10n, theme, colorScheme),

          if (_settings.enabled || _settings.dailyQuotePushEnabled) ...[
            const SizedBox(height: 16),

            // 权限状态卡片（检测所有必需权限）
            _buildPermissionStatusCard(l10n, theme, colorScheme),
          ],

          if (_settings.enabled) ...[
            const SizedBox(height: 16),

            // 推送模式选择（只显示 智能/自定义 两个选项）
            _buildModeSelectionCard(l10n, theme, colorScheme),

            // 自定义模式：显示完整高级选项
            if (_settings.pushMode == PushMode.custom) ...[
              const SizedBox(height: 16),

              // 推送时间设置
              _buildTimeSettingsCard(l10n, theme, colorScheme),

              const SizedBox(height: 16),

              // 推送频率
              _buildFrequencyCard(l10n, theme, colorScheme),

              const SizedBox(height: 16),

              // 高级选项（回顾类型、天气筛选、标签筛选）
              _buildAdvancedOptionsCard(l10n, theme, colorScheme),
            ],

            const SizedBox(height: 24),

            // 测试推送按钮 - 仅在开发者模式显示
            Consumer<SettingsService>(
              builder: (context, settingsService, _) {
                if (!settingsService.appSettings.developerMode) {
                  return const SizedBox.shrink();
                }
                return _buildTestButton(l10n, theme, colorScheme);
              },
            ),

            const SizedBox(height: 16),

            // 每日一言独立推送（始终显示，独立于智能推送开关）
            _buildDailyQuoteCard(l10n, theme, colorScheme),

            const SizedBox(height: 16),

            // 说明卡片
            _buildNoticeCard(l10n, theme, colorScheme),
          ],

          // 当智能推送未启用时，每日一言卡片单独显示
          if (!_settings.enabled) ...[
            const SizedBox(height: 16),

            // 每日一言独立推送（始终显示，独立于智能推送开关）
            _buildDailyQuoteCard(l10n, theme, colorScheme),
          ],

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  /// 主开关卡片
}
