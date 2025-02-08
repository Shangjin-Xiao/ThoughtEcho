import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/ai_settings.dart';

class SettingsService extends ChangeNotifier {
  static const String _aiSettingsKey = 'ai_settings';
  final SharedPreferences _prefs;
  late AISettings _aiSettings;

  AISettings get aiSettings => _aiSettings;

  SettingsService(this._prefs) {
    _loadSettings();
  }

  void _loadSettings() {
    final String? settingsJson = _prefs.getString(_aiSettingsKey);
    if (settingsJson != null) {
      _aiSettings = AISettings.fromJson(json.decode(settingsJson));
    } else {
      _aiSettings = AISettings.defaultSettings();
    }
    notifyListeners();
  }

  static Future<SettingsService> create() async {
    final prefs = await SharedPreferences.getInstance();
    return SettingsService(prefs);
  }

  Future<void> updateAISettings(AISettings settings) async {
    _aiSettings = settings;
    await _prefs.setString(_aiSettingsKey, json.encode(settings.toJson()));
    notifyListeners();
  }
}