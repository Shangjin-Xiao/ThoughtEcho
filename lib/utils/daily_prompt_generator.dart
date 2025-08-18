import 'dart:math';
import '../services/weather_service.dart';

class DailyPromptGenerator {
  // 时间段常量
  static const String _morning = '早上';
  static const String _afternoon = '下午';
  static const String _evening = '晚上';
  static const String _lateNight = '深夜';

  // 默认提示常量 - 积极正面的思考引导
  static const List<String> _defaultPrompts = [
    "今天有什么值得感恩的事？",
    "给过去的自己一句鼓励的话，会说什么？",
    "今天学到了什么让你感到兴奋的新东西？",
    "什么美好的想法正在等待你去实现？",
    "最近什么让你感到快乐和满足？",
    "克服困难后有什么值得庆祝的感悟？",
    "如果明天完全自由，你最想做什么有意义的事？",
    "今天遇到的挑战教会了你什么宝贵经验？",
    "哪些积极的小习惯正在让你变得更好？",
    "此刻，你想对未来的自己说什么温暖的话？",
    "今天有什么小小的成就值得为自己骄傲？",
    "什么温暖的回忆让你嘴角不禁上扬？"
  ];
  // 获取默认的每日提示
  static String getDefaultPrompt() {
    // 使用日期为种子选择一个提示，确保同一天显示相同提示
    final today = DateTime.now();
    final dayOfYear = today.difference(DateTime(today.year, 1, 1)).inDays;
    final index = dayOfYear % _defaultPrompts.length;
    return _defaultPrompts[index];
  }

  // 根据时间和天气生成提示
  static String generatePromptBasedOnContext({
    String? city,
    String? weather,
    String? temperature,
  }) {
    final now = DateTime.now();
    final hour = now.hour;

    String timeOfDay;
    if (hour >= 5 && hour < 12) {
      timeOfDay = _morning;
    } else if (hour >= 12 && hour < 18) {
      timeOfDay = _afternoon;
    } else if (hour >= 18 && hour < 23) {
      timeOfDay = _evening;
    } else {
      timeOfDay = _lateNight;
    }

    List<String> prompts = [];

    // 通用积极提示
    prompts.addAll([
      "此刻，你有什么特别的想法或美好感受想要记录下来吗？",
      "回顾今天，有什么让你印象深刻的温暖瞬间？",
      "静下心来，感受一下当下的情绪，它想告诉你什么美好的信息？",
      "今天有什么小小的进步或收获让你感到欣慰？",
      "什么事物让你感到充满希望和动力？"
    ]);

    // 基于时间的提示
    _addTimeBasedPrompts(prompts, timeOfDay);

    // 获取天气key（只查找一次）
    String? weatherKey;
    if (weather != null) {
      weatherKey = WeatherService.weatherKeyToLabel.keys.firstWhere(
        (k) =>
            weather == k || weather == WeatherService.getWeatherDescription(k),
        orElse: () => weather,
      );
    }

    // 基于时间和天气的组合提示
    if (weatherKey != null) {
      _addTimeWeatherPrompts(prompts, timeOfDay, weatherKey);
      _addWeatherPrompts(prompts, weatherKey);
    }

    // 基于温度的提示
    _addTemperaturePrompts(prompts, temperature);

    // 基于城市的提示
    if (city != null && city.isNotEmpty) {
      prompts.add("身在 $city，这座城市今天给你带来了什么灵感？");
    }

    // 随机选择一条提示
    if (prompts.isEmpty) {
      return "今天，你有什么新的感悟或美好的想法想要分享呢？";
    }

    final random = Random();
    return prompts[random.nextInt(prompts.length)];
  }

  // 添加基于时间的提示
  static void _addTimeBasedPrompts(List<String> prompts, String timeOfDay) {
    switch (timeOfDay) {
      case _morning:
        prompts.addAll([
          "新的一天开始了，你对今天有什么美好的期待？",
          "早晨的空气闻起来怎么样？它让你想起了什么温馨的回忆？",
          "为今天设定一个让你兴奋的小目标吧，可以是什么呢？",
          "晨光中，什么积极的想法正在你心中萌芽？"
        ]);
        break;
      case _afternoon:
        prompts.addAll([
          "午后的阳光或微风，让你有什么愉悦的感触？",
          "今天过半，有什么进展顺利让你感到满意的事情吗？",
          "花点时间放松一下，想想让你感到安心和快乐的事物。",
          "午后时光，什么美好的计划正在你心中酝酿？"
        ]);
        break;
      case _evening:
        prompts.addAll([
          "夜幕降临，回顾今天，有什么值得庆祝或感恩的事？",
          "此刻的宁静适合思考，你脑海中浮现了什么美好的画面？",
          "为明天做个充满希望的计划或设想吧。",
          "夕阳西下，今天的哪个时刻让你感到特别温暖？"
        ]);
        break;
      case _lateNight:
        prompts.addAll([
          "夜深人静，有什么温馨的想法或美好的灵感悄然浮现？",
          "此刻的寂静让你想到了什么珍贵的回忆？",
          "睡前放下杂念，记录下此刻内心的平静和满足。",
          "繁星点点，什么美好的愿望正在你心中闪耀？"
        ]);
        break;
    }
  }

  // 添加基于时间和天气组合的提示
  static void _addTimeWeatherPrompts(
    List<String> prompts,
    String timeOfDay,
    String weatherKey,
  ) {
    switch (timeOfDay) {
      case _morning:
        switch (weatherKey) {
          case 'clear':
            prompts.add("清晨的阳光洒满窗台，此刻你的心情如何？有什么美好的计划吗？");
            break;
          case 'rain':
            prompts.add("听着清晨温柔的雨声，内心是否格外宁静？有什么温暖的感悟？");
            break;
          case 'cloudy':
          case 'partly_cloudy':
            prompts.add("云层微厚的早晨，正适合慢慢品味，思考一下最近的美好收获。");
            break;
        }
        break;
      case _afternoon:
        switch (weatherKey) {
          case 'clear':
            prompts.add("午后暖阳正好，适合小憩片刻，记录下此刻的惬意和满足。");
            break;
          case 'rain':
            prompts.add("雨天的午后，窗外滴答作响，屋内适合读一本书或写下温暖的想法。");
            break;
        }
        break;
      case _evening:
      case _lateNight:
        switch (weatherKey) {
          case 'clear':
            prompts.add("夜幕降临，星光或月色正好，此刻有什么美好的心愿或温暖的回忆？");
            break;
          case 'rain':
            prompts.add("雨夜漫漫，适合独处思考，最近有什么让你感到欣慰或期待的事？");
            break;
          case 'wind':
            prompts.add("晚风轻拂的夜晚，思绪是否也随风飘远？记录下此刻美好的灵感吧。");
            break;
        }
        break;
    }
  }

  // 添加基于天气的通用积极提示
  static void _addWeatherPrompts(List<String> prompts, String weatherKey) {
    switch (weatherKey) {
      case 'clear':
        prompts.addAll(["阳光明媚的日子，有什么让你感到开心和充满活力？", "这样的好天气，适合做些什么让你放松和快乐的事情？"]);
        break;
      case 'rain':
        prompts.addAll(["听着雨声，你的心情是否格外宁静和平和？", "雨天适合沉思，有什么温暖的想法在脑海中萦绕？"]);
        break;
      case 'cloudy':
      case 'partly_cloudy':
        prompts.addAll(["多云的天空下，你的思绪飘向了什么美好的地方？", "阴天有时也别有韵味，它让你想起了什么珍贵的回忆？"]);
        break;
      case 'snow':
        prompts.addAll(["窗外的雪景给你带来了怎样的纯净感受？", "下雪天，适合窝在温暖的地方思考些什么美好的事？"]);
        break;
    }
  }

  // 添加基于温度的积极提示
  static void _addTemperaturePrompts(
    List<String> prompts,
    String? temperature,
  ) {
    if (temperature == null) return;

    try {
      final tempValue = double.parse(temperature.replaceAll('°C', '').trim());
      if (tempValue > 28) {
        prompts.add("天气有点热，此刻你最想做什么舒适的事来享受夏日时光？");
      } else if (tempValue < 10) {
        prompts.add("天气有点冷，注意保暖的同时，有什么温暖人心的想法吗？");
      }
    } catch (e) {
      // 忽略温度解析错误
    }
  }
}
