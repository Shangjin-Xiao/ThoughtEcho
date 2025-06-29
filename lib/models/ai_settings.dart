class AISettings {
  final String apiKey;
  final String apiUrl;
  final String model;
  final double temperature;
  final int maxTokens;
  final String? hostOverride;

  AISettings({
    required this.apiKey,
    this.apiUrl = '',
    this.model = '',
    this.temperature = 0.7,
    this.maxTokens = 1000,
    this.hostOverride,
  });

  Map<String, dynamic> toJson() {
    return {
      'apiKey': apiKey,
      'apiUrl': apiUrl,
      'model': model,
      'temperature': temperature,
      'maxTokens': maxTokens,
      'hostOverride': hostOverride,
    };
  }

  factory AISettings.fromJson(Map<String, dynamic> map) {
    return AISettings(
      apiKey: map['apiKey'] ?? '',
      apiUrl: map['apiUrl'] ?? '',
      model: map['model'] ?? '',
      temperature:
          map['temperature'] != null
              ? (map['temperature'] as num).toDouble()
              : 0.7,
      maxTokens:
          map['maxTokens'] != null ? (map['maxTokens'] as num).toInt() : 1000,
      hostOverride: map['hostOverride'],
    );
  }

  factory AISettings.defaultSettings() => AISettings(
    apiKey: '',
    apiUrl: '',
    model: '',
    temperature: 0.7,
    maxTokens: 1000,
  );

  AISettings copyWith({
    String? apiKey,
    String? apiUrl,
    String? model,
    double? temperature,
    int? maxTokens,
    String? hostOverride,
  }) {
    return AISettings(
      apiKey: apiKey ?? this.apiKey,
      apiUrl: apiUrl ?? this.apiUrl,
      model: model ?? this.model,
      temperature: temperature ?? this.temperature,
      maxTokens: maxTokens ?? this.maxTokens,
      hostOverride: hostOverride ?? this.hostOverride,
    );
  }
}
