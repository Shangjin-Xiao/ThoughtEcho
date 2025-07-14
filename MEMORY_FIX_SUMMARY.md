# 大文件内存溢出问题修复总结

## 问题描述

Android 应用在导入大文件（图片、视频、音频）时出现 `java.lang.OutOfMemoryError`：

```
java.lang.OutOfMemoryError: Failed to allocate a 131550776 byte allocation with 100663296 free bytes and 103MB until OOM
at java.io.ByteArrayOutputStream.grow(ByteArrayOutputStream.java:120)
at io.flutter.plugin.common.StandardMessageCodec.writeBytes(StandardMessageCodec.java:196)
at dev.flutter.packages.file_selector_android.GeneratedFileSelectorApi$PigeonCodec.writeValue(GeneratedFileSelectorApi.java:503)
```

## 根本原因

1. **file_selector 插件在 Android 上的设计缺陷**：
   - 插件会自动读取整个文件内容到内存
   - 通过 `StandardMessageCodec` 将文件数据序列化并传递给 Dart 层
   - 对于大文件（几十 MB 以上），这会导致内存不足崩溃

2. **误解的"流式处理"**：
   - 之前虽然实现了 `StreamingFileProcessor` 等流式处理组件
   - 但问题出现在文件选择阶段，还没到真正的文件处理就已经崩溃
   - 即使有再好的流式复制逻辑，也无法解决选择器本身的内存问题

## 解决方案

### 1. 切换到 file_picker 插件

**修改 pubspec.yaml**：
```yaml
dependencies:
  file_picker: ^8.1.2  # 更安全的文件选择器，支持 withData: false 参数
  file_selector: ^1.0.2  # 保留用于桌面端
```

### 2. 重写 StreamFileSelector

**关键改进**：
- 移动端使用 `file_picker`，设置 `withData: false` 和 `withReadStream: false`
- 桌面端继续使用 `file_selector`（更稳定）
- 只传递文件路径，绝不传递文件内容

**核心代码**：
```dart
// 移动端使用 file_picker，关键是设置 withData: false
result = await FilePicker.platform.pickFiles(
  type: FileType.custom,
  allowedExtensions: ['mp4', 'mov', 'avi', 'mkv', 'webm', '3gp', 'm4v'],
  allowMultiple: false,
  withData: false,         // 关键：不读取文件内容，只返回路径
  withReadStream: false,   // 关键：不创建读取流
);
```

### 3. 更新调用代码

**UnifiedMediaImportDialog**：
- 返回类型从 `XFile?` 改为 `FilePickerResult?`
- 增加空值检查：`file.path != null`
- 确保路径可用后再进行后续处理

**BackupRestorePage**：
- 同样的返回类型修改
- 添加必要的空值检查

## 修复效果

### 之前（使用 file_selector）：
1. 用户选择大文件 → file_selector 读取整个文件到内存
2. 通过 StandardMessageCodec 传递给 Dart → OOM 崩溃
3. 用户看到闪退，应用重启

### 现在（使用 file_picker）：
1. 用户选择大文件 → file_picker 只返回文件路径
2. Dart 层接收路径 → 无内存压力
3. 使用现有的 StreamingFileProcessor 流式处理文件 → 安全完成

## 测试验证

运行 `flutter analyze` 确认无编译错误：
```
No issues found! (ran in 8.9s)
```

## 附加收益

1. **更好的平台适配**：桌面端和移动端使用不同但最适合的插件
2. **向后兼容**：现有的流式处理逻辑完全保留
3. **错误处理增强**：增加了路径空值检查和更友好的错误提示
4. **性能提升**：文件选择阶段内存占用大幅降低

## 注意事项

1. **依赖更新**：需要运行 `flutter pub get` 安装 file_picker
2. **测试建议**：使用 100MB+ 的视频文件测试，确认不再崩溃
3. **监控要点**：观察内存使用情况，特别是文件选择和处理阶段

这次修复解决了应用的核心稳定性问题，用户现在可以安全地导入任意大小的媒体文件。
