# AI笔记卡片生成功能设计文档

## 功能概述

将AI卡片生成功能集成到现有应用中，提供两个主要使用场景：
1. **分享功能增强** - 在笔记分享时提供AI生成卡片选项
2. **AI周期报告** - 在周报/月报中展示精选笔记卡片

## 核心功能设计

### 1. AI卡片生成服务

```dart
class AICardGenerationService {
  // 为单条笔记生成卡片
  Future<GeneratedCard> generateCard(Quote note);
  
  // 为周期报告生成精选卡片
  Future<List<GeneratedCard>> generateFeaturedCards(
    List<Quote> notes, 
    {int maxCards = 6}
  );
  
  // 保存卡片为图片
  Future<String> saveCardAsImage(GeneratedCard card);
}
```

### 2. 数据模型

```dart
class GeneratedCard {
  final String noteId;
  final String originalContent;    // 保持原始笔记内容
  final CardVisualStyle style;     // AI生成的视觉样式
  final Widget cardWidget;         // 渲染的卡片组件
}

class CardVisualStyle {
  final Color primaryColor;
  final Color backgroundColor;
  final String backgroundType;     // gradient/pattern/solid
  final Map<String, dynamic> backgroundConfig;
  final String iconType;
  final List<String> decorations;
}
```

## 集成点设计

### 1. 分享功能集成

#### 1.1 笔记详情页分享菜单
```dart
// 在现有的分享选项中添加
PopupMenuItem(
  value: 'share_card',
  child: ListTile(
    leading: Icon(Icons.auto_awesome),
    title: Text('生成卡片分享'),
  ),
),
```

#### 1.2 分享流程
```
用户点击"生成卡片分享" 
→ AI分析笔记内容生成卡片样式
→ 显示卡片预览
→ 用户确认后保存/分享图片
```

### 2. AI周期报告集成

#### 2.1 报告页面结构
```dart
class AIPeriodicReportPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          _buildTimeSelector(),      // 周/月选择
          _buildDataOverview(),      // 数据概览
          _buildFeaturedCards(),     // AI生成的精选卡片
          _buildInsights(),          // AI洞察分析
        ],
      ),
    );
  }
}
```

#### 2.2 卡片展示区域
```dart
Widget _buildFeaturedCards() {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          '精选笔记',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
      Container(
        height: 200,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(horizontal: 16),
          itemBuilder: (context, index) {
            return Container(
              width: 160,
              margin: EdgeInsets.only(right: 12),
              child: AIGeneratedCardWidget(card: featuredCards[index]),
            );
          },
        ),
      ),
    ],
  );
}
```

## AI实现策略

### 1. 卡片生成提示词

```
你是一位UI设计师，为这条笔记设计精美卡片：

笔记内容："${note.content}"
笔记信息：时间${note.date}，分类${note.category}

设计要求：
1. 根据内容情感选择合适配色
2. 选择与主题相关的背景样式  
3. 确保文字清晰易读
4. 整体现代美观

返回JSON格式设计参数：
{
  "primaryColor": "#hex值",
  "backgroundColor": "#hex值", 
  "backgroundType": "gradient/pattern/solid",
  "backgroundConfig": {...},
  "decorations": [...]
}
```

### 2. 笔记筛选策略

```
分析这些笔记，选出最适合制作卡片的6条：

筛选标准：
1. 内容有深度或特别有趣
2. 情感积极或有启发性
3. 主题多样化，避免重复
4. 长度适中，适合卡片展示

返回选中笔记的ID和理由。
```

## 技术实现

### 1. 卡片渲染组件

```dart
class AIGeneratedCardWidget extends StatelessWidget {
  final GeneratedCard card;
  
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: card.style.primaryColor.withOpacity(0.2),
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            // AI生成的背景
            _buildDynamicBackground(card.style),
            
            // 笔记内容
            Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                card.originalContent,
                style: TextStyle(
                  color: card.style.textColor,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ),
            
            // 装饰元素
            ..._buildDecorations(card.style.decorations),
          ],
        ),
      ),
    );
  }
}
```

### 2. 背景生成器

```dart
class DynamicBackgroundGenerator {
  Widget generate(CardVisualStyle style) {
    switch (style.backgroundType) {
      case 'gradient':
        return _buildGradient(style.backgroundConfig);
      case 'pattern':
        return _buildPattern(style.backgroundConfig);
      case 'solid':
        return Container(color: style.backgroundColor);
      default:
        return Container(color: Colors.white);
    }
  }
}
```

## 用户体验流程

### 1. 分享场景
```
笔记详情页 → 点击分享 → 选择"生成卡片分享" 
→ AI生成卡片（2-3秒）→ 预览确认 → 保存/分享图片
```

### 2. 报告场景
```
AI功能页 → 周期报告 → 选择时间范围 
→ AI分析生成报告和精选卡片 → 浏览卡片 → 可单独分享卡片
```

## 设置选项

在AI设置页面添加：
```dart
SwitchListTile(
  title: Text('AI卡片生成'),
  subtitle: Text('允许将笔记生成为精美分享卡片'),
  value: settings.enableAICardGeneration,
  onChanged: (value) => updateSetting(value),
),
```

## 实现优先级

### Phase 1: 核心功能 (2周)
1. 实现AICardGenerationService
2. 创建基础的卡片渲染组件
3. 设计AI生成提示词

### Phase 2: 分享集成 (1周)
1. 在笔记分享菜单中添加卡片选项
2. 实现卡片预览和保存功能
3. 集成到现有分享流程

### Phase 3: 报告集成 (1周)
1. 在AI周期报告中添加精选卡片区域
2. 实现笔记筛选和批量卡片生成
3. 优化展示效果和交互

### Phase 4: 优化完善 (1周)
1. 性能优化和缓存机制
2. 用户体验细节调整
3. 错误处理和异常情况

## 总结

这个功能将AI卡片生成无缝集成到现有应用中，通过两个关键入口（分享功能和周期报告）为用户提供价值。设计简洁实用，避免过度复杂化，专注于核心用户需求：美化分享和精选展示。