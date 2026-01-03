import 'dart:io';
import 'dart:ui' as ui;

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

  ui.Size? _imageSize;
  bool _loadingImage = true;

  @override
  void initState() {
    super.initState();
    _loadImageSize();
  }

  Future<void> _loadImageSize() async {
    try {
      final bytes = await File(widget.imagePath).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      if (!mounted) return;
      setState(() {
        _imageSize = ui.Size(
          frame.image.width.toDouble(),
          frame.image.height.toDouble(),
        );
        _loadingImage = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _imageSize = null;
        _loadingImage = false;
      });
    }
  }

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
            child: _loadingImage
                ? const Center(child: CircularProgressIndicator())
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final imageSize = _imageSize;
                      if (imageSize == null ||
                          imageSize.width <= 0 ||
                          imageSize.height <= 0) {
                        return Center(
                          child: Text(l10n.getDataFailed),
                        );
                      }

                      final maxW = constraints.maxWidth;
                      final maxH = constraints.maxHeight;
                      final scale =
                          (maxW / imageSize.width).clamp(0.0, double.infinity);
                      final scaleH =
                          (maxH / imageSize.height).clamp(0.0, double.infinity);
                      final s = scale < scaleH ? scale : scaleH;

                      final displayW = imageSize.width * s;
                      final displayH = imageSize.height * s;

                      final dx = (maxW - displayW) / 2.0;
                      final dy = (maxH - displayH) / 2.0;

                      return Stack(
                        children: [
                          Positioned.fill(
                            child: Center(
                              child: SizedBox(
                                width: displayW,
                                height: displayH,
                                child: Image.file(
                                  File(widget.imagePath),
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                          ),

                          // 文字区域高亮
                          ...widget.detectedRegions.asMap().entries.map((entry) {
                            final index = entry.key;
                            final region = entry.value;
                            final isSelected = _selectedRegionIndex == index;

                            final left = dx + region.left * s;
                            final top = dy + region.top * s;
                            final width = region.width * s;
                            final height = region.height * s;

                            return Positioned(
                              left: left,
                              top: top,
                              width: width,
                              height: height,
                              child: GestureDetector(
                                behavior: HitTestBehavior.translucent,
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
                                        ? theme.colorScheme.primary
                                            .withOpacity(0.18)
                                        : Colors.transparent,
                                  ),
                                ),
                              ),
                            );
                          }),
                        ],
                      );
                    },
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
