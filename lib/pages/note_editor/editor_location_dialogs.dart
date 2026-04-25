part of '../note_full_editor_page.dart';

/// Location and weather dialog handlers and basic fetch methods.
extension _NoteEditorLocationDialogs on _NoteFullEditorPageState {
  Future<void> _showLocationDialogInEditor(
    BuildContext context,
    ThemeData theme,
  ) async {
    final l10n = AppLocalizations.of(context);
    final hasLocationData =
        _originalLocation != null ||
        (_originalLatitude != null && _originalLongitude != null);
    final hasCoordinates =
        _originalLatitude != null && _originalLongitude != null;
    final hasOnlyCoordinates = _originalLocation == null && hasCoordinates;

    String title;
    String content;
    List<Widget> actions = [];

    if (!hasLocationData) {
      // 没有位置数据
      title = l10n.cannotAddLocation;
      content = l10n.cannotAddLocationDesc;
      actions = [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.iKnow),
        ),
      ];
    } else {
      // 有位置数据
      title = l10n.locationInfo;
      content = hasOnlyCoordinates
          ? l10n.locationUpdateHint(
              LocationService.formatCoordinates(
                _originalLatitude,
                _originalLongitude,
              ),
            )
          : l10n.locationRemoveHint(
              LocationService.formatLocationForDisplay(
                _originalLocation ?? _location,
              ),
            );
      actions = [
        if (_showLocation)
          TextButton(
            onPressed: () => Navigator.pop(context, 'remove'),
            child: Text(l10n.remove),
          ),
        if (hasOnlyCoordinates)
          TextButton(
            onPressed: () => Navigator.pop(context, 'update'),
            child: Text(l10n.updateLocation),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context, 'cancel'),
          child: Text(l10n.cancel),
        ),
      ];
    }

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: actions,
      ),
    );

    if (!mounted) {
      return; // Ensure the widget is still in the tree before using context
    }

    if (result == 'update' && hasCoordinates) {
      // 尝试用坐标更新地址
      try {
        // 获取当前语言设置（在异步操作前获取，避免context跨越异步间隙）
        if (!context.mounted) return;
        final locationService = Provider.of<LocationService>(
          context,
          listen: false,
        );
        final localeCode = locationService.currentLocaleCode;
        final addressInfo =
            await LocalGeocodingService.getAddressFromCoordinates(
              _originalLatitude!,
              _originalLongitude!,
              localeCode: localeCode,
            );
        if (addressInfo != null && mounted) {
          final formattedAddress = addressInfo['formatted_address'];
          if (formattedAddress != null && formattedAddress.isNotEmpty) {
            _updateState(() {
              _location = formattedAddress;
              _originalLocation = formattedAddress;
            });
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(l10n.locationUpdatedTo(formattedAddress)),
                ),
              );
            }
          } else if (context.mounted) {
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text(l10n.cannotGetLocationTitle),
                content: Text(l10n.cannotGetAddress),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(l10n.iKnow),
                  ),
                ],
              ),
            );
          }
        } else if (mounted && context.mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(l10n.cannotGetLocationTitle),
              content: Text(l10n.cannotGetAddress),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(l10n.iKnow),
                ),
              ],
            ),
          );
        }
      } catch (e) {
        if (mounted && context.mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(l10n.cannotGetLocationTitle),
              content: Text(l10n.updateFailed(e.toString())),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(l10n.iKnow),
                ),
              ],
            ),
          );
        }
      }
    } else if (result == 'remove') {
      _updateState(() {
        _showLocation = false;
      });
    }
  }

  /// 编辑模式下的天气对话框
  /// 注：天气编辑模式下暂时采用简化逻辑，此方法保留以备将来扩展
  // ignore: unused_element
  Future<void> _showWeatherDialogInEditor(
    BuildContext context,
    ThemeData theme,
  ) async {
    final l10n = AppLocalizations.of(context);
    final hasWeatherData = _originalWeather != null;

    String title;
    String content;
    List<Widget> actions = [];

    if (!hasWeatherData) {
      // 没有天气数据
      title = l10n.cannotAddWeather;
      content = l10n.cannotAddWeatherDesc;
      actions = [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.iKnow),
        ),
      ];
    } else {
      // 有天气数据
      final weatherDesc = WeatherService.getLocalizedWeatherDescription(
        AppLocalizations.of(context),
        _originalWeather!,
      );
      title = l10n.weatherInfo2;
      content = l10n.weatherRemoveHint(
        '$weatherDesc${_temperature != null ? " $_temperature" : ""}',
      );
      actions = [
        if (_showWeather)
          TextButton(
            onPressed: () => Navigator.pop(context, 'remove'),
            child: Text(l10n.remove),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context, 'cancel'),
          child: Text(l10n.cancel),
        ),
      ];
    }

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: actions,
      ),
    );

    if (result == 'remove') {
      _updateState(() {
        _showWeather = false;
      });
    }
  }

  /// 编辑模式下手动获取位置和天气
  Future<void> _fetchLocationWeather() async {
    final result = await LocationWeatherHelper.fetch(
      context: context,
      includeWeather: true,
      showPermissionDialog: false, // 权限失败显示 SnackBar
    );

    if (result.permissionDenied && mounted) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.cannotGetLocationPermissionShort),
          duration: AppConstants.snackBarDurationError,
        ),
      );
      return;
    }

    if (mounted) {
      _updateState(() {
        if (result.hasLocation) {
          _location = result.address;
          _latitude = result.latitude;
          _longitude = result.longitude;
        }
        if (result.hasWeather) {
          _weather = result.weather;
          _temperature = result.temperature;
        }
      });
    }
  }
}
