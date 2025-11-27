# ThoughtEcho 国际化使用指南

本目录包含 ThoughtEcho 应用的国际化（i18n）资源文件。

## 文件说明

- `app_zh.arb` - 中文翻译模板（主模板）
- `app_en.arb` - 英文翻译
- `app_localizations.dart` - 生成的国际化代码（自动生成，勿手动修改）
- `app_localizations_zh.dart` - 生成的中文实现（自动生成，勿手动修改）
- `app_localizations_en.dart` - 生成的英文实现（自动生成，勿手动修改）

## 如何添加新的翻译词条

1. 在 `app_zh.arb` 中添加新的键值对：

```json
{
  "@@locale": "zh",
  "newKey": "新文本",
  "@newKey": {
    "description": "新文本的描述（可选）"
  }
}
```

2. 在 `app_en.arb` 中添加对应的英文翻译：

```json
{
  "@@locale": "en",
  "newKey": "New Text"
}
```

3. 运行代码生成命令：

```bash
flutter gen-l10n
```

## 如何在代码中使用翻译

1. 首先导入生成的本地化文件：

```dart
import 'package:thoughtecho/l10n/app_localizations.dart';
```

2. 在 Widget 中使用：

```dart
// 获取本地化实例
final l10n = AppLocalizations.of(context);

// 使用翻译文本
Text(l10n.appTitle)
Text(l10n.cancel)
Text(l10n.confirm)
```

## 带参数的翻译

如果需要带参数的翻译，可以使用占位符：

在 ARB 文件中：
```json
{
  "welcomeMessage": "欢迎，{name}！",
  "@welcomeMessage": {
    "description": "欢迎消息",
    "placeholders": {
      "name": {
        "type": "String",
        "example": "用户"
      }
    }
  }
}
```

在代码中使用：
```dart
Text(l10n.welcomeMessage('张三'))
```

## 复数形式

对于需要处理复数的翻译：

```json
{
  "itemCount": "{count, plural, =0{没有项目} =1{1 个项目} other{{count} 个项目}}",
  "@itemCount": {
    "description": "项目数量",
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  }
}
```

## 配置文件

项目根目录的 `l10n.yaml` 包含国际化配置：

- `arb-dir`: ARB 文件目录
- `template-arb-file`: 主模板文件
- `output-localization-file`: 生成的输出文件名
- `output-class`: 生成的类名
- `preferred-supported-locales`: 首选语言顺序

## 重新生成代码

每次修改 ARB 文件后，运行以下命令重新生成代码：

```bash
flutter gen-l10n
```

或者在运行 `flutter run` 或 `flutter build` 时会自动生成。

## 注意事项

1. 所有翻译键必须在模板文件 `app_zh.arb` 中定义
2. 其他语言文件中的键必须与模板文件中的键匹配
3. 修改 ARB 文件后需要重新运行 `flutter gen-l10n`
4. 生成的 `app_localizations*.dart` 文件由工具自动生成，请勿手动修改
