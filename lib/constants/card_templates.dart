import '../models/generated_card.dart';

/// 卡片模板常量
class CardTemplates {
  /// 知识卡片模板
  static String knowledgeTemplate({
    required String content,
    String? author,
    String? date,
  }) {
    final displayContent =
        content.length > 80 ? '${content.substring(0, 80)}...' : content;
    final displayDate =
        date ??
        '${DateTime.now().year}年${DateTime.now().month}月${DateTime.now().day}日';

    // 将长文本分行处理
    final lines = _splitTextIntoLines(displayContent, 20);

    return '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 600">
  <defs>
    <linearGradient id="knowledgeBg" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" style="stop-color:#667eea;stop-opacity:1" />
      <stop offset="100%" style="stop-color:#764ba2;stop-opacity:1" />
    </linearGradient>
  </defs>

  <!-- 背景 -->
  <rect width="400" height="600" fill="url(#knowledgeBg)" rx="20"/>

  <!-- 顶部装饰 -->
  <circle cx="350" cy="50" r="25" fill="#FFFFFF" fill-opacity="0.1"/>
  <circle cx="50" cy="50" r="15" fill="#FFFFFF" fill-opacity="0.1"/>

  <!-- 图标背景 -->
  <circle cx="200" cy="100" r="30" fill="#FFFFFF" fill-opacity="0.2"/>
  <rect x="185" y="85" width="30" height="30" fill="white" rx="3"/>
  <rect x="188" y="88" width="24" height="2" fill="#667eea"/>
  <rect x="188" y="92" width="20" height="2" fill="#667eea"/>
  <rect x="188" y="96" width="22" height="2" fill="#667eea"/>
  <rect x="188" y="100" width="18" height="2" fill="#667eea"/>
  <rect x="188" y="104" width="24" height="2" fill="#667eea"/>

  <!-- 标题 -->
  <text x="200" y="160" text-anchor="middle" fill="white" font-family="Arial, sans-serif" font-size="18" font-weight="bold">
    知识笔记
  </text>

  <!-- 内容区域 -->
  <rect x="30" y="190" width="340" height="280" fill="#FFFFFF" fill-opacity="0.95" rx="15"/>

  <!-- 内容文字 - 使用text元素替代foreignObject -->
  ${_generateTextLines(lines, 200, 230, 16, '#333333')}

  <!-- 底部信息 -->
  <text x="200" y="520" text-anchor="middle" fill="white" font-family="Arial, sans-serif" font-size="12">
    ${author != null ? '作者：$author' : ''}
  </text>
  <text x="200" y="550" text-anchor="middle" fill="#FFFFFF" fill-opacity="0.8" font-family="Arial, sans-serif" font-size="12">
    $displayDate · ThoughtEcho
  </text>
</svg>
''';
  }

  /// 引用卡片模板
  static String quoteTemplate({
    required String content,
    String? author,
    String? date,
  }) {
    final displayContent =
        content.length > 60 ? '${content.substring(0, 60)}...' : content;
    final displayDate =
        date ??
        '${DateTime.now().year}年${DateTime.now().month}月${DateTime.now().day}日';
    final displayAuthor = author ?? '佚名';

    // 将引用内容分行
    final lines = _splitTextIntoLines(displayContent, 18);

    return '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 600">
  <defs>
    <linearGradient id="quoteBg" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" style="stop-color:#ffecd2;stop-opacity:1" />
      <stop offset="100%" style="stop-color:#fcb69f;stop-opacity:1" />
    </linearGradient>
  </defs>

  <!-- 背景 -->
  <rect width="400" height="600" fill="url(#quoteBg)" rx="20"/>

  <!-- 装饰引号 -->
  <text x="80" y="120" fill="#FFFFFF" fill-opacity="0.3" font-family="Arial, sans-serif" font-size="60">"</text>
  <text x="320" y="480" fill="#FFFFFF" fill-opacity="0.3" font-family="Arial, sans-serif" font-size="60">"</text>

  <!-- 标题 -->
  <text x="200" y="180" text-anchor="middle" fill="white" font-family="Arial, sans-serif" font-size="18" font-weight="bold">
    名言警句
  </text>

  <!-- 内容区域 -->
  <rect x="40" y="220" width="320" height="200" fill="#FFFFFF" fill-opacity="0.9" rx="15"/>

  <!-- 引用内容 - 使用text元素 -->
  ${_generateTextLines(lines, 200, 260, 16, '#333333')}

  <!-- 作者信息 -->
  <text x="200" y="470" text-anchor="middle" fill="white" font-family="Arial, sans-serif" font-size="16" font-weight="bold">
    —— $displayAuthor
  </text>

  <!-- 底部信息 -->
  <text x="200" y="550" text-anchor="middle" fill="#FFFFFF" fill-opacity="0.8" font-family="Arial, sans-serif" font-size="12">
    $displayDate · ThoughtEcho
  </text>
</svg>
''';
  }

  /// 哲学思考卡片模板
  static String philosophicalTemplate({
    required String content,
    String? author,
    String? date,
  }) {
    final displayContent =
        content.length > 80 ? '${content.substring(0, 80)}...' : content;
    final displayDate =
        date ??
        '${DateTime.now().year}年${DateTime.now().month}月${DateTime.now().day}日';

    // 将思考内容分行
    final lines = _splitTextIntoLines(displayContent, 20);

    return '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 600">
  <defs>
    <linearGradient id="philoBg" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" style="stop-color:#2c3e50;stop-opacity:1" />
      <stop offset="100%" style="stop-color:#34495e;stop-opacity:1" />
    </linearGradient>
  </defs>

  <!-- 背景 -->
  <rect width="400" height="600" fill="url(#philoBg)" rx="20"/>

  <!-- 装饰元素 -->
  <circle cx="100" cy="100" r="40" fill="#FFFFFF" fill-opacity="0.05"/>
  <circle cx="300" cy="500" r="30" fill="#FFFFFF" fill-opacity="0.05"/>

  <!-- 图标背景 -->
  <circle cx="200" cy="120" r="35" fill="#FFFFFF" fill-opacity="0.1"/>
  <!-- 思考图标 - 用简单形状替代emoji -->
  <circle cx="190" cy="110" r="8" fill="white"/>
  <circle cx="210" cy="110" r="8" fill="white"/>
  <path d="M 185 125 Q 200 135 215 125" stroke="white" stroke-width="3" fill="none"/>
  <circle cx="200" cy="140" r="3" fill="white"/>
  <circle cx="205" cy="150" r="2" fill="white"/>
  <circle cx="210" cy="158" r="1" fill="white"/>

  <!-- 标题 -->
  <text x="200" y="190" text-anchor="middle" fill="white" font-family="Arial, sans-serif" font-size="18" font-weight="bold">
    哲学思考
  </text>

  <!-- 内容区域 -->
  <rect x="30" y="230" width="340" height="250" fill="#FFFFFF" fill-opacity="0.95" rx="15"/>

  <!-- 思考内容 - 使用text元素 -->
  ${_generateTextLines(lines, 200, 270, 16, '#333333')}

  <!-- 底部信息 -->
  <text x="200" y="530" text-anchor="middle" fill="white" font-family="Arial, sans-serif" font-size="12">
    ${author != null ? '思考者：$author' : ''}
  </text>
  <text x="200" y="560" text-anchor="middle" fill="#FFFFFF" fill-opacity="0.8" font-family="Arial, sans-serif" font-size="12">
    $displayDate · ThoughtEcho
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
    }
  }

  /// 将文本分割成多行
  static List<String> _splitTextIntoLines(String text, int maxCharsPerLine) {
    final lines = <String>[];
    final words = text.split('');
    String currentLine = '';

    for (final char in words) {
      if (currentLine.length + 1 <= maxCharsPerLine) {
        currentLine += char;
      } else {
        if (currentLine.isNotEmpty) {
          lines.add(currentLine);
          currentLine = char;
        }
      }
    }

    if (currentLine.isNotEmpty) {
      lines.add(currentLine);
    }

    return lines.take(8).toList(); // 最多8行
  }

  /// 生成多行文本的SVG元素
  static String _generateTextLines(
    List<String> lines,
    double centerX,
    double startY,
    double fontSize,
    String color,
  ) {
    final buffer = StringBuffer();

    for (int i = 0; i < lines.length; i++) {
      final y = startY + (i * (fontSize + 4));
      buffer.writeln(
        '<text x="$centerX" y="$y" text-anchor="middle" fill="$color" font-family="Arial, sans-serif" font-size="$fontSize">${lines[i]}</text>',
      );
    }

    return buffer.toString();
  }
}
