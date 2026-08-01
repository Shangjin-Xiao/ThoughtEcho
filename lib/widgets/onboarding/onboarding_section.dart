import 'package:flutter/material.dart';

/// 引导页第 2、3 屏共用的骨架：标题区 + 可滚动内容。
///
/// 两屏用同一个骨架，是为了让它们的标题字号、留白和滚动边距完全一致——
/// 各写各的必然会漂移，用户翻页时会看到标题「跳」一下。
///
/// [bottomInset] 给底部悬浮导航条让位：导航条是 `Positioned` 浮在 `PageView`
/// 之上的，内容不预留这段高度的话，最后一张卡片会被压在导航条底下够不着。
class OnboardingPageScaffold extends StatelessWidget {
  const OnboardingPageScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    this.description,
    required this.children,
    this.bottomInset = 120,
  });

  final String title;
  final String subtitle;
  final String? description;
  final List<Widget> children;
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24, 32, 24, bottomInset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (description != null) ...[
            const SizedBox(height: 4),
            Text(
              description!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 28),
          ...children,
        ],
      ),
    );
  }
}

/// 一块设置分区：图标 + 标题 + 可选说明，下面是内容。
///
/// 用 `Card` 而不是自己搭 `Container` + `BoxDecoration`：`cardTheme` 已经按风格
/// 配好了描边与投影（手工风格发丝边+零投影，material 走投影），自己再搭一套的结果
/// 就是和同屏其它卡片的圆角、高光对不齐。`Card` 本身是 `Material`，顺带解决了
/// 内部 `RadioListTile` / 水波纹需要 `Material` 祖先的问题。
class OnboardingSection extends StatelessWidget {
  const OnboardingSection({
    super.key,
    required this.icon,
    required this.title,
    this.description,
    this.child,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String? description;

  /// 分区内容。开关型分区只有标题和 [trailing]，没有内容体，传 null。
  final Widget? child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleSmall),
                      if (description != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          description!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 8),
                  trailing!,
                ],
              ],
            ),
            if (child != null) ...[
              const SizedBox(height: 16),
              child!,
            ],
          ],
        ),
      ),
    );
  }
}
