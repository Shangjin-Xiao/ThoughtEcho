part of '../add_note_dialog.dart';

extension _AddNoteDialogLocationWeather on _AddNoteDialogState {
  /// 获取新建笔记的实时位置（与全屏编辑器逻辑一致）
  // TODO(low): 位置/天气获取逻辑与 note_full_editor_page.dart 大量重复，
  // 可提取为 LocationWeatherHelper 共享。
  Future<void> _fetchLocationForNewNote() async {
    final locationService = _cachedLocationService;
    if (locationService == null) return;

    // 检查并请求权限（与全屏编辑器一致）
    if (!locationService.hasLocationPermission) {
      bool permissionGranted =
          await locationService.requestLocationPermission();
      if (!permissionGranted) {
        if (mounted && context.mounted) {
          final l10n = AppLocalizations.of(context);
          setState(() {
            _includeLocation = false;
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

    try {
      final position = await locationService.getCurrentLocation();
      if (position != null && mounted) {
        final location = locationService.getFormattedLocation();
        setState(() {
          _newLatitude = position.latitude;
          _newLongitude = position.longitude;
          _newLocation = location.isNotEmpty ? location : null;
        });
      } else if (mounted) {
        // 获取位置失败，提示并还原开关状态
        setState(() {
          _includeLocation = false;
        });
        if (context.mounted) {
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
    } catch (e) {
      logDebug('对话框获取位置失败: $e');
      if (mounted && context.mounted) {
        final l10n = AppLocalizations.of(context);
        setState(() {
          _includeLocation = false;
        });
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(l10n.getLocationFailedTitle),
            content: Text(l10n.getLocationFailedDesc(e.toString())),
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

  /// 获取新建笔记的天气信息
  Future<void> _fetchWeatherForNewNote() async {
    final weatherService = _cachedWeatherService;
    final locationService = _cachedLocationService;
    if (weatherService == null) return;

    try {
      // 天气需要位置坐标
      double? lat = _newLatitude;
      double? lon = _newLongitude;

      // 如果还没有坐标，尝试从 locationService 获取
      if (lat == null || lon == null) {
        lat = locationService?.currentPosition?.latitude;
        lon = locationService?.currentPosition?.longitude;
      }

      if (lat == null || lon == null) {
        // 没有坐标，无法获取天气
        if (mounted) {
          setState(() {
            _includeWeather = false;
          });
          if (context.mounted) {
            final l10n = AppLocalizations.of(context);
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
        }
        return;
      }

      // 获取天气
      await weatherService.getWeatherData(lat, lon);

      if (!weatherService.hasData && mounted) {
        // 天气获取失败
        setState(() {
          _includeWeather = false;
        });
        if (context.mounted) {
          final l10n = AppLocalizations.of(context);
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
      logDebug('对话框获取天气失败: $e');
      if (mounted) {
        setState(() {
          _includeWeather = false;
        });
        if (context.mounted) {
          final l10n = AppLocalizations.of(context);
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
  }

  /// 获取位置提示文本（支持坐标显示）
  /// 修复：新建模式只显示实时获取的位置，而不是从 LocationService 获取的缓存位置
  String _getLocationTooltipText(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // 编辑模式：显示原始位置
    if (widget.initialQuote != null) {
      if (_originalLocation != null && _originalLocation!.isNotEmpty) {
        return LocationService.formatLocationForDisplay(_originalLocation);
      }
      if (_originalLatitude != null && _originalLongitude != null) {
        return LocationService.formatCoordinates(
          _originalLatitude,
          _originalLongitude,
        );
      }
      return l10n.noLocationInfo;
    }

    // 新建模式：只显示实时获取的位置
    if (_newLocation != null && _newLocation!.isNotEmpty) {
      return LocationService.formatLocationForDisplay(_newLocation);
    }
    if (_newLatitude != null && _newLongitude != null) {
      return LocationService.formatCoordinates(_newLatitude, _newLongitude);
    }
    // 未获取位置时显示"当前位置"提示
    return l10n.currentLocationLabel;
  }

  /// 编辑模式下的位置对话框
  Future<void> _showLocationDialog(
    BuildContext context,
    ThemeData theme,
  ) async {
    final l10n = AppLocalizations.of(context);
    final hasLocationData = _originalLocation != null ||
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
          ? l10n.locationUpdateHint(LocationService.formatCoordinates(
              _originalLatitude, _originalLongitude))
          : l10n.locationRemoveHint(
              LocationService.formatLocationForDisplay(_originalLocation),
            );
      actions = [
        if (_includeLocation)
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

    if (result == 'update' && hasCoordinates) {
      // 尝试用坐标更新地址
      try {
        // 获取当前语言设置
        final localeCode = _cachedLocationService?.currentLocaleCode;
        final addressInfo =
            await LocalGeocodingService.getAddressFromCoordinates(
          _originalLatitude!,
          _originalLongitude!,
          localeCode: localeCode,
        );
        if (addressInfo != null && mounted) {
          final formattedAddress = addressInfo['formatted_address'];
          if (formattedAddress != null && formattedAddress.isNotEmpty) {
            setState(() {
              _originalLocation = formattedAddress;
              _includeLocation = true;
            });
            if (context.mounted) {
              final l10n = AppLocalizations.of(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text(l10n.locationUpdatedTo(formattedAddress))),
              );
            }
          } else if (context.mounted) {
            final l10n = AppLocalizations.of(context);
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(l10n.cannotGetAddress)));
          }
        } else if (mounted && context.mounted) {
          final l10n = AppLocalizations.of(context);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(l10n.cannotGetAddress)));
        }
      } catch (e) {
        if (mounted && context.mounted) {
          final l10n = AppLocalizations.of(context);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(
              SnackBar(content: Text(l10n.updateFailed(e.toString()))));
        }
      }
    } else if (result == 'remove') {
      setState(() {
        _includeLocation = false;
      });
    }
  }

  /// 编辑模式下的天气对话框
  Future<void> _showWeatherDialog(BuildContext context, ThemeData theme) async {
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
      title = l10n.weatherInfo2;
      final weatherDisplay =
          '$_originalWeather${_originalTemperature != null ? " $_originalTemperature" : ""}';
      content = l10n.weatherRemoveHint(weatherDisplay);
      actions = [
        if (_includeWeather)
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
      setState(() {
        _includeWeather = false;
      });
    }
  }

  /// 新建模式下的位置信息对话框
  /// 支持查看当前坐标、手动触发地址解析、移除位置
  Future<void> _showNewNoteLocationDialog(
    BuildContext context,
    ThemeData theme,
  ) async {
    final l10n = AppLocalizations.of(context);
    final hasAddress = _newLocation != null && _newLocation!.isNotEmpty;
    final hasCoordinates = _newLatitude != null && _newLongitude != null;
    final hasOnlyCoordinates = !hasAddress && hasCoordinates;

    String title;
    String content;
    List<Widget> actions = [];

    if (!hasCoordinates) {
      // 没有任何位置数据
      title = l10n.cannotGetLocationTitle;
      content = l10n.cannotGetLocationDesc;
      actions = [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.iKnow),
        ),
      ];
    } else {
      title = l10n.locationInfo;
      content = hasOnlyCoordinates
          ? l10n.locationUpdateHint(
              LocationService.formatCoordinates(_newLatitude, _newLongitude))
          : l10n.locationRemoveHint(
              LocationService.formatLocationForDisplay(_newLocation),
            );
      actions = [
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

    if (result == 'update' && hasCoordinates) {
      // 尝试用坐标更新地址（优先在线 Nominatim → 回退系统 SDK）
      try {
        // 先尝试通过 locationService 的完整解析链
        final locationService = _cachedLocationService;
        if (locationService != null && locationService.hasCoordinates) {
          await locationService.getAddressFromLatLng();
          final resolved = locationService.getFormattedLocation();
          if (resolved.isNotEmpty && mounted) {
            setState(() {
              _newLocation = resolved;
            });
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text(l10n.locationUpdatedTo(
                        LocationService.formatLocationForDisplay(resolved)))),
              );
            }
            return;
          }
        }

        // 回退到直接调用 LocalGeocodingService
        final localeCode = locationService?.currentLocaleCode;
        final addressInfo =
            await LocalGeocodingService.getAddressFromCoordinates(
          _newLatitude!,
          _newLongitude!,
          localeCode: localeCode,
        );
        if (addressInfo != null && mounted) {
          final formattedAddress = addressInfo['formatted_address'];
          if (formattedAddress != null && formattedAddress.isNotEmpty) {
            setState(() {
              _newLocation = formattedAddress;
            });
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text(l10n.locationUpdatedTo(
                        LocationService.formatLocationForDisplay(
                            formattedAddress)))),
              );
            }
          } else if (context.mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(l10n.cannotGetAddress)));
          }
        } else if (mounted && context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(l10n.cannotGetAddress)));
        }
      } catch (e) {
        if (mounted && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.updateFailed(e.toString()))));
        }
      }
    } else if (result == 'remove') {
      setState(() {
        _includeLocation = false;
        _newLocation = null;
        _newLatitude = null;
        _newLongitude = null;
      });
    }
  }

  /// 新建模式下的天气信息对话框
  /// 支持查看当前天气、移除天气
  Future<void> _showNewNoteWeatherDialog(
    BuildContext context,
    ThemeData theme,
  ) async {
    final l10n = AppLocalizations.of(context);
    final weatherService = _cachedWeatherService;
    final hasWeatherData = weatherService?.hasData ?? false;

    String title;
    String content;
    List<Widget> actions = [];

    if (!hasWeatherData) {
      // 没有天气数据（获取失败或离线）
      title = l10n.weatherFetchFailedTitle;
      content = l10n.weatherFetchFailedDesc;
      actions = [
        TextButton(
          onPressed: () => Navigator.pop(context, 'remove'),
          child: Text(l10n.remove),
        ),
        // 如果有坐标，允许重试获取天气
        if (_newLatitude != null && _newLongitude != null)
          TextButton(
            onPressed: () => Navigator.pop(context, 'retry'),
            child: Text(l10n.retry),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context, 'cancel'),
          child: Text(l10n.cancel),
        ),
      ];
    } else {
      // 有天气数据
      title = l10n.weatherInfo2;
      final weatherDisplay = weatherService!.getFormattedWeather(l10n);
      content = l10n.weatherRemoveHint(weatherDisplay.isNotEmpty
          ? weatherDisplay
          : '${weatherService.currentWeather}');
      actions = [
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
      setState(() {
        _includeWeather = false;
      });
    } else if (result == 'retry') {
      _fetchWeatherForNewNote();
    }
  }
}
