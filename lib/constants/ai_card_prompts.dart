/// AI卡片生成提示词常量
class AICardPrompts {
  /// 智能内容相关SVG卡片生成提示词
  static String randomStylePosterPrompt({
    required String content,
    String? author,
    String? date,
    String? location,
    String? weather,
    String? temperature,
    String? dayPeriod,
    String? source,
    String brandName = '心迹',
  }) {
    return '''
您是一位专业的平面设计师和SVG开发专家，擅长根据文本内容创造相关的视觉元素和图形设计。

请分析以下笔记内容，并创建一个包含相关视觉元素的SVG卡片：

##内容分析要求
- 深度分析笔记内容的主题、情感和关键概念
- 识别内容中的核心元素（如：学习、工作、生活、情感、自然、科技等）
- 根据内容特征选择相应的视觉符号和图形元素
- 确定最适合的色彩情感表达

##视觉元素生成要求
- **根据内容主题添加相关图标和符号**：
  * 学习内容：书本、笔、灯泡、大脑、齿轮等
  * 工作内容：电脑、图表、箭头、目标、时钟等
  * 情感内容：心形、花朵、星星、云朵、太阳等
  * 自然内容：树叶、山峰、水滴、鸟类、花草等
  * 科技内容：电路、网络、数据、几何图形等
  * 哲学思考：无穷符号、天平、问号、迷宫等
- **创建与内容呼应的装饰元素**：
  * 背景纹理或图案
  * 几何装饰图形
  * 线条和边框设计
  * 渐变和色彩过渡
- **使用象征性的视觉隐喻**：
  * 将抽象概念转化为具体图形
  * 创建视觉层次和焦点
  * 增强内容的情感表达

##设计风格与SOTA增强
- **使用弥散渐变背景 (SOTA Mesh Gradients)**：
  * 通过多个叠加的大尺寸圆心/椭圆 `<circle>` 配合重度高斯模糊 `feGaussianBlur` (stdDeviation="40-80") 模拟现代 Mesh Gradient 效果。
- **毛玻璃质感 (Premium Glassmorphism)**：
  * 使用半透明填充、细窄的白色/浅色描边以及柔和的投影 `feDropShadow` 创建悬浮层感。
- **SOTA 排版 (Modern Typography)**：
  * 使用系统字体栈，优化字间距 `letter-spacing` 和行高。重要文字可使用 `font-weight="bold"`。
- **色彩方案**：使用高饱和度与深色背景的碰撞，或极简的高级灰阶配合重点色彩点缀。

##技术规格
- 使用纯SVG格式，必须设置viewBox="0 0 400 600"
- 必须包含xmlns="http://www.w3.org/2000/svg"命名空间
- SVG元素总数控制在100个以内，确保渲染效率
- 充分利用 `<defs>` 定义滤镜和渐变：
  * `feGaussianBlur`: 用于背景弥散
  * `feDropShadow`: 用于增强层级感
  * `linearGradient` / `radialGradient`: 用于质感表达
- 字体：system-ui, -apple-system, Inter, Arial, sans-serif
- 文字换行：请根据 400px 宽度合理分段文字，必要时使用多个 `<text>` 或 `<tspan>`。

##布局和排版
- 卡片尺寸固定为400x600像素
- 旗舰级布局建议：大背景 + 悬浮圆角内容块 + 底部图标化元数据。
- 图标化元数据建议：在日期、地点前绘制简单的 SVG 图形（如日历、定位针、小太阳等路径）。
- 应用名展示：$brandName 应作为品牌印记优雅地出现在角落或底部。

##文字内容严格限制（重要！）
**允许显示的内容：**
- 笔记原始内容（一字不差）
- 笔记元数据：作者、日期、地点、天气、来源
- 应用名称：$brandName

**严格禁止的内容：**
- 任何多余的标题、说明词（如“内容：”、“总结：”）
- 任何解释性废话

##输出要求
- 只输出完整的SVG代码，不包含任何其他内容
- 不要包含markdown代码块标记
- 确保代码有效并符合标准，SVG必须以<svg开头，以</svg>结尾
- 文字内容必须是一字不差的原始内容。

待处理内容：
$content

可用元数据：
${author != null ? '作者: $author\n' : ''}${source != null ? '来源: $source\n' : ''}${date != null ? '日期: $date\n' : ''}${location != null ? '地点: $location\n' : ''}${weather != null ? '天气: $weather${temperature != null ? ' $temperature' : ''}\n' : ''}${dayPeriod != null ? '时间段: $dayPeriod\n' : ''}

请直接输出极致美观、具备 SOTA 视觉质感的 SVG 代码：
''';
  }

  /// 智能内容相关卡片生成提示词（旗舰 SOTA 增强版）
  static String intelligentCardPrompt({
    required String content,
    String? author,
    String? date,
    String? location,
    String? weather,
    String? temperature,
    String? dayPeriod,
    String? source,
    String brandName = '心迹',
  }) {
    return '''
您是一位顶级的视觉设计师和 SVG 专家。请为以下笔记内容生成一张具备 SOTA (State-Of-The-Art) 质感的分享卡片。

## 待处理内容
$content
${author != null ? '作者：$author' : ''}
${source != null ? '来源：$source' : ''}
${date != null ? '日期：$date' : ''}
${location != null ? '地点：$location' : ''}
${weather != null ? '天气：$weather${temperature != null ? ' $temperature' : ''}' : ''}
${dayPeriod != null ? '时间段：$dayPeriod' : ''}

## SOTA 设计原则
1. **弥散光感 (Mesh Gradients)**: 使用多个叠加的 `<circle>` 配合重度高斯模糊 `feGaussianBlur` (stdDeviation="50-80") 创造梦幻的弥散背景。
2. **磨砂玻璃 (Glassmorphism)**: 核心内容区域使用半透明背景 (white/black with low alpha)，细描边，以及柔和投影 `feDropShadow`。
3. **旗舰级排版**: 
   - 使用 `system-ui, -apple-system, sans-serif`。
   - 优化行高 (line-height) 和字间距 (letter-spacing)。
   - 重要信息采用 `font-weight="bold"`。
4. **图标化元数据**: 在日期、地点、作者前绘制简洁的 SVG 几何图形作为装饰。

## 技术规格
- viewBox="0 0 400 600"
- 包含 xmlns="http://www.w3.org/2000/svg"
- 元素总数控制在 100 个以内。
- 严禁输出 Markdown 代码块标记（如 ```svg）。
- 严禁添加“摘要：”、“内容：”等说明性标签。

请直接输出极致美感、旗舰质感的 SVG 代码：
''';
  }

  /// 内容相关视觉元素增强提示词 (SOTA Edition)
  static String contentAwareVisualPrompt({
    required String content,
    String? author,
    String? date,
    String? location,
    String? weather,
    String? temperature,
    String? dayPeriod,
    String? source,
    String brandName = '心迹',
  }) {
    return '''
您是一位极具创意和美感的视觉艺术家。请根据以下文本内容的主题和情感，创作一张 SOTA 级别的 SVG 视觉增强卡片。

## 待处理内容
$content
${author != null ? '作者：$author' : ''}
${source != null ? '来源：$source' : ''}
${date != null ? '日期：$date' : ''}
${location != null ? '地点：$location' : ''}
${weather != null ? '天气：$weather${temperature != null ? ' $temperature' : ''}' : ''}
${dayPeriod != null ? '时间段：$dayPeriod' : ''}

## 创作要求
1. **主题呼应**: 识别内容的核心主题（如科技、自然、情感、工作），并生成高度契合的抽象视觉元素或图标。
2. **色彩哲学**: 根据情感基调选择色彩方案（例如：冷静技术用青/蓝，温馨生活用暖橙/粉）。
3. **视觉层级**:
   - 底层：弥散渐变背景 (stdDeviation="60")。
   - 中层：悬浮的毛玻璃内容块，带 `feDropShadow`。
   - 顶层：与内容相关的装饰图形（几何、线条或路径图标）。
4. **品牌植入**: 应用名 "$brandName" 应作为设计的一部分优雅呈现。

## 约束条件
- viewBox="0 0 400 600"
- 仅输出纯 SVG 源码，不含 Markdown。
- 文字内容必须保持原样。

请开始你的视觉艺术创作，输出 SOTA 质感的 SVG 代码：
''';
  }
}
