part of '../note_full_editor_page.dart';

/// Location and weather dialog handlers and basic fetch methods.
extension _NoteEditorLocationDialogs on _NoteFullEditorPageState {
  // ignore: unused_element
  Future<void> _showLocationDialogInEditor(
    BuildContext context,
    ThemeData theme,
  ) async {
    final l10n = AppLocalizations.of(context);
    final hasLocationData = _metadataState.originalLocation != null ||
        (_metadataState.originalLatitude != null &&
            _metadataState.originalLongitude != null);
    final hasCoordinates = _metadataState.originalLatitude != null &&
        _metadataState.originalLongitude != null;
    final hasOnlyCoordinates =
        _metadataState.originalLocation == null && hasCoordinates;
    final hasPoiName = _metadataState.poiName != null &&
        _metadataState.poiName!.trim().isNotEmpty;

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
      final locationInfoText = hasOnlyCoordinates
          ? l10n.locationUpdateHint(
              LocationService.formatCoordinates(
                _metadataState.originalLatitude,
                _metadataState.originalLongitude,
              ),
            )
          : l10n.locationRemoveHint(
              LocationService.formatLocationForDisplay(
                _metadataState.originalLocation ?? _metadataState.location,
              ),
            );
      content = hasPoiName
          ? '${l10n.poiNameLabel}: ${_metadataState.poiName!.trim()}\n\n$locationInfoText'
          : locationInfoText;
      actions = [
        if (_metadataState.showLocation)
          TextButton(
            onPressed: () => Navigator.pop(context, 'remove'),
            child: Text(l10n.remove),
          ),
        if (hasPoiName)
          TextButton(
            onPressed: () => Navigator.pop(context, 'clear_poi'),
            child: Text('${l10n.clear} ${l10n.poiNameLabel}'),
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
        // 获取当前语言设置（在异步操作前获取，避免 context 跨越异步间隙）
        if (!context.mounted) return;
        final localeCode = l10n.localeName;
        final addressInfo =
            await LocalGeocodingService.getAddressFromCoordinates(
          _metadataState.originalLatitude!,
          _metadataState.originalLongitude!,
          localeCode: localeCode,
        );
        if (addressInfo != null && mounted) {
          // 使用 country,province,city,district 拼成标准存储格式，
          // 而不是 formatted_address（带空格英文拼接），
          // 避免 formatLocationForDisplay 解析失败导致显示英文。
          final country = addressInfo['country'] ?? '';
          final province = addressInfo['province'] ?? '';
          final city = addressInfo['city'] ?? '';
          final district = addressInfo['district'] ?? '';
          final standardAddress = '$country,$province,$city,$district';
          final hasAnyField =
              country.isNotEmpty || province.isNotEmpty || city.isNotEmpty;
          if (hasAnyField) {
            _updateState(() {
              _metadataState.location = standardAddress;
              _metadataState.originalLocation = standardAddress;
            });
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    l10n.locationUpdatedTo(
                      LocationService.formatLocationForDisplay(standardAddress),
                    ),
                  ),
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
        _metadataState.showLocation = false;
        _metadataState.location = null;
        _metadataState.latitude = null;
        _metadataState.longitude = null;
        _metadataState.originalLocation = null;
        _metadataState.originalLatitude = null;
        _metadataState.originalLongitude = null;
      });
    } else if (result == 'clear_poi') {
      _updateState(() {
        _metadataState.poiName = null;
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
    final hasWeatherData = _metadataState.originalWeather != null;

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
        _metadataState.originalWeather!,
      );
      title = l10n.weatherInfo2;
      content = l10n.weatherRemoveHint(
        '$weatherDesc${_metadataState.temperature != null ? " $_metadataState.temperature" : ""}',
      );
      actions = [
        if (_metadataState.showWeather)
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
        _metadataState.showWeather = false;
      });
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
