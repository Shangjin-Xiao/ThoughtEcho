// ignore_for_file: invalid_use_of_protected_member
part of 'smart_push_settings_page.dart';

extension _SmartPushSettingsPageBasicSections on _SmartPushSettingsPageState {
  /// 主开关卡片
  Widget _buildMainSwitchCard(
    AppLocalizations l10n,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: _settings.enabled
              ? colorScheme.primary.withValues(alpha: 0.3)
              : colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      color: _settings.enabled
          ? colorScheme.primaryContainer.withValues(alpha: 0.3)
          : colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: _settings.enabled
                    ? colorScheme.primary.withValues(alpha: 0.15)
                    : colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                _settings.enabled
                    ? Icons.notifications_active
                    : Icons.notifications_off_outlined,
                color: _settings.enabled
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.smartPushEnable,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.smartPushEnableDesc,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: _settings.enabled,
              onChanged: (value) async {
                if (value) {
                  // 开启时请求权限
                  final smartPushService = context.read<SmartPushService>();

                  // 1. 请求通知权限
                  final hasNotificationPermission =
                      await smartPushService.requestNotificationPermission();
                  if (!hasNotificationPermission) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(l10n.smartPushPermissionRequired),
                        backgroundColor: colorScheme.error,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                    return;
                  }

                  // 2. 检查精确闹钟权限 (Android 12+)
                  final hasExactAlarmPermission =
                      await smartPushService.checkExactAlarmPermission();
                  if (!hasExactAlarmPermission) {
                    if (!mounted) return;
                    // 直接申请精确闹钟权限（无需询问）
                    final granted =
                        await smartPushService.requestExactAlarmPermission();
                    if (!granted && mounted) {
                      // 显示降级提示
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            AppLocalizations.of(context).exactAlarmDeniedHint,
                          ),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  }
                }

                if (!mounted) return;
                setState(() {
                  _settings = _settings.copyWith(enabled: value);
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 推送模式选择卡片 - 简化为智能/自定义两个选项
  Widget _buildModeSelectionCard(
    AppLocalizations l10n,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    // 将非 smart/custom 模式映射到 custom（兼容旧数据）
    final effectiveMode = (_settings.pushMode == PushMode.smart)
        ? PushMode.smart
        : PushMode.custom;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outline.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.category_outlined,
                  color: colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.smartPushContentType,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // 智能推送选项
            _buildSimpleModeOption(
              theme,
              colorScheme,
              isSelected: effectiveMode == PushMode.smart,
              icon: Icons.auto_awesome,
              title: l10n.smartPushModeSmart,
              subtitle: l10n.smartPushModeSmartDesc,
              isRecommended: true,
              onTap: () {
                setState(() {
                  _settings = _settings.copyWith(
                    pushMode: PushMode.smart,
                    showAdvancedOptions: false,
                  );
                  _animationController.reverse();
                });
              },
            ),
            const SizedBox(height: 8),
            // 自定义推送选项
            _buildSimpleModeOption(
              theme,
              colorScheme,
              isSelected: effectiveMode == PushMode.custom,
              icon: Icons.tune,
              title: l10n.smartPushModeCustom,
              subtitle: l10n.smartPushModeCustomDesc,
              onTap: () {
                setState(() {
                  _settings = _settings.copyWith(pushMode: PushMode.custom);
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 简化的模式选项组件
  Widget _buildSimpleModeOption(
    ThemeData theme,
    ColorScheme colorScheme, {
    required bool isSelected,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool isRecommended = false,
  }) {
    return Material(
      color: isSelected
          ? colorScheme.primaryContainer.withValues(alpha: 0.5)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isSelected
                      ? colorScheme.primary.withValues(alpha: 0.15)
                      : colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: isSelected
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: isSelected
                                ? FontWeight.w500
                                : FontWeight.normal,
                          ),
                        ),
                        if (isRecommended) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.primary.withValues(
                                alpha: 0.15,
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              AppLocalizations.of(context).recommended,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colorScheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                isSelected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: isSelected
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 显示所有推送相关权限的状态，并提供快捷修复入口
  Widget _buildPermissionStatusCard(
    AppLocalizations l10n,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    // 只有在启用了任何推送功能时才显示权限检查
    if (!_settings.enabled && !_settings.dailyQuotePushEnabled) {
      return const SizedBox.shrink();
    }

    return FutureBuilder<PushPermissionStatus>(
      future: context.read<SmartPushService>().getPushPermissionStatus(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }

        final status = snapshot.data!;

        // 如果所有权限都已授予，则不显示警告卡片
        // 注意：allPermissionsGranted 已包含自启动权限的判断
        if (status.allPermissionsGranted) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Card(
            elevation: 0,
            color: colorScheme.errorContainer.withValues(alpha: 0.3),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: colorScheme.error.withValues(alpha: 0.3)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: colorScheme.error,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          l10n.smartPushPermissionWarningTitle,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.smartPushPermissionWarningDesc,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onErrorContainer.withValues(
                        alpha: 0.8,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 通知权限
                  _buildPermissionItem(
                    icon: Icons.notifications_outlined,
                    title: l10n.smartPushNotificationPermission,
                    isGranted: status.notificationEnabled,
                    onTap: status.notificationEnabled
                        ? null
                        : () async {
                            final smartPushService =
                                context.read<SmartPushService>();
                            await smartPushService
                                .requestNotificationPermission();
                            setState(() {});
                          },
                    theme: theme,
                    colorScheme: colorScheme,
                  ),

                  // 精确闹钟权限 (Android 12+)
                  if (status.sdkVersion >= 31)
                    _buildPermissionItem(
                      icon: Icons.alarm_outlined,
                      title: l10n.smartPushExactAlarmTitle,
                      isGranted: status.exactAlarmEnabled,
                      onTap: status.exactAlarmEnabled
                          ? null
                          : () async {
                              final smartPushService =
                                  context.read<SmartPushService>();
                              await smartPushService
                                  .requestExactAlarmPermission();
                              setState(() {});
                            },
                      theme: theme,
                      colorScheme: colorScheme,
                    ),

                  // 电池优化豁免
                  _buildPermissionItem(
                    icon: Icons.battery_saver_outlined,
                    title: l10n.smartPushBatteryOptimization,
                    isGranted: status.batteryOptimizationExempted,
                    onTap: status.batteryOptimizationExempted
                        ? null
                        : () async {
                            final smartPushService =
                                context.read<SmartPushService>();
                            await smartPushService
                                .requestBatteryOptimizationExemption();
                            setState(() {});
                          },
                    theme: theme,
                    colorScheme: colorScheme,
                  ),

                  // 自启动权限（如果是需要的厂商）
                  if (status.needsAutoStartPermission)
                    _buildAutoStartItem(
                      smartPushService: context.read<SmartPushService>(),
                      manufacturer: status.manufacturer,
                      isGranted: status.autoStartGranted,
                      l10n: l10n,
                      theme: theme,
                      colorScheme: colorScheme,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// 构建单个权限项
  Widget _buildPermissionItem({
    required IconData icon,
    required String title,
    required bool isGranted,
    required VoidCallback? onTap,
    required ThemeData theme,
    required ColorScheme colorScheme,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            children: [
              Icon(
                isGranted ? Icons.check_circle : icon,
                size: 20,
                color: isGranted ? Colors.green : colorScheme.error,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onErrorContainer,
                    decoration: isGranted ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
              if (!isGranted)
                Icon(Icons.chevron_right, size: 20, color: colorScheme.error),
            ],
          ),
        ),
      ),
    );
  }

  /// 自启动权限项（带厂商特定指引）
  Widget _buildAutoStartItem({
    required SmartPushService smartPushService,
    required String manufacturer,
    required bool isGranted,
    required AppLocalizations l10n,
    required ThemeData theme,
    required ColorScheme colorScheme,
  }) {
    final instructions = smartPushService.getAutoStartInstructions(
      manufacturer,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: () {
          _showAutoStartInstructionsDialog(
            manufacturer: manufacturer,
            instructions: instructions,
            l10n: l10n,
            theme: theme,
            colorScheme: colorScheme,
          );
        },
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            children: [
              Icon(
                isGranted ? Icons.check_circle : Icons.rocket_launch_outlined,
                size: 20,
                color: isGranted ? Colors.green : colorScheme.error,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.smartPushAutoStartPermission,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onErrorContainer,
                        decoration:
                            isGranted ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    Text(
                      l10n.smartPushAutoStartHint,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onErrorContainer.withValues(
                          alpha: 0.7,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                isGranted ? Icons.chevron_right : Icons.help_outline,
                size: 20,
                color: isGranted
                    ? colorScheme.onSurfaceVariant.withValues(alpha: 0.5)
                    : colorScheme.error,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 显示自启动设置指引对话框
  void _showAutoStartInstructionsDialog({
    required String manufacturer,
    required String instructions,
    required AppLocalizations l10n,
    required ThemeData theme,
    required ColorScheme colorScheme,
  }) {
    final displayManufacturer = manufacturer.isNotEmpty
        ? manufacturer.toUpperCase()
        : l10n.smartPushUnknownManufacturer;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.rocket_launch_outlined, color: colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(l10n.smartPushAutoStartTitle)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                displayManufacturer,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.smartPushAutoStartInstructions,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(instructions, style: theme.textTheme.bodyMedium),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.smartPushAutoStartNote,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final smartPushService = Provider.of<SmartPushService>(
                context,
                listen: false,
              );
              await smartPushService.setAutoStartGranted(true);
              if (mounted) {
                Navigator.of(context).pop();
                // 刷新状态
                setState(() {});
              }
            },
            child: Text(l10n.iHaveConfigured),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );
  }

  Future<void> _editDailyQuoteTime() async {
    final slot = _settings.dailyQuotePushTime;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: slot.hour, minute: slot.minute),
    );
    if (time != null) {
      setState(() {
        _settings = _settings.copyWith(
          dailyQuotePushTime: slot.copyWith(
            hour: time.hour,
            minute: time.minute,
          ),
        );
      });
    }
  }
}
