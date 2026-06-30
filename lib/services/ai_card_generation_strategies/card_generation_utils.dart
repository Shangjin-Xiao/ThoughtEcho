/// 卡片生成通用工具类
class CardGenerationUtils {
  // 天气本地化映射 - 多语言支持
  // Key: 英文标准名（小写）, Value: Map<languageCode, localizedName>
  static const Map<String, Map<String, String>> _weatherLocalizations = {
    // 基础天气类型
    'clear': {'zh': '晴', 'en': 'Clear', 'ja': '晴れ', 'fr': 'Dégagé'},
    'sunny': {'zh': '晴', 'en': 'Sunny', 'ja': '晴れ', 'fr': 'Ensoleillé'},
    'partly_cloudy': {
      'zh': '少云',
      'en': 'Partly Cloudy',
      'ja': '晴れ時々曇り',
      'fr': 'Partiellement nuageux'
    },
    'cloudy': {'zh': '多云', 'en': 'Cloudy', 'ja': '曇り', 'fr': 'Nuageux'},
    'overcast': {'zh': '阴', 'en': 'Overcast', 'ja': '曇天', 'fr': 'Couvert'},
    'fog': {'zh': '雾', 'en': 'Fog', 'ja': '霧', 'fr': 'Brouillard'},
    'haze': {'zh': '霾', 'en': 'Haze', 'ja': '霞', 'fr': 'Brume'},
    'windy': {'zh': '有风', 'en': 'Windy', 'ja': '風', 'fr': 'Venteux'},

    // 雨类天气
    'drizzle': {'zh': '毛毛雨', 'en': 'Drizzle', 'ja': '霧雨', 'fr': 'Bruine'},
    'light rain': {
      'zh': '小雨',
      'en': 'Light Rain',
      'ja': '小雨',
      'fr': 'Pluie légère'
    },
    'rain': {'zh': '雨', 'en': 'Rain', 'ja': '雨', 'fr': 'Pluie'},
    'moderate rain': {
      'zh': '中雨',
      'en': 'Moderate Rain',
      'ja': '中雨',
      'fr': 'Pluie modérée'
    },
    'heavy rain': {
      'zh': '大雨',
      'en': 'Heavy Rain',
      'ja': '大雨',
      'fr': 'Forte pluie'
    },
    'freezing_rain': {
      'zh': '冻雨',
      'en': 'Freezing Rain',
      'ja': '凍雨',
      'fr': 'Pluie verglaçante'
    },
    'rain_shower': {
      'zh': '阵雨',
      'en': 'Rain Shower',
      'ja': 'にわか雨',
      'fr': 'Averse'
    },
    'thunderstorm': {
      'zh': '雷雨',
      'en': 'Thunderstorm',
      'ja': '雷雨',
      'fr': 'Orage'
    },
    'thunderstorm_heavy': {
      'zh': '雷暴雨',
      'en': 'Heavy Thunderstorm',
      'ja': '激しい雷雨',
      'fr': 'Orage violent'
    },

    // 雪类天气
    'snow': {'zh': '雪', 'en': 'Snow', 'ja': '雪', 'fr': 'Neige'},
    'light snow': {
      'zh': '小雪',
      'en': 'Light Snow',
      'ja': '小雪',
      'fr': 'Neige légère'
    },
    'heavy snow': {
      'zh': '大雪',
      'en': 'Heavy Snow',
      'ja': '大雪',
      'fr': 'Forte neige'
    },
    'snow_grains': {
      'zh': '雪粒',
      'en': 'Snow Grains',
      'ja': '雪あられ',
      'fr': 'Grésil'
    },
    'snow_shower': {
      'zh': '阵雪',
      'en': 'Snow Shower',
      'ja': 'にわか雪',
      'fr': 'Averse de neige'
    },
    'sleet': {'zh': '雨夹雪', 'en': 'Sleet', 'ja': 'みぞれ', 'fr': 'Grésil'},

    // 其他格式变体
    'rainy': {'zh': '雨', 'en': 'Rainy', 'ja': '雨', 'fr': 'Pluvieux'},
    'snowy': {'zh': '雪', 'en': 'Snowy', 'ja': '雪', 'fr': 'Neigeux'},
    'stormy': {'zh': '暴风雨', 'en': 'Stormy', 'ja': '嵐', 'fr': 'Orageux'},
  };

  /// 本地化天气字符串
  /// [languageCode] 语言代码 ('zh', 'en', 'ja', 'fr', etc.)
  static String? localizeWeather(String? weather,
      {String languageCode = 'zh'}) {
    if (weather == null || weather.trim().isEmpty) return null;
    final w = weather.toLowerCase().trim();
    final variants = <String>{
      w,
      w.replaceAll('_', ' '),
      w.replaceAll(' ', '_'),
    };

    for (final key in variants) {
      if (_weatherLocalizations.containsKey(key)) {
        return _weatherLocalizations[key]?[languageCode] ??
            _weatherLocalizations[key]?['en'] ??
            weather;
      }
    }

    // 未命中保持原样（可能已是目标语言）
    return weather;
  }

  // 时间段本地化 - 多语言支持
  static const Map<String, Map<String, String>> _dayPeriodLocalizations = {
    'moring': {
      'zh': '晨间',
      'en': 'Morning',
      'ja': '朝',
      'fr': 'Matin'
    }, // 兼容常见拼写错误
    'morning': {'zh': '晨间', 'en': 'Morning', 'ja': '朝', 'fr': 'Matin'},
    'noon': {'zh': '正午', 'en': 'Noon', 'ja': '正午', 'fr': 'Midi'},
    'afternoon': {
      'zh': '午后',
      'en': 'Afternoon',
      'ja': '午後',
      'fr': 'Après-midi'
    },
    'evening': {'zh': '傍晚', 'en': 'Evening', 'ja': '夕方', 'fr': 'Soir'},
    'night': {'zh': '夜晚', 'en': 'Night', 'ja': '夜', 'fr': 'Nuit'},
    'dawn': {'zh': '黎明', 'en': 'Dawn', 'ja': '夜明け', 'fr': 'Aube'},
    'dusk': {'zh': '黄昏', 'en': 'Dusk', 'ja': '夕暮れ', 'fr': 'Crépuscule'},
    'late night': {
      'zh': '深夜',
      'en': 'Late Night',
      'ja': '深夜',
      'fr': 'Tard dans la nuit'
    },
    'midnight': {'zh': '午夜', 'en': 'Midnight', 'ja': '真夜中', 'fr': 'Minuit'},
  };

  /// 本地化时间段字符串
  static String? localizeDayPeriod(String? period,
      {String languageCode = 'zh'}) {
    if (period == null || period.trim().isEmpty) return null;
    final p = period.toLowerCase().trim();

    if (_dayPeriodLocalizations.containsKey(p)) {
      return _dayPeriodLocalizations[p]?[languageCode] ??
          _dayPeriodLocalizations[p]?['en'] ??
          period;
    }

    // 未命中保持原样（可能已是目标语言）
    return period;
  }

  /// 格式化日期 - 支持多语言
  /// [languageCode] 语言代码 ('zh', 'en', 'ja', 'fr', etc.)
  static String formatDate(String dateStr, {String languageCode = 'zh'}) {
    try {
      final date = DateTime.parse(dateStr);
      switch (languageCode) {
        case 'zh':
        case 'ja':
          // 中日文: 2026年1月22日
          return '${date.year}年${date.month}月${date.day}日';
        case 'fr':
          // 法文: 22/01/2026
          final d = date.day.toString().padLeft(2, '0');
          final m = date.month.toString().padLeft(2, '0');
          return '$d/$m/${date.year}';
        case 'en':
        default:
          // 英文格式: Jan 22, 2026
          const months = [
            'Jan',
            'Feb',
            'Mar',
            'Apr',
            'May',
            'Jun',
            'Jul',
            'Aug',
            'Sep',
            'Oct',
            'Nov',
            'Dec'
          ];
          return '${months[date.month - 1]} ${date.day}, ${date.year}';
      }
    } catch (e) {
      return dateStr;
    }
  }
}
