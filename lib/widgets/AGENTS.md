# WIDGETS 模块

可复用 UI 组件层。拆分子目录：`note_list/`（5 文件）、`common/`、`local_ai/`、`onboarding/`。

## 复杂度警告
`add_note_dialog.dart`（88k+ 行）和 `quote_item_widget.dart`（40k+ 行）是最大 Widget 文件，修改前确认影响范围。

## 规范
- **单一职责**：build 方法不超过 50 行，能 `StatelessWidget` 就不用 `StatefulWidget`
- **国际化（严格）**：所有用户可见文本必须 `AppLocalizations.of(context)!.xxx`，Tooltip/SemanticsLabel 同理
- **颜色**：`Theme.of(context).colorScheme`，禁止硬编码
- **长列表**：必须 `ListView.builder`，禁止 `Column(children: map.toList())`
- **mounted 检查**：async 后访问 context 前必须 `if (mounted)`
- **动画**：复杂用 `LottieAnimationWidget`，简单用 `AnimatedContainer/Opacity`，自定义 `AnimationController` 必须 `dispose()`
- **Service 访问**：读取用 `context.read<>()`，监听用 `context.watch<>()` 或 `Consumer<>`
