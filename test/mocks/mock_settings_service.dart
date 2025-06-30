import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import '../../lib/services/settings_service.dart';
import '../../lib/models/ai_provider_settings.dart';

// Mock class generation annotation
@GenerateMocks([SettingsService])
class MockSettingsService extends Mock implements SettingsService {
  // Mock settings data
  Map<String, dynamic> _settings = {
    'theme_mode': 'system',
    'language': 'zh_CN',
    'auto_location': true,
    'auto_weather': true,
    'ai_auto_analysis': false,
    'backup_enabled': true,
    'notification_enabled': true,
  };

  final MultiAISettings _mockMultiAISettings = MultiAISettings(
    providers: [
      AIProviderSettings(
        id: 'openai',
        name: 'OpenAI',
        baseUrl: 'https://api.openai.com/v1',
        isEnabled: true,
        models: ['gpt-3.5-turbo', 'gpt-4'],
        defaultModel: 'gpt-3.5-turbo',
      ),
      AIProviderSettings(
        id: 'anthropic',
        name: 'Anthropic',
        baseUrl: 'https://api.anthropic.com/v1',
        isEnabled: false,
        models: ['claude-3-haiku', 'claude-3-sonnet'],
        defaultModel: 'claude-3-haiku',
      ),
    ],
    currentProviderId: 'openai',
  );

  @override
  MultiAISettings get multiAISettings => _mockMultiAISettings;

  @override
  Future<void> initialize() async {
    // Mock initialization - do nothing
    await Future.delayed(const Duration(milliseconds: 100));
  }

  @override
  Future<T?> get<T>(String key, {T? defaultValue}) async {
    final value = _settings[key];
    if (value == null) return defaultValue;
    
    if (T == String) return value as T?;
    if (T == bool) return value as T?;
    if (T == int) return value as T?;
    if (T == double) return value as T?;
    
    return value as T?;
  }

  @override
  Future<void> set<T>(String key, T value) async {
    _settings[key] = value;
    notifyListeners();
  }

  @override
  Future<void> remove(String key) async {
    _settings.remove(key);
    notifyListeners();
  }

  @override
  Future<void> clear() async {
    _settings.clear();
    notifyListeners();
  }

  @override
  Future<bool> contains(String key) async {
    return _settings.containsKey(key);
  }

  @override
  Future<Set<String>> getKeys() async {
    return _settings.keys.toSet();
  }

  // Theme settings
  @override
  Future<String> getThemeMode() async {
    return _settings['theme_mode'] as String? ?? 'system';
  }

  @override
  Future<void> setThemeMode(String mode) async {
    _settings['theme_mode'] = mode;
    notifyListeners();
  }

  @override
  Future<String> getLanguage() async {
    return _settings['language'] as String? ?? 'zh_CN';
  }

  @override
  Future<void> setLanguage(String language) async {
    _settings['language'] = language;
    notifyListeners();
  }

  // Location settings
  @override
  Future<bool> getAutoLocation() async {
    return _settings['auto_location'] as bool? ?? true;
  }

  @override
  Future<void> setAutoLocation(bool enabled) async {
    _settings['auto_location'] = enabled;
    notifyListeners();
  }

  // Weather settings
  @override
  Future<bool> getAutoWeather() async {
    return _settings['auto_weather'] as bool? ?? true;
  }

  @override
  Future<void> setAutoWeather(bool enabled) async {
    _settings['auto_weather'] = enabled;
    notifyListeners();
  }

  // AI settings
  @override
  Future<bool> getAIAutoAnalysis() async {
    return _settings['ai_auto_analysis'] as bool? ?? false;
  }

  @override
  Future<void> setAIAutoAnalysis(bool enabled) async {
    _settings['ai_auto_analysis'] = enabled;
    notifyListeners();
  }

  @override
  Future<void> updateMultiAISettings(MultiAISettings settings) async {
    // Update the mock settings
    _mockMultiAISettings.providers.clear();
    _mockMultiAISettings.providers.addAll(settings.providers);
    _mockMultiAISettings.currentProviderId = settings.currentProviderId;
    notifyListeners();
  }

  @override
  Future<void> addAIProvider(AIProviderSettings provider) async {
    final existingIndex = _mockMultiAISettings.providers
        .indexWhere((p) => p.id == provider.id);
    
    if (existingIndex != -1) {
      _mockMultiAISettings.providers[existingIndex] = provider;
    } else {
      _mockMultiAISettings.providers.add(provider);
    }
    notifyListeners();
  }

  @override
  Future<void> removeAIProvider(String providerId) async {
    _mockMultiAISettings.providers.removeWhere((p) => p.id == providerId);
    
    // If we removed the current provider, switch to the first available
    if (_mockMultiAISettings.currentProviderId == providerId &&
        _mockMultiAISettings.providers.isNotEmpty) {
      _mockMultiAISettings.currentProviderId = _mockMultiAISettings.providers.first.id;
    }
    notifyListeners();
  }

  @override
  Future<void> setCurrentAIProvider(String providerId) async {
    if (_mockMultiAISettings.providers.any((p) => p.id == providerId)) {
      _mockMultiAISettings.currentProviderId = providerId;
      notifyListeners();
    }
  }

  // Backup settings
  @override
  Future<bool> getBackupEnabled() async {
    return _settings['backup_enabled'] as bool? ?? true;
  }

  @override
  Future<void> setBackupEnabled(bool enabled) async {
    _settings['backup_enabled'] = enabled;
    notifyListeners();
  }

  @override
  Future<String?> getBackupPath() async {
    return _settings['backup_path'] as String?;
  }

  @override
  Future<void> setBackupPath(String? path) async {
    if (path != null) {
      _settings['backup_path'] = path;
    } else {
      _settings.remove('backup_path');
    }
    notifyListeners();
  }

  // Notification settings
  @override
  Future<bool> getNotificationEnabled() async {
    return _settings['notification_enabled'] as bool? ?? true;
  }

  @override
  Future<void> setNotificationEnabled(bool enabled) async {
    _settings['notification_enabled'] = enabled;
    notifyListeners();
  }

  // Editor settings
  @override
  Future<bool> getShowToolbar() async {
    return _settings['show_toolbar'] as bool? ?? true;
  }

  @override
  Future<void> setShowToolbar(bool show) async {
    _settings['show_toolbar'] = show;
    notifyListeners();
  }

  @override
  Future<bool> getAutoSave() async {
    return _settings['auto_save'] as bool? ?? true;
  }

  @override
  Future<void> setAutoSave(bool enabled) async {
    _settings['auto_save'] = enabled;
    notifyListeners();
  }

  @override
  Future<int> getAutoSaveInterval() async {
    return _settings['auto_save_interval'] as int? ?? 30; // 30 seconds
  }

  @override
  Future<void> setAutoSaveInterval(int seconds) async {
    _settings['auto_save_interval'] = seconds;
    notifyListeners();
  }

  // Data management
  @override
  Future<Map<String, dynamic>> exportSettings() async {
    return Map<String, dynamic>.from(_settings);
  }

  @override
  Future<void> importSettings(Map<String, dynamic> settings, {bool merge = true}) async {
    if (merge) {
      _settings.addAll(settings);
    } else {
      _settings = Map<String, dynamic>.from(settings);
    }
    notifyListeners();
  }

  @override
  Future<void> resetToDefaults() async {
    _settings = {
      'theme_mode': 'system',
      'language': 'zh_CN',
      'auto_location': true,
      'auto_weather': true,
      'ai_auto_analysis': false,
      'backup_enabled': true,
      'notification_enabled': true,
      'show_toolbar': true,
      'auto_save': true,
      'auto_save_interval': 30,
    };
    
    // Reset AI settings to defaults
    _mockMultiAISettings.providers.clear();
    _mockMultiAISettings.providers.add(
      AIProviderSettings(
        id: 'openai',
        name: 'OpenAI',
        baseUrl: 'https://api.openai.com/v1',
        isEnabled: true,
        models: ['gpt-3.5-turbo', 'gpt-4'],
        defaultModel: 'gpt-3.5-turbo',
      ),
    );
    _mockMultiAISettings.currentProviderId = 'openai';
    
    notifyListeners();
  }

  // Test helper methods
  void setMockSetting(String key, dynamic value) {
    _settings[key] = value;
    notifyListeners();
  }

  Map<String, dynamic> getAllSettings() {
    return Map<String, dynamic>.from(_settings);
  }

  void clearAllSettings() {
    _settings.clear();
    notifyListeners();
  }

  void addMockAIProvider(AIProviderSettings provider) {
    _mockMultiAISettings.providers.add(provider);
    notifyListeners();
  }

  void setMockCurrentProvider(String providerId) {
    _mockMultiAISettings.currentProviderId = providerId;
    notifyListeners();
  }
}