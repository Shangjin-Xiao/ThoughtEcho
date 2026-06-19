part of '../note_full_editor_page.dart';

/// Location and weather section of the metadata dialog.
extension _NoteEditorMetadataLocationSection on _NoteFullEditorPageState {
  /// Builds the location/weather section for the metadata dialog.
  ///
  /// [setDialogState] is the StatefulBuilder's setState for refreshing
  /// the dialog UI, while [setState] on [this] refreshes the page state.
  Widget _buildMetadataLocationWeatherSection(
    ThemeData theme,
    AppLocalizations l10n,
    StateSetter setDialogState,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 位置和天气
        Row(
          children: [
            Text(
              l10n.locationAndWeather,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Spacer(),
            // 编辑模式提示
            if (widget.initialQuote != null)
              Text(
                l10n.recordedOnFirstSave,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),

        // 位置和天气选择容器
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 位置和天气开关
              RepaintBoundary(
                child: Row(
                  children: [
                    // 位置信息按钮
                    Expanded(
                      child: Stack(
                        children: [
                          FilterChip(
                            key: const ValueKey('full_editor_location_chip'),
                            avatar: Icon(
                              Icons.location_on,
                              color: _showLocation
                                  ? theme.colorScheme.primary
                                  : Colors.grey,
                              size: 18,
                            ),
                            label: Text(l10n.locationLabel),
                            selected: _showLocation,
                            onSelected: (value) async {
                              // 编辑模式下统一提示只读
                              if (widget.initialQuote?.id != null) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(l10n.editModeMetadataReadOnlyHint),
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                                }
                                return;
                              }
                              // 新建模式
                              if (value &&
                                  _location == null &&
                                  _latitude == null) {
                                // 先设置为选中，获取失败后会在回调中取消
                                _updateState(() {
                                  _showLocation = true;
                                });
                                setDialogState(() {});
                                await _fetchLocationForNewNoteWithFailCallback(
                                  () {
                                    // 失败回调：取消选中
                                    _updateState(() {
                                      _showLocation = false;
                                    });
                                    setDialogState(() {});
                                  },
                                );
                              } else {
                                _updateState(() {
                                  _showLocation = value;
                                });
                                setDialogState(() {});
                              }
                            },
                            selectedColor: theme.colorScheme.primaryContainer,
                          ),
                          // 小红点：有坐标但没地址时提示可更新（仅已保存笔记）
                          if (widget.initialQuote?.id != null &&
                              _originalLocation == null &&
                              _originalLatitude != null &&
                              _originalLongitude != null)
                            Positioned(
                              right: 0,
                              top: 0,
                              child: Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.error,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // 天气信息按钮
                    Expanded(
                      child: FilterChip(
                        key: const ValueKey('full_editor_weather_chip'),
                        avatar: Icon(
                          _weather != null
                              ? _getWeatherIcon(_weather!)
                              : Icons.cloud,
                          color: _showWeather
                              ? theme.colorScheme.primary
                              : Colors.grey,
                          size: 18,
                        ),
                        label: Text(l10n.weatherLabel),
                        selected: _showWeather,
                        onSelected: (value) async {
                          // 编辑模式下统一只读提示
                          if (widget.initialQuote?.id != null) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(l10n.editModeMetadataReadOnlyHint),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            }
                            return;
                          }
                          // 新建模式
                          if (value && _weather == null) {
                            // 先设置为选中，获取失败后会在回调中取消
                            _updateState(() {
                              _showWeather = true;
                            });
                            setDialogState(() {});
                            await _fetchLocationWeatherWithFailCallback(() {
                              // 失败回调：取消选中
                              _updateState(() {
                                _showWeather = false;
                              });
                              setDialogState(() {});
                            });
                          } else {
                            _updateState(() {
                              _showWeather = value;
                            });
                            setDialogState(() {});
                          }
                        },
                        selectedColor: theme.colorScheme.primaryContainer,
                      ),
                    ),
                    // 刷新按钮 - 仅新建模式显示（未保存的笔记）
                    if (widget.initialQuote?.id == null)
                      IconButton(
                        icon: const Icon(Icons.refresh, size: 20),
                        tooltip: l10n.refreshLocationWeather,
                        onPressed: () {
                          _fetchLocationWeather();
                          setDialogState(() {});
                        },
                      ),
                  ],
                ),
              ),

              // 显示位置和天气信息
              if (_location != null ||
                  _latitude != null ||
                  _weather != null) ...[
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),
                if (_location != null || _latitude != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Icon(
                          Icons.location_on,
                          size: 16,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _buildLocationDisplayText(l10n),
                            style: TextStyle(
                              fontSize: 14,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_weather != null)
                  Row(
                    children: [
                      Icon(
                        _getWeatherIcon(_weather!),
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        WeatherService.getLocalizedWeatherDescription(
                          AppLocalizations.of(context),
                          _weather!,
                        ),
                        style: TextStyle(
                          fontSize: 14,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (_temperature != null)
                        Text(
                          ' $_temperature',
                          style: TextStyle(
                            fontSize: 14,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
              ],

              // 编辑模式下无数据时的提示（只有真正编辑已保存的笔记时才显示）
              // initialQuote.id 不为空表示是已保存的笔记
              if (widget.initialQuote?.id != null &&
                  _originalLocation == null &&
                  _originalLatitude == null &&
                  _originalWeather == null) ...[
                const SizedBox(height: 8),
                Text(
                  l10n.noteNoLocationWeatherInfo,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  String _buildLocationDisplayText(AppLocalizations l10n) {
    if (_poiName != null && _poiName!.trim().isNotEmpty) {
      return _poiName!.trim();
    }

    final formattedLocation =
        LocationService.formatLocationForDisplay(_location);
    if (formattedLocation.isNotEmpty) {
      return formattedLocation;
    }

    if (_latitude != null && _longitude != null) {
      return LocationService.formatCoordinates(_latitude, _longitude);
    }

    return l10n.gettingLocationHint;
  }
}
