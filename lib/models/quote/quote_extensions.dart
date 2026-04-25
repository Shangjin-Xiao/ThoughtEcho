part of '../quote_model.dart';

/// Extension providing convenience getters and validation methods for Quote
extension QuoteExtensions on Quote {
  /// Check if the quote has location information
  bool get hasLocation =>
      (location != null && location!.isNotEmpty) || hasCoordinates;

  /// Check if the quote has geographic coordinates
  bool get hasCoordinates => latitude != null && longitude != null;

  /// Check if the quote has weather information
  bool get hasWeather => weather != null && weather!.isNotEmpty;

  /// Check if the quote has AI analysis
  bool get hasAiAnalysis => aiAnalysis != null && aiAnalysis!.isNotEmpty;

  /// Check if the quote has tags
  bool get hasTags => tagIds.isNotEmpty;

  /// Check if the quote has keywords
  bool get hasKeywords => keywords != null && keywords!.isNotEmpty;

  /// Get the sentiment label in Chinese
  String? get sentimentLabel =>
      sentiment != null ? Quote.sentimentKeyToLabel[sentiment] : null;

  /// Get the full source information with fallback
  String get fullSource {
    final s = source;
    if (s != null && s.isNotEmpty) return s;
    return '未知来源';
  }

  /// Validate the completeness of the Quote object
  bool get isValid {
    try {
      return Quote.isValidContent(content) &&
          Quote.isValidDate(date) &&
          Quote.isValidColorHex(colorHex) &&
          (sentiment == null || Quote.sentimentKeyToLabel.containsKey(sentiment!));
    } catch (e) {
      return false;
    }
  }
}
