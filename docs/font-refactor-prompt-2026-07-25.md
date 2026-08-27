# FontWeight 重构任务 Prompt

你需要把这个 Flutter 项目中大约 296 处 inline FontWeight 用法重构为 Theme.of(context).textTheme 引用。

## 背景
Flutter 3.41+ 改变了 FontWeight 的渲染行为，导致字体变粗。解决方案是把散落在各处的 hardcoded fontWeight 收口到 theme 统一管理。详细背景见 `squad/font_issue_handoff.md`。

## 你要做什么

### 第一步：搜索网络，了解最新 API
- 搜索 Flutter 3.44 的 TextTheme、ThemeData 最新 API
- 搜索 Material 3 Typography 的 textTheme slot 定义（displayLarge/Medium/Small, headlineLarge/Medium/Small, titleLarge/Medium/Small, bodyLarge/Medium/Small, labelLarge/Medium/Small）
- 确认每个 slot 的默认 fontSize 和 fontWeight
- **不要凭记忆假设，用最新文档**

### 第二步：逐文件替换
运行以下命令找到所有需要改的文件：
```bash
grep -rl "FontWeight\.\(bold\|w600\|w500\)" lib/ --include="*.dart" | grep -v "gen_l10n\|\.mocks\." | sort
```

对每个文件：
1. 读取完整文件，理解每个 FontWeight 的上下文
2. 根据 fontSize + 语义，映射到合适的 textTheme slot：
   - fontSize 20+ bold → titleLarge
   - fontSize 16 bold → titleMedium  
   - fontSize 14 bold → titleSmall
   - fontSize 14 w600 → labelLarge
   - fontSize 12 w500 → labelMedium
   - fontSize 11 w500 → labelSmall
   - 以上只是参考，**以你搜索到的最新 M3 规范为准**
3. 如果有额外样式（color, letterSpacing 等），用 `?.copyWith(color: xxx)` 保留
4. 条件判断型（`isSelected ? FontWeight.bold : FontWeight.normal`）保留 inline，但考虑降档（bold→w600, w600→w500）
5. 确保 widget 的 build 方法有 `context` 可用

### 第三步：不要改的
- `pw.FontWeight.bold`（pdf 库类型）
- `lib/gen_l10n/` 下所有文件
- `*.mocks.dart` 文件
- `lib/theme/app_theme.dart` 中 appBarTheme 的 fontWeight（那是 theme 层本身的设置）

### 第四步：验证
每改完一批文件后运行：
```bash
dart format lib/
flutter analyze --no-fatal-infos
```
确保无编译错误和格式问题。

### 第五步：提交
改完后 commit 并 push：
```bash
git add -A
git commit -m "refactor: 将 inline FontWeight 重构为 Theme.of(context).textTheme 引用

将 ~296 处 hardcoded FontWeight.bold/w600/w500 改为引用 theme textTheme，
使字重统一由主题管理。Flutter 3.41+ FontWeight 精准映射 wght 轴导致
升级后字体变粗，收口到 theme 后可一处调整全局生效。"
git push
```

## 项目规范
- 读一下根目录的 `AGENTS.md`，遵守项目的代码规范
- 代码注释可用中文
- 缩进 2 空格，行宽 80 字符
- UI 可见文本必须用国际化（`AppLocalizations`），不要硬编码
