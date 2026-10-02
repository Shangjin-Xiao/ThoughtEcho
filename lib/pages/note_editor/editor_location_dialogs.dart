part of '../note_full_editor_page.dart';

/// Location and weather dialog handlers and basic fetch methods.
extension _NoteEditorLocationDialogs on _NoteFullEditorPageState {
  Future<void> _showLocationDialogInEditor(
    BuildContext context,
    ThemeData theme,
  ) async {
    final action = await NoteMetadataDialogs.showLocationInfoDialog(
      context: context,
      location: _metadataState.originalLocation ?? _metadataState.location,
      latitude: _metadataState.originalLatitude,
      longitude: _metadataState.originalLongitude,
      poiName: _metadataState.poiName,
      isSelected: _metadataState.showLocation,
    );

    if (!mounted || !context.mounted || action == null) return;

    switch (action) {
      case NoteLocationDialogAction.remove:
        _updateState(() {
          _metadataState.showLocation = false;
          _metadataState.location = null;
          _metadataState.latitude = null;
          _metadataState.longitude = null;
          _metadataState.poiName = null;
          _metadataState.originalLocation = null;
          _metadataState.originalLatitude = null;
          _metadataState.originalLongitude = null;
        });
        break;
      case NoteLocationDialogAction.clearPoi:
        _updateState(() {
          _metadataState.poiName = null;
        });
        break;
      case NoteLocationDialogAction.updateLocation:
        if (_metadataState.originalLatitude != null &&
            _metadataState.originalLongitude != null) {
          final standardAddress =
              await NoteMetadataDialogs.updateAddressFromCoordinates(
            context: context,
            latitude: _metadataState.originalLatitude!,
            longitude: _metadataState.originalLongitude!,
          );
          if (standardAddress != null && mounted) {
            _updateState(() {
              _metadataState.location = standardAddress;
              _metadataState.originalLocation = standardAddress;
              _metadataState.showLocation = true;
            });
          }
        }
        break;
    }
  }

  /// 编辑模式下的天气对话框
  Future<void> _showWeatherDialogInEditor(
    BuildContext context,
    ThemeData theme,
  ) async {
    final action = await NoteMetadataDialogs.showWeatherInfoDialog(
      context: context,
      weather: _metadataState.originalWeather,
      temperature: _metadataState.temperature,
      isSelected: _metadataState.showWeather,
    );

    if (!mounted || action == null) return;

    switch (action) {
      case NoteWeatherDialogAction.remove:
        _updateState(() {
          _metadataState.showWeather = false;
          _metadataState.weather = null;
          _metadataState.temperature = null;
          _metadataState.originalWeather = null;
        });
        break;
    }
  }

  Future<void> _fetchLocationWeather() async {
    final locationService = Provider.of<LocationService>(
      context,
      listen: false,
    );
    final weatherService = Provider.of<WeatherService>(context, listen: false);

    // 检查并请求权限
    if (!await LocationWeatherHelper.ensureLocationPermission(
      locationService,
    )) {
      if (mounted && context.mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.cannotGetLocationPermissionShort),
            duration: AppConstants.snackBarDurationError,
          ),
        );
      }
      return;
    }

    final snapshot = await LocationWeatherHelper.fetchLocation(
      locationService,
    );
    if (snapshot != null && mounted) {
      // 优化：将网络请求包装为 Future，避免阻塞主线程
      try {
        // 更新位置信息（包括经纬度）
        _updateState(() {
          _metadataState.location =
              snapshot.location.isNotEmpty ? snapshot.location : null;
          _metadataState.latitude = snapshot.position.latitude;
          _metadataState.longitude = snapshot.position.longitude;
        });

        // 异步获取天气数据，不阻塞UI
        _fetchWeatherAsync(
          weatherService,
          snapshot.position.latitude,
          snapshot.position.longitude,
        );
      } catch (e) {
        logError('获取位置天气失败', error: e, source: 'NoteFullEditorPage');
      }
    } else if (mounted && context.mounted) {
      // 获取位置失败，给出提示
      final l10n = AppLocalizations.of(context);
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.cannotGetLocationTitle),
          content: Text(l10n.cannotGetLocationDesc),
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

  // 异步获取天气数据的辅助方法
  Future<void> _fetchWeatherAsync(
    WeatherService weatherService,
    double latitude,
    double longitude,
  ) async {
    try {
      await weatherService.getWeatherData(latitude, longitude);

      // 优化：仅在组件仍然挂载时更新状态
      if (mounted) {
        _updateState(() {
          _metadataState.weather = weatherService.currentWeather;
          _metadataState.temperature = weatherService.temperature;
        });
      }
    } catch (e) {
      logError('获取天气数据失败', error: e, source: 'NoteFullEditorPage');
    }
  }
}
