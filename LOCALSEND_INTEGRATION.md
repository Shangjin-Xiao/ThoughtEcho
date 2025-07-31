# LocalSend Integration Documentation

## 概述

本文档描述了在ThoughtEcho（心迹）笔记应用中集成LocalSend本地同步功能的完整实现方案。

## 实现的功能

### 核心服务

#### LocalSendService
统一的LocalSend服务，提供完整的笔记和媒体文件同步功能：

- **设备发现**: 使用mDNS协议自动发现局域网中的设备
- **笔记同步**: 支持JSON格式的笔记数据传输，包含富文本内容
- **媒体文件传输**: 自动收集并传输笔记中的图片、音频、视频文件
- **进度跟踪**: 实时显示传输进度和状态
- **错误处理**: 完善的异常处理和日志记录

#### 主要功能特性

1. **发送功能**
   - 笔记选择界面，支持多选和全选
   - 设备扫描和选择
   - 媒体文件自动收集
   - 实时传输进度显示

2. **接收功能**
   - 自动启动接收服务器
   - 支持JSON格式笔记导入
   - 媒体文件自动保存到应用目录
   - 导入进度显示

3. **用户界面**
   - 双标签页设计（发送/接收）
   - 服务器状态指示器
   - 设备列表显示
   - 操作说明卡片

### 集成点

#### 1. 主应用Provider集成
在`main.dart`中添加了`LocalSendService`到Provider系统：

```dart
ChangeNotifierProvider(create: (_) => localSendService),
```

#### 2. 笔记项目上下文菜单
在`QuoteItemWidget`中添加了"局域网同步"选项：

```dart
PopupMenuItem<String>(
  value: 'local_sync',
  child: Row(
    children: [
      Icon(Icons.wifi, color: theme.colorScheme.primary),
      const SizedBox(width: 8),
      const Text('局域网同步'),
    ],
  ),
),
```

#### 3. 主界面导航
在`HomePage`中添加了同步页面导航功能：

```dart
void _showLocalSyncPage(Quote quote) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (context) => const NoteSyncPage()),
  );
}
```

### 技术架构

#### 服务依赖关系
```
LocalSendService
├── DatabaseService (笔记数据操作)
├── MediaFileService (媒体文件管理)
├── LocalSendServer (接收服务器)
└── LocalSendSendProvider (发送功能)
```

#### 数据流
1. **发送流程**:
   用户选择笔记 → 扫描设备 → 导出JSON → 收集媒体文件 → 传输文件

2. **接收流程**:
   启动服务器 → 接收文件 → 解析JSON → 导入笔记 → 保存媒体文件

### 文件结构

#### 新增文件
- `lib/services/localsend_service.dart` - 统一的LocalSend服务
- `lib/pages/note_sync_page.dart` - 同步页面UI（已更新）

#### 修改文件
- `lib/main.dart` - 添加Provider注册和服务初始化
- `lib/widgets/quote_item_widget.dart` - 添加同步菜单项
- `lib/widgets/note_list_view.dart` - 传递同步回调
- `lib/pages/home_page.dart` - 添加同步页面导航
- `lib/services/media_file_service.dart` - 转换为实例服务

### 兼容性保证

#### 现有架构兼容
- 保持现有的Provider模式和ChangeNotifier架构
- 复用现有的DatabaseService和MediaFileService
- 遵循项目的日志和错误处理模式

#### 数据格式兼容
- 使用项目现有的Quote模型
- 支持富文本（deltaContent）传输
- 保持标签和分类信息完整性

### 配置和部署

#### 依赖要求
需要确保以下LocalSend相关包已正确配置在`pubspec.yaml`中：
- LocalSend核心库
- mDNS发现库
- 网络通信库

#### 权限要求
- 网络访问权限
- 本地存储权限
- WiFi状态访问权限

### 使用说明

#### 发送笔记
1. 在笔记列表中，点击笔记的"更多"菜单
2. 选择"局域网同步"
3. 在同步页面选择要发送的笔记
4. 扫描并选择目标设备
5. 确认发送

#### 接收笔记
1. 进入同步页面的"接收"标签
2. 点击"启动接收"开启服务器
3. 等待其他设备发送文件
4. 接收到的笔记会自动导入

### 错误处理

#### 常见问题
1. **设备发现失败**: 检查WiFi连接和网络权限
2. **传输中断**: 自动重试机制和状态恢复
3. **媒体文件缺失**: 错误日志记录和用户提示
4. **JSON格式错误**: 兼容性检查和降级处理

#### 日志记录
所有操作都会记录到应用的统一日志系统，包括：
- 设备发现日志
- 传输进度日志
- 错误和异常日志
- 性能统计日志

### 测试建议

#### 功能测试
1. 单设备服务器启动/停止测试
2. 多设备发现和连接测试
3. 不同大小笔记的传输测试
4. 媒体文件传输测试
5. 网络中断恢复测试

#### 性能测试
1. 大量笔记选择性能
2. 大文件传输内存使用
3. 长时间运行稳定性
4. 并发传输处理能力

### 维护和扩展

#### 代码维护
- 遵循项目现有的代码风格
- 定期更新LocalSend依赖版本
- 监控网络API变化

#### 功能扩展
- 支持增量同步
- 添加同步历史记录
- 实现自动发现和配对
- 支持更多文件格式

## 结论

LocalSend集成已完全集成到ThoughtEcho应用中，提供了完整的本地局域网同步功能。该实现保持了与现有架构的兼容性，提供了良好的用户体验，并具有良好的可维护性和可扩展性。

所有更改都经过仔细设计，确保不影响现有功能的同时，为用户提供了强大的本地同步能力。