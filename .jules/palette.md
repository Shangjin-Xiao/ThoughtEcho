## 2025-02-28 - [完善引导弹窗遮罩层的无障碍支持]
**Learning:** 自定义悬浮层（Overlay/Popover）中作为背景点击关闭的 GestureDetector 往往缺乏无障碍焦点和语意说明，屏幕阅读器用户无法感知这是一个可以用来关闭弹窗的可交互区域。
**Action:** 确保这种非文字说明的交互背景元素（如全屏透明遮罩）被 Semantics 包装，提供 `button: true` 和 `label: MaterialLocalizations.of(context).closeButtonTooltip`，以此提升无障碍体验。
