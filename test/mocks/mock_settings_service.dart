/// Mock SettingsService for testing
import 'package:flutter/material.dart';
import 'package:mockito/mockito.dart';

import '../../lib/models/ai_settings.dart';
import '../../lib/models/app_settings.dart';
import '../../lib/models/multi_ai_settings.dart';

class MockSettingsService extends ChangeNotifier with Mock {
  AISettings _aiSettings = const AISettings();
  AppSettings _appSettings = const AppSettings();
  MultiAISettings _multiAISettings = const MultiAISettings();
  ThemeMode _themeMode = ThemeMode.system;
  
  bool _isInitialized = false;
  Map<String, dynamic> _preferences = {};

  // Getters
  AISettings get aiSettings => _aiSettings;
  AppSettings get appSettings => _appSettings;
  MultiAISettings get multiAISettings => _multiAISettings;
  ThemeMode get themeMode => _themeMode;
  bool get isInitialized => _isInitialized;

  /// Initialize mock settings service
  Future<void> initialize() async {
    await Future.delayed(const Duration(milliseconds: 100));
    _isInitialized = true;
    
    // Set default settings
    _aiSettings = const AISettings(
      apiKey: '',
      model: 'gpt-3.5-turbo',
      temperature: 0.7,
      maxTokens: 2000,
      enableAnalysis: true,
    );
    
    _appSettings = const AppSettings(
      enableNotifications: true,
      autoSave: true,
      fontSize: 16.0,
      lineHeight: 1.5,
      enableClipboardMonitoring: false,
      backupInterval: 7,
    );
    
    _multiAISettings = const MultiAISettings(
      enableMultiProvider: false,
      fallbackEnabled: true,
      maxRetries: 3,
      timeout: 30,
    );
    
    notifyListeners();
  }

  /// Update AI settings
  Future<void> updateAISettings(AISettings settings) async {
    await Future.delayed(const Duration(milliseconds: 50));
    _aiSettings = settings;
    _preferences['ai_settings'] = settings.toJson();
    notifyListeners();
  }

  /// Update app settings
  Future<void> updateAppSettings(AppSettings settings) async {
    await Future.delayed(const Duration(milliseconds: 50));
    _appSettings = settings;
    _preferences['app_settings'] = settings.toJson();
    notifyListeners();
  }

  /// Update multi AI settings
  Future<void> updateMultiAISettings(MultiAISettings settings) async {
    await Future.delayed(const Duration(milliseconds: 50));
    _multiAISettings = settings;
    _preferences['multi_ai_settings'] = settings.toJson();
    notifyListeners();
  }

  /// Update theme mode
  Future<void> updateThemeMode(ThemeMode mode) async {
    await Future.delayed(const Duration(milliseconds: 30));
    _themeMode = mode;
    _preferences['theme_mode'] = mode.index;
    notifyListeners();
  }

  /// Get preference
  T? getPreference<T>(String key) {
    return _preferences[key] as T?;
  }

  /// Set preference
  Future<void> setPreference<T>(String key, T value) async {
    await Future.delayed(const Duration(milliseconds: 30));
    _preferences[key] = value;
    notifyListeners();
  }

  /// Check if onboarding is complete
  bool isOnboardingComplete() {
    return _preferences['onboarding_complete'] ?? false;
  }

  /// Mark onboarding as complete
  Future<void> markOnboardingComplete() async {
    await Future.delayed(const Duration(milliseconds: 50));
    _preferences['onboarding_complete'] = true;
    notifyListeners();
  }

  /// Check if database migration is complete
  bool isDatabaseMigrationComplete() {
    return _preferences['database_migration_complete'] ?? false;
  }

  /// Mark database migration as complete
  Future<void> markDatabaseMigrationComplete() async {
    await Future.delayed(const Duration(milliseconds: 50));
    _preferences['database_migration_complete'] = true;
    notifyListeners();
  }

  /// Check if initial database setup is complete
  bool isInitialDatabaseSetupComplete() {
    return _preferences['initial_database_setup_complete'] ?? false;
  }

  /// Mark initial database setup as complete
  Future<void> markInitialDatabaseSetupComplete() async {
    await Future.delayed(const Duration(milliseconds: 50));
    _preferences['initial_database_setup_complete'] = true;
    notifyListeners();
  }

  /// Check if app is installed
  bool isAppInstalled() {
    return _preferences['app_installed'] ?? false;
  }

  /// Mark app as installed
  Future<void> markAppInstalled() async {
    await Future.delayed(const Duration(milliseconds: 50));
    _preferences['app_installed'] = true;
    notifyListeners();
  }

  /// Check if app is upgraded
  bool isAppUpgraded() {
    return _preferences['app_upgraded'] ?? false;
  }

  /// Mark app as upgraded
  Future<void> markAppUpgraded() async {
    await Future.delayed(const Duration(milliseconds: 50));
    _preferences['app_upgraded'] = true;
    notifyListeners();
  }

  /// Get last version
  String? getLastVersion() {
    return _preferences['last_version'] as String?;
  }

  /// Set last version
  Future<void> setLastVersion(String version) async {
    await Future.delayed(const Duration(milliseconds: 30));
    _preferences['last_version'] = version;
    notifyListeners();
  }

  /// Clear all settings
  Future<void> clearAllSettings() async {
    await Future.delayed(const Duration(milliseconds: 100));
    _preferences.clear();
    _aiSettings = const AISettings();
    _appSettings = const AppSettings();
    _multiAISettings = const MultiAISettings();
    _themeMode = ThemeMode.system;
    notifyListeners();
  }

  /// Export settings
  Map<String, dynamic> exportSettings() {
    return Map.from(_preferences);
  }

  /// Import settings
  Future<void> importSettings(Map<String, dynamic> settings) async {
    await Future.delayed(const Duration(milliseconds: 100));
    _preferences = Map.from(settings);
    
    // Restore settings from preferences
    if (_preferences['ai_settings'] != null) {
      _aiSettings = AISettings.fromJson(_preferences['ai_settings']);
    }
    if (_preferences['app_settings'] != null) {
      _appSettings = AppSettings.fromJson(_preferences['app_settings']);
    }
    if (_preferences['multi_ai_settings'] != null) {
      _multiAISettings = MultiAISettings.fromJson(_preferences['multi_ai_settings']);
    }
    if (_preferences['theme_mode'] != null) {
      _themeMode = ThemeMode.values[_preferences['theme_mode']];
    }
    
    notifyListeners();
  }

  /// Reset to default settings
  Future<void> resetToDefaults() async {
    await Future.delayed(const Duration(milliseconds: 100));
    await clearAllSettings();
    await initialize();
  }

  /// Set test data
  void setTestData({
    AISettings? aiSettings,
    AppSettings? appSettings,
    MultiAISettings? multiAISettings,
    ThemeMode? themeMode,
    Map<String, dynamic>? preferences,
  }) {
    if (aiSettings != null) _aiSettings = aiSettings;
    if (appSettings != null) _appSettings = appSettings;
    if (multiAISettings != null) _multiAISettings = multiAISettings;
    if (themeMode != null) _themeMode = themeMode;
    if (preferences != null) _preferences.addAll(preferences);
    notifyListeners();
  }
}