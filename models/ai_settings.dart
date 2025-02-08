class AISettings {
  final String apiUrl;
  final String apiKey;
  final String model;

  const AISettings({
    required this.apiUrl,
    required this.apiKey,
    required this.model,
  });

  Map<String, dynamic> toJson() => {
    'apiUrl': apiUrl,
    'apiKey': apiKey,
    'model': model,
  };

  factory AISettings.fromJson(Map<String, dynamic> json) => AISettings(
    apiUrl: json['apiUrl'] ?? 'http://localhost:8000/v1/chat/completions',
    apiKey: json['apiKey'] ?? '',
    model: json['model'] ?? 'gpt-3.5-turbo',
  );

  factory AISettings.defaultSettings() => const AISettings(
    apiUrl: 'http://localhost:8000/v1/chat/completions',
    apiKey: '',
    model: 'gpt-3.5-turbo',
  );

  AISettings copyWith({
    String? apiUrl,
    String? apiKey,
    String? model,
  }) {
    return AISettings(
      apiUrl: apiUrl ?? this.apiUrl,
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
    );
  }
}
