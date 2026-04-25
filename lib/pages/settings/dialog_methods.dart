part of '../settings_page.dart';

/// Extension containing dialog and interaction methods
extension _DialogMethods on SettingsPageState {
  // --- 版本检查方法 ---
  Future<void> _checkForUpdates({bool showNoUpdateMessage = true}) async {
    if (_isCheckingUpdate) return;

    setState(() {
      _isCheckingUpdate = true;
      _updateCheckMessage = null;
    });

    try {
      final versionInfo = await VersionCheckService.checkForUpdates(
        forceRefresh: true,
      );

      setState(() {
        _isCheckingUpdate = false;
      });

      if (mounted) {
        await UpdateBottomSheet.show(
          context,
          versionInfo,
          showNoUpdateMessage: showNoUpdateMessage,
        );
      }
    } catch (e) {
      setState(() {
        _isCheckingUpdate = false;
        _updateCheckMessage = e.toString();
      });

      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.checkUpdateFailed(e.toString())),
            backgroundColor: Theme.of(context).colorScheme.error,
            duration: AppConstants.snackBarDurationError,
          ),
        );
      }
    }
  }

  // 显示城市搜索对话框
  void _showCitySearchDialog(BuildContext context) {
    final locationService = Provider.of<LocationService>(
      context,
      listen: false,
    );
    final weatherService = Provider.of<WeatherService>(context, listen: false);

    // 创建天气搜索控制器
    final weatherController = WeatherSearchController(
      locationService,
      weatherService,
    );

    showDialog(
      context: context,
      builder: (dialogContext) => ChangeNotifierProvider.value(
        value: weatherController,
        child: Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            height: MediaQuery.of(context).size.height * 0.7,
            width: MediaQuery.of(context).size.width * 0.9,
            padding: const EdgeInsets.all(8.0),
            child: CitySearchWidget(
              weatherController: weatherController,
              initialCity: locationService.city,
              onSuccess: () {
                // 刷新设置页面的状态
                if (mounted) {
                  setState(() {
                    _locationController.text =
                        locationService.getFormattedLocation();
                  });
                }
              },
            ),
          ),
        ),
      ),
    ).then((_) {
      // 对话框关闭后，释放控制器
      weatherController.dispose();
    });
  }

  // --- 处理 Logo 三击激活开发者模式 ---
  void _handleLogoTap() async {
    final now = DateTime.now();

    // 如果距离上次点击超过2秒，重置计数
    if (_lastLogoTap != null && now.difference(_lastLogoTap!).inSeconds > 2) {
      _logoTapCount = 0;
    }

    _lastLogoTap = now;
    _logoTapCount++;

    if (_logoTapCount >= 3) {
      _logoTapCount = 0;
      final settingsService = context.read<SettingsService>();
      final currentSettings = settingsService.appSettings;
      final newDeveloperMode = !currentSettings.developerMode;

      await settingsService.updateAppSettings(
        currentSettings.copyWith(developerMode: newDeveloperMode),
      );

      // 同步更新日志服务的持久化状态
      UnifiedLogService.instance.setPersistenceEnabled(newDeveloperMode);

      if (!mounted) return;
      final l10n = AppLocalizations.of(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newDeveloperMode
                ? l10n.developerModeEnabled
                : l10n.developerModeDisabled,
          ),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );

      // 关闭对话框
      Navigator.of(context).pop();
    }
  }
}
