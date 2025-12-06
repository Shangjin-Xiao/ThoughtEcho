import '../models/generated_card.dart';

/// 卡片模板常量 - 重构版
/// 核心设计原则：
/// 1. 文字渲染使用固定布局，避免复杂的自适应计算
/// 2. 统一使用 viewBox="0 0 400 600" 确保一致性
/// 3. 简化元数据展示，避免信息过载
class CardTemplates {
  // ============ 核心常量 ============
  static const double _viewBoxWidth = 400.0;
  static const double _viewBoxHeight = 600.0;
  static const int _maxContentCharsPerLine = 16; // 中文字符每行最大数量
  static const int _maxContentLines = 6; // 内容最大行数
  static const double _contentFontSize = 18.0;
  static const double _lineHeight = 1.7;

  /// 现代化知识卡片模板
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
    final textLines = _wrapText(
      content,
      _maxContentCharsPerLine,
      _maxContentLines,
    );
    final metaText = _buildMetaText(
      date: date,
      location: location,
      weather: weather,
      temperature: temperature,
    );
    final brandText = _buildBrandText(author: author, source: source);

    // 计算内容区域起始Y位置（居中显示）
    final contentHeight = textLines.length * _contentFontSize * _lineHeight;
    const contentAreaTop = 180.0;
    const contentAreaHeight = 280.0;
    final contentStartY = contentAreaTop +
        (contentAreaHeight - contentHeight) / 2 +
        _contentFontSize +
        20;

    return '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $_viewBoxWidth $_viewBoxHeight">
  <defs>
    <linearGradient id="knowledgeBg" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#4f46e5"/>
      <stop offset="50%" stop-color="#7c3aed"/>
      <stop offset="100%" stop-color="#db2777"/>
    </linearGradient>
    <linearGradient id="cardBg" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%" stop-color="#ffffff" stop-opacity="0.98"/>
      <stop offset="100%" stop-color="#f8fafc" stop-opacity="0.98"/>
    </linearGradient>
    <filter id="cardShadow" x="-10%" y="-10%" width="120%" height="120%">
      <feDropShadow dx="0" dy="4" stdDeviation="8" flood-color="#000000" flood-opacity="0.15"/>
    </filter>
  </defs>

  <!-- 背景 -->
  <rect width="$_viewBoxWidth" height="$_viewBoxHeight" fill="url(#knowledgeBg)" rx="24"/>
  
  <!-- 装饰元素 -->
  <circle cx="340" cy="80" r="40" fill="#ffffff" fill-opacity="0.1"/>
  <circle cx="60" cy="520" r="30" fill="#ffffff" fill-opacity="0.08"/>

  <!-- 顶部图标 -->
  <circle cx="200" cy="100" r="32" fill="#ffffff" fill-opacity="0.9"/>
  <g transform="translate(200, 100)">
    <rect x="-10" y="-7" width="20" height="14" fill="#4f46e5" rx="2"/>
    <line x1="-7" y1="-3" x2="7" y2="-3" stroke="#ffffff" stroke-width="1.5"/>
    <line x1="-7" y1="0" x2="5" y2="0" stroke="#ffffff" stroke-width="1.5"/>
    <line x1="-7" y1="3" x2="3" y2="3" stroke="#ffffff" stroke-width="1.5"/>
  </g>

  <!-- 内容卡片 -->
  <rect x="24" y="$contentAreaTop" width="352" height="$contentAreaHeight" fill="url(#cardBg)" rx="16" filter="url(#cardShadow)"/>
  <rect x="40" y="${contentAreaTop + 16}" width="48" height="3" fill="#4f46e5" rx="1.5"/>

  <!-- 内容文字 -->
${_renderTextLines(textLines, 200.0, contentStartY, _contentFontSize, '#1e293b')}

  <!-- 底部信息区 -->
  <rect x="24" y="480" width="352" height="96" fill="#000000" fill-opacity="0.2" rx="20"/>
  <text x="200" y="518" text-anchor="middle" fill="#ffffff" font-family="system-ui, -apple-system, sans-serif" font-size="11" fill-opacity="0.9">${_escape(metaText)}</text>
  <text x="200" y="545" text-anchor="middle" fill="#ffffff" font-family="system-ui, -apple-system, sans-serif" font-size="11" fill-opacity="0.7">${_escape(brandText)}</text>
</svg>
''';
  }

  /// 引用卡片模板
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
    final textLines = _wrapText(
      content,
      _maxContentCharsPerLine,
      _maxContentLines,
    );
    final metaText = _buildMetaText(
      date: date,
      location: location,
      weather: weather,
      temperature: temperature,
    );
    final authorDisplay = author ?? source ?? '';

    final contentHeight = textLines.length * _contentFontSize * _lineHeight;
    const contentAreaTop = 200.0;
    const contentAreaHeight = 240.0;
    final contentStartY = contentAreaTop +
        (contentAreaHeight - contentHeight) / 2 +
        _contentFontSize +
        20;

    return '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $_viewBoxWidth $_viewBoxHeight">
  <defs>
    <linearGradient id="quoteBg" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#f59e0b"/>
      <stop offset="50%" stop-color="#ef4444"/>
      <stop offset="100%" stop-color="#ec4899"/>
    </linearGradient>
    <linearGradient id="quoteCardBg" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%" stop-color="#ffffff" stop-opacity="0.98"/>
      <stop offset="100%" stop-color="#fef7ff" stop-opacity="0.98"/>
    </linearGradient>
    <filter id="quoteShadow" x="-10%" y="-10%" width="120%" height="120%">
      <feDropShadow dx="0" dy="4" stdDeviation="8" flood-color="#000000" flood-opacity="0.15"/>
    </filter>
  </defs>

  <!-- 背景 -->
  <rect width="$_viewBoxWidth" height="$_viewBoxHeight" fill="url(#quoteBg)" rx="24"/>
  
  <!-- 装饰引号 -->
  <text x="50" y="140" fill="#ffffff" fill-opacity="0.25" font-family="Georgia, serif" font-size="72" font-weight="bold">"</text>
  <text x="350" y="440" fill="#ffffff" fill-opacity="0.25" font-family="Georgia, serif" font-size="72" font-weight="bold">"</text>

  <!-- 内容卡片 -->
  <rect x="32" y="$contentAreaTop" width="336" height="$contentAreaHeight" fill="url(#quoteCardBg)" rx="16" filter="url(#quoteShadow)"/>
  <rect x="48" y="${contentAreaTop + 16}" width="60" height="3" fill="#f59e0b" rx="1.5"/>

  <!-- 引用内容 -->
${_renderTextLines(textLines, 200.0, contentStartY, _contentFontSize, '#374151')}

  <!-- 作者信息 -->
${authorDisplay.isNotEmpty ? '''
  <rect x="48" y="460" width="304" height="36" fill="#f59e0b" fill-opacity="0.15" rx="10"/>
  <text x="200" y="484" text-anchor="middle" fill="#92400e" font-family="system-ui, -apple-system, sans-serif" font-size="13" font-weight="500" font-style="italic">— ${_escape(authorDisplay)}</text>
''' : ''}

  <!-- 底部信息 -->
  <rect x="32" y="510" width="336" height="72" fill="#000000" fill-opacity="0.2" rx="18"/>
  <text x="200" y="542" text-anchor="middle" fill="#ffffff" font-family="system-ui, -apple-system, sans-serif" font-size="11" fill-opacity="0.85">${_escape(metaText)}</text>
  <text x="200" y="565" text-anchor="middle" fill="#ffffff" font-family="system-ui, -apple-system, sans-serif" font-size="10" fill-opacity="0.6">心迹 · ThoughtEcho</text>
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

  /// 将文本分割成多行（改进：更准确的字符宽度计算+强制截断）
  static List<String> _splitTextIntoAdaptiveLines(
    String text,
    int maxLineChars, {
    int maxLines = 8,
  }) {
    final lines = <String>[];
    // 先按换行符预分割
    final paragraphs = text.split('\n');

    for (final para in paragraphs) {
      if (para.trim().isEmpty) continue;

      final words = para.split(' ');
      String currentLine = '';
      int currentWidth = 0;

      for (final word in words) {
        // 计算单词宽度：中文字符算2,英文数字算1
        int wordWidth = _stringWidth(word);

        // 如果单词本身就超长,强制拆分
        if (wordWidth > maxLineChars) {
          if (currentLine.isNotEmpty) {
            lines.add(currentLine.trim());
            currentLine = '';
            currentWidth = 0;
          }
          // 将长单词按字符拆分
          for (int i = 0; i < word.length;) {
            String chunk = '';
            int chunkWidth = 0;
            while (i < word.length &&
                chunkWidth + _charWidth(word[i]) <= maxLineChars) {
              chunk += word[i];
              chunkWidth += _charWidth(word[i]);
              i++;
            }
            if (chunk.isNotEmpty) lines.add(chunk);
          }
          continue;
        }

        // 如果添加这个单词会超出宽度,换行
        if (currentWidth + wordWidth + (currentLine.isEmpty ? 0 : 1) >
            maxLineChars) {
          if (currentLine.isNotEmpty) {
            lines.add(currentLine.trim());
          }
          currentLine = word;
          currentWidth = wordWidth;
        } else {
          if (currentLine.isNotEmpty) {
            currentLine += ' $word';
            currentWidth += wordWidth + 1;
          } else {
            currentLine = word;
            currentWidth = wordWidth;
          }
        }
      }

      // 添加段落最后一行
      if (currentLine.trim().isNotEmpty) {
        lines.add(currentLine.trim());
      }
    }

    // 如果行数超过限制,直接截断并添加省略号
    if (lines.length > maxLines) {
      final truncated = lines.sublist(0, maxLines);
      if (truncated.isNotEmpty) {
        truncated[truncated.length - 1] = '${truncated.last}...';
      }
      return truncated;
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
  static String _generateModernTextLines(
    List<String> lines,
    double centerX,
    double startY,
    double fontSize,
    String color,
    double lineHeight, {
    bool verticalCenter = true,
    double areaHeight = 320,
  }) {
    final buffer = StringBuffer();

    // 计算实际需要的高度
    double actualLineHeight = fontSize * lineHeight;
    double totalH = lines.length * actualLineHeight;

    // 如果内容太高,自动调整字体大小和行高（留15%安全边距）
    double adjustedFontSize = fontSize;
    double adjustedLineHeight = lineHeight;
    if (totalH > areaHeight * 0.85) {
      double scaleFactor = (areaHeight * 0.85) / totalH;
      adjustedFontSize = fontSize * scaleFactor;
      // 最小字体12px,避免过小难以辨认
      if (adjustedFontSize < 12) adjustedFontSize = 12;
      adjustedLineHeight = lineHeight * scaleFactor;
      actualLineHeight = adjustedFontSize * adjustedLineHeight;
      totalH = lines.length * actualLineHeight;
    }

    double offsetY = verticalCenter ? (areaHeight - totalH) / 2 : 0;
    // 限制offsetY最小为上边距10px
    if (offsetY < 10) offsetY = 10;

    for (int i = 0; i < lines.length; i++) {
      final y = startY + offsetY + (i * actualLineHeight);
      // 确保不超出区域底部（留10px下边距）
      if (y > startY + areaHeight - 10) break;

      buffer.writeln(
        '<text x="$centerX" y="$y" text-anchor="middle" fill="$color" font-family="system-ui, -apple-system, sans-serif" font-size="${adjustedFontSize.toStringAsFixed(1)}" font-weight="400">${_escape(lines[i])}</text>',
      );
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

  // ============ 新增工具方法（重构版） ============

  /// 简化的文字换行 - 按字符数量直接截断
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
      int lastSpace = segment.lastIndexOf(' ');

      if (lastSpace > maxCharsPerLine * 0.5) {
        lines.add(segment.substring(0, lastSpace).trim());
        currentIndex += lastSpace + 1;
      } else {
        lines.add(segment.trim());
        currentIndex = endIndex;
      }
    }

    if (currentIndex < cleanText.length && lines.isNotEmpty) {
      String lastLine = lines.last;
      if (lastLine.length > 3) {
        lines[lines.length - 1] =
            '${lastLine.substring(0, lastLine.length - 3)}...';
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
    String color,
  ) {
    final buffer = StringBuffer();
    const lineHeightRatio = 1.7;
    final lineSpacing = fontSize * lineHeightRatio;

    for (int i = 0; i < lines.length; i++) {
      final y = startY + i * lineSpacing;
      buffer.writeln(
        '  <text x="$centerX" y="${y.toStringAsFixed(1)}" text-anchor="middle" fill="$color" font-family="system-ui, -apple-system, sans-serif" font-size="${fontSize.toStringAsFixed(0)}" font-weight="400">${_escape(lines[i])}</text>',
      );
    }

    return buffer.toString();
  }

  /// 构建元数据文本（日期、位置、天气）
  static String _buildMetaText({
    String? date,
    String? location,
    String? weather,
    String? temperature,
  }) {
    final parts = <String>[];

    if (date != null && date.isNotEmpty) {
      parts.add(date);
    }

    if (location != null && location.isNotEmpty) {
      final shortLocation = location.split(',').first.trim();
      if (shortLocation.isNotEmpty) {
        parts.add(shortLocation);
      }
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

  /// 构建品牌文本（作者、来源、心迹标识）
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

  /// 构建元数据行列表（兼容旧代码）
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

  /// 构建元数据文本块（兼容旧代码）
  static String _buildMetadataTextBlock(
    List<String> lines, {
    required double centerX,
    required double startY,
    required double lineHeight,
    required String color,
  }) {
    final buf = StringBuffer();
    for (int i = 0; i < lines.length; i++) {
      final y = startY + i * lineHeight;
      final opacity = i == 0 ? 0.9 : 0.75;
      buf.writeln(
        '<text x="$centerX" y="$y" text-anchor="middle" fill="$color" font-family="system-ui, -apple-system, sans-serif" font-size="11" fill-opacity="$opacity">${_escape(lines[i])}</text>',
      );
    }
    return buf.toString();
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
