# 心迹年度报告生成提示词

## 任务说明
你需要根据用户的笔记数据，生成一份类似年度报告的HTML页面。请使用提供的HTML模板，将其中的示例数据替换为基于用户真实数据分析得出的内容。

## 数据分析要求

### 1. 基础统计数据
- 计算总笔记数量
- 统计有效记录天数
- 计算使用的标签数量
- 分析月度笔记数量分布
- 与去年同期对比（如果有历史数据）

### 2. 标签使用分析
- 找出使用频率最高的标签（前10个）
- 分析标签使用趋势
- 识别用户最关注的主题领域
- 计算每个标签对应的笔记数量

### 3. 写作习惯分析
- 分析用户最活跃的记录时间段
- 计算平均笔记长度
- 统计最长的连续记录天数
- 分析笔记创建的时间模式

### 4. 内容质量分析
- 识别较长的深度思考笔记（字数超过平均值1.5倍）
- 选择正面积极的笔记内容作为年度回顾
- 避免选择消极、负面或私密的内容
- 优先选择包含成长、学习、感悟类型的笔记

## 内容替换指南

### HTML模板中需要替换的数据点：
1. **年度标题**: 将"2024"替换为实际年份
2. **基础统计**: 
   - 记录天数
   - 总笔记数
   - 使用标签数
3. **月度数据**: 替换12个月的笔记数量
4. **标签云**: 替换为用户实际使用的热门标签
5. **精彩回顾**: 选择3-5条积极正面的笔记内容
6. **成就数据**: 根据实际情况调整成就描述和数字
7. **增长指标**: 计算同比增长百分比

### 内容选择原则：
1. **积极导向**: 优先选择正面、积极、成长相关的内容
2. **隐私保护**: 避免过于私密或敏感的个人信息
3. **代表性**: 选择能代表用户全年思考轨迹的内容
4. **多样性**: 涵盖不同主题和时间段的内容

## 输出格式
直接输出完整的HTML代码，确保：
1. 所有示例数据都被替换为真实数据
2. HTML结构完整，样式保持不变
3. 内容积极正面，符合年度总结的氛围
4. 数据准确，计算无误

## 注意事项
1. 如果某些数据不足，可以用合理的方式处理（如"暂无数据"）
2. 保持HTML的响应式设计和移动端适配
3. 确保所有文本内容都是中文
4. 日期格式使用"YYYY年MM月DD日"
5. 数字较大时使用千分位分隔符（如1,247）

## 示例数据说明
模板中的所有数字和内容都是示例，需要根据用户实际数据进行替换：
- 总笔记数: 1,247 → 用户实际笔记数
- 记录天数: 365 → 实际有笔记的天数
- 标签数: 89 → 用户实际使用的标签数
- 月度数据: 需要根据实际每月笔记数量调整
- 笔记内容: 需要选择用户实际的正面笔记内容
