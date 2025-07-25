/// AI卡片生成提示词常量
class AICardPrompts {
  /// 智能内容相关SVG卡片生成提示词
  static String randomStylePosterPrompt({required String content}) {
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

##设计风格
- 根据内容情感选择设计风格：温暖、冷静、活力、沉稳、创新、传统等
- 使用现代化的设计语言，参考Material Design、iOS设计规范
- 配色方案要与内容情感高度匹配
- 字体选择要体现内容的性格特征

##技术规格
- 使用纯SVG格式，必须设置viewBox="0 0 400 600"
- 必须包含xmlns="http://www.w3.org/2000/svg"命名空间
- SVG元素总数控制在80个以内，确保渲染效率
- 只使用基础SVG元素：rect, circle, ellipse, line, path, text, g, defs
- 支持渐变、阴影等基础效果，避免复杂滤镜
- 使用系统字体：system-ui, Arial, sans-serif

##布局和排版
- 卡片尺寸固定为400x600像素
- 内容区域留出合理边距（建议24-32px）
- 文字内容居中或左对齐，确保可读性
- 视觉元素与文字内容协调布局
- 重要信息突出显示，次要信息适当弱化

##具体实现示例
- 学习笔记：添加书本图标、知识网络图、学习进度条等
- 工作总结：添加图表、箭头、目标图标、时间轴等
- 情感记录：添加心情图标、天气元素、情感色彩等
- 生活感悟：添加生活场景元素、自然图案、温馨色调等
- 技术笔记：添加代码符号、网络图、几何图形等

##文字内容严格限制（重要！）
**允许显示的内容：**
- 笔记原始内容（一字不差）
- 笔记元数据：作者信息、日期信息
- 应用名称：心迹（中文名）

**严格禁止的内容：**
- 任何标题、分类、标签（如"知识卡片"、"学习笔记"、"今日感悟"）
- 任何前缀标签（如"内容："、"摘要："、"要点："、"思考："）
- 任何解释性文字、总结、补充说明
- 任何主题词汇（如"学习"、"工作"、"生活"、"情感"）
- 任何描述性文字（如"精彩内容"、"重要笔记"）

##输出要求
- 只输出完整的SVG代码，不包含任何其他内容
- 不要包含markdown代码块标记
- 确保代码有效并符合SVG 1.1标准
- SVG必须以<svg开头，以</svg>结尾
- 文字内容只能是提供的笔记内容，不添加任何额外文字

待处理内容：
$content

请直接输出包含相关视觉元素的SVG代码，文字部分只显示上述笔记内容：
''';
  }

  /// 智能内容相关卡片生成提示词（增强版）
  static String intelligentCardPrompt({
    required String content,
    String? author,
    String? date,
  }) {
    return '''
您是一位专业的平面设计师和SVG开发专家，擅长根据文本内容创造相关的视觉元素和符号。

请深度分析以下内容，并生成包含相关视觉元素的SVG卡片：

##待处理内容
$content
${author != null ? '作者：$author' : ''}
${date != null ? '日期：$date' : ''}

##内容分析和视觉元素匹配
请根据内容特征添加相应的视觉元素：

**学习/知识类内容**：
- 图标：书本📚、灯泡💡、大脑🧠、铅笔✏️、齿轮⚙️
- 元素：知识网络图、学习路径、进度条、思维导图
- 色彩：蓝色系（智慧）、紫色系（创新）

**工作/职场类内容**：
- 图标：电脑💻、图表📊、目标🎯、时钟⏰、箭头➡️
- 元素：流程图、数据可视化、时间轴、成长曲线
- 色彩：商务蓝、专业灰、成功绿

**情感/心情类内容**：
- 图标：心形❤️、花朵🌸、星星⭐、云朵☁️、太阳☀️
- 元素：情感波浪、心情色彩、温馨图案、柔和线条
- 色彩：暖色调、粉色系、橙色系

**生活/日常类内容**：
- 图标：房屋🏠、咖啡☕、植物🌱、音乐🎵、相机📷
- 元素：生活场景、日常物品、温馨装饰、生活节奏
- 色彩：自然绿、温暖黄、舒适棕

**自然/环境类内容**：
- 图标：树叶🍃、山峰🏔️、水滴💧、鸟类🐦、花草🌿
- 元素：自然纹理、有机形状、环境图案、季节元素
- 色彩：自然绿、天空蓝、大地棕

**科技/创新类内容**：
- 图标：电路⚡、网络🌐、数据📊、几何图形🔷、代码符号
- 元素：科技线条、数字图案、未来感图形、连接网络
- 色彩：科技蓝、未来紫、创新青

**哲学/思考类内容**：
- 图标：无穷符号∞、天平⚖️、问号❓、迷宫🌀、智慧眼👁️
- 元素：思考泡泡、哲学符号、深度图案、抽象几何
- 色彩：深邃蓝、智慧紫、沉思灰

##设计实现要求
- **必须根据内容添加相关的视觉元素**，不能只是纯文字卡片
- 视觉元素要与内容主题高度相关，增强表达效果
- 使用现代化设计语言，简洁而富有表现力
- 创建清晰的视觉层次：背景 → 装饰元素 → 主要内容 → 细节
- 色彩搭配要体现内容的情感色调
- 字体选择要匹配内容的性格特征

##具体实现指南
1. **背景设计**：根据内容情感选择渐变色或纯色背景
2. **主要图标**：在卡片顶部或中心位置添加1-2个主要相关图标
3. **装饰元素**：添加2-4个小型装饰图形，呼应主题
4. **文字排版**：确保内容清晰可读，与视觉元素协调
5. **整体平衡**：视觉元素与文字内容比例协调，不喧宾夺主

##技术规格
- 使用纯SVG格式，viewBox="0 0 400 600"
- 必须包含xmlns="http://www.w3.org/2000/svg"
- SVG元素总数控制在60个以内
- 使用基础SVG元素：rect, circle, ellipse, line, path, text, g, defs
- 支持linearGradient渐变效果
- 字体使用：system-ui, Arial, sans-serif

##文字内容严格要求（必须遵守！）
- **文字内容只能是提供的笔记内容，一字不能改**
- **绝对禁止添加任何标题、分类、标签或说明文字**
- **不要添加"学习笔记"、"工作总结"、"生活感悟"等分类标题**
- **不要添加"内容"、"摘要"、"要点"、"思考"等标签前缀**
- **不要添加任何解释、总结或补充说明**
- 如果笔记内容较长，可以合理分行，但不能删减内容
- 保持原始笔记的语言风格和表达方式

##输出要求
- 只输出完整的SVG代码，不包含任何其他内容
- 不要包含markdown代码块标记
- 确保代码有效并符合SVG 1.1标准
- SVG必须以<svg开头，以</svg>结尾
- 文字部分只显示：笔记内容 + 元数据 + "心迹"

示例格式：
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 600">
  <!-- 背景和渐变定义 -->
  <!-- 相关视觉元素 -->
  <!-- 笔记内容（无标题标签） -->
  <!-- 作者、日期等元数据 -->
  <!-- 心迹应用名 -->
</svg>

请直接输出包含相关视觉元素的SVG代码，文字严格按照上述要求：
''';
  }

  /// 内容相关视觉元素增强提示词
  static String contentAwareVisualPrompt({required String content}) {
    return '''
您是一位专业的视觉设计师，擅长将文字内容转化为相关的视觉符号和图形元素。

请分析以下笔记内容，并创建一个包含丰富相关视觉元素的SVG卡片：

##内容分析
$content

##视觉元素创作要求

**第一步：内容主题识别**
- 识别内容的核心主题和关键词
- 分析内容的情感色调（积极/消极/中性）
- 确定内容的类别（学习/工作/生活/情感/技术等）

**第二步：相关图标选择**
根据识别的主题，选择2-3个相关图标：
- 学习：书本、笔记本、灯泡、大脑、学位帽
- 工作：电脑、图表、目标、时钟、文件夹
- 生活：房屋、咖啡杯、植物、音乐符号、相机
- 情感：心形、花朵、星星、彩虹、太阳
- 技术：齿轮、电路、网络、代码符号、芯片
- 自然：树叶、山峰、水滴、云朵、动物
- 运动：跑步、球类、奖杯、健身、户外
- 艺术：画笔、调色板、音符、戏剧面具、相机

**第三步：装饰元素设计**
添加3-5个装饰性元素：
- 几何图形：圆形、三角形、线条、波浪
- 自然元素：叶子、花瓣、星点、光晕
- 抽象图案：渐变形状、纹理、图案
- 连接元素：箭头、线条、路径、网络

**第四步：色彩情感匹配**
- 学习/知识：蓝色系（#3B82F6, #1E40AF, #6366F1）
- 工作/商务：灰蓝系（#475569, #64748B, #334155）
- 生活/温馨：暖色系（#F59E0B, #EF4444, #EC4899）
- 情感/浪漫：粉色系（#F472B6, #EC4899, #BE185D）
- 技术/创新：青色系（#06B6D4, #0891B2, #0E7490）
- 自然/环保：绿色系（#10B981, #059669, #047857）

**第五步：布局设计**
- 顶部区域：主要图标和装饰元素
- 中心区域：文字内容，确保可读性
- 底部区域：次要装饰和信息
- 整体平衡：视觉元素不超过30%的空间占比

##技术实现要求
- SVG尺寸：viewBox="0 0 400 600"
- 包含命名空间：xmlns="http://www.w3.org/2000/svg"
- 元素总数：40-60个，确保性能
- 使用基础SVG元素和渐变效果
- 字体：system-ui, Arial, sans-serif

##文字内容绝对要求（核心规则！）
- **文字内容必须且只能是提供的笔记内容**
- **严格禁止添加任何形式的标题、标签、分类或说明**
- **不允许添加"学习"、"工作"、"生活"、"思考"等分类词汇**
- **不允许添加"内容："、"笔记："、"要点："等前缀**
- **不允许添加"总结"、"感悟"、"心得"等后缀**
- **不允许对原文进行任何形式的修改、总结或解释**
- 原文是什么就显示什么，保持100%的原始性

##输出要求
- 只输出完整的SVG代码
- 不包含markdown标记或解释文字
- 确保视觉元素与内容高度相关
- SVG代码必须有效且可渲染
- 文字部分只显示：笔记内容 + 元数据 + "心迹"

请直接输出包含丰富相关视觉元素的SVG代码，文字严格按照上述要求：
''';
  }
}
