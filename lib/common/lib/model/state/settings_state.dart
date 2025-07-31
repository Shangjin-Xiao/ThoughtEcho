/// Settings state model
import '../device.dart';
import '../persistence/color_mode.dart';
import '../send_mode.dart';

class SettingsState {
  final String alias;
  final Device deviceInfo;
  final int port;
  final bool https;
  final bool multicastGroup;
  final String? destination;
  final bool saveToGallery;
  final bool quickSave;
  final bool quickSaveFromFavorites;
  final String? receivePin;
  final bool autoFinish;
  final bool minimizeToTray;
  final bool launchAtStartup;
  final bool autoAccept;
  final SendMode sendMode;
  final ColorMode colorMode;
  final bool animations;

  const SettingsState({
    required this.alias,
    required this.deviceInfo,
    required this.port,
    required this.https,
    required this.multicastGroup,
    this.destination,
    required this.saveToGallery,
    required this.quickSave,
    required this.quickSaveFromFavorites,
    this.receivePin,
    required this.autoFinish,
    required this.minimizeToTray,
    required this.launchAtStartup,
    required this.autoAccept,
    required this.sendMode,
    required this.colorMode,
    required this.animations,
  });
}