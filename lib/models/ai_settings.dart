export '../services/settings_service.dart' show AISettings;

class AISettings {
  final String apiKey;
  final String apiUrl;
  final String model;

  AISettings({
    required this.apiKey,
    this.apiUrl = '',
    this.model = '',
  });

  Map<String, dynamic> toJson() {
    return {
      'apiKey': apiKey,
      'apiUrl': apiUrl,
      'model': model,
    };
  }

  factory AISettings.fromJson(Map<String, dynamic> map) {
    return AISettings(
      apiKey: map['apiKey'] ?? '',
      apiUrl: map['apiUrl'] ?? '',
      model: map['model'] ?? '',
    );
  }

  factory AISettings.defaultSettings() => AISettings(
        apiKey: '',
        apiUrl: '',
        model: '',
      );

  AISettings copyWith({
    String? apiKey,
    String? apiUrl,
    String? model,
  }) {
    return AISettings(
      apiKey: apiKey ?? this.apiKey,
      apiUrl: apiUrl ?? this.apiUrl,
      model: model ?? this.model,
    );
  }
}
