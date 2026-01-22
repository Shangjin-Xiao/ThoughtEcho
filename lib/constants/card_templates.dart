import 'dart:math' as math;

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
  static const double _contentFontSize = 18.0;
  static const double _lineHeight = 1.6;

  /// 现代化知识卡片模板
  /// 特点：极光渐变背景，磨砂玻璃质感，高对比度文字
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
    const contentAreaTop = 160.0;
    const contentAreaHeight = 300.0;
    final maxLines = _calculateMaxLines(contentAreaHeight);
    final textLines = _wrapText(content, 18, maxLines);
    final metaText = _buildMetaText(
        date: date,
        location: location,
        weather: weather,
        temperature: temperature);
    final brandText = _buildBrandText(author: author, source: source);

    final contentHeight = textLines.length * _contentFontSize * _lineHeight;
    final contentStartY = contentAreaTop +
        (contentAreaHeight - contentHeight) / 2 +
        _contentFontSize;

    return '''
 <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $_viewBoxWidth $_viewBoxHeight" preserveAspectRatio="xMidYMid meet">
   <defs>
     <filter id="auroraBlur" x="-50%" y="-50%" width="200%" height="200%">
       <feGaussianBlur stdDeviation="40"/>
     </filter>
     <linearGradient id="glassStroke" x1="0%" y1="0%" x2="100%" y2="100%">
       <stop offset="0%" stop-color="#ffffff" stop-opacity="0.4"/>
       <stop offset="100%" stop-color="#ffffff" stop-opacity="0.05"/>
     </linearGradient>
   </defs>

   <!-- 深色背景 -->
   <rect width="$_viewBoxWidth" height="$_viewBoxHeight" fill="#020617" rx="24"/>
  
   <!-- 极光光晕 -->
   <circle cx="50" cy="100" r="150" fill="#7c3aed" fill-opacity="0.4" filter="url(#auroraBlur)"/>
   <circle cx="350" cy="500" r="180" fill="#0891b2" fill-opacity="0.4" filter="url(#auroraBlur)"/>
   <circle cx="200" cy="300" r="120" fill="#db2777" fill-opacity="0.25" filter="url(#auroraBlur)"/>

   <!-- 玻璃卡片容器 -->
   <rect x="24" y="24" width="352" height="552" rx="20" fill="#ffffff" fill-opacity="0.03" stroke="url(#glassStroke)" stroke-width="1.5"/>

   <!-- 装饰元素 -->
   <circle cx="340" cy="60" r="40" fill="#ffffff" fill-opacity="0.03"/>
   <path d="M60 540 L80 520 L100 540" fill="none" stroke="#ffffff" stroke-opacity="0.2" stroke-width="2"/>
   <rect x="175" y="40" width="50" height="3" rx="1.5" fill="#ffffff" fill-opacity="0.2"/>

   <!-- 内容文字 -->
 ${_renderTextLines(textLines, 200.0, contentStartY, _contentFontSize, '#f1f5f9', fontWeight: '500', fontFamily: 'PingFang SC, system-ui, sans-serif')}

   <!-- 底部信息 -->
   <rect x="150" y="510" width="100" height="1" fill="#ffffff" fill-opacity="0.15"/>
   <text x="200" y="535" text-anchor="middle" fill="#94a3b8" font-family="PingFang SC, sans-serif" font-size="11" letter-spacing="0.5">${_escape(metaText)}</text>
   <text x="200" y="555" text-anchor="middle" fill="#64748b" font-family="PingFang SC, sans-serif" font-size="10">${_escape(brandText)}</text>
 </svg>
 ''';
  }

  /// 正念/自然模板
  /// 特点：有机流体形状，大地色系，纸张质感
  static String mindfulTemplate({
    required String content,
    String? author,
    String? date,
    String? source,
    String? location,
    String? weather,
    String? temperature,
    String? dayPeriod,
  }) {
    const contentAreaTop = 160.0;
    const contentAreaHeight = 300.0;
    final maxLines = _calculateMaxLines(contentAreaHeight);
    final textLines = _wrapText(content, 18, maxLines);
    final metaText = _buildMetaText(
        date: date,
        location: location,
        weather: weather,
        temperature: temperature);
    final brandText = _buildBrandText(author: author, source: source);

    final contentHeight = textLines.length * _contentFontSize * _lineHeight;
    final contentStartY = contentAreaTop +
        (contentAreaHeight - contentHeight) / 2 +
        _contentFontSize;

    return '''
 <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $_viewBoxWidth $_viewBoxHeight" preserveAspectRatio="xMidYMid meet">
   <defs>
     <filter id="paperNoise">
       <feTurbulence type="fractalNoise" baseFrequency="0.6" numOctaves="3" stitchTiles="stitch"/>
       <feColorMatrix type="matrix" values="0 0 0 0 0.9  0 0 0 0 0.88  0 0 0 0 0.83  0 0 0 1 0"/>
       <feBlend mode="multiply" in2="SourceGraphic"/>
     </filter>
     <linearGradient id="warmGrad" x1="0%" y1="0%" x2="0%" y2="100%">
       <stop offset="0%" stop-color="#fffbeb"/>
       <stop offset="100%" stop-color="#fef3c7"/>
     </linearGradient>
   </defs>

   <!-- 背景 -->
   <rect width="$_viewBoxWidth" height="$_viewBoxHeight" fill="url(#warmGrad)" rx="24"/>
   
   <!-- 有机形状 -->
   <path d="M-50 0 Q100 150 250 50 T450 0 V300 H-50 Z" fill="#dcfce7" fill-opacity="0.7"/>
   <path d="M-50 600 Q150 450 300 550 T450 600 V600 H-50 Z" fill="#ffedd5" fill-opacity="0.8"/>
   
   <!-- 质感叠层 -->
   <rect width="$_viewBoxWidth" height="$_viewBoxHeight" filter="url(#paperNoise)" opacity="0.4" rx="24"/>

   <!-- 内容区域 -->
   <rect x="40" y="140" width="320" height="340" rx="16" fill="#ffffff" fill-opacity="0.6"/>

   <!-- 内容文字 -->
 ${_renderTextLines(textLines, 200.0, contentStartY, _contentFontSize, '#431407', fontFamily: 'Songti SC, Georgia, serif', fontWeight: '500')}

   <!-- 底部信息 -->
   <circle cx="200" cy="510" r="3" fill="#a8a29e"/>
   <text x="200" y="535" text-anchor="middle" fill="#78350f" font-family="Songti SC, serif" font-size="11">${_escape(metaText)}</text>
   <text x="200" y="555" text-anchor="middle" fill="#92400e" font-family="Songti SC, serif" font-size="10">${_escape(brandText)}</text>
 </svg>
 ''';
  }

  /// 霓虹赛博模板
  /// 特点：暗黑网格，霓虹线条，等宽字体
  static String neonCyberTemplate({
    required String content,
    String? author,
    String? date,
    String? source,
    String? location,
    String? weather,
    String? temperature,
    String? dayPeriod,
  }) {
    const contentAreaTop = 140.0;
    const contentAreaHeight = 340.0;
    final maxLines = _calculateMaxLines(contentAreaHeight);
    final textLines = _wrapText(content, 20, maxLines);
    final metaText = _buildMetaText(
        date: date,
        location: location,
        weather: weather,
        temperature: temperature);
    final brandText = _buildBrandText(author: author, source: source);

    final contentHeight = textLines.length * _contentFontSize * _lineHeight;
    final contentStartY = contentAreaTop +
        (contentAreaHeight - contentHeight) / 2 +
        _contentFontSize;

    final buffer = StringBuffer();
    final lineSpacing = _contentFontSize * _lineHeight;
    for (int i = 0; i < textLines.length; i++) {
      final y = contentStartY + i * lineSpacing;
      buffer.writeln(
          '<text x="50" y="${y.toStringAsFixed(1)}" text-anchor="start" fill="#22d3ee" font-family="Courier New, monospace" font-size="16" font-weight="bold">${_escape(textLines[i])}</text>');
    }
    final renderedText = buffer.toString();

    return '''
 <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $_viewBoxWidth $_viewBoxHeight" preserveAspectRatio="xMidYMid meet">
   <defs>
     <pattern id="cyberGrid" width="40" height="40" patternUnits="userSpaceOnUse">
       <rect width="40" height="40" fill="none" stroke="#1e293b" stroke-width="1"/>
       <rect width="2" height="2" fill="#334155" x="0" y="0"/>
     </pattern>
     <linearGradient id="scanline" x1="0" y1="0" x2="0" y2="100%">
       <stop offset="0%" stop-color="#000" stop-opacity="0"/>
       <stop offset="50%" stop-color="#000" stop-opacity="0.3"/>
       <stop offset="100%" stop-color="#000" stop-opacity="0"/>
     </linearGradient>
   </defs>

   <!-- 背景 -->
   <rect width="$_viewBoxWidth" height="$_viewBoxHeight" fill="#020617" rx="24"/>
   <rect width="$_viewBoxWidth" height="$_viewBoxHeight" fill="url(#cyberGrid)" rx="24"/>

   <!-- 霓虹装饰 -->
   <rect x="0" y="60" width="8" height="60" fill="#22d3ee"/>
   <rect x="392" y="480" width="8" height="60" fill="#d946ef"/>
   <rect x="40" y="110" width="320" height="1" fill="#22d3ee" fill-opacity="0.5"/>
   <rect x="40" y="490" width="320" height="1" fill="#d946ef" fill-opacity="0.5"/>

   <!-- 内容文字 -->
   $renderedText

   <!-- 底部信息 -->
   <text x="200" y="530" text-anchor="middle" fill="#94a3b8" font-family="Courier New, monospace" font-size="10">SYS.LOG: ${_escape(metaText)}</text>
   <text x="200" y="550" text-anchor="middle" fill="#64748b" font-family="Courier New, monospace" font-size="10">// ${_escape(brandText)}</text>
   
   <!-- 扫描线层 -->
   <rect width="$_viewBoxWidth" height="$_viewBoxHeight" fill="url(#scanline)" rx="24" pointer-events="none"/>
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
    const contentAreaTop = 150.0;
    const contentAreaHeight = 320.0;
    final maxLines = _calculateMaxLines(contentAreaHeight);
    final textLines = _wrapText(content, 18, maxLines);
    final metaText = _buildMetaText(
        date: date,
        location: location,
        weather: weather,
        temperature: temperature);
    final authorDisplay = author ?? source ?? '';

    final contentHeight = textLines.length * _contentFontSize * _lineHeight;
    final contentStartY = contentAreaTop +
        (contentAreaHeight - contentHeight) / 2 +
        _contentFontSize;

    return '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $_viewBoxWidth $_viewBoxHeight" preserveAspectRatio="xMidYMid meet">
  <defs>
    <linearGradient id="quoteBg" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#ff9a9e"/>
      <stop offset="100%" stop-color="#fecfef"/>
    </linearGradient>
    <filter id="quoteShadow" x="-20%" y="-20%" width="140%" height="140%">
      <feDropShadow dx="0" dy="6" stdDeviation="10" flood-color="#9d174d" flood-opacity="0.2"/>
    </filter>
  </defs>

  <!-- 背景 -->
  <rect width="$_viewBoxWidth" height="$_viewBoxHeight" fill="url(#quoteBg)" rx="24"/>
  
  <!-- 装饰引号 -->
  <text x="50" y="140" fill="#ffffff" fill-opacity="0.6" font-family="Georgia, serif" font-size="140" font-weight="bold">“</text>
  <text x="350" y="460" text-anchor="end" fill="#ffffff" fill-opacity="0.6" font-family="Georgia, serif" font-size="140" font-weight="bold">”</text>

  <!-- 内容卡片 -->
  <rect x="40" y="$contentAreaTop" width="320" height="$contentAreaHeight" fill="#ffffff" fill-opacity="0.95" rx="4" filter="url(#quoteShadow)"/>

  <!-- 引用内容 -->
${_renderTextLines(textLines, 200.0, contentStartY, _contentFontSize, '#881337', fontFamily: 'Songti SC, SimSun, Georgia, serif', fontStyle: 'italic', fontWeight: '500')}

  <!-- 作者信息 -->
${authorDisplay.isNotEmpty ? '''
  <line x1="150" y1="490" x2="250" y2="490" stroke="#be185d" stroke-width="2"/>
  <text x="200" y="515" text-anchor="middle" fill="#9d174d" font-family="Songti SC, SimSun, Georgia, serif" font-size="15" font-weight="bold">${_escape(authorDisplay)}</text>
''' : ''}

  <!-- 底部信息 -->
  <text x="200" y="550" text-anchor="middle" fill="#be185d" font-family="PingFang SC, Microsoft YaHei, system-ui, sans-serif" font-size="10" fill-opacity="0.8">${_escape(metaText)}</text>
  <text x="200" y="565" text-anchor="middle" fill="#be185d" font-family="PingFang SC, Microsoft YaHei, system-ui, sans-serif" font-size="9" fill-opacity="0.6">心迹 · ThoughtEcho</text>
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
    const contentAreaTop = 180.0;
    const contentAreaHeight = 280.0;
    final maxLines = _calculateMaxLines(contentAreaHeight);
    final textLines = _wrapText(content, 18, maxLines);
    final metaText = _buildMetaText(
        date: date,
        location: location,
        weather: weather,
        temperature: temperature);
    final brandText = _buildBrandText(author: author, source: source);

    final contentHeight = textLines.length * _contentFontSize * _lineHeight;
    final contentStartY = contentAreaTop +
        (contentAreaHeight - contentHeight) / 2 +
        _contentFontSize;

    return '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $_viewBoxWidth $_viewBoxHeight" preserveAspectRatio="xMidYMid meet">
  <defs>
    <linearGradient id="philoBg" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%" stop-color="#0f172a"/>
      <stop offset="100%" stop-color="#1e1b4b"/>
    </linearGradient>
    <radialGradient id="starGlow" cx="50%" cy="50%" r="50%">
      <stop offset="0%" stop-color="#ffffff" stop-opacity="0.6"/>
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
  <circle cx="200" cy="300" r="150" fill="url(#starGlow)" fill-opacity="0.08"/>

  <!-- 思考图标 -->
  <g transform="translate(200, 100)">
    <circle cx="0" cy="0" r="40" fill="#ffffff" fill-opacity="0.05"/>
    <path d="M-15 -10 C-20 -15 -10 -22 0 -18 C10 -22 20 -15 15 -10 C22 -6 22 6 15 10 C20 15 10 22 0 18 C-10 22 -20 15 -15 10 C-22 6 -22 -6 -15 -10 Z" fill="none" stroke="#a5b4fc" stroke-width="1.5"/>
    <circle cx="0" cy="0" r="5" fill="#a5b4fc"/>
  </g>

  <!-- 内容区域 -->
  <rect x="32" y="$contentAreaTop" width="336" height="$contentAreaHeight" fill="#ffffff" fill-opacity="0.05" rx="16" stroke="#ffffff" stroke-width="0.5" stroke-opacity="0.1"/>

  <!-- 内容文字 -->
${_renderTextLines(textLines, 200.0, contentStartY, _contentFontSize, '#f8fafc', fontWeight: '500')}

  <!-- 底部信息 -->
  <line x1="120" y1="510" x2="280" y2="510" stroke="#ffffff" stroke-opacity="0.15"/>
  <text x="200" y="540" text-anchor="middle" fill="#94a3b8" font-family="system-ui, sans-serif" font-size="11">${_escape(metaText)}</text>
  <text x="200" y="560" text-anchor="middle" fill="#64748b" font-family="system-ui, sans-serif" font-size="10">${_escape(brandText)}</text>
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
    const contentAreaTop = 160.0;
    const contentAreaHeight = 300.0;
    final maxLines = _calculateMaxLines(contentAreaHeight);
    final textLines = _wrapText(content, 16, maxLines);
    final metaText = _buildMetaText(
        date: date,
        location: location,
        weather: weather,
        temperature: temperature);
    final brandText = _buildBrandText(author: author, source: source);

    final contentHeight = textLines.length * _contentFontSize * _lineHeight;
    final contentStartY = contentAreaTop +
        (contentAreaHeight - contentHeight) / 2 +
        _contentFontSize;

    return '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $_viewBoxWidth $_viewBoxHeight" preserveAspectRatio="xMidYMid meet">
  <defs>
    <filter id="minimalShadow" x="-10%" y="-10%" width="120%" height="120%">
      <feDropShadow dx="0" dy="4" stdDeviation="12" flood-color="#000000" flood-opacity="0.08"/>
    </filter>
  </defs>

  <!-- 背景 -->
  <rect width="$_viewBoxWidth" height="$_viewBoxHeight" fill="#f1f5f9" rx="24"/>
  
  <!-- 内容卡片 -->
  <rect x="40" y="60" width="320" height="480" fill="#ffffff" rx="2" filter="url(#minimalShadow)"/>
  
  <!-- 装饰线 -->
  <rect x="180" y="100" width="40" height="3" fill="#1e293b"/>

  <!-- 内容文字 -->
${_renderTextLines(textLines, 200.0, contentStartY, _contentFontSize, '#0f172a', fontWeight: '400', fontFamily: 'Helvetica Neue, Arial, sans-serif')}

  <!-- 底部信息 -->
  <text x="200" y="480" text-anchor="middle" fill="#94a3b8" font-family="Helvetica Neue, Arial, sans-serif" font-size="10" letter-spacing="2">${_escape(metaText.toUpperCase())}</text>
  <text x="200" y="500" text-anchor="middle" fill="#cbd5e1" font-family="Helvetica Neue, Arial, sans-serif" font-size="9">${_escape(brandText)}</text>
</svg>
''';
  }

  /// 自然卡片模板
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
    const contentAreaTop = 160.0;
    const contentAreaHeight = 300.0;
    final maxLines = _calculateMaxLines(contentAreaHeight);
    final textLines = _wrapText(content, 18, maxLines);
    final metaText = _buildMetaText(
        date: date,
        location: location,
        weather: weather,
        temperature: temperature);
    final brandText = _buildBrandText(author: author, source: source);

    final contentHeight = textLines.length * _contentFontSize * _lineHeight;
    final contentStartY = contentAreaTop +
        (contentAreaHeight - contentHeight) / 2 +
        _contentFontSize;

    return '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $_viewBoxWidth $_viewBoxHeight" preserveAspectRatio="xMidYMid meet">
  <defs>
    <linearGradient id="natureBg" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%" stop-color="#dcfce7"/>
      <stop offset="100%" stop-color="#bbf7d0"/>
    </linearGradient>
  </defs>

  <!-- 背景 -->
  <rect width="$_viewBoxWidth" height="$_viewBoxHeight" fill="url(#natureBg)" rx="24"/>
  
  <!-- 装饰叶子 -->
  <path d="M0 0 Q100 80 200 0 L400 0 L400 120 Q300 200 200 120 Q100 80 0 120 Z" fill="#4ade80" fill-opacity="0.3"/>
  <circle cx="340" cy="520" r="100" fill="#22c55e" fill-opacity="0.1"/>
  <circle cx="50" cy="560" r="60" fill="#16a34a" fill-opacity="0.1"/>

  <!-- 图标 -->
  <circle cx="200" cy="100" r="32" fill="#ffffff" fill-opacity="0.8"/>
  <path transform="translate(188, 88) scale(1.5)" d="M12 2C7.5 2 4 6.5 4 12s4.5 10 9 10c4.5 0 9-4.5 9-10S16.5 2 12 2zm0 18c-3.5 0-7-3.5-7-8s3.5-8 7-8 7 3.5 7 8-3.5 8-7 8z" fill="#15803d"/>

  <!-- 内容文字 -->
${_renderTextLines(textLines, 200.0, contentStartY, _contentFontSize, '#14532d', fontWeight: '500')}

  <!-- 底部信息 -->
  <rect x="120" y="490" width="160" height="1" fill="#15803d" fill-opacity="0.3"/>
  <text x="200" y="520" text-anchor="middle" fill="#15803d" font-family="system-ui, sans-serif" font-size="11" font-weight="500">${_escape(metaText)}</text>
  <text x="200" y="540" text-anchor="middle" fill="#166534" font-family="system-ui, sans-serif" font-size="10" fill-opacity="0.8">${_escape(brandText)}</text>
</svg>
''';
  }

  /// 复古卡片模板
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
    const contentAreaTop = 160.0;
    const contentAreaHeight = 300.0;
    final maxLines = _calculateMaxLines(contentAreaHeight);
    final textLines = _wrapText(content, 17, maxLines);
    final metaText = _buildMetaText(
        date: date,
        location: location,
        weather: weather,
        temperature: temperature);
    final brandText = _buildBrandText(author: author, source: source);

    final contentHeight = textLines.length * _contentFontSize * _lineHeight;
    final contentStartY = contentAreaTop +
        (contentAreaHeight - contentHeight) / 2 +
        _contentFontSize;

    return '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $_viewBoxWidth $_viewBoxHeight" preserveAspectRatio="xMidYMid meet">
  <defs>
    <filter id="noise">
      <feTurbulence type="fractalNoise" baseFrequency="0.8" numOctaves="3" stitchTiles="stitch"/>
      <feColorMatrix type="saturate" values="0"/>
      <feComponentTransfer>
        <feFuncA type="linear" slope="0.15"/>
      </feComponentTransfer>
    </filter>
  </defs>

  <!-- 背景 -->
  <rect width="$_viewBoxWidth" height="$_viewBoxHeight" fill="#fdf6e3" rx="24"/>
  <rect width="$_viewBoxWidth" height="$_viewBoxHeight" fill="#d2b48c" fill-opacity="0.2" rx="24"/>
  <rect width="$_viewBoxWidth" height="$_viewBoxHeight" filter="url(#noise)" rx="24"/>
  
  <!-- 边框 -->
  <rect x="24" y="24" width="352" height="552" fill="none" stroke="#78350f" stroke-width="2" rx="16" stroke-dasharray="8 6"/>
  <rect x="32" y="32" width="336" height="536" fill="none" stroke="#78350f" stroke-width="1" rx="12" stroke-opacity="0.3"/>

  <!-- 装饰 -->
  <circle cx="200" cy="80" r="6" fill="#78350f"/>
  <line x1="100" y1="80" x2="180" y2="80" stroke="#78350f" stroke-width="1"/>
  <line x1="220" y1="80" x2="300" y2="80" stroke="#78350f" stroke-width="1"/>

  <!-- 内容文字 -->
${_renderTextLines(textLines, 200.0, contentStartY, _contentFontSize, '#451a03', fontFamily: 'Courier New, Courier, monospace', fontWeight: 'bold')}

  <!-- 底部信息 -->
  <text x="200" y="500" text-anchor="middle" fill="#78350f" font-family="Courier New, Courier, monospace" font-size="11" font-weight="bold">${_escape(metaText)}</text>
  <text x="200" y="525" text-anchor="middle" fill="#92400e" font-family="Courier New, Courier, monospace" font-size="10">${_escape(brandText)}</text>
</svg>
''';
  }

  /// 水墨卡片模板
  /// 特点：黑白水墨，中国风，禅意
  static String inkTemplate({
    required String content,
    String? author,
    String? date,
    String? source,
    String? location,
    String? weather,
    String? temperature,
    String? dayPeriod,
  }) {
    const contentAreaTop = 160.0;
    const contentAreaHeight = 300.0;
    final maxLines = _calculateMaxLines(contentAreaHeight);
    final textLines = _wrapText(content, 16, maxLines);
    final metaText = _buildMetaText(
        date: date,
        location: location,
        weather: weather,
        temperature: temperature);
    final brandText = _buildBrandText(author: author, source: source);

    final contentHeight = textLines.length * _contentFontSize * _lineHeight;
    final contentStartY = contentAreaTop +
        (contentAreaHeight - contentHeight) / 2 +
        _contentFontSize;

    return '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $_viewBoxWidth $_viewBoxHeight" preserveAspectRatio="xMidYMid meet">
  <defs>
    <filter id="inkBlur">
      <feGaussianBlur stdDeviation="3"/>
    </filter>
  </defs>

  <!-- 背景 -->
  <rect width="$_viewBoxWidth" height="$_viewBoxHeight" fill="#fafaf9" rx="24"/>
  
  <!-- 水墨装饰 -->
  <path d="M-40 40 Q100 120 250 20 T480 80" stroke="#000000" stroke-width="50" stroke-opacity="0.04" fill="none" filter="url(#inkBlur)"/>
  <path d="M-40 560 Q180 480 280 560 T520 520" stroke="#000000" stroke-width="40" stroke-opacity="0.06" fill="none" filter="url(#inkBlur)"/>
  
  <!-- 印章 -->
  <rect x="300" y="100" width="40" height="40" fill="#dc2626" rx="4" fill-opacity="0.9"/>
  <text x="320" y="128" text-anchor="middle" fill="#ffffff" font-family="serif" font-size="24" font-weight="bold">心</text>

  <!-- 内容文字 -->
${_renderTextLines(textLines, 200.0, contentStartY, _contentFontSize, '#1c1917', fontFamily: 'KaiTi, STKaiti, serif', fontWeight: 'bold')}

  <!-- 底部信息 -->
  <line x1="180" y1="500" x2="220" y2="500" stroke="#a8a29e" stroke-width="1"/>
  <text x="200" y="530" text-anchor="middle" fill="#57534e" font-family="KaiTi, STKaiti, serif" font-size="12">${_escape(metaText)}</text>
  <text x="200" y="550" text-anchor="middle" fill="#78716c" font-family="KaiTi, STKaiti, serif" font-size="11">${_escape(brandText)}</text>
</svg>
''';
  }

  /// 赛博朋克模板
  /// 特点：霓虹色，故障风，科技感
  static String cyberpunkTemplate({
    required String content,
    String? author,
    String? date,
    String? source,
    String? location,
    String? weather,
    String? temperature,
    String? dayPeriod,
  }) {
    const contentAreaTop = 160.0;
    const contentAreaHeight = 300.0;
    final maxLines = _calculateMaxLines(contentAreaHeight);
    final textLines = _wrapText(content, 18, maxLines);
    final metaText = _buildMetaText(
        date: date,
        location: location,
        weather: weather,
        temperature: temperature);
    final brandText = _buildBrandText(author: author, source: source);

    final contentHeight = textLines.length * _contentFontSize * _lineHeight;
    final contentStartY = contentAreaTop +
        (contentAreaHeight - contentHeight) / 2 +
        _contentFontSize;

    return '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $_viewBoxWidth $_viewBoxHeight" preserveAspectRatio="xMidYMid meet">
  <defs>
    <linearGradient id="cyberBg" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#09090b"/>
      <stop offset="100%" stop-color="#1e1b4b"/>
    </linearGradient>
    <filter id="neonGlow">
      <feGaussianBlur stdDeviation="2.5" result="coloredBlur"/>
      <feMerge>
        <feMergeNode in="coloredBlur"/>
        <feMergeNode in="SourceGraphic"/>
      </feMerge>
    </filter>
  </defs>

  <!-- 背景 -->
  <rect width="$_viewBoxWidth" height="$_viewBoxHeight" fill="url(#cyberBg)" rx="24"/>
  
  <!-- 霓虹边框 -->
  <rect x="10" y="10" width="380" height="580" fill="none" stroke="#06b6d4" stroke-width="2" rx="16" stroke-opacity="0.5"/>
  <rect x="14" y="14" width="372" height="572" fill="none" stroke="#d946ef" stroke-width="2" rx="14" filter="url(#neonGlow)"/>
  
  <!-- 故障装饰 -->
  <rect x="0" y="120" width="400" height="2" fill="#06b6d4" fill-opacity="0.3"/>
  <rect x="0" y="480" width="400" height="2" fill="#d946ef" fill-opacity="0.3"/>
  <rect x="40" y="110" width="20" height="20" fill="none" stroke="#06b6d4" stroke-width="2"/>
  <rect x="340" y="470" width="20" height="20" fill="none" stroke="#d946ef" stroke-width="2"/>

  <!-- 内容文字 -->
${_renderTextLines(textLines, 200.0, contentStartY, _contentFontSize, '#e2e8f0', fontFamily: 'Courier New, monospace', fontWeight: 'bold')}

  <!-- 底部信息 -->
  <text x="200" y="530" text-anchor="middle" fill="#22d3ee" font-family="Courier New, monospace" font-size="11" filter="url(#neonGlow)">${_escape(metaText)}</text>
  <text x="200" y="555" text-anchor="middle" fill="#e879f9" font-family="Courier New, monospace" font-size="10">${_escape(brandText)}</text>
</svg>
''';
  }

  /// 几何抽象模板
  /// 特点：几何图形，鲜艳色彩，现代艺术
  static String geometricTemplate({
    required String content,
    String? author,
    String? date,
    String? source,
    String? location,
    String? weather,
    String? temperature,
    String? dayPeriod,
  }) {
    const contentAreaTop = 160.0;
    const contentAreaHeight = 300.0;
    final maxLines = _calculateMaxLines(contentAreaHeight);
    final textLines = _wrapText(content, 17, maxLines);
    final metaText = _buildMetaText(
        date: date,
        location: location,
        weather: weather,
        temperature: temperature);
    final brandText = _buildBrandText(author: author, source: source);

    final contentHeight = textLines.length * _contentFontSize * _lineHeight;
    final contentStartY = contentAreaTop +
        (contentAreaHeight - contentHeight) / 2 +
        _contentFontSize;

    return '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $_viewBoxWidth $_viewBoxHeight" preserveAspectRatio="xMidYMid meet">
  <defs>
    <pattern id="geoPattern" width="40" height="40" patternUnits="userSpaceOnUse">
      <rect width="40" height="40" fill="#fff1f2"/>
      <circle cx="20" cy="20" r="8" fill="#fecdd3"/>
    </pattern>
  </defs>

  <!-- 背景 -->
  <rect width="$_viewBoxWidth" height="$_viewBoxHeight" fill="url(#geoPattern)" rx="24"/>
  
  <!-- 几何图形 -->
  <circle cx="0" cy="0" r="180" fill="#f43f5e" fill-opacity="0.9"/>
  <rect x="220" y="420" width="200" height="200" fill="#3b82f6" fill-opacity="0.9" rx="20" transform="rotate(15 320 520)"/>
  <polygon points="320,60 420,160 360,200" fill="#fbbf24" fill-opacity="1"/>

  <!-- 内容区域背景 -->
  <rect x="30" y="140" width="340" height="340" fill="#ffffff" fill-opacity="0.98" rx="8" stroke="#111827" stroke-width="2"/>

  <!-- 内容文字 -->
${_renderTextLines(textLines, 200.0, contentStartY, _contentFontSize, '#111827', fontWeight: 'bold')}

  <!-- 底部信息 -->
  <text x="200" y="520" text-anchor="middle" fill="#4b5563" font-family="system-ui, sans-serif" font-size="11" font-weight="600">${_escape(metaText)}</text>
  <text x="200" y="540" text-anchor="middle" fill="#6b7280" font-family="system-ui, sans-serif" font-size="10">${_escape(brandText)}</text>
</svg>
''';
  }

  /// 学术/笔记模板（新增）
  /// 特点：蓝图风格，网格纸，严谨
  static String academicTemplate({
    required String content,
    String? author,
    String? date,
    String? source,
    String? location,
    String? weather,
    String? temperature,
    String? dayPeriod,
  }) {
    const contentAreaTop = 150.0;
    const contentAreaHeight = 320.0;
    final maxLines = _calculateMaxLines(contentAreaHeight);
    final textLines = _wrapText(content, 18, maxLines);
    final metaText = _buildMetaText(
        date: date,
        location: location,
        weather: weather,
        temperature: temperature);
    final brandText = _buildBrandText(author: author, source: source);

    final contentHeight = textLines.length * _contentFontSize * _lineHeight;
    final contentStartY = contentAreaTop +
        (contentAreaHeight - contentHeight) / 2 +
        _contentFontSize;

    return '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $_viewBoxWidth $_viewBoxHeight" preserveAspectRatio="xMidYMid meet">
  <defs>
    <pattern id="gridBlue" width="20" height="20" patternUnits="userSpaceOnUse">
      <rect width="20" height="20" fill="#f0f9ff"/>
      <path d="M 20 0 L 0 0 0 20" fill="none" stroke="#bae6fd" stroke-width="1"/>
    </pattern>
  </defs>

  <!-- 背景 -->
  <rect width="$_viewBoxWidth" height="$_viewBoxHeight" fill="url(#gridBlue)" rx="24"/>
  
  <!-- 顶部条 -->
  <rect x="0" y="0" width="$_viewBoxWidth" height="60" fill="#0284c7" rx="24"/>
  <rect x="0" y="40" width="$_viewBoxWidth" height="20" fill="#0284c7"/>
  
  <!-- 标题文字 -->
  <text x="30" y="38" fill="#ffffff" font-family="system-ui, sans-serif" font-size="18" font-weight="bold">NOTE</text>
  <circle cx="360" cy="30" r="10" fill="#ffffff" fill-opacity="0.3"/>

  <!-- 内容文字 -->
${_renderTextLines(textLines, 200.0, contentStartY, _contentFontSize, '#0c4a6e', fontWeight: '500')}

  <!-- 底部信息 -->
  <line x1="40" y1="500" x2="360" y2="500" stroke="#0284c7" stroke-width="2"/>
  <text x="200" y="530" text-anchor="middle" fill="#0369a1" font-family="system-ui, sans-serif" font-size="11" font-weight="600">${_escape(metaText)}</text>
  <text x="200" y="550" text-anchor="middle" fill="#0ea5e9" font-family="system-ui, sans-serif" font-size="10">${_escape(brandText)}</text>
</svg>
''';
  }

  /// 情感/日记模板（新增）
  /// 特点：柔和渐变，圆润，温馨
  static String emotionalTemplate({
    required String content,
    String? author,
    String? date,
    String? source,
    String? location,
    String? weather,
    String? temperature,
    String? dayPeriod,
  }) {
    const contentAreaTop = 160.0;
    const contentAreaHeight = 300.0;
    final maxLines = _calculateMaxLines(contentAreaHeight);
    final textLines = _wrapText(content, 18, maxLines);
    final metaText = _buildMetaText(
        date: date,
        location: location,
        weather: weather,
        temperature: temperature);
    final brandText = _buildBrandText(author: author, source: source);

    final contentHeight = textLines.length * _contentFontSize * _lineHeight;
    final contentStartY = contentAreaTop +
        (contentAreaHeight - contentHeight) / 2 +
        _contentFontSize;

    return '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $_viewBoxWidth $_viewBoxHeight" preserveAspectRatio="xMidYMid meet">
  <defs>
    <linearGradient id="emotionBg" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#fff1f2"/>
      <stop offset="100%" stop-color="#ffe4e6"/>
    </linearGradient>
  </defs>

  <!-- 背景 -->
  <rect width="$_viewBoxWidth" height="$_viewBoxHeight" fill="url(#emotionBg)" rx="24"/>
  
  <!-- 柔和气泡 -->
  <circle cx="50" cy="50" r="120" fill="#fda4af" fill-opacity="0.2"/>
  <circle cx="350" cy="550" r="150" fill="#f43f5e" fill-opacity="0.1"/>
  <circle cx="320" cy="100" r="40" fill="#fb7185" fill-opacity="0.2"/>

  <!-- 内容卡片 -->
  <rect x="40" y="140" width="320" height="340" fill="#ffffff" fill-opacity="0.6" rx="30"/>

  <!-- 内容文字 -->
${_renderTextLines(textLines, 200.0, contentStartY, _contentFontSize, '#881337', fontWeight: '500')}

  <!-- 底部信息 -->
  <text x="200" y="520" text-anchor="middle" fill="#9f1239" font-family="system-ui, sans-serif" font-size="11">${_escape(metaText)}</text>
  <text x="200" y="540" text-anchor="middle" fill="#be185d" font-family="system-ui, sans-serif" font-size="10">${_escape(brandText)}</text>
</svg>
''';
  }

  /// 开发者/代码模板（新增）
  /// 特点：IDE风格，深色，行号
  static String devTemplate({
    required String content,
    String? author,
    String? date,
    String? source,
    String? location,
    String? weather,
    String? temperature,
    String? dayPeriod,
  }) {
    const contentAreaTop = 140.0;
    const contentAreaHeight = 360.0;
    final maxLines = _calculateMaxLines(contentAreaHeight);
    final textLines = _wrapText(
        content, 20, maxLines); // Monospace fits more chars? Adjusted width.
    final metaText = _buildMetaText(
        date: date,
        location: location,
        weather: weather,
        temperature: temperature);
    final brandText = _buildBrandText(author: author, source: source);

    final contentHeight = textLines.length * _contentFontSize * _lineHeight;
    final contentStartY = contentAreaTop +
        (contentAreaHeight - contentHeight) / 2 +
        _contentFontSize;

    // 生成行号
    final lineNumbers =
        List.generate(textLines.length, (i) => (i + 1).toString()).join('\n');
    String renderLineNumbers(int count, double startY, double fontSize) {
      final buffer = StringBuffer();
      final lineSpacing = fontSize * _lineHeight;
      for (int i = 0; i < count; i++) {
        buffer.writeln(
            '<text x="50" y="${startY + i * lineSpacing}" text-anchor="end" fill="#4b5563" font-family="monospace" font-size="14">${i + 1}</text>');
      }
      return buffer.toString();
    }

    return '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $_viewBoxWidth $_viewBoxHeight" preserveAspectRatio="xMidYMid meet">
  <!-- 背景 -->
  <rect width="$_viewBoxWidth" height="$_viewBoxHeight" fill="#1e1e1e" rx="24"/>
  
  <!-- 顶部栏 -->
  <rect x="0" y="0" width="$_viewBoxWidth" height="40" fill="#252526" rx="24"/>
  <rect x="0" y="20" width="$_viewBoxWidth" height="20" fill="#252526"/>
  <circle cx="30" cy="20" r="6" fill="#ff5f56"/>
  <circle cx="50" cy="20" r="6" fill="#ffbd2e"/>
  <circle cx="70" cy="20" r="6" fill="#27c93f"/>
  <text x="200" y="24" text-anchor="middle" fill="#9ca3af" font-family="monospace" font-size="12">untitled.txt</text>

  <!-- 行号区域背景 -->
  <rect x="0" y="40" width="60" height="560" fill="#1e1e1e"/>
  
  <!-- 行号 -->
  ${renderLineNumbers(textLines.length, contentStartY, _contentFontSize)}

  <!-- 内容文字 (左对齐) -->
  ${(() {
      final buffer = StringBuffer();
      final lineSpacing = _contentFontSize * _lineHeight;
      for (int i = 0; i < textLines.length; i++) {
        final y = contentStartY + i * lineSpacing;
        // 简单的语法高亮模拟：奇数行白色，偶数行浅蓝 (太复杂，统一用亮色)
        buffer.writeln(
            '<text x="70" y="$y" text-anchor="start" fill="#d4d4d4" font-family="monospace" font-size="16">${_escape(textLines[i])}</text>');
      }
      return buffer.toString();
    })()}

  <!-- 底部状态栏 -->
  <rect x="0" y="570" width="$_viewBoxWidth" height="30" fill="#007acc"/>
  <text x="20" y="588" fill="#ffffff" font-family="sans-serif" font-size="10">UTF-8</text>
  <text x="380" y="588" text-anchor="end" fill="#ffffff" font-family="sans-serif" font-size="10">${_escape(brandText)}</text>
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
      case CardType.gradient:
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
      case CardType.ink:
        return inkTemplate(
          content: content,
          author: author,
          date: date,
          source: source,
          location: location,
          weather: weather,
          temperature: temperature,
          dayPeriod: dayPeriod,
        );
      case CardType.cyberpunk:
        return cyberpunkTemplate(
          content: content,
          author: author,
          date: date,
          source: source,
          location: location,
          weather: weather,
          temperature: temperature,
          dayPeriod: dayPeriod,
        );
      case CardType.geometric:
        return geometricTemplate(
          content: content,
          author: author,
          date: date,
          source: source,
          location: location,
          weather: weather,
          temperature: temperature,
          dayPeriod: dayPeriod,
        );
      case CardType.academic:
        return academicTemplate(
          content: content,
          author: author,
          date: date,
          source: source,
          location: location,
          weather: weather,
          temperature: temperature,
          dayPeriod: dayPeriod,
        );
      case CardType.emotional:
        return emotionalTemplate(
          content: content,
          author: author,
          date: date,
          source: source,
          location: location,
          weather: weather,
          temperature: temperature,
          dayPeriod: dayPeriod,
        );
      case CardType.dev:
        return devTemplate(
          content: content,
          author: author,
          date: date,
          source: source,
          location: location,
          weather: weather,
          temperature: temperature,
          dayPeriod: dayPeriod,
        );
      case CardType.mindful:
        return mindfulTemplate(
          content: content,
          author: author,
          date: date,
          source: source,
          location: location,
          weather: weather,
          temperature: temperature,
          dayPeriod: dayPeriod,
        );
      case CardType.neonCyber:
        return neonCyberTemplate(
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

  /// 根据内容区域高度动态计算可容纳的最大行数
  static int _calculateMaxLines(double contentAreaHeight) {
    final lineSpacing = _contentFontSize * _lineHeight;
    return math.max(2, (contentAreaHeight / lineSpacing).floor());
  }

  /// 文本换行处理 (支持中英文混合排版，并保留手动换行)
  static List<String> _wrapText(
    String text,
    int maxCharsPerLine,
    int maxLines,
  ) {
    final normalized =
        text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trimRight();
    if (normalized.trim().isEmpty) {
      return [''];
    }

    final paragraphs = normalized.split('\n');
    final lines = <String>[];
    final double maxWidth = maxCharsPerLine * 2.0;
    bool truncated = false;

    for (final rawParagraph in paragraphs) {
      if (lines.length >= maxLines) {
        truncated = true;
        break;
      }

      final paragraph = rawParagraph.trim();
      if (paragraph.isEmpty) {
        if (lines.isNotEmpty &&
            lines.last.isNotEmpty &&
            lines.length < maxLines) {
          lines.add('');
        }
        continue;
      }

      final segment = paragraph.replaceAll(RegExp(r'\s+'), ' ');
      int currentStart = 0;

      while (currentStart < segment.length && lines.length < maxLines) {
        double currentWidth = 0;
        int currentEnd = currentStart;

        while (currentEnd < segment.length) {
          final char = segment[currentEnd];
          final charWidth = char.codeUnitAt(0) <= 255 ? 1.0 : 2.0;
          if (currentWidth + charWidth > maxWidth) {
            break;
          }
          currentWidth += charWidth;
          currentEnd++;
        }

        if (currentEnd == currentStart) {
          currentEnd++;
        }

        String line = segment.substring(currentStart, currentEnd);

        if (currentEnd < segment.length &&
            segment[currentEnd] != ' ' &&
            line.contains(' ')) {
          final lastSpaceIndex = line.lastIndexOf(' ');
          if (lastSpaceIndex >= 0 &&
              lastSpaceIndex >= (line.length * 0.4).floor()) {
            line = line.substring(0, lastSpaceIndex);
            currentEnd = currentStart + lastSpaceIndex + 1;
          }
        }

        lines.add(line.trim());
        currentStart = currentEnd;
      }

      if (currentStart < segment.length) {
        truncated = true;
        break;
      }
    }

    if (lines.isEmpty) {
      return [''];
    }

    while (lines.length > 1 && lines.last.trim().isEmpty) {
      lines.removeLast();
    }

    if (truncated && lines.isNotEmpty) {
      for (int i = lines.length - 1; i >= 0; i--) {
        if (lines[i].trim().isEmpty) {
          lines.removeAt(i);
          continue;
        }
        final line = lines[i];
        final cutIndex = line.length > 3 ? line.length - 3 : 0;
        lines[i] = '${line.substring(0, cutIndex)}...';
        if (i < lines.length - 1) {
          lines.removeRange(i + 1, lines.length);
        }
        break;
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
    String fontWeight = '400',
  }) {
    final buffer = StringBuffer();
    final lineSpacing = fontSize * _lineHeight;

    for (int i = 0; i < lines.length; i++) {
      final y = startY + i * lineSpacing;
      buffer.writeln(
        '  <text x="$centerX" y="${y.toStringAsFixed(1)}" text-anchor="middle" fill="$color" font-family="$fontFamily" font-size="${fontSize.toStringAsFixed(0)}" font-style="$fontStyle" font-weight="$fontWeight">${_escape(lines[i])}</text>',
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
