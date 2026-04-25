part of '../note_full_editor_page.dart';

/// Location and weather fetch methods with notification and failure handling.
extension _NoteEditorLocationFetch on _NoteFullEditorPageState {
  Future<void> _fetchLocationWeatherWithNotification() async {
    final result = await LocationWeatherHelper.fetch(
      context: context,
      includeWeather: _showWeather,
      showWeatherErrorDialog: _showWeather,
    );

    if (mounted) {
      _updateState(() {
        if (result.permissionDenied || !result.hasLocation) {
          _showLocation = false;
          _showWeather = false;
        } else {
          _location = result.address;
          _latitude = result.latitude;
          _longitude = result.longitude;
          if (_showWeather) {
            _weather = result.weather;
            _temperature = result.temperature;
            if (_weather == null) {
              _showWeather = false;
            }
          }
        }
      });
    }
  }

  /// 新建模式下获取位置和天气，失败时调用回调取消选中
  /// 用于天气按钮点击时的处理
  Future<void> _fetchLocationWeatherWithFailCallback(
    VoidCallback onFail,
  ) async {
    final result = await LocationWeatherHelper.fetch(
      context: context,
      includeWeather: true,
      showWeatherErrorDialog: true,
      locationErrorContent: AppLocalizations.of(
        context,
      ).locationAndWeatherUnavailable,
    );

    if (mounted) {
      if (!result.hasLocation || !result.hasWeather) {
        onFail();
      }

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

  /// 新建模式下获取位置，失败时调用回调取消选中
  Future<void> _fetchLocationForNewNoteWithFailCallback(
    VoidCallback onFail,
  ) async {
    final result = await LocationWeatherHelper.fetch(
      context: context,
      includeWeather: false,
    );

    if (result.permissionDenied || !result.hasLocation) {
      onFail();
      return;
    }

    if (mounted) {
      _updateState(() {
        _location = result.address;
        _latitude = result.latitude;
        _longitude = result.longitude;
      });
    }
  }
}
