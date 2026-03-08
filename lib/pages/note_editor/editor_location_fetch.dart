part of '../note_full_editor_page.dart';

/// Location and weather fetch methods with notification and failure handling.
extension NoteEditorLocationFetch on _NoteFullEditorPageState {
  Future<void> _fetchLocationWeatherWithNotification() async {
    final locationService = Provider.of<LocationService>(
      context,
      listen: false,
    );
    final weatherService = Provider.of<WeatherService>(context, listen: false);

    // 检查并请求权限
    if (!locationService.hasLocationPermission) {
      bool permissionGranted =
          await locationService.requestLocationPermission();
      if (!permissionGranted) {
        if (mounted) {
          final l10n = AppLocalizations.of(context);
          setState(() {
            _showLocation = false;
            _showWeather = false;
          });
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(l10n.cannotGetLocationTitle),
              content: Text(l10n.cannotGetLocationPermissionShort),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(l10n.iKnow),
                ),
              ],
            ),
          );
        }
        return;
      }
    }

    final position = await locationService.getCurrentLocation();
    if (position != null && mounted) {
      final location = locationService.getFormattedLocation();

      setState(() {
        _location = location.isNotEmpty ? location : null;
        _latitude = position.latitude;
        _longitude = position.longitude;
      });

      // 获取天气
      try {
        await weatherService.getWeatherData(
          position.latitude,
          position.longitude,
        );
        if (mounted) {
          setState(() {
            _weather = weatherService.currentWeather;
            _temperature = weatherService.temperature;
          });
          // 天气获取失败（无数据）
          if (_weather == null && _showWeather) {
            final l10n = AppLocalizations.of(context);
            setState(() {
              _showWeather = false;
            });
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text(l10n.weatherFetchFailedTitle),
                content: Text(l10n.weatherFetchFailedDesc),
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
      } catch (e) {
        logError('获取天气数据失败', error: e, source: 'NoteFullEditorPage');
        if (mounted && _showWeather) {
          final l10n = AppLocalizations.of(context);
          setState(() {
            _showWeather = false;
          });
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(l10n.weatherFetchFailedTitle),
              content: Text(l10n.weatherFetchFailedDesc),
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
    } else if (mounted) {
      // 位置获取失败
      final l10n = AppLocalizations.of(context);
      setState(() {
        _showLocation = false;
        _showWeather = false;
      });
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

  /// 新建模式下获取位置和天气，失败时调用回调取消选中
  /// 用于天气按钮点击时的处理
  Future<void> _fetchLocationWeatherWithFailCallback(
      VoidCallback onFail) async {
    final weatherService = Provider.of<WeatherService>(context, listen: false);
    final result = await _fetchLocationCore(onFail: onFail);
    if (result.permissionDenied) return;

    if (result.position == null) {
      // 位置获取失败 - 用于天气按钮场景，显示天气相关错误
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        onFail();
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(l10n.weatherFetchFailedTitle),
            content: Text(l10n.locationAndWeatherUnavailable),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(l10n.iKnow),
              ),
            ],
          ),
        );
      }
      return;
    }

    // 获取天气
    try {
      await weatherService.getWeatherData(
        result.position!.latitude,
        result.position!.longitude,
      );
      if (mounted) {
        setState(() {
          _weather = weatherService.currentWeather;
          _temperature = weatherService.temperature;
        });
        // 天气获取失败（无数据）
        if (_weather == null) {
          final l10n = AppLocalizations.of(context);
          onFail();
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(l10n.weatherFetchFailedTitle),
              content: Text(l10n.weatherFetchFailedDesc),
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
    } catch (e) {
      logError('获取天气数据失败', error: e, source: 'NoteFullEditorPage');
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        onFail();
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(l10n.weatherFetchFailedTitle),
            content: Text(l10n.weatherFetchFailedDesc),
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
  }

  /// 获取位置的公共逻辑，处理权限检查、位置获取、状态更新和"有坐标无地址"弹窗
  ///
  /// 返回值：
  /// - permissionDenied == true: 权限被拒绝（已显示弹窗，已调用 onFail）
  /// - position == null: 位置获取失败（需调用者显示失败弹窗和调用 onFail）
  /// - position != null: 成功（已更新 setState，如果 location 为空已显示"有坐标无地址"弹窗）
  Future<({bool permissionDenied, Position? position})> _fetchLocationCore({
    required VoidCallback onFail,
  }) async {
    final locationService =
        Provider.of<LocationService>(context, listen: false);

    // 检查并请求权限
    if (!locationService.hasLocationPermission) {
      bool permissionGranted =
          await locationService.requestLocationPermission();
      if (!permissionGranted) {
        if (mounted && context.mounted) {
          final l10n = AppLocalizations.of(context);
          onFail();
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(l10n.cannotGetLocationTitle),
              content: Text(l10n.cannotGetLocationPermissionShort),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(l10n.iKnow),
                ),
              ],
            ),
          );
        }
        return (permissionDenied: true, position: null);
      }
    }

    try {
      final position = await locationService.getCurrentLocation();
      if (position != null && mounted) {
        final location = locationService.getFormattedLocation();

        setState(() {
          _location = location.isNotEmpty ? location : null;
          _latitude = position.latitude;
          _longitude = position.longitude;
        });

        return (permissionDenied: false, position: position);
      }

      return (permissionDenied: false, position: null);
    } catch (e) {
      logError('获取位置失败', error: e, source: 'NoteFullEditorPage');
      return (permissionDenied: false, position: null);
    }
  }

  /// 新建模式下获取位置，失败时调用回调取消选中
  Future<void> _fetchLocationForNewNoteWithFailCallback(
      VoidCallback onFail) async {
    final result = await _fetchLocationCore(onFail: onFail);
    if (result.permissionDenied) return;

    if (result.position == null && mounted) {
      // 位置获取失败 - 用于位置按钮场景
      final l10n = AppLocalizations.of(context);
      onFail();
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
}
