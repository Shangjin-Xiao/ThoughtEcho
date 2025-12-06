import '../models/generated_card.dart';

/// 卡片模板常量 - 优化版
/// 核心设计原则：
/// 1. 视觉美感：优化配色、间距和排版
/// 2. 结构清晰：统一的 viewBox 和布局逻辑
/// 3. 丰富多样：提供多种风格满足不同场景
class CardTemplates {
  // ============ 核心常量 ============
  static const double _viewBoxWidth = 400.0;
  static const double _viewBoxHeight = 600.0;
  static const int _maxContentCharsPerLine = 16; // 中文字符每行最大数量
  static const int _maxContentLines = 7; // 内容最大行数
  static const double _contentFontSize = 18.0;
  static const double _lineHeight = 1.6;

  /// 现代化知识卡片模板
  /// 特点：清新渐变，磨砂玻璃质感，网格背景
  static String knowledgeTemplate({
    required String content,
    String? author,
    String? date,
    String? source,
    String? location,
    String? weather,
    String? temperature,
    String? dayPeriod,
  }) {
    final textLines = _wrapText(content, _maxContentCharsPerLine, _maxContentLines);
    final metaText = _buildMetaText(date: date, location: location, weather: weather, temperature: temperature);
    final brandText = _buildBrandText(author: author, source: source);

    final contentHeight = textLines.length * _contentFontSize * _lineHeight;
    const contentAreaTop = 160.0;
    const contentAreaHeight = 300.0;
    final contentStartY = contentAreaTop + (contentAreaHeight - contentHeight) / 2 + _contentFontSize;

    return '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $_viewBoxWidth $_viewBoxHeight">
  <defs>
    <linearGradient id="knowledgeBg" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#6366f1"/>
      <stop offset="50%" stop-color="#8b5cf6"/>
      <stop offset="100%" stop-color="#d946ef"/>
    </linearGradient>
    <linearGradient id="cardBg" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%" stop-color="#ffffff" stop-opacity="0.95"/>
      <stop offset="100%" stop-color="#f8fafc" stop-opacity="0.9"/>
    </linearGradient>
    <filter id="cardShadow" x="-20%" y="-20%" width="140%" height="140%">
      <feDropShadow dx="0" dy="8" stdDeviation="12" flood-color="#000000" flood-opacity="0.1"/>
    </filter>
    <pattern id="gridPattern" width="20" height="20" patternUnits="userSpaceOnUse">
      <circle cx="1" cy="1" r="1" fill="#ffffff" fill-opacity="0.2"/>
    </pattern>
  </defs>

  <!-- 背景 -->
  <rect width="$_viewBoxWidth" height="$_viewBoxHeight" fill="url(#knowledgeBg)" rx="24"/>
  <rect width="$_viewBoxWidth" height="$_viewBoxHeight" fill="url(#gridPattern)" rx="24"/>
  
  <!-- 装饰元素 -->
  <circle cx="360" cy="60" r="80" fill="#ffffff" fill-opacity="0.1"/>
  <circle cx="40" cy="540" r="60" fill="#ffffff" fill-opacity="0.1"/>

  <!-- 顶部图标 -->
  <circle cx="200" cy="90" r="36" fill="#ffffff" fill-opacity="0.2"/>
  <circle cx="200" cy="90" r="28" fill="#ffffff" fill-opacity="0.95"/>
  <g transform="translate(200, 90)">
    <rect x="-10" y="-8" width="20" height="16" rx="2" fill="none" stroke="#6366f1" stroke-width="2"/>
    <line x1="-6" y1="-3" x2="6" y2="-3" stroke="#6366f1" stroke-width="2" stroke-linecap="round"/>
    <line x1="-6" y1="3" x2="2" y2="3" stroke="#6366f1" stroke-width="2" stroke-linecap="round"/>
  </g>

  <!-- 内容卡片 -->
  <rect x="24" y="$contentAreaTop" width="352" height="$contentAreaHeight" fill="url(#cardBg)" rx="20" filter="url(#cardShadow)"/>
  
  <!-- 内容文字 -->
${_renderTextLines(textLines, 200.0, contentStartY, _contentFontSize, '#1e293b')}

  <!-- 底部信息 -->
  <rect x="40" y="490" width="320" height="1" fill="#ffffff" fill-opacity="0.3"/>
  <text x="200" y="520" text-anchor="middle" fill="#ffffff" font-family="system-ui, sans-serif" font-size="12" font-weight="500">${_escape(metaText)}</text>
  <text x="200" y="545" text-anchor="middle" fill="#ffffff" font-family="system-ui, sans-serif" font-size="11" fill-opacity="0.8">${_escape(brandText)}</text>
</svg>
''';
  }

  /// 引用卡片模板
  /// 特点：暖色调，大引号装饰，强调作者
  static String quoteTemplate({
    required String content,
    String? author,
    String? date,
    String? source,
    String? location,
    String? weather,
    String? temperature,
    String? dayPeriod,
  }) {
    final textLines = _wrapText(content, _maxContentCharsPerLine, _maxContentLines);
    final metaText = _buildMetaText(date: date, location: location, weather: weather, temperature: temperature);
    final authorDisplay = author ?? source ?? '';

    final contentHeight = textLines.length * _contentFontSize * _lineHeight;
    const contentAreaTop = 180.0;
    const contentAreaHeight = 260.0;
    final contentStartY = contentAreaTop + (contentAreaHeight - contentHeight) / 2 + _contentFontSize;

    return '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $_viewBoxWidth $_viewBoxHeight">
  <defs>
    <linearGradient id="quoteBg" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#ff9a9e"/>
      <stop offset="100%" stop-color="#fecfef"/>
    </linearGradient>
    <filter id="quoteShadow" x="-20%" y="-20%" width="140%" height="140%">
      <feDropShadow dx="0" dy="4" stdDeviation="8" flood-color="#000000" flood-opacity="0.1"/>
    </filter>
  </defs>

  <!-- 背景 -->
  <rect width="$_viewBoxWidth" height="$_viewBoxHeight" fill="url(#quoteBg)" rx="24"/>
  
  <!-- 装饰引号 -->
  <text x="40" y="140" fill="#ffffff" fill-opacity="0.4" font-family="Georgia, serif" font-size="120" font-weight="bold">“</text>
  <text x="360" y="460" text-anchor="end" fill="#ffffff" fill-opacity="0.4" font-family="Georgia, serif" font-size="120" font-weight="bold">”</text>

  <!-- 内容卡片 -->
  <rect x="32" y="$contentAreaTop" width="336" height="$contentAreaHeight" fill="#ffffff" fill-opacity="0.9" rx="16" filter="url(#quoteShadow)"/>

  <!-- 引用内容 -->
${_renderTextLines(textLines, 200.0, contentStartY, _contentFontSize, '#374151', fontFamily: 'Georgia, serif', fontStyle: 'italic')}

  <!-- 作者信息 -->
${authorDisplay.isNotEmpty ? '''
  <text x="200" y="480" text-anchor="middle" fill="#be185d" font-family="system-ui, sans-serif" font-size="14" font-weight="600">— ${_escape(authorDisplay)} —</text>
''' : ''}

  <!-- 底部信息 -->
  <text x="200" y="540" text-anchor="middle" fill="#881337" font-family="system-ui, sans-serif" font-size="11" fill-opacity="0.7">${_escape(metaText)}</text>
  <text x="200" y="560" text-anchor="middle" fill="#881337" font-family="system-ui, sans-serif" font-size="10" fill-opacity="0.5">心迹 · ThoughtEcho</text>
</svg>
''';
  }

  /// 哲学思考卡片模板
  /// 特点：深邃星空，思考泡泡，沉浸感
  static String philosophicalTemplate({
    required String content,
    String? author,
    String? date,
    String? source,
    String? location,
    String? weather,
    String? temperature,
    String? dayPeriod,
  }) {
    final textLines = _wrapText(content, _maxContentCharsPerLine, _maxContentLines);
    final metaText = _buildMetaText(date: date, location: location, weather: weather, temperature: temperature);
    final brandText = _buildBrandText(author: author, source: source);

    final contentHeight = textLines.length * _contentFontSize * _lineHeight;
    const contentAreaTop = 180.0;
    const contentAreaHeight = 280.0;
    final contentStartY = contentAreaTop + (contentAreaHeight - contentHeight) / 2 + _contentFontSize;

    return '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $_viewBoxWidth $_viewBoxHeight">
  <defs>
    <linearGradient id="philoBg" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#0f172a"/>
      <stop offset="50%" stop-color="#1e1b4b"/>
      <stop offset="100%" stop-color="#312e81"/>
    </linearGradient>
    <radialGradient id="starGlow" cx="50%" cy="50%" r="50%">
      <stop offset="0%" stop-color="#ffffff" stop-opacity="0.8"/>
      <stop offset="100%" stop-color="#ffffff" stop-opacity="0"/>
    </radialGradient>
  </defs>

  <!-- 背景 -->
  <rect width="$_viewBoxWidth" height="$_viewBoxHeight" fill="url(#philoBg)" rx="24"/>

  <!-- 星星装饰 -->
  <circle cx="50" cy="80" r="1.5" fill="#ffffff" fill-opacity="0.8"/>
  <circle cx="350" cy="120" r="2" fill="#ffffff" fill-opacity="0.6"/>
  <circle cx="100" cy="500" r="1" fill="#ffffff" fill-opacity="0.7"/>
  <circle cx="300" cy="550" r="1.5" fill="#ffffff" fill-opacity="0.5"/>
  <circle cx="200" cy="300" r="150" fill="url(#starGlow)" fill-opacity="0.05"/>

  <!-- 思考图标 -->
  <circle cx="200" cy="100" r="32" fill="#ffffff" fill-opacity="0.1"/>
  <g transform="translate(200, 100)">
    <path d="M-12 -8 C-15 -12 -8 -18 0 -15 C8 -18 15 -12 12 -8 C18 -5 18 5 12 8 C15 12 8 18 0 15 C-8 18 -15 12 -12 8 C-18 5 -18 -5 -12 -8 Z" fill="none" stroke="#a5b4fc" stroke-width="1.5"/>
    <circle cx="0" cy="0" r="4" fill="#a5b4fc"/>
  </g>

  <!-- 内容区域 -->
  <rect x="32" y="$contentAreaTop" width="336" height="$contentAreaHeight" fill="#ffffff" fill-opacity="0.05" rx="16" stroke="#ffffff" stroke-width="0.5" stroke-opacity="0.1"/>

  <!-- 内容文字 -->
${_renderTextLines(textLines, 200.0, contentStartY, _contentFontSize, '#e2e8f0')}

  <!-- 底部信息 -->
  <line x1="100" y1="500" x2="300" y2="500" stroke="#ffffff" stroke-opacity="0.1"/>
  <text x="200" y="530" text-anchor="middle" fill="#94a3b8" font-family="system-ui, sans-serif" font-size="11">${_escape(metaText)}</text>
  <text x="200" y="555" text-anchor="middle" fill="#64748b" font-family="system-ui, sans-serif" font-size="11">${_escape(brandText)}</text>
</svg>
''';
  }

  /// 简约卡片模板
  /// 特点：极简黑白灰，重点突出，留白
  static String minimalistTemplate({
    required String content,
    String? author,
    String? date,
    String? source,
    String? location,
    String? weather,
    String? temperature,
    String? dayPeriod,
  }) {
    final textLines = _wrapText(content, _maxContentCharsPerLine, _maxContentLines);
    final metaText = _buildMetaText(date: date, location: location, weather: weather, temperature: temperature);
    final brandText = _buildBrandText(author: author, source: source);

    final contentHeight = textLines.length * _contentFontSize * _lineHeight;
    const contentAreaTop = 160.0;
    const contentAreaHeight = 300.0;
    final contentStartY = contentAreaTop + (contentAreaHeight - contentHeight) / 2 + _contentFontSize;

    return '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $_viewBoxWidth $_viewBoxHeight">
  <defs>
    <linearGradient id="minimalistBg" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#f8fafc"/>
      <stop offset="100%" stop-color="#e2e8f0"/>
    </linearGradient>
    <filter id="minimalShadow" x="-10%" y="-10%" width="120%" height="120%">
      <feDropShadow dx="0" dy="2" stdDeviation="4" flood-color="#000000" flood-opacity="0.05"/>
    </filter>
  </defs>

  <!-- 背景 -->
  <rect width="$_viewBoxWidth" height="$_viewBoxHeight" fill="url(#minimalistBg)" rx="24"/>
  
  <!-- 顶部装饰条 -->
  <rect x="0" y="0" width="$_viewBoxWidth" height="12" fill="#0f172a"/>

  <!-- 内容卡片 -->
  <rect x="40" y="80" width="320" height="440" fill="#ffffff" rx="2" filter="url(#minimalShadow)"/>
  
  <!-- 装饰线 -->
  <rect x="180" y="120" width="40" height="2" fill="#0f172a"/>

  <!-- 内容文字 -->
${_renderTextLines(textLines, 200.0, contentStartY, _contentFontSize, '#0f172a')}

  <!-- 底部信息 -->
  <text x="200" y="460" text-anchor="middle" fill="#64748b" font-family="system-ui, sans-serif" font-size="10" letter-spacing="1">${_escape(metaText.toUpperCase())}</text>
  <text x="200" y="480" text-anchor="middle" fill="#94a3b8" font-family="system-ui, sans-serif" font-size="9">${_escape(brandText)}</text>
</svg>
''';
  }

  /// 自然卡片模板（新增）
  /// 特点：绿色系，有机形状，清新自然
  static String natureTemplate({
    required String content,
    String? author,
    String? date,
    String? source,
    String? location,
    String? weather,
    String? temperature,
    String? dayPeriod,
  }) {
    final textLines = _wrapText(content, _maxContentCharsPerLine, _maxContentLines);
    final metaText = _buildMetaText(date: date, location: location, weather: weather, temperature: temperature);
    final brandText = _buildBrandText(author: author, source: source);

    final contentHeight = textLines.length * _contentFontSize * _lineHeight;
    const contentAreaTop = 160.0;
    const contentAreaHeight = 300.0;
    final contentStartY = contentAreaTop + (contentAreaHeight - contentHeight) / 2 + _contentFontSize;

    return '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $_viewBoxWidth $_viewBoxHeight">
  <defs>
    <linearGradient id="natureBg" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%" stop-color="#ecfccb"/>
      <stop offset="100%" stop-color="#dcfce7"/>
    </linearGradient>
  </defs>

  <!-- 背景 -->
  <rect width="$_viewBoxWidth" height="$_viewBoxHeight" fill="url(#natureBg)" rx="24"/>
  
  <!-- 装饰叶子 -->
  <path d="M0 0 Q100 50 200 0 L400 0 L400 100 Q300 150 200 100 Q100 50 0 100 Z" fill="#84cc16" fill-opacity="0.2"/>
  <circle cx="320" cy="500" r="120" fill="#166534" fill-opacity="0.05"/>
  <circle cx="60" cy="550" r="80" fill="#15803d" fill-opacity="0.05"/>

  <!-- 图标 -->
  <circle cx="200" cy="100" r="32" fill="#ffffff" fill-opacity="0.6"/>
  <path transform="translate(188, 88) scale(1.5)" d="M12 2C7.5 2 4 6.5 4 12s4.5 10 9 10c4.5 0 9-4.5 9-10S16.5 2 12 2zm0 18c-3.5 0-7-3.5-7-8s3.5-8 7-8 7 3.5 7 8-3.5 8-7 8z" fill="#15803d"/>

  <!-- 内容文字 -->
${_renderTextLines(textLines, 200.0, contentStartY, _contentFontSize, '#14532d')}

  <!-- 底部信息 -->
  <rect x="100" y="480" width="200" height="1" fill="#15803d" fill-opacity="0.2"/>
  <text x="200" y="510" text-anchor="middle" fill="#166534" font-family="system-ui, sans-serif" font-size="11">${_escape(metaText)}</text>
  <text x="200" y="530" text-anchor="middle" fill="#15803d" font-family="system-ui, sans-serif" font-size="10" fill-opacity="0.7">${_escape(brandText)}</text>
</svg>
''';
  }

  /// 复古卡片模板（新增）
  /// 特点：纸张纹理，衬线字体，怀旧色调
  static String retroTemplate({
    required String content,
    String? author,
    String? date,
    String? source,
    String? location,
    String? weather,
    String? temperature,
    String? dayPeriod,
  }) {
    final textLines = _wrapText(content, _maxContentCharsPerLine, _maxContentLines);
    final metaText = _buildMetaText(date: date, location: location, weather: weather, temperature: temperature);
    final brandText = _buildBrandText(author: author, source: source);

    final contentHeight = textLines.length * _contentFontSize * _lineHeight;
    const contentAreaTop = 160.0;
    const contentAreaHeight = 300.0;
    final contentStartY = contentAreaTop + (contentAreaHeight - contentHeight) / 2 + _contentFontSize;

    return '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $_viewBoxWidth $_viewBoxHeight">
  <defs>
    <filter id="noise">
      <feTurbulence type="fractalNoise" baseFrequency="0.8" numOctaves="3" stitchTiles="stitch"/>
      <feColorMatrix type="saturate" values="0"/>
      <feComponentTransfer>
        <feFuncA type="linear" slope="0.1"/>
      </feComponentTransfer>
    </filter>
  </defs>

  <!-- 背景 -->
  <rect width="$_viewBoxWidth" height="$_viewBoxHeight" fill="#f5f5dc" rx="24"/>
  <rect width="$_viewBoxWidth" height="$_viewBoxHeight" fill="#d2b48c" fill-opacity="0.2" rx="24"/>
  <rect width="$_viewBoxWidth" height="$_viewBoxHeight" filter="url(#noise)" rx="24"/>
  
  <!-- 边框 -->
  <rect x="20" y="20" width="360" height="560" fill="none" stroke="#78350f" stroke-width="2" rx="16" stroke-dasharray="4 4"/>
  <rect x="28" y="28" width="344" height="544" fill="none" stroke="#78350f" stroke-width="1" rx="12" stroke-opacity="0.5"/>

  <!-- 装饰 -->
  <circle cx="200" cy="80" r="4" fill="#78350f"/>
  <line x1="160" y1="80" x2="240" y2="80" stroke="#78350f" stroke-width="1"/>

  <!-- 内容文字 -->
${_renderTextLines(textLines, 200.0, contentStartY, _contentFontSize, '#451a03', fontFamily: 'Courier New, monospace')}

  <!-- 底部信息 -->
  <text x="200" y="500" text-anchor="middle" fill="#78350f" font-family="Courier New, monospace" font-size="11">${_escape(metaText)}</text>
  <text x="200" y="520" text-anchor="middle" fill="#92400e" font-family="Courier New, monospace" font-size="10">${_escape(brandText)}</text>
</svg>
''';
  }

  /// 根据卡片类型获取对应模板
  static String getTemplateByType({
    required CardType type,
    required String content,
    String? author,
    String? date,
    String? source,
    String? location,
    String? weather,
    String? temperature,
    String? dayPeriod,
  }) {
    switch (type) {
      case CardType.knowledge:
      case CardType.gradient: // 暂用知识模板
        return knowledgeTemplate(
          content: content,
          author: author,
          date: date,
          source: source,
          location: location,
          weather: weather,
          temperature: temperature,
          dayPeriod: dayPeriod,
        );
      case CardType.quote:
        return quoteTemplate(
          content: content,
          author: author,
          date: date,
          source: source,
          location: location,
          weather: weather,
          temperature: temperature,
          dayPeriod: dayPeriod,
        );
      case CardType.philosophical:
        return philosophicalTemplate(
          content: content,
          author: author,
          date: date,
          source: source,
          location: location,
          weather: weather,
          temperature: temperature,
          dayPeriod: dayPeriod,
        );
      case CardType.minimalist:
        return minimalistTemplate(
          content: content,
          author: author,
          date: date,
          source: source,
          location: location,
          weather: weather,
          temperature: temperature,
          dayPeriod: dayPeriod,
        );
      case CardType.nature:
        return natureTemplate(
          content: content,
          author: author,
          date: date,
          source: source,
          location: location,
          weather: weather,
          temperature: temperature,
          dayPeriod: dayPeriod,
        );
      case CardType.retro:
        return retroTemplate(
          content: content,
          author: author,
          date: date,
          source: source,
          location: location,
          weather: weather,
          temperature: temperature,
          dayPeriod: dayPeriod,
        );
    }
  }

  // ============ 工具方法 ============

  /// 文本换行处理
  static List<String> _wrapText(
    String text,
    int maxCharsPerLine,
    int maxLines,
  ) {
    String cleanText = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (cleanText.isEmpty) return [''];

    final lines = <String>[];
    int currentIndex = 0;

    while (currentIndex < cleanText.length && lines.length < maxLines) {
      int endIndex = currentIndex + maxCharsPerLine;

      if (endIndex >= cleanText.length) {
        lines.add(cleanText.substring(currentIndex));
        break;
      }

      String segment = cleanText.substring(currentIndex, endIndex);
      // 简单的中文/英文断行优化
      int lastSpace = segment.lastIndexOf(' ');
      // 如果是中文环境，空格断行不是必须的，但如果有空格且靠后，可以利用
      // 这里简化处理：如果空格在后半部分，则在空格处断行；否则强制断行
      if (lastSpace > maxCharsPerLine * 0.6) {
        lines.add(segment.substring(0, lastSpace).trim());
        currentIndex += lastSpace + 1;
      } else {
        lines.add(segment.trim());
        currentIndex = endIndex;
      }
    }

    if (currentIndex < cleanText.length && lines.isNotEmpty) {
      String lastLine = lines.last;
      if (lastLine.length > 2) {
        lines[lines.length - 1] = '${lastLine.substring(0, lastLine.length - 2)}...';
      } else {
        lines[lines.length - 1] = '$lastLine...';
      }
    }

    return lines.isEmpty ? [''] : lines;
  }

  /// 生成SVG文字行
  static String _renderTextLines(
    List<String> lines,
    double centerX,
    double startY,
    double fontSize,
    String color, {
    String fontFamily = 'system-ui, -apple-system, sans-serif',
    String fontStyle = 'normal',
  }) {
    final buffer = StringBuffer();
    final lineSpacing = fontSize * _lineHeight;

    for (int i = 0; i < lines.length; i++) {
      final y = startY + i * lineSpacing;
      buffer.writeln(
        '  <text x="$centerX" y="${y.toStringAsFixed(1)}" text-anchor="middle" fill="$color" font-family="$fontFamily" font-size="${fontSize.toStringAsFixed(0)}" font-style="$fontStyle" font-weight="400">${_escape(lines[i])}</text>',
      );
    }

    return buffer.toString();
  }

  /// 构建元数据文本
  static String _buildMetaText({
    String? date,
    String? location,
    String? weather,
    String? temperature,
  }) {
    final parts = <String>[];
    if (date != null && date.isNotEmpty) parts.add(date);
    if (location != null && location.isNotEmpty) {
      final shortLocation = location.split(',').first.trim();
      if (shortLocation.isNotEmpty) parts.add(shortLocation);
    }
    if (weather != null && weather.isNotEmpty) {
      String weatherText = _localizeWeather(weather);
      if (temperature != null && temperature.isNotEmpty) {
        weatherText = '$weatherText $temperature';
      }
      parts.add(weatherText);
    }
    return parts.isEmpty ? '' : parts.join(' · ');
  }

  /// 构建品牌文本
  static String _buildBrandText({String? author, String? source}) {
    final parts = <String>[];
    if (author != null && author.isNotEmpty) {
      parts.add(author);
    } else if (source != null && source.isNotEmpty) {
      parts.add(source);
    }
    parts.add('心迹 · ThoughtEcho');
    return parts.join(' · ');
  }

  /// 天气本地化
  static String _localizeWeather(String weather) {
    final w = weather.toLowerCase().trim();
    const weatherMap = {
      'clear': '晴',
      'sunny': '晴',
      'cloudy': '多云',
      'partly_cloudy': '少云',
      'overcast': '阴',
      'rain': '雨',
      'drizzle': '小雨',
      'light rain': '小雨',
      'heavy rain': '大雨',
      'thunderstorm': '雷雨',
      'snow': '雪',
      'light snow': '小雪',
      'heavy snow': '大雪',
      'fog': '雾',
      'haze': '霾',
      'windy': '有风',
    };
    return weatherMap[w] ?? weather;
  }

  /// XML转义
  static String _escape(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}
