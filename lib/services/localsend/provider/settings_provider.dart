import 'package:common/model/state/settings_state.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Provider for application settings
final settingsProvider = Provider<SettingsState>((ref) {
  // Return default settings
  return const SettingsState(
    alias: "ThoughtEcho Device",
    port: 53317,
    https: false,
    receivePin: null,
    shareViaLinkAutoAccept: false,
    quickSave: false,
    quickSaveFromFavorites: false,
    destination: null,
    saveToGallery: false,
  );
});
