import '../models/generated_card.dart';

/// 卡片模板常量
class CardTemplates {
  /// 现代化知识卡片模板（参考302.ai设计）
  static String knowledgeTemplate({
    required String content,
    String? author,
    String? date,
  }) {
    final displayContent = _processDisplayContent(content, maxLength: 180);
    final displayDate = date ??
        '${DateTime.now().year}年${DateTime.now().month}月${DateTime.now().day}日';
    final lines = _splitTextIntoAdaptiveLines(displayContent, 26, maxLines: 8);

    return '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 600">
  <defs>
    <!-- 现代渐变背景 -->
    <linearGradient id="modernKnowledgeBg" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" style="stop-color:#4f46e5;stop-opacity:1" />
      <stop offset="50%" style="stop-color:#7c3aed;stop-opacity:1" />
      <stop offset="100%" style="stop-color:#db2777;stop-opacity:1" />
    </linearGradient>

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
  <rect width="400" height="600" fill="url(#modernKnowledgeBg)" rx="24"/>

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
  <rect x="24" y="520" width="352" height="60" fill="#ffffff" fill-opacity="0.1" rx="20"/>

  <!-- 作者信息 -->
  ${author != null ? '<text x="200" y="545" text-anchor="middle" fill="#ffffff" font-family="system-ui, -apple-system, sans-serif" font-size="13" font-weight="500">$author</text>' : ''}

  <!-- 日期和品牌 -->
  <text x="200" y="565" text-anchor="middle" fill="#ffffff" fill-opacity="0.8" font-family="system-ui, -apple-system, sans-serif" font-size="11">
    $displayDate · 心迹 · ThoughtEcho
  </text>

  <!-- 右下角装饰点 -->
  <circle cx="360" cy="560" r="3" fill="#ffffff" fill-opacity="0.6"/>
</svg>
''';
  }

  /// 现代化引用卡片模板
  static String quoteTemplate({
    required String content,
    String? author,
    String? date,
  }) {
    final displayContent = _processDisplayContent(content, maxLength: 140);
    final displayDate = date ??
        '${DateTime.now().year}年${DateTime.now().month}月${DateTime.now().day}日';
    final lines = _splitTextIntoAdaptiveLines(displayContent, 22, maxLines: 8);

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
  <rect x="32" y="500" width="336" height="50" fill="#ffffff" fill-opacity="0.15" rx="20"/>
  <text x="200" y="530" text-anchor="middle" fill="#ffffff" font-family="system-ui, -apple-system, sans-serif" font-size="12" fill-opacity="0.9">
    $displayDate · 心迹 · ThoughtEcho
  </text>
</svg>
''';
  }

  /// 现代化哲学思考卡片模板
  static String philosophicalTemplate({
    required String content,
    String? author,
    String? date,
  }) {
    final displayContent = _processDisplayContent(content, maxLength: 200);
    final displayDate = date ??
        '${DateTime.now().year}年${DateTime.now().month}月${DateTime.now().day}日';
    final lines = _splitTextIntoAdaptiveLines(displayContent, 26, maxLines: 8);

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

  <!-- 日期信息 -->
  <text x="200" y="565" text-anchor="middle" fill="#ffffff" fill-opacity="0.8" font-family="system-ui, -apple-system, sans-serif" font-size="11">
    $displayDate · 心迹 · ThoughtEcho
  </text>

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
  }) {
    final displayContent = _processDisplayContent(content, maxLength: 160);
    final displayDate = date ??
        '${DateTime.now().year}年${DateTime.now().month}月${DateTime.now().day}日';
    final lines = _splitTextIntoAdaptiveLines(displayContent, 22, maxLines: 8);

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
  ${author != null ? '<text x="212" y="440" text-anchor="middle" fill="#64748b" font-family="system-ui, -apple-system, sans-serif" font-size="12" font-weight="500">$author</text>' : ''}

  <text x="212" y="460" text-anchor="middle" fill="#94a3b8" font-family="system-ui, -apple-system, sans-serif" font-size="10">
    $displayDate · 心迹 · ThoughtEcho
  </text>
</svg>
''';
  }

  /// 根据卡片类型获取对应模板
  static String getTemplateByType({
    required CardType type,
    required String content,
    String? author,
    String? date,
  }) {
    switch (type) {
      case CardType.knowledge:
        return knowledgeTemplate(content: content, author: author, date: date);
      case CardType.quote:
        return quoteTemplate(content: content, author: author, date: date);
      case CardType.philosophical:
        return philosophicalTemplate(
          content: content,
          author: author,
          date: date,
        );
      case CardType.minimalist:
        return minimalistTemplate(content: content, author: author, date: date);
      case CardType.gradient:
        // 暂时使用知识模板，后续可添加专门的渐变模板
        return knowledgeTemplate(content: content, author: author, date: date);
    }
  }

  /// 将文本分割成多行
  static List<String> _splitTextIntoAdaptiveLines(String text, int maxLineChars,
      {int maxLines = 8}) {
    final lines = <String>[];
    String current = '';
    int count = 0;
    for (int i = 0; i < text.length; i++) {
      // 英文和数字算1，汉字和罕见字符算2
      count += RegExp(r'[A-Za-z0-9]').hasMatch(text[i]) ? 1 : 2;
      current += text[i];
      if (count >= maxLineChars || text[i] == '\n') {
        lines.add(current.trim());
        current = '';
        count = 0;
      }
    }
    if (current.isNotEmpty) lines.add(current.trim());
    // 若行太多，缩小每行字数再重新切，防止溢出
    // 避免递归爆炸
    if (lines.length > maxLines && maxLineChars > 5) {
      int tighter = (maxLineChars * 0.8).floor();
      return _splitTextIntoAdaptiveLines(text, tighter, maxLines: maxLines);
    }
    if (lines.length > maxLines) {
      // 强行等分切块
      int chunk = (text.length / maxLines).ceil();
      List<String> result = [];
      for (int i = 0; i < text.length; i += chunk) {
        result.add(text.substring(
            i, (i + chunk > text.length) ? text.length : i + chunk));
      }
      return result.take(maxLines).toList();
    }
    return lines.take(maxLines).toList();
  }

  /// 生成现代化多行文本的SVG元素
  static String _generateModernTextLines(List<String> lines, double centerX,
      double startY, double fontSize, String color, double lineHeight,
      {bool verticalCenter = true, double areaHeight = 320}) {
    final buffer = StringBuffer();
    double totalH = lines.length * fontSize * lineHeight;
    double offsetY = verticalCenter ? (areaHeight - totalH) / 2 : 0;
    for (int i = 0; i < lines.length; i++) {
      final y = startY + offsetY + (i * (fontSize * lineHeight));
      buffer.writeln(
          '<text x="$centerX" y="$y" text-anchor="middle" fill="$color" font-family="system-ui, -apple-system, BlinkMacSystemFont, BlinkMacSystemFont, sans-serif" font-size="$fontSize" font-weight="400">${lines[i]}</text>');
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
