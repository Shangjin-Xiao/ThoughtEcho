import 'package:flutter/material.dart';
import '../../gen_l10n/app_localizations.dart';

/// 图片文字区域选择组件
/// 
/// 显示检测到的文字区域，用户点选识别
class ImageTextSelector extends StatefulWidget {
  final String imagePath;
  final List<Rect> detectedRegions;
  final Function(Rect)? onRegionSelected;

  const ImageTextSelector({
    super.key,
    required this.imagePath,
    required this.detectedRegions,
    this.onRegionSelected,
  });

  @override
  State<ImageTextSelector> createState() => _ImageTextSelectorState();
}

class _ImageTextSelectorState extends State<ImageTextSelector> {
  int? _selectedRegionIndex;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.ocrSelectRegion),
      ),
      body: Column(
        children: [
          // 提示文本
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              l10n.ocrSelectRegionHint,
              style: theme.textTheme.bodyMedium,
            ),
          ),

          // 图片和文字区域
          Expanded(
            child: Stack(
              children: [
                // TODO: 显示图片 - 后端实现后添加
                Center(
                  child: Container(
                    color: Colors.grey[300],
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.image,
                          size: 64,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          l10n.featureComingSoon,
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // TODO: 文字区域高亮 - 后端实现后添加
                ...widget.detectedRegions.asMap().entries.map((entry) {
                  final index = entry.key;
                  final region = entry.value;
                  final isSelected = _selectedRegionIndex == index;

                  return Positioned(
                    left: region.left,
                    top: region.top,
                    width: region.width,
                    height: region.height,
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedRegionIndex = index;
                        });
                        widget.onRegionSelected?.call(region);
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: isSelected
                                ? theme.colorScheme.primary
                                : theme.colorScheme.outline,
                            width: 2,
                          ),
                          color: isSelected
                              ? theme.colorScheme.primary.withValues(alpha: 0.2)
                              : Colors.transparent,
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),

          // 确认按钮
          if (_selectedRegionIndex != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    Navigator.of(context).pop(_selectedRegionIndex);
                  },
                  child: Text(l10n.confirm),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
