# 年度报告功能

这是 ThoughtEcho 应用的年度报告功能实现，参考了各大 APP 的年度报告设计风格，结合笔记应用的特点。

## 功能特色

### 🎨 设计亮点
- **多页滑动展示**：7个页面展示不同维度的数据
- **精美动画效果**：渐入动画和页面切换动画
- **响应式设计**：适配不同屏幕尺寸
- **深色模式支持**：自动适配系统主题

### 📊 数据统计
1. **封面页**：年份展示和品牌标识
2. **概览页**：总笔记数、写作天数、最长连续、标签使用
3. **写作习惯**：最活跃时间、喜欢的日子、平均字数、最长笔记
4. **标签分析**：最常用标签的排行和使用频率
5. **时间轴**：12个月的笔记数量变化趋势
6. **深度洞察**：AI分析用户的思考密度、成长轨迹、写作节奏
7. **结束页**：感谢和鼓励继续记录

### 🚀 交互体验
- **触摸翻页**：点击屏幕任意位置进入下一页
- **进度指示**：底部显示当前页面进度
- **分享功能**：可分享年度报告（待实现）
- **震动反馈**：页面切换时提供触觉反馈

## 技术实现

### 数据模型
```dart
class AnnualStats {
  final int year;                    // 年份
  final int totalNotes;             // 总笔记数
  final int activeDays;             // 活跃天数
  final int longestStreak;          // 最长连续天数
  final int totalTags;              // 标签总数
  final double averageWordsPerNote; // 平均每篇字数
  final int longestNoteWords;       // 最长笔记字数
  final int? mostActiveHour;        // 最活跃小时
  final String? mostActiveWeekday;  // 最活跃星期
  final List<TagStat> topTags;      // 热门标签
  final List<MonthlyStat> monthlyStats; // 月度统计
}
```

### 核心算法
- **连续天数计算**：通过日期排序和差值计算得出最长连续记录天数
- **时间分析**：统计每小时和每天的记录频率
- **标签分析**：计算标签使用频率和占比
- **趋势分析**：月度数据对比和增长趋势

### 动画设计
- 使用 `AnimationController` 和 `Tween` 实现复杂动画
- 分阶段延迟动画营造层次感
- 页面切换使用 `PageView` 和缓动曲线

## 使用方法

### 1. 基础使用
```dart
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (context) => AnnualReportPage(
      year: 2024,
      quotes: userQuotes, // 用户的笔记数据
    ),
  ),
);
```

### 2. 演示模式
```dart
// 查看演示页面
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (context) => AnnualReportDemoPage(),
  ),
);
```

### 3. 集成到应用中
在设置页面或主页添加入口：
```dart
ListTile(
  leading: Icon(Icons.analytics),
  title: Text('年度报告'),
  subtitle: Text('查看您的年度数据统计'),
  onTap: () {
    // 从数据库获取当年数据
    final currentYear = DateTime.now().year;
    final quotes = await DatabaseService.getQuotesByYear(currentYear);
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AnnualReportPage(
          year: currentYear,
          quotes: quotes,
        ),
      ),
    );
  },
)
```

## 扩展功能

### 计划中的功能
- [ ] 分享到社交媒体
- [ ] 保存为图片
- [ ] 多年度对比
- [ ] 自定义报告样式
- [ ] AI 生成个性化洞察
- [ ] 导出PDF报告

### 自定义选项
- 修改颜色主题
- 调整页面内容
- 添加新的统计维度
- 自定义洞察文案

## 注意事项

1. **性能优化**：大量数据时建议添加分页加载
2. **内存管理**：注意 AnimationController 的释放
3. **兼容性**：确保在不同 Flutter 版本下正常运行
4. **数据安全**：用户数据仅在本地处理，不上传到服务器

## 设计参考

本功能设计参考了以下 APP 的年度报告：
- 网易云音乐年度报告
- 支付宝年度账单
- 微信读书年度报告
- GitHub Contributions
- Spotify Wrapped

结合 ThoughtEcho 笔记应用的特点，专注于思考轨迹和写作习惯的展示。
