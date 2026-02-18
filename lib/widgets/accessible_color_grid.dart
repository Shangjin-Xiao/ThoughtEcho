import 'package:flutter/material.dart';
import '../gen_l10n/app_localizations.dart';
import '../utils/color_utils.dart';

class AccessibleColorGrid extends StatelessWidget {
  final String? selectedColorHex;
  final ValueChanged<Color> onColorSelected;

  const AccessibleColorGrid({
    super.key,
    this.selectedColorHex,
    required this.onColorSelected,
  });

  // 预设颜色列表 - 更现代的轻柔色调
  static const List<Color> presetColors = [
    Colors.transparent, // 透明/无
    Color(0xFFF9E4E4), // 轻红色
    Color(0xFFFFF0E1), // 轻橙色
    Color(0xFFFFFBE5), // 轻黄色
    Color(0xFFE8F5E9), // 轻绿色
    Color(0xFFE1F5FE), // 轻蓝色
    Color(0xFFF3E5F5), // 轻紫色
    Color(0xFFFCE4EC), // 轻粉色

    Color(0xFFEF9A9A), // 红色
    Color(0xFFFFCC80), // 橙色
    Color(0xFFFFF59D), // 黄色
    Color(0xFFA5D6A7), // 绿色
    Color(0xFF90CAF9), // 蓝色
    Color(0xFFCE93D8), // 紫色
    Color(0xFFF48FB1), // 粉色

    Color(0xFFD32F2F), // 深红色
    Color(0xFFF57C00), // 深橙色
    Color(0xFFFBC02D), // 深黄色
    Color(0xFF388E3C), // 深绿色
    Color(0xFF1976D2), // 深蓝色
    Color(0xFF7B1FA2), // 深紫色
    Color(0xFFC2185B), // 深粉色
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);

    return Container(
      width: 280,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              l10n.presetColors,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.start,
            children: presetColors.asMap().entries.map((entry) {
              final index = entry.key;
              final color = entry.value;
              String? colorHex;
              if (color != Colors.transparent) {
                colorHex =
                    '#${color.toARGB32().toRadixString(16).substring(2)}';
              }

              final bool isSelected = color == Colors.transparent
                  ? selectedColorHex == null
                  : selectedColorHex == colorHex;

              // Generate accessible label
              String label;
              if (color == Colors.transparent) {
                label = l10n.noColor;
              } else {
                // Try to map colors to simple names based on index/row if possible,
                // or just use generic "Color option X".
                // Row 1 (0-7): Light variants
                // Row 2 (8-14): Normal variants
                // Row 3 (15-21): Deep variants (though duplicates in code)
                // We can use simple heuristics or just index.
                label = '${l10n.color} ${index + 1}';
              }

              return Semantics(
                label: label,
                selected: isSelected,
                button: true,
                child: InkWell(
                  onTap: () => onColorSelected(color),
                  borderRadius: BorderRadius.circular(21),
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(21),
                      border: Border.all(
                        color: isSelected
                            ? colorScheme.primary
                            : color == Colors.transparent
                            ? Colors.grey.applyOpacity(0.5)
                            : Colors.transparent,
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.applyOpacity(0.05),
                          spreadRadius: 1,
                          blurRadius: 3,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Center(
                      child: isSelected
                          ? Icon(
                              Icons.check_circle,
                              color:
                                  color == Colors.transparent ||
                                      color.computeLuminance() > 0.7
                                  ? colorScheme.primary
                                  : Colors.white,
                              size: 24,
                            )
                          : color == Colors.transparent
                          ? const Icon(
                              Icons.block,
                              color: Colors.grey,
                              size: 18,
                            )
                          : null,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
