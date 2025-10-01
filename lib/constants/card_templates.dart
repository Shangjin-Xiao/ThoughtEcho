import '../models/generated_card.dart';

/// 卡片模板常量
class CardTemplates {
  /// 现代化知识卡片模板（参考302.ai设计）
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
    final displayContent = _processDisplayContent(content, maxLength: 180);
    final displayDate = date ??
        '${DateTime.now().year}年${DateTime.now().month}月${DateTime.now().day}日';
    final lines = _splitTextIntoAdaptiveLines(displayContent, 26, maxLines: 8);

    final normalizedWeather = _normalizeWeatherType(weather);
    final palette = _selectPalette(dayPeriod, normalizedWeather);
    final bgGradientId = (dayPeriod != null || normalizedWeather != null)
        ? 'dynamicKnowledgeBg'
        : 'modernKnowledgeBg';
    final backgroundGradientDef = (dayPeriod != null ||
            normalizedWeather != null)
        ? _buildDynamicGradientDef(bgGradientId, palette)
        : '''<linearGradient id="modernKnowledgeBg" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" style="stop-color:#4f46e5;stop-opacity:1" />
      <stop offset="50%" style="stop-color:#7c3aed;stop-opacity:1" />
      <stop offset="100%" style="stop-color:#db2777;stop-opacity:1" />
    </linearGradient>''';

    final weatherLayer = _buildWeatherSceneOverlay(
      dayPeriod: dayPeriod,
      weather: normalizedWeather,
      palette: palette,
      width: 400,
      height: 600,
    );

    final metaLines = _buildMetadataLines(
      date: displayDate,
      location: location,
      weather: weather,
      temperature: temperature,
      source: source ?? author,
      appMark: '心迹 · ThoughtEcho',
    );

    return '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 600">
  <defs>
    <!-- 背景渐变（可能为动态） -->
    $backgroundGradientDef

    <!-- 内容区域渐变 -->
    <linearGradient id="contentBg" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%" style="stop-color:#ffffff;stop-opacity:0.95" />
      <stop offset="100%" style="stop-color:#f8fafc;stop-opacity:0.95" />
    </linearGradient>

    <!-- 阴影滤镜 -->
    <filter id="shadow" x="-20%" y="-20%" width="140%" height="140%">
      <feDropShadow dx="0" dy="4" stdDeviation="8" flood-color="#000000" flood-opacity="0.1"/>
    </filter>
  </defs>

  <!-- 主背景 -->
  <rect width="400" height="600" fill="url(#$bgGradientId)" rx="24"/>

  $weatherLayer

  <!-- 装饰性几何元素 -->
  <circle cx="350" cy="80" r="40" fill="#ffffff" fill-opacity="0.08"/>
  <circle cx="60" cy="520" r="30" fill="#ffffff" fill-opacity="0.06"/>
  <rect x="320" y="500" width="60" height="60" fill="#ffffff" fill-opacity="0.04" rx="12" transform="rotate(15 350 530)"/>

  <!-- 顶部图标区域 -->
  <circle cx="200" cy="120" r="36" fill="#ffffff" fill-opacity="0.15"/>
  <circle cx="200" cy="120" r="28" fill="#ffffff" fill-opacity="0.9"/>

  <!-- 现代化知识图标 -->
  <g transform="translate(200, 120)">
    <!-- 书本图标 -->
    <rect x="-12" y="-8" width="24" height="16" fill="#4f46e5" rx="2"/>
    <rect x="-10" y="-6" width="20" height="2" fill="#ffffff"/>
    <rect x="-10" y="-2" width="16" height="1.5" fill="#ffffff"/>
    <rect x="-10" y="1" width="18" height="1.5" fill="#ffffff"/>
    <rect x="-10" y="4" width="14" height="1.5" fill="#ffffff"/>
  </g>

  <!-- 主内容区域 -->
  <rect x="24" y="180" width="352" height="320" fill="url(#contentBg)" rx="20" filter="url(#shadow)"/>

  <!-- 内容标题装饰线 -->
  <rect x="40" y="200" width="60" height="3" fill="#4f46e5" rx="1.5"/>

  <!-- 内容文字 -->
  ${_generateModernTextLines(lines, 200, 240, 16, '#1e293b', 1.5, verticalCenter: true, areaHeight: 320)}

  <!-- 底部信息区域 -->
  <rect x="24" y="520" width="352" height="72" fill="#000000" fill-opacity="0.18" rx="20"/>
  ${_buildMetadataTextBlock(metaLines, centerX: 200, startY: 540, lineHeight: 15, color: '#ffffff')}

  <!-- 右下角装饰点 -->
  <circle cx="360" cy="560" r="3" fill="#ffffff" fill-opacity="0.6"/>
</svg>
''';
  }

  /// 归一化天气字符串 -> 简单类别
  static String? _normalizeWeatherType(String? weather) {
    if (weather == null) return null;
    final w = weather.toLowerCase();
    if (w.contains('晴') || w.contains('sun') || w.contains('clear')) {
      return 'sunny';
    }
    if (w.contains('多云') || w.contains('云') || w.contains('cloud')) {
      return 'cloudy';
    }
    if (w.contains('雨') || w.contains('drizzle') || w.contains('showers')) {
      return 'rain';
    }
    if (w.contains('雪') || w.contains('snow')) {
      return 'snow';
    }
    if (w.contains('雾') ||
        w.contains('fog') ||
        w.contains('霾') ||
        w.contains('mist')) {
      return 'fog';
    }
    if (w.contains('雷') || w.contains('storm') || w.contains('电')) {
      return 'storm';
    }
    if (w.contains('风') || w.contains('wind')) {
      return 'windy';
    }
    return null;
  }

  /// 为时间段/天气选择颜色调色板
  static List<String> _selectPalette(String? dayPeriod, String? weather) {
    // 优先时间段再天气
    switch (dayPeriod) {
      case 'morning':
        return ['#ffedd5', '#fde68a', '#fbbf24']; // 温暖晨光
      case 'afternoon':
        return ['#bfdbfe', '#60a5fa', '#0ea5e9']; // 明亮蓝
      case 'evening':
        return ['#fed7aa', '#fb923c', '#f97316']; // 暖夕阳
      case 'night':
        return ['#1e3a8a', '#1e40af', '#0f172a']; // 深夜蓝
    }
    switch (weather) {
      case 'sunny':
        return ['#fef3c7', '#fde68a', '#f59e0b'];
      case 'cloudy':
        return ['#e2e8f0', '#cbd5e1', '#94a3b8'];
      case 'rain':
        return ['#c7d2fe', '#93c5fd', '#64748b'];
      case 'snow':
        return ['#f1f5f9', '#e2e8f0', '#cbd5e1'];
      case 'fog':
        return ['#f1f5f9', '#cbd5e1', '#94a3b8'];
      case 'storm':
        return ['#475569', '#334155', '#1e293b'];
      case 'windy':
        return ['#bae6fd', '#7dd3fc', '#38bdf8'];
    }
    // default neutral soft gradient (避免过度紫色)
    return ['#e0f2fe', '#bfdbfe', '#93c5fd'];
  }

  static String _buildDynamicGradientDef(String id, List<String> palette) {
    final stops = List.generate(palette.length, (i) {
      final pct = (i / (palette.length - 1) * 100).toStringAsFixed(0);
      return '<stop offset="$pct%" style="stop-color:${palette[i]};stop-opacity:1" />';
    }).join();
    return '<linearGradient id="$id" x1="0%" y1="0%" x2="100%" y2="100%">$stops</linearGradient>';
  }

  /// 构建天气/时间段场景叠加层（轻量元素，不喧宾夺主）
  static String _buildWeatherSceneOverlay({
    required String? dayPeriod,
    required String? weather,
    required List<String> palette,
    required double width,
    required double height,
  }) {
    final elements = StringBuffer();
    // 月亮或太阳
    if (dayPeriod == 'night') {
      elements.writeln(
          '<circle cx="320" cy="90" r="32" fill="#f1f5f9" fill-opacity="0.85"/>');
      elements
          .writeln('<circle cx="330" cy="80" r="32" fill="#0f172a"/>'); // 月亮缺口
      // 星星
      for (final star in [
        [60, 100],
        [100, 60],
        [140, 110],
        [260, 70]
      ]) {
        elements.writeln(
            '<circle cx="${star[0]}" cy="${star[1]}" r="2" fill="#f8fafc" />');
      }
    } else if (dayPeriod == 'morning' || weather == 'sunny') {
      elements.writeln(
          '<circle cx="340" cy="80" r="40" fill="#fcd34d" fill-opacity="0.9"/>');
      elements.writeln(
          '<circle cx="340" cy="80" r="55" fill="#fde68a" fill-opacity="0.35"/>');
    } else if (dayPeriod == 'evening') {
      elements.writeln(
          '<circle cx="340" cy="90" r="38" fill="#fb923c" fill-opacity="0.9"/>');
      elements.writeln(
          '<circle cx="340" cy="90" r="54" fill="#fdba74" fill-opacity="0.35"/>');
    }

    // 天气特效
    switch (weather) {
      case 'cloudy':
        elements.writeln(_cloud(80, 120, 60));
        elements.writeln(_cloud(150, 90, 80));
        break;
      case 'rain':
        elements.writeln(_cloud(140, 95, 100));
        // 雨滴
        for (int i = 0; i < 12; i++) {
          final x = 100 + (i * 12);
          final y = 140 + (i % 3) * 8;
          elements.writeln(
              '<line x1="$x" y1="$y" x2="$x" y2="${y + 16}" stroke="#60a5fa" stroke-width="2" stroke-linecap="round"/>');
        }
        break;
      case 'snow':
        elements.writeln(_cloud(140, 95, 100));
        for (int i = 0; i < 18; i++) {
          final x = 90 + (i * 10) % 220;
          final y = 150 + (i * 7) % 80;
          elements.writeln(
              '<circle cx="$x" cy="$y" r="2" fill="#ffffff" fill-opacity="0.9"/>');
        }
        break;
      case 'fog':
        for (int i = 0; i < 4; i++) {
          final y = 140 + i * 18;
          elements.writeln(
              '<rect x="20" y="$y" width="360" height="10" fill="#ffffff" fill-opacity="${0.05 + i * 0.05}" rx="5"/>');
        }
        break;
      case 'storm':
        elements.writeln(_cloud(150, 95, 110));
        // 闪电
        elements.writeln(
            '<path d="M180 140 L200 140 L185 180 L210 180 L160 250 L175 200 L150 200 Z" fill="#fde047" fill-opacity="0.85"/>');
        break;
      case 'windy':
        for (int i = 0; i < 3; i++) {
          final y = 150 + i * 20;
          elements.writeln(
              '<path d="M40 $y Q120 ${y - 10} 200 $y T360 $y" stroke="#38bdf8" stroke-width="3" fill="none" stroke-linecap="round" stroke-opacity="0.6"/>');
        }
        break;
    }

    if (elements.isEmpty) return '';
    final content = elements.toString();
    return '<g opacity="0.9">$content</g>';
  }

  static String _cloud(double cx, double cy, double w) {
    final h = w * 0.6;
    final left = cx - w / 2;
    final rx = (w / 2).toString();
    final ry = (h / 2).toString();
    final cx1 = (cx - w * 0.3).toString();
    final cy1 = (cy + h * 0.05).toString();
    final rx1 = (w * 0.35).toString();
    final ry1 = (h * 0.4).toString();
    final cx2 = (cx + w * 0.3).toString();
    final cy2 = (cy + h * 0.05).toString();
    final rx2 = (w * 0.33).toString();
    final ry2 = (h * 0.38).toString();
    final h25 = (h * 0.25).toString();
    final h12 = (h * 0.12).toString();
    return '<g fill="#ffffff" fill-opacity="0.75">'
        '<ellipse cx="$cx" cy="$cy" rx="$rx" ry="$ry" />'
        '<ellipse cx="$cx1" cy="$cy1" rx="$rx1" ry="$ry1" />'
        '<ellipse cx="$cx2" cy="$cy2" rx="$rx2" ry="$ry2" />'
        '<rect x="$left" y="$cy" width="$w" height="$h25" rx="$h12" />'
        '</g>';
  }

  static List<String> _buildMetadataLines({
    required String date,
    String? location,
    String? weather,
    String? temperature,
    String? source,
    required String appMark,
  }) {
    final lines = <String>[];
    final line1Parts = <String>[date];
    if (location != null && location.trim().isNotEmpty) {
      line1Parts.add(location.trim());
    }
    if (weather != null && weather.trim().isNotEmpty) {
      final wt = temperature != null && temperature.trim().isNotEmpty
          ? '$weather ${temperature.trim()}'
          : weather.trim();
      line1Parts.add(wt);
    }
    lines.add(line1Parts.join(' · '));

    final line2Parts = <String>[];
    if (source != null && source.trim().isNotEmpty) {
      line2Parts.add(source.trim());
    }
    line2Parts.add(appMark);
    lines.add(line2Parts.join(' · '));
    return lines;
  }

  static String _buildMetadataTextBlock(List<String> lines,
      {required double centerX,
      required double startY,
      required double lineHeight,
      required String color}) {
    final buf = StringBuffer();
    for (int i = 0; i < lines.length; i++) {
      final y = startY + i * lineHeight;
      final opacity = i == 0 ? 0.9 : 0.75;
      buf.writeln(
          '<text x="$centerX" y="$y" text-anchor="middle" fill="$color" font-family="system-ui, -apple-system, sans-serif" font-size="11" fill-opacity="$opacity">${_escape(lines[i])}</text>');
    }
    return buf.toString();
  }

  static String _escape(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
  }

  /// 现代化引用卡片模板
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
    final displayContent = _processDisplayContent(content, maxLength: 140);
    final displayDate = date ??
        '${DateTime.now().year}年${DateTime.now().month}月${DateTime.now().day}日';
    final lines = _splitTextIntoAdaptiveLines(displayContent, 22, maxLines: 8);
    final metaLines = _buildMetadataLines(
      date: displayDate,
      location: location,
      weather: weather,
      temperature: temperature,
      source: source ?? author,
      appMark: '心迹 · ThoughtEcho',
    );

    return '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 600">
  <defs>
    <!-- 温暖渐变背景 -->
    <linearGradient id="modernQuoteBg" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" style="stop-color:#f59e0b;stop-opacity:1" />
      <stop offset="50%" style="stop-color:#ef4444;stop-opacity:1" />
      <stop offset="100%" style="stop-color:#ec4899;stop-opacity:1" />
    </linearGradient>

    <!-- 内容卡片渐变 -->
    <linearGradient id="quoteCardBg" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%" style="stop-color:#ffffff;stop-opacity:0.98" />
      <stop offset="100%" style="stop-color:#fef7ff;stop-opacity:0.98" />
    </linearGradient>

    <!-- 引号渐变 -->
    <linearGradient id="quoteMarkGradient" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" style="stop-color:#ffffff;stop-opacity:0.3" />
      <stop offset="100%" style="stop-color:#ffffff;stop-opacity:0.1" />
    </linearGradient>
  </defs>

  <!-- 主背景 -->
  <rect width="400" height="600" fill="url(#modernQuoteBg)" rx="24"/>

  <!-- 装饰性元素 -->
  <circle cx="80" cy="100" r="50" fill="#ffffff" fill-opacity="0.06"/>
  <circle cx="320" cy="500" r="40" fill="#ffffff" fill-opacity="0.08"/>

  <!-- 大型装饰引号 -->
  <text x="60" y="140" fill="url(#quoteMarkGradient)" font-family="Georgia, serif" font-size="80" font-weight="bold">"</text>
  <text x="340" y="460" fill="url(#quoteMarkGradient)" font-family="Georgia, serif" font-size="80" font-weight="bold">"</text>

  <!-- 主内容卡片 -->
  <rect x="32" y="200" width="336" height="280" fill="url(#quoteCardBg)" rx="20" filter="url(#shadow)"/>

  <!-- 顶部装饰线 -->
  <rect x="48" y="220" width="80" height="3" fill="#f59e0b" rx="1.5"/>

  <!-- 引用内容 -->
  ${_generateModernTextLines(lines, 200, 260, 17, '#374151', 1.5, verticalCenter: true, areaHeight: 260)}

  <!-- 作者信息区域 -->
  ${author != null ? '''
  <rect x="48" y="420" width="304" height="40" fill="#f59e0b" fill-opacity="0.1" rx="12"/>
  <text x="200" y="445" text-anchor="middle" fill="#92400e" font-family="system-ui, -apple-system, sans-serif" font-size="14" font-weight="600" font-style="italic">
    — $author
  </text>
  ''' : ''}

  <!-- 底部信息 -->
  <rect x="32" y="500" width="336" height="72" fill="#000000" fill-opacity="0.18" rx="20"/>
  ${_buildMetadataTextBlock(metaLines, centerX: 200, startY: 520, lineHeight: 15, color: '#ffffff')}
</svg>
''';
  }

  /// 现代化哲学思考卡片模板
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
    final displayContent = _processDisplayContent(content, maxLength: 200);
    final displayDate = date ??
        '${DateTime.now().year}年${DateTime.now().month}月${DateTime.now().day}日';
    final lines = _splitTextIntoAdaptiveLines(displayContent, 26, maxLines: 8);
    final metaLines = _buildMetadataLines(
      date: displayDate,
      location: location,
      weather: weather,
      temperature: temperature,
      source: source ?? author,
      appMark: '心迹 · ThoughtEcho',
    );

    return '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 600">
  <defs>
    <!-- 深邃渐变背景 -->
    <linearGradient id="modernPhiloBg" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" style="stop-color:#1e1b4b;stop-opacity:1" />
      <stop offset="50%" style="stop-color:#312e81;stop-opacity:1" />
      <stop offset="100%" style="stop-color:#581c87;stop-opacity:1" />
    </linearGradient>

    <!-- 内容区域渐变 -->
    <linearGradient id="philoContentBg" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%" style="stop-color:#f8fafc;stop-opacity:0.98" />
      <stop offset="100%" style="stop-color:#e2e8f0;stop-opacity:0.98" />
    </linearGradient>

    <!-- 思考泡泡渐变 -->
    <radialGradient id="thoughtBubble" cx="50%" cy="50%" r="50%">
      <stop offset="0%" style="stop-color:#ffffff;stop-opacity:0.2" />
      <stop offset="100%" style="stop-color:#ffffff;stop-opacity:0.05" />
    </radialGradient>

    <!-- 阴影滤镜 -->
    <filter id="shadow" x="-20%" y="-20%" width="140%" height="140%">
      <feDropShadow dx="0" dy="4" stdDeviation="8" flood-color="#000000" flood-opacity="0.1"/>
    </filter>
  </defs>

  <!-- 主背景 -->
  <rect width="400" height="600" fill="url(#modernPhiloBg)" rx="24"/>

  <!-- 装饰性思考泡泡 -->
  <circle cx="100" cy="120" r="60" fill="url(#thoughtBubble)"/>
  <circle cx="320" cy="480" r="45" fill="url(#thoughtBubble)"/>
  <circle cx="80" cy="450" r="25" fill="#ffffff" fill-opacity="0.08"/>

  <!-- 顶部思考图标区域 -->
  <circle cx="200" cy="130" r="40" fill="#ffffff" fill-opacity="0.15"/>
  <circle cx="200" cy="130" r="32" fill="#ffffff" fill-opacity="0.9"/>

  <!-- 现代化思考图标 -->
  <g transform="translate(200, 130)">
    <!-- 大脑轮廓 -->
    <path d="M -15 -8 Q -18 -12 -12 -15 Q -5 -18 5 -15 Q 12 -12 15 -8 Q 18 -2 15 5 Q 12 12 5 15 Q -5 18 -12 15 Q -18 12 -15 5 Q -18 -2 -15 -8 Z"
          fill="#1e1b4b" stroke="#312e81" stroke-width="1"/>
    <!-- 思考线条 -->
    <path d="M -8 -5 Q 0 -8 8 -5" stroke="#312e81" stroke-width="1.5" fill="none"/>
    <path d="M -6 0 Q 0 -2 6 0" stroke="#312e81" stroke-width="1.5" fill="none"/>
    <path d="M -4 5 Q 0 3 4 5" stroke="#312e81" stroke-width="1.5" fill="none"/>
  </g>

  <!-- 主内容区域 -->
  <rect x="24" y="200" width="352" height="300" fill="url(#philoContentBg)" rx="20" filter="url(#shadow)"/>

  <!-- 顶部装饰线 -->
  <rect x="40" y="220" width="100" height="3" fill="#1e1b4b" rx="1.5"/>

  <!-- 哲学内容 -->
  ${_generateModernTextLines(lines, 200, 260, 16, '#1e293b', 1.5, verticalCenter: true, areaHeight: 300)}

  <!-- 底部思考者信息 -->
  <rect x="24" y="520" width="352" height="60" fill="#ffffff" fill-opacity="0.1" rx="20"/>

  <!-- 作者信息 -->
  ${author != null ? '<text x="200" y="545" text-anchor="middle" fill="#ffffff" font-family="system-ui, -apple-system, sans-serif" font-size="13" font-weight="500" font-style="italic">思考者：$author</text>' : ''}

  <!-- 底部信息重写 -->
  ${_buildMetadataTextBlock(metaLines, centerX: 200, startY: 535, lineHeight: 15, color: '#ffffff')}

  <!-- 装饰性思考点 -->
  <circle cx="50" cy="550" r="2" fill="#ffffff" fill-opacity="0.6"/>
  <circle cx="60" cy="545" r="1.5" fill="#ffffff" fill-opacity="0.4"/>
  <circle cx="68" cy="542" r="1" fill="#ffffff" fill-opacity="0.3"/>
</svg>
''';
  }

  /// 现代化简约卡片模板（新增）
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
    final displayContent = _processDisplayContent(content, maxLength: 160);
    final displayDate = date ??
        '${DateTime.now().year}年${DateTime.now().month}月${DateTime.now().day}日';
    final lines = _splitTextIntoAdaptiveLines(displayContent, 22, maxLines: 8);
    final metaLines = _buildMetadataLines(
      date: displayDate,
      location: location,
      weather: weather,
      temperature: temperature,
      source: source ?? author,
      appMark: '心迹 · ThoughtEcho',
    );

    return '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 600">
  <defs>
    <!-- 简约渐变 -->
    <linearGradient id="minimalistBg" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" style="stop-color:#f8fafc;stop-opacity:1" />
      <stop offset="100%" style="stop-color:#e2e8f0;stop-opacity:1" />
    </linearGradient>

    <!-- 强调色渐变 -->
    <linearGradient id="accentGradient" x1="0%" y1="0%" x2="100%" y2="0%">
      <stop offset="0%" style="stop-color:#3b82f6;stop-opacity:1" />
      <stop offset="100%" style="stop-color:#1d4ed8;stop-opacity:1" />
    </linearGradient>

    <!-- 阴影滤镜 -->
    <filter id="shadow" x="-20%" y="-20%" width="140%" height="140%">
      <feDropShadow dx="0" dy="4" stdDeviation="8" flood-color="#000000" flood-opacity="0.1"/>
    </filter>
  </defs>

  <!-- 主背景 -->
  <rect width="400" height="600" fill="url(#minimalistBg)" rx="24"/>

  <!-- 顶部强调条 -->
  <rect x="0" y="0" width="400" height="8" fill="url(#accentGradient)" rx="24"/>

  <!-- 左侧装饰线 -->
  <rect x="24" y="80" width="4" height="440" fill="#3b82f6" rx="2"/>

  <!-- 内容区域 -->
  <rect x="48" y="120" width="328" height="360" fill="#ffffff" rx="16" filter="url(#shadow)"/>

  <!-- 内容文字 -->
  ${_generateModernTextLines(lines, 212, 180, 16, '#1e293b', 1.5, verticalCenter: true, areaHeight: 240)}

  <!-- 底部信息 -->
  ${_buildMetadataTextBlock(metaLines, centerX: 212, startY: 430, lineHeight: 14, color: '#64748b')}
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
      case CardType.gradient:
        // 暂时使用知识模板，后续可添加专门的渐变模板
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
    }
  }

  /// 将文本分割成多行（改进：更准确的字符宽度计算）
  static List<String> _splitTextIntoAdaptiveLines(String text, int maxLineChars,
      {int maxLines = 8}) {
    final lines = <String>[];
    final words = text.split(' ');
    String currentLine = '';
    int currentWidth = 0;
    
    for (final word in words) {
      // 计算单词宽度：中文字符算2，英文数字算1
      int wordWidth = 0;
      for (int i = 0; i < word.length; i++) {
        wordWidth += _charWidth(word[i]);
      }
      
      // 如果是换行符，强制换行
      if (word.contains('\n')) {
        final parts = word.split('\n');
        for (int i = 0; i < parts.length; i++) {
          if (i > 0) {
            if (currentLine.isNotEmpty) {
              lines.add(currentLine.trim());
            }
            currentLine = '';
            currentWidth = 0;
          }
          if (parts[i].isNotEmpty) {
            currentLine += '${parts[i]} ';
            currentWidth += _stringWidth(parts[i]) + 1;
          }
        }
        continue;
      }
      
      // 如果添加这个单词会超出宽度，换行
      if (currentWidth + wordWidth + 1 > maxLineChars && currentLine.isNotEmpty) {
        lines.add(currentLine.trim());
        currentLine = '$word ';
        currentWidth = wordWidth + 1;
      } else {
        currentLine += '$word ';
        currentWidth += wordWidth + 1;
      }
      
      // 如果当前行太长（单个长单词），强制换行
      if (currentWidth > maxLineChars * 1.2) {
        lines.add(currentLine.trim());
        currentLine = '';
        currentWidth = 0;
      }
    }
    
    // 添加最后一行
    if (currentLine.trim().isNotEmpty) {
      lines.add(currentLine.trim());
    }
    
    // 如果行数超过限制，缩短每行字符数重试
    if (lines.length > maxLines && maxLineChars > 8) {
      final newMaxChars = (maxLineChars * 0.85).floor();
      return _splitTextIntoAdaptiveLines(text, newMaxChars, maxLines: maxLines);
    }
    
    // 如果仍然超过，截断
    if (lines.length > maxLines) {
      return lines.sublist(0, maxLines);
    }
    
    return lines;
  }
  
  /// 计算单个字符的显示宽度
  static int _charWidth(String char) {
    // 中文字符、全角符号等算2，英文数字算1
    final code = char.codeUnitAt(0);
    if (code > 0x4E00 && code < 0x9FFF) return 2; // CJK统一汉字
    if (code > 0x3000 && code < 0x303F) return 2; // CJK符号和标点
    if (code > 0xFF00 && code < 0xFFEF) return 2; // 全角ASCII
    return 1; // 其他字符（包括ASCII）
  }
  
  /// 计算字符串的总显示宽度
  static int _stringWidth(String str) {
    int width = 0;
    for (int i = 0; i < str.length; i++) {
      width += _charWidth(str[i]);
    }
    return width;
  }

  /// 生成现代化多行文本的SVG元素（改进：防止溢出）
  static String _generateModernTextLines(List<String> lines, double centerX,
      double startY, double fontSize, String color, double lineHeight,
      {bool verticalCenter = true, double areaHeight = 320}) {
    final buffer = StringBuffer();
    
    // 计算实际需要的高度
    double actualLineHeight = fontSize * lineHeight;
    double totalH = lines.length * actualLineHeight;
    
    // 如果内容太高，自动调整字体大小和行高
    double adjustedFontSize = fontSize;
    double adjustedLineHeight = lineHeight;
    if (totalH > areaHeight * 0.9) {
      // 留10%边距
      double scaleFactor = (areaHeight * 0.9) / totalH;
      adjustedFontSize = fontSize * scaleFactor;
      adjustedLineHeight = lineHeight * scaleFactor;
      actualLineHeight = adjustedFontSize * adjustedLineHeight;
      totalH = lines.length * actualLineHeight;
    }
    
    double offsetY = verticalCenter ? (areaHeight - totalH) / 2 : 0;
    
    for (int i = 0; i < lines.length; i++) {
      final y = startY + offsetY + (i * actualLineHeight);
      // 确保不超出区域
      if (y > startY + areaHeight) break;
      
      buffer.writeln(
          '<text x="$centerX" y="$y" text-anchor="middle" fill="$color" font-family="system-ui, -apple-system, sans-serif" font-size="${adjustedFontSize.toStringAsFixed(1)}" font-weight="400">${_escape(lines[i])}</text>');
    }
    return buffer.toString();
  }

  /// 智能处理显示内容，保持完整性同时满足UI约束
  static String _processDisplayContent(String content, {int maxLength = 200}) {
    // 如果内容不超过限制，直接返回
    if (content.length <= maxLength) {
      return content;
    }

    // 尝试在单词边界截断
    final truncated = content.substring(0, maxLength);
    final lastSpaceIndex = truncated.lastIndexOf(' ');

    // 如果找到空格，在该处截断；否则在字符限制处截断
    if (lastSpaceIndex > maxLength * 0.7) {
      // 确保不会截断太多
      return '${truncated.substring(0, lastSpaceIndex)}...';
    } else {
      return '$truncated...';
    }
  }
}
