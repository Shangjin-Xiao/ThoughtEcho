# 心迹（ThoughtEcho）项目 - GitHub Copilot 自定义指令

## 项目概述

心迹（ThoughtEcho）是一款基于Flutter开发的本地优先笔记应用，专注于帮助用户捕捉思维火花，整理个人思考，并通过AI技术提供内容分析和智能洞察。应用采用本地存储优先策略，确保用户数据隐私和离线可用性。

## 代码风格指南

### Dart & Flutter 规范
- 遵循 Dart 官方代码风格指南
- 使用 flutter_lints 包确保代码质量
- 所有类和公共方法必须添加文档注释
- 使用 Provider 进行状态管理，避免复杂的状态逻辑
- 异步操作使用 async/await，避免嵌套回调

### 命名约定
- 使用 `camelCase` 命名变量和函数
- 使用 `PascalCase` 命名类和枚举
- 使用 `snake_case` 命名文件和数据库字段
- 使用有意义的描述性名称，避免缩写
- 私有变量和方法使用下划线前缀（`_privateMethod`）

### UI 开发规范
- 使用 Material 3 设计，优先采用 Flutter 官方组件
- 确保所有界面元素适配不同屏幕尺寸
- 使用 SizedBox 和 Padding 而非 EdgeInsets 直接设置间距
- 抽取重复的UI组件为独立widget
- 使用 MediaQuery 进行响应式设计

### 数据处理
- 使用 sqflite 进行本地数据存储
- 数据库操作封装在 DatabaseService 中
- 模型类使用不可变模式（immutable pattern）
- 使用 fromJson/toJson 方法进行序列化
- 所有非简单查询操作应包含在事务中

### 错误处理
- 使用 try/catch 块捕获异常
- 记录错误信息到日志系统（LogService）
- 向用户提供友好的错误信息
- 实现错误恢复机制，特别是数据库操作
- 全局错误处理器用于未捕获的异常

## 项目架构指南

### 分层架构
- **UI层**：页面（pages）和可重用组件（widgets）
- **业务逻辑层**：服务（services）和提供者（providers）
- **数据层**：数据模型（models）和存储服务（database_service）

### 文件组织
- 将相关功能代码放在同一目录下
- 使用特性驱动的目录结构
- 按文件类型和功能组织代码
- 保持目录层次简单，避免过深嵌套

### 依赖注入
- 使用 Provider 进行依赖注入
- 避免硬编码依赖，使用接口而非实现
- 服务初始化应在应用启动时完成

## 技术栈指南

### 核心依赖
- Flutter 3.19+ 框架
- Provider 状态管理
- sqflite 本地数据库
- http 网络请求
- flutter_quill 富文本编辑
- geolocator 位置服务
- mmkv 高性能存储

### 界面组件
- flex_color_scheme 主题管理
- dynamic_color Material You支持
- flutter_markdown Markdown渲染
- lottie 动画效果
- flutter_spinkit 加载动画
- flutter_svg SVG图像支持

### 平台特定代码
- 使用条件导入处理平台特定代码
- Web平台使用内存数据库代替SQLite
- 移动平台使用原生API获取位置和权限

## 功能实现指南

### 笔记功能
- 笔记内容存储在quotes表中
- 支持富文本编辑和纯文本模式
- 笔记可添加多个标签（通过tag_ids字段）
- 实现笔记内容的全文搜索
- 提供多种排序和筛选方式

### AI功能
- 使用HTTPS请求调用外部AI API
- 提示词模板存储在本地
- 异步处理AI响应，避免UI阻塞
- 提供分析结果的缓存机制
- 支持关键词提取、情感分析和内容摘要

### 环境感知功能
- 使用geolocator获取位置信息
- 使用geocoding进行地理编码
- 通过API获取天气信息
- 位置和天气信息与笔记关联

### 数据备份
- 数据导出为JSON格式文件
- 支持增量备份和全量备份
- 提供数据导入时的冲突解决策略
- 实现数据库迁移和版本控制

## 测试指南

### 单元测试
- 为所有服务类编写单元测试
- 使用mock对象模拟依赖
- 测试各种边界条件和错误情况
- 使用测试组织函数group和test

### 集成测试
- 测试关键用户流程
- 验证UI与后端服务的交互
- 使用WidgetTester进行界面测试
- 检查性能指标是否满足要求

## 常见模式与示例

### 服务类模板
```dart
class ServiceName with ChangeNotifier {
  // 单例模式
  static ServiceName? _instance;
  
  static ServiceName get instance {
    _instance ??= ServiceName();
    return _instance;
  }
  
  factory ServiceName() => instance;

  // 依赖项
  final _otherService = OtherService();

  // 初始化方法
  Future<void> initialize() async {
    try {
      // 初始化逻辑
    } catch (e) {
      LogService().logError('ServiceName初始化失败', e);
      rethrow;
    }
  }

  // 服务方法
  Future<ReturnType> methodName(ParamType param) async {
    try {
      // 方法实现
      return result;
    } catch (e) {
      LogService().logError('methodName失败', e);
      throw Exception('操作失败: $e');
    }
  }
}
```

### 数据模型模板
```dart
class ModelName {
  final String id;
  final String name;
  final String? optionalField;

  const ModelName({
    required this.id,
    required this.name,
    this.optionalField,
  });

  // 从JSON构造
  factory ModelName.fromJson(Map<String, dynamic> json) => ModelName(
    id: json['id'],
    name: json['name'],
    optionalField: json['optional_field'],
  );

  // 转换为JSON
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'optional_field': optionalField,
  };

  // 复制方法
  ModelName copyWith({
    String? id,
    String? name,
    String? optionalField,
  }) {
    return ModelName(
      id: id ?? this.id,
      name: name ?? this.name,
      optionalField: optionalField ?? this.optionalField,
    );
  }
}
```

### 页面模板
```dart
class PageName extends StatefulWidget {
  const PageName({super.key});

  @override
  State<PageName> createState() => _PageNameState();
}

class _PageNameState extends State<PageName> {
  // 状态变量
  bool _isLoading = false;
  
  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // 加载数据
    } catch (e) {
      // 错误处理
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('页面标题')),
      body: _isLoading
          ? const AppLoadingView()
          : _buildContent(),
      floatingActionButton: FloatingActionButton(
        onPressed: _onActionPressed,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildContent() {
    // 构建页面内容
    return Container();
  }

  void _onActionPressed() {
    // 处理操作
  }
}
```

### 对话框模板
```dart
Future<T?> showCustomDialog<T>(BuildContext context) {
  return showDialog<T>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('对话框标题'),
      content: const Text('对话框内容'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () {
            // 执行操作
            Navigator.of(context).pop(result);
          },
          child: const Text('确定'),
        },
      ],
    ),
  );
}
```

### 数据库操作模板
```dart
// 在DatabaseService类中
Future<List<Quote>> getQuotes({
  int? limit,
  int? offset,
  String? searchTerm,
  List<String>? tagIds,
  String orderBy = 'date',
  bool ascending = false,
}) async {
  final db = await database;
  String query = 'SELECT * FROM quotes';
  List<dynamic> args = [];

  // 构建WHERE子句
  List<String> whereClauses = [];
  
  if (searchTerm != null && searchTerm.isNotEmpty) {
    whereClauses.add('content LIKE ?');
    args.add('%$searchTerm%');
  }
  
  if (tagIds != null && tagIds.isNotEmpty) {
    List<String> tagClauses = [];
    for (var tagId in tagIds) {
      tagClauses.add('tag_ids LIKE ?');
      args.add('%$tagId%');
    }
    whereClauses.add('(${tagClauses.join(' OR ')})');
  }
  
  if (whereClauses.isNotEmpty) {
    query += ' WHERE ${whereClauses.join(' AND ')}';
  }
  
  // 排序
  query += ' ORDER BY $orderBy ${ascending ? 'ASC' : 'DESC'}';
  
  // 分页
  if (limit != null) {
    query += ' LIMIT ?';
    args.add(limit);
    
    if (offset != null) {
      query += ' OFFSET ?';
      args.add(offset);
    }
  }
  
  final result = await db.rawQuery(query, args);
  return result.map((json) => Quote.fromJson(json)).toList();
}
```

## 最佳实践

### 性能优化
- 使用 `const` 构造器提高性能
- 实现 `==` 和 `hashCode` 优化列表性能
- 避免不必要的重建（rebuilds）
- 使用懒加载和分页加载大量数据
- 缓存计算结果和网络请求

### 安全性
- 敏感数据使用 flutter_secure_storage 存储
- API密钥不应硬编码在应用中
- 数据库访问添加错误处理
- 验证用户输入，防止安全漏洞
- 遵循最小权限原则

### 可访问性
- 添加语义标签（semantics）
- 支持屏幕阅读器
- 提供足够的颜色对比度
- 适当的点击目标大小
- 支持动态文本缩放

### 国际化
- 使用 intl 包处理翻译
- 外部化所有用户可见的字符串
- 考虑文本长度变化的布局适应
- 支持RTL（从右到左）语言
- 适配不同的日期和数字格式
