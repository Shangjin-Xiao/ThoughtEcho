# ThoughtEcho 国际化指南

## 如何使用

在 Widget 中使用翻译文本：

```dart
import 'package:thoughtecho/l10n/app_localizations.dart';

// 在 build 方法中
Text(S.of(context).appTitle)
```

## 添加新的翻译

1. 在 `app_zh.arb` 中添加中文文本和描述
2. 在 `app_en.arb` 中添加对应的英文翻译
3. 运行 `flutter gen-l10n` 生成代码
4. 在代码中使用 `S.of(context).yourKey`

## 文件说明

- `app_zh.arb` - 中文翻译（模板文件）
- `app_en.arb` - 英文翻译
- `app_localizations.dart` - 自动生成，不要手动编辑
