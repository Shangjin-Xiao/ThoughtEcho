import 'dart:math';
import '../services/weather_service.dart';

class DailyPromptGenerator {
  // 获取默认的每日提示
  static String getDefaultPrompt() {
    final List<String> defaultPrompts = [
      "今天有什么值得感恩的事？",
      "给过去的自己一句话，会说什么？",
      "今天学到了什么新东西？",
      "什么事想做却还没行动？",
      "最近什么让你感到快乐？",
      "克服困难后有什么感悟？",
      "如果明天完全自由，你会做什么？",
      "今天的挑战是什么？",
      "哪些小习惯正在改变你？",
      "此刻，你想对自己说什么？",
    ];

    // 使用日期为种子选择一个提示，确保同一天显示相同提示
    final today = DateTime.now();
    final dayOfYear = today.difference(DateTime(today.year, 1, 1)).inDays;
    final index = dayOfYear % defaultPrompts.length;
    return defaultPrompts[index];
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
      timeOfDay = '早上';
    } else if (hour >= 12 && hour < 18) {
      timeOfDay = '下午';
    } else if (hour >= 18 && hour < 23) {
      timeOfDay = '晚上';
    } else {
      timeOfDay = '深夜';
    }

    List<String> prompts = [];

    // 通用提示
    prompts.addAll([
      "此刻，你有什么特别的想法或感受想要记录下来吗？",
      "回顾今天，有什么让你印象深刻的瞬间？",
      "静下心来，感受一下当下的情绪，它想告诉你什么？",
    ]);

    // 基于时间的提示
    if (timeOfDay == '早上') {
      prompts.addAll([
        "新的一天开始了，你对今天有什么期待？",
        "早晨的空气闻起来怎么样？它让你想起了什么？",
        "为今天设定一个小目标吧，可以是什么呢？",
      ]);
    } else if (timeOfDay == '下午') {
      prompts.addAll([
        "午后的阳光或微风，让你有什么感触？",
        "今天过半，有什么进展顺利或遇到挑战的事情吗？",
        "花点时间放松一下，想想让你感到平静的事物。",
      ]);
    } else if (timeOfDay == '晚上') {
      prompts.addAll([
        "夜幕降临，回顾今天，有什么值得回味或反思的？",
        "此刻的宁静适合思考，你脑海中浮现了什么？",
        "为明天做个简单的计划或设想吧。",
      ]);
    } else {
      // 深夜
      prompts.addAll([
        "夜深人静，有什么心事或灵感悄然浮现？",
        "此刻的寂静让你想到了什么？",
        "睡前放下杂念，记录下此刻的心情。",
      ]);
    }

    // --- 结合时间和天气的提示 ---
    if (weather != null) {
      final weatherKey = WeatherService.weatherKeyToLabel.keys.firstWhere(
        (k) =>
            weather == k || weather == WeatherService.getWeatherDescription(k),
        orElse: () => weather,
      );
      if (timeOfDay == '早上') {
        if (weatherKey == 'clear') {
          prompts.add("清晨的阳光洒满窗台，此刻你的心情如何？有什么新的计划吗？");
        } else if (weatherKey == 'rain') {
          prompts.add("听着清晨的雨声，内心是否格外宁静？有什么特别的感悟？");
        } else if (weatherKey == 'cloudy' || weatherKey == 'partly_cloudy') {
          prompts.add("云层微厚的早晨，适合放慢脚步，思考一下最近的得失。");
        }
      } else if (timeOfDay == '下午') {
        if (weatherKey == 'clear') {
          prompts.add("午后暖阳正好，适合小憩片刻，或是记录下此刻的惬意。");
        } else if (weatherKey == 'rain') {
          prompts.add("雨天的午后，窗外滴答作响，屋内适合读一本书或写点什么。");
        }
      } else if (timeOfDay == '晚上' || timeOfDay == '深夜') {
        if (weatherKey == 'clear') {
          prompts.add("夜幕降临，星光或月色正好，此刻有什么心事或梦想？");
        } else if (weatherKey == 'rain') {
          prompts.add("雨夜漫漫，适合独处思考，最近有什么让你困惑或欣喜的事？");
        } else if (weatherKey == 'wind') {
          prompts.add("晚风轻拂的夜晚，思绪是否也随风飘远？记录下此刻的灵感吧。");
        }
      }
    }

    // 基于天气的提示 (如果天气信息可用)
    if (weather != null) {
      final weatherKey = WeatherService.weatherKeyToLabel.keys.firstWhere(
        (k) =>
            weather == k || weather == WeatherService.getWeatherDescription(k),
        orElse: () => weather,
      );
      if (weatherKey == 'clear') {
        prompts.addAll(["阳光明媚的日子，有什么让你感到开心？", "这样的好天气，适合做些什么让你放松的事情？"]);
      } else if (weatherKey == 'rain') {
        prompts.addAll(["听着雨声，你的心情是怎样的？", "雨天适合沉思，有什么想法在脑海中萦绕？"]);
      } else if (weatherKey == 'cloudy' || weatherKey == 'partly_cloudy') {
        prompts.addAll(["多云的天空下，你的思绪飘向了何方？", "阴天有时也别有韵味，它让你想起了什么？"]);
      } else if (weatherKey == 'snow') {
        prompts.addAll(["窗外的雪景给你带来了怎样的感受？", "下雪天，适合窝在温暖的地方思考些什么？"]);
      }
    }

    // 基于温度的提示 (如果温度信息可用)
    if (temperature != null) {
      try {
        final tempValue = double.parse(temperature.replaceAll('°C', '').trim());
        if (tempValue > 28) {
          prompts.add("天气有点热，此刻你最想做什么来降降温？");
        } else if (tempValue < 10) {
          prompts.add("天气有点冷，注意保暖的同时，有什么温暖的想法吗？");
        }
      } catch (e) {
        // debugPrint("解析温度失败: $e"); // 不打印，避免干扰
      }
    }

    // 基于城市的提示 (如果城市信息可用)
    if (city != null && city.isNotEmpty) {
      prompts.add("身在 $city，这座城市今天给你带来了什么灵感？");
    }

    // 随机选择一条提示（修改为只返回一条）
    final random = Random();
    prompts.shuffle(random); // 打乱列表顺序

    // 如果没有提示，返回一个默认值
    if (prompts.isEmpty) {
      return "今天，你有什么新的感悟或想法呢？";
    }

    // 返回随机选中的一条提示
    return prompts.first;
  }
} 