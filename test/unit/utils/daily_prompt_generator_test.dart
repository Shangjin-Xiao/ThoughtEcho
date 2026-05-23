import "package:flutter_test/flutter_test.dart";
import "package:thoughtecho/utils/daily_prompt_generator.dart";
import "package:thoughtecho/gen_l10n/app_localizations.dart";

class FakeAppLocalizations implements AppLocalizations {
  @override
  String get promptDefault1 => "default_1";
  @override
  String get promptDefault2 => "default_2";
  @override
  String get promptDefault3 => "default_3";
  @override
  String get promptDefault4 => "default_4";
  @override
  String get promptDefault5 => "default_5";
  @override
  String get promptDefault6 => "default_6";
  @override
  String get promptDefault7 => "default_7";
  @override
  String get promptDefault8 => "default_8";
  @override
  String get promptDefault9 => "default_9";
  @override
  String get promptDefault10 => "default_10";
  @override
  String get promptDefault11 => "default_11";
  @override
  String get promptDefault12 => "default_12";

  @override
  String get promptGeneric1 => "generic_1";
  @override
  String get promptGeneric2 => "generic_2";
  @override
  String get promptGeneric3 => "generic_3";
  @override
  String get promptGeneric4 => "generic_4";
  @override
  String get promptGeneric5 => "generic_5";

  @override
  String get promptMorning1 => "morning_1";
  @override
  String get promptMorning2 => "morning_2";
  @override
  String get promptMorning3 => "morning_3";
  @override
  String get promptMorning4 => "morning_4";

  @override
  String get promptAfternoon1 => "afternoon_1";
  @override
  String get promptAfternoon2 => "afternoon_2";
  @override
  String get promptAfternoon3 => "afternoon_3";
  @override
  String get promptAfternoon4 => "afternoon_4";

  @override
  String get promptEvening1 => "evening_1";
  @override
  String get promptEvening2 => "evening_2";
  @override
  String get promptEvening3 => "evening_3";
  @override
  String get promptEvening4 => "evening_4";

  @override
  String get promptLateNight1 => "latenight_1";
  @override
  String get promptLateNight2 => "latenight_2";
  @override
  String get promptLateNight3 => "latenight_3";
  @override
  String get promptLateNight4 => "latenight_4";

  @override
  String get promptClearMorning => "clear_morning";
  @override
  String get promptRainMorning => "rain_morning";
  @override
  String get promptCloudyMorning => "cloudy_morning";

  @override
  String get promptClearAfternoon => "clear_afternoon";
  @override
  String get promptRainAfternoon => "rain_afternoon";

  @override
  String get promptClearEvening => "clear_evening";
  @override
  String get promptRainEvening => "rain_evening";
  @override
  String get promptWindEvening => "wind_evening";

  @override
  String get promptClearWeather1 => "clear_weather_1";
  @override
  String get promptClearWeather2 => "clear_weather_2";
  @override
  String get promptRainWeather1 => "rain_weather_1";
  @override
  String get promptRainWeather2 => "rain_weather_2";
  @override
  String get promptCloudyWeather1 => "cloudy_weather_1";
  @override
  String get promptCloudyWeather2 => "cloudy_weather_2";
  @override
  String get promptSnowWeather1 => "snow_weather_1";
  @override
  String get promptSnowWeather2 => "snow_weather_2";

  @override
  String get promptHotWeather => "hot_weather";
  @override
  String get promptColdWeather => "cold_weather";

  @override
  String get promptFallback => "fallback";
  @override
  String promptCityContext(String city) => "city_$city";

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late FakeAppLocalizations mockL10n;

  setUp(() {
    mockL10n = FakeAppLocalizations();
  });

  group("DailyPromptGenerator", () {
    test("getDefaultPrompt returns a prompt based on day of year", () {
      final result = DailyPromptGenerator.getDefaultPrompt(mockL10n);
      expect(result, isNotEmpty);
      expect(result, startsWith("default_"));
    });

    test("generatePromptBasedOnContext includes generic and time prompts", () {
      final result =
          DailyPromptGenerator.generatePromptBasedOnContext(mockL10n);
      expect(result, isNotEmpty);
      expect(
        result.startsWith("generic_") ||
            result.startsWith("morning_") ||
            result.startsWith("afternoon_") ||
            result.startsWith("evening_") ||
            result.startsWith("latenight_"),
        isTrue,
      );
    });

    test("generatePromptBasedOnContext includes city when provided", () {
      final result = DailyPromptGenerator.generatePromptBasedOnContext(mockL10n,
          city: "Tokyo");
      expect(result, isNotEmpty);
    });

    test("generatePromptBasedOnContext includes temperature prompts", () {
      final resultCold = DailyPromptGenerator.generatePromptBasedOnContext(
          mockL10n,
          temperature: "5°C");
      expect(resultCold, isNotEmpty);

      final resultHot = DailyPromptGenerator.generatePromptBasedOnContext(
          mockL10n,
          temperature: "35°C");
      expect(resultHot, isNotEmpty);
    });

    test("generatePromptBasedOnContext handles invalid temperature gracefully",
        () {
      final result = DailyPromptGenerator.generatePromptBasedOnContext(mockL10n,
          temperature: "unknown");
      expect(result, isNotEmpty);
    });

    test("generatePromptBasedOnContext includes weather prompts", () {
      final result = DailyPromptGenerator.generatePromptBasedOnContext(mockL10n,
          weather: "clear");
      expect(result, isNotEmpty);
    });
  });
}
