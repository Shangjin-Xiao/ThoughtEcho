part of '../settings_page.dart';

/// Extension containing helper methods
extension _HelperMethods on SettingsPageState {
  // --- 辅助函数：启动 URL ---
  Future<void> _launchUrl(String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.cannotOpenLink(url)),
          duration: AppConstants.snackBarDurationError,
        ),
      );
    }
  }

  /// 当设置页真正可见时触发功能引导
  void showGuidesIfNeeded({bool Function()? shouldShow}) {
    if (_guidesTriggered) return;

    final allShown =
        FeatureGuideHelper.hasShown(context, 'settings_preferences') &&
            FeatureGuideHelper.hasShown(context, 'settings_startup') &&
            FeatureGuideHelper.hasShown(context, 'settings_theme');

    if (allShown) {
      _guidesTriggered = true;
      return;
    }

    _guidesTriggered = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showSettingsGuides(shouldShow: shouldShow);
    });
  }

  /// 显示设置页功能引导
  void _showSettingsGuides({bool Function()? shouldShow}) {
    // 依次显示多个引导，等待前一个消失再显示下一个
    FeatureGuideHelper.showSequence(
      context: context,
      guides: [
        ('settings_preferences', _preferencesGuideKey),
        ('settings_startup', _startupPageGuideKey),
        ('settings_theme', _themeGuideKey),
      ],
      shouldShow: () {
        if (!mounted) {
          return false;
        }
        if (shouldShow != null && !shouldShow()) {
          return false;
        }
        return true;
      },
    );
  }

  void _initLocationController() {
    // 延迟初始化，确保 Provider 可用
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final locationService = Provider.of<LocationService>(
          context,
          listen: false,
        );
        _locationController.text = locationService.getFormattedLocation();
      }
    });
  }
}
