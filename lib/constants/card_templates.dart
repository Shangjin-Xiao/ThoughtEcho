import '../models/generated_card.dart';

/// 卡片模板常量
class CardTemplates {
  /// 知识卡片模板
  static String knowledgeTemplate({
    required String content,
    String? author,
    String? date,
  }) {
    final displayContent = content.length > 120 ? '${content.substring(0, 120)}...' : content;
    final displayDate = date ?? '${DateTime.now().year}年${DateTime.now().month}月${DateTime.now().day}日';
    
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
  <circle cx="350" cy="50" r="25" fill="rgba(255,255,255,0.1)"/>
  <circle cx="50" cy="50" r="15" fill="rgba(255,255,255,0.1)"/>
  
  <!-- 图标 -->
  <circle cx="200" cy="100" r="30" fill="rgba(255,255,255,0.2)"/>
  <text x="200" y="110" text-anchor="middle" fill="white" font-family="Arial, sans-serif" font-size="24">📚</text>
  
  <!-- 标题 -->
  <text x="200" y="160" text-anchor="middle" fill="white" font-family="Arial, sans-serif" font-size="18" font-weight="bold">
    知识笔记
  </text>
  
  <!-- 内容区域 -->
  <rect x="30" y="190" width="340" height="280" fill="rgba(255,255,255,0.95)" rx="15"/>
  
  <!-- 内容文字 -->
  <foreignObject x="50" y="210" width="300" height="240">
    <div xmlns="http://www.w3.org/1999/xhtml" style="font-family: Arial, sans-serif; font-size: 16px; line-height: 1.6; color: #333; padding: 20px; text-align: left;">
      ${displayContent.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;')}
    </div>
  </foreignObject>
  
  <!-- 底部信息 -->
  <text x="200" y="520" text-anchor="middle" fill="white" font-family="Arial, sans-serif" font-size="12">
    ${author != null ? '作者：$author' : ''}
  </text>
  <text x="200" y="550" text-anchor="middle" fill="rgba(255,255,255,0.8)" font-family="Arial, sans-serif" font-size="12">
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
    final displayContent = content.length > 100 ? '${content.substring(0, 100)}...' : content;
    final displayDate = date ?? '${DateTime.now().year}年${DateTime.now().month}月${DateTime.now().day}日';
    final displayAuthor = author ?? '佚名';
    
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
  <text x="80" y="120" fill="rgba(255,255,255,0.3)" font-family="Arial, sans-serif" font-size="60">"</text>
  <text x="320" y="480" fill="rgba(255,255,255,0.3)" font-family="Arial, sans-serif" font-size="60">"</text>
  
  <!-- 标题 -->
  <text x="200" y="180" text-anchor="middle" fill="white" font-family="Arial, sans-serif" font-size="18" font-weight="bold">
    名言警句
  </text>
  
  <!-- 内容区域 -->
  <rect x="40" y="220" width="320" height="200" fill="rgba(255,255,255,0.9)" rx="15"/>
  
  <!-- 引用内容 -->
  <foreignObject x="60" y="240" width="280" height="160">
    <div xmlns="http://www.w3.org/1999/xhtml" style="font-family: Arial, sans-serif; font-size: 18px; line-height: 1.5; color: #333; padding: 20px; text-align: center; font-style: italic;">
      ${displayContent.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;')}
    </div>
  </foreignObject>
  
  <!-- 作者信息 -->
  <text x="200" y="470" text-anchor="middle" fill="white" font-family="Arial, sans-serif" font-size="16" font-weight="bold">
    —— $displayAuthor
  </text>
  
  <!-- 底部信息 -->
  <text x="200" y="550" text-anchor="middle" fill="rgba(255,255,255,0.8)" font-family="Arial, sans-serif" font-size="12">
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
    final displayContent = content.length > 100 ? '${content.substring(0, 100)}...' : content;
    final displayDate = date ?? '${DateTime.now().year}年${DateTime.now().month}月${DateTime.now().day}日';
    
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
  <circle cx="100" cy="100" r="40" fill="rgba(255,255,255,0.05)"/>
  <circle cx="300" cy="500" r="30" fill="rgba(255,255,255,0.05)"/>
  
  <!-- 图标 -->
  <circle cx="200" cy="120" r="35" fill="rgba(255,255,255,0.1)"/>
  <text x="200" y="135" text-anchor="middle" fill="white" font-family="Arial, sans-serif" font-size="28">🤔</text>
  
  <!-- 标题 -->
  <text x="200" y="190" text-anchor="middle" fill="white" font-family="Arial, sans-serif" font-size="18" font-weight="bold">
    哲学思考
  </text>
  
  <!-- 内容区域 -->
  <rect x="30" y="230" width="340" height="250" fill="rgba(255,255,255,0.95)" rx="15"/>
  
  <!-- 思考内容 -->
  <foreignObject x="50" y="250" width="300" height="210">
    <div xmlns="http://www.w3.org/1999/xhtml" style="font-family: Arial, sans-serif; font-size: 16px; line-height: 1.6; color: #333; padding: 20px; text-align: center;">
      ${displayContent.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;')}
    </div>
  </foreignObject>
  
  <!-- 底部信息 -->
  <text x="200" y="530" text-anchor="middle" fill="white" font-family="Arial, sans-serif" font-size="12">
    ${author != null ? '思考者：$author' : ''}
  </text>
  <text x="200" y="560" text-anchor="middle" fill="rgba(255,255,255,0.8)" font-family="Arial, sans-serif" font-size="12">
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
        return philosophicalTemplate(content: content, author: author, date: date);
    }
  }
}
