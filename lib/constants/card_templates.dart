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
  static const int _maxContentLines = 11; // 内容最大行数（增加以避免截断）
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
    // 增加宽度利用率：18字符
    final textLines = _wrapText(content, 18, _maxContentLines);
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
    // 优化：增加宽度到18字符，增加行数限制
    final textLines = _wrapText(content, 18, 10);
    final metaText = _buildMetaText(date: date, location: location, weather: weather, temperature: temperature);
    final authorDisplay = author ?? source ?? '';

    final contentHeight = textLines.length * _contentFontSize * _lineHeight;
    // 优化布局：扩大内容区域
    const contentAreaTop = 160.0;
    const contentAreaHeight = 300.0;
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
  
  <!-- 装饰引号：调整位置以适应更大的内容区域 -->
  <text x="40" y="120" fill="#ffffff" fill-opacity="0.4" font-family="Georgia, serif" font-size="120" font-weight="bold">“</text>
  <text x="360" y="480" text-anchor="end" fill="#ffffff" fill-opacity="0.4" font-family="Georgia, serif" font-size="120" font-weight="bold">”</text>

  <!-- 内容卡片 -->
  <rect x="32" y="$contentAreaTop" width="336" height="$contentAreaHeight" fill="#ffffff" fill-opacity="0.9" rx="16" filter="url(#quoteShadow)"/>

  <!-- 引用内容 -->
${_renderTextLines(textLines, 200.0, contentStartY, _contentFontSize, '#374151', fontFamily: 'Georgia, serif', fontStyle: 'italic')}

  <!-- 作者信息 -->
${authorDisplay.isNotEmpty ? '''
  <text x="200" y="490" text-anchor="middle" fill="#be185d" font-family="system-ui, sans-serif" font-size="14" font-weight="600">— ${_escape(authorDisplay)} —</text>
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
    // 增加宽度利用率：18字符
    final textLines = _wrapText(content, 18, _maxContentLines);
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

  <!-- 内容文字：提高对比度，使用纯白并加粗 -->
${_renderTextLines(textLines, 200.0, contentStartY, _contentFontSize, '#ffffff', fontWeight: '500')}

  <!-- 底部信息 -->
  <line x1="100" y1="500" x2="300" y2="500" stroke="#ffffff" stroke-opacity="0.1"/>
  <text x="200" y="530" text-anchor="middle" fill="#cbd5e1" font-family="system-ui, sans-serif" font-size="11">${_escape(metaText)}</text>
  <text x="200" y="555" text-anchor="middle" fill="#94a3b8" font-family="system-ui, sans-serif" font-size="11">${_escape(brandText)}</text>
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
    // 保持16字符，因为内容区域较窄 (320px)
    final textLines = _wrapText(content, 16, _maxContentLines);
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
    // 增加宽度利用率：18字符
    final textLines = _wrapText(content, 18, _maxContentLines);
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
    // 17字符，适应边框
    final textLines = _wrapText(content, 17, _maxContentLines);
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

  /// 水墨卡片模板（新增）
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
    // 保持16字符，避免与水墨装饰重叠
    final textLines = _wrapText(content, 16, _maxContentLines);
    final metaText = _buildMetaText(date: date, location: location, weather: weather, temperature: temperature);
    final brandText = _buildBrandText(author: author, source: source);

    final contentHeight = textLines.length * _contentFontSize * _lineHeight;
    const contentAreaTop = 160.0;
    const contentAreaHeight = 300.0;
    final contentStartY = contentAreaTop + (contentAreaHeight - contentHeight) / 2 + _contentFontSize;

    return '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $_viewBoxWidth $_viewBoxHeight">
  <defs>
    <filter id="inkBlur">
      <feGaussianBlur stdDeviation="2"/>
    </filter>
  </defs>

  <!-- 背景 -->
  <rect width="$_viewBoxWidth" height="$_viewBoxHeight" fill="#fdfbf7" rx="24"/>
  
  <!-- 水墨装饰 -->
  <path d="M-50 50 Q100 150 200 50 T450 100" stroke="#000000" stroke-width="40" stroke-opacity="0.05" fill="none" filter="url(#inkBlur)"/>
  <path d="M-50 550 Q150 450 250 550 T500 500" stroke="#000000" stroke-width="30" stroke-opacity="0.08" fill="none" filter="url(#inkBlur)"/>
  <circle cx="320" cy="120" r="40" fill="#ef4444" fill-opacity="0.8"/>
  <text x="320" y="128" text-anchor="middle" fill="#ffffff" font-family="serif" font-size="24" font-weight="bold">禅</text>

  <!-- 内容文字 -->
${_renderTextLines(textLines, 200.0, contentStartY, _contentFontSize, '#1c1917', fontFamily: 'KaiTi, STKaiti, serif')}

  <!-- 底部信息 -->
  <line x1="180" y1="500" x2="220" y2="500" stroke="#a8a29e" stroke-width="1"/>
  <text x="200" y="530" text-anchor="middle" fill="#57534e" font-family="KaiTi, STKaiti, serif" font-size="12">${_escape(metaText)}</text>
  <text x="200" y="550" text-anchor="middle" fill="#78716c" font-family="KaiTi, STKaiti, serif" font-size="11">${_escape(brandText)}</text>
</svg>
''';
  }

  /// 赛博朋克模板（新增）
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
    // 18字符，全宽
    final textLines = _wrapText(content, 18, _maxContentLines);
    final metaText = _buildMetaText(date: date, location: location, weather: weather, temperature: temperature);
    final brandText = _buildBrandText(author: author, source: source);

    final contentHeight = textLines.length * _contentFontSize * _lineHeight;
    const contentAreaTop = 160.0;
    const contentAreaHeight = 300.0;
    final contentStartY = contentAreaTop + (contentAreaHeight - contentHeight) / 2 + _contentFontSize;

    return '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $_viewBoxWidth $_viewBoxHeight">
  <defs>
    <linearGradient id="cyberBg" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#09090b"/>
      <stop offset="100%" stop-color="#18181b"/>
    </linearGradient>
    <filter id="neonGlow">
      <feGaussianBlur stdDeviation="2" result="coloredBlur"/>
      <feMerge>
        <feMergeNode in="coloredBlur"/>
        <feMergeNode in="SourceGraphic"/>
      </feMerge>
    </filter>
  </defs>

  <!-- 背景 -->
  <rect width="$_viewBoxWidth" height="$_viewBoxHeight" fill="url(#cyberBg)" rx="24"/>
  
  <!-- 霓虹装饰 -->
  <path d="M0 0 L400 0 L400 600 L0 600 Z" fill="none" stroke="#06b6d4" stroke-width="4" stroke-opacity="0.5"/>
  <path d="M20 20 L380 20 L380 580 L20 580 Z" fill="none" stroke="#d946ef" stroke-width="2" filter="url(#neonGlow)"/>
  
  <!-- 故障线条 -->
  <line x1="0" y1="100" x2="400" y2="100" stroke="#06b6d4" stroke-width="1" stroke-opacity="0.3"/>
  <line x1="0" y1="500" x2="400" y2="500" stroke="#d946ef" stroke-width="1" stroke-opacity="0.3"/>

  <!-- 内容文字 -->
${_renderTextLines(textLines, 200.0, contentStartY, _contentFontSize, '#e2e8f0', fontFamily: 'Courier New, monospace')}

  <!-- 底部信息 -->
  <text x="200" y="530" text-anchor="middle" fill="#22d3ee" font-family="Courier New, monospace" font-size="11" filter="url(#neonGlow)">${_escape(metaText)}</text>
  <text x="200" y="550" text-anchor="middle" fill="#e879f9" font-family="Courier New, monospace" font-size="10">${_escape(brandText)}</text>
</svg>
''';
  }

  /// 几何抽象模板（新增）
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
    // 17字符，适应内容框
    final textLines = _wrapText(content, 17, _maxContentLines);
    final metaText = _buildMetaText(date: date, location: location, weather: weather, temperature: temperature);
    final brandText = _buildBrandText(author: author, source: source);

    final contentHeight = textLines.length * _contentFontSize * _lineHeight;
    const contentAreaTop = 160.0;
    const contentAreaHeight = 300.0;
    final contentStartY = contentAreaTop + (contentAreaHeight - contentHeight) / 2 + _contentFontSize;

    return '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $_viewBoxWidth $_viewBoxHeight">
  <defs>
    <pattern id="geoPattern" width="40" height="40" patternUnits="userSpaceOnUse">
      <rect width="40" height="40" fill="#fff1f2"/>
      <circle cx="20" cy="20" r="10" fill="#fecdd3"/>
    </pattern>
  </defs>

  <!-- 背景 -->
  <rect width="$_viewBoxWidth" height="$_viewBoxHeight" fill="url(#geoPattern)" rx="24"/>
  
  <!-- 几何图形 -->
  <circle cx="0" cy="0" r="150" fill="#f43f5e" fill-opacity="0.8"/>
  <rect x="250" y="450" width="200" height="200" fill="#3b82f6" fill-opacity="0.8" transform="rotate(45 350 550)"/>
  <polygon points="300,50 400,150 350,200" fill="#fbbf24" fill-opacity="0.9"/>

  <!-- 内容区域背景 -->
  <rect x="30" y="140" width="340" height="340" fill="#ffffff" fill-opacity="0.95" rx="4"/>

  <!-- 内容文字 -->
${_renderTextLines(textLines, 200.0, contentStartY, _contentFontSize, '#111827', fontWeight: '600')}

  <!-- 底部信息 -->
  <text x="200" y="520" text-anchor="middle" fill="#4b5563" font-family="system-ui, sans-serif" font-size="11" font-weight="bold">${_escape(metaText)}</text>
  <text x="200" y="540" text-anchor="middle" fill="#6b7280" font-family="system-ui, sans-serif" font-size="10">${_escape(brandText)}</text>
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
    }
  }

  // ============ 工具方法 ============

  /// 文本换行处理 (支持中英文混合排版)
  static List<String> _wrapText(
    String text,
    int maxCharsPerLine,
    int maxLines,
  ) {
    String cleanText = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (cleanText.isEmpty) return [''];

    final lines = <String>[];
    // 设定总宽度单位：中文字符宽2，英文字符宽1
    // maxCharsPerLine 是以中文字符为标准的，所以总宽度 = maxCharsPerLine * 2
    final double maxWidth = maxCharsPerLine * 2.0;
    
    int currentStart = 0;
    
    while (currentStart < cleanText.length && lines.length < maxLines) {
      double currentWidth = 0;
      int currentEnd = currentStart;
      
      // 寻找当前行的结束位置
      while (currentEnd < cleanText.length) {
        final char = cleanText[currentEnd];
        // 简单判断：ASCII字符宽1，其他宽2
        final charWidth = char.codeUnitAt(0) <= 255 ? 1.0 : 2.0;
        
        if (currentWidth + charWidth > maxWidth) {
          break;
        }
        currentWidth += charWidth;
        currentEnd++;
      }
      
      // 如果一行都放不下一个字符（理论上不应该），强制放一个
      if (currentEnd == currentStart && currentStart < cleanText.length) {
        currentEnd++;
      }

      String line = cleanText.substring(currentStart, currentEnd);
      
      // 简单的单词断行处理（仅针对英文环境优化）
      // 如果当前行截断了单词（末尾不是空格，且下一行开头不是空格），且当前行包含空格
      if (currentEnd < cleanText.length && 
          cleanText[currentEnd] != ' ' && 
          line.contains(' ') &&
          line.lastIndexOf(' ') > line.length * 0.6) { // 只有空格靠后才折行，避免过早折行
         
         int lastSpaceIndex = line.lastIndexOf(' ');
         line = line.substring(0, lastSpaceIndex);
         currentEnd = currentStart + lastSpaceIndex + 1; // +1 跳过空格
      }

      lines.add(line.trim());
      currentStart = currentEnd;
    }

    // 处理截断省略号
    if (currentStart < cleanText.length && lines.isNotEmpty) {
      String lastLine = lines.last;
      // 简单处理：移除最后两个字符加省略号
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
