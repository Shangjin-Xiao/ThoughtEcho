/// 文字区域高亮叠加层
///
/// 在图片上显示检测到的文字块，带有精美的高亮效果

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../models/ocr_result.dart';
import '../../gen_l10n/app_localizations.dart';

/// 文字块高亮叠加层
class TextBlockOverlay extends StatefulWidget {
  final String imagePath;
  final OCRResult ocrResult;
  final Function(Set<int>)? onSelectionChanged;

  const TextBlockOverlay({
    super.key,
    required this.imagePath,
    required this.ocrResult,
    this.onSelectionChanged,
  });

  @override
  State<TextBlockOverlay> createState() => _TextBlockOverlayState();
}

class _TextBlockOverlayState extends State<TextBlockOverlay>
    with SingleTickerProviderStateMixin {
  final Set<int> _selectedBlocks = {};
  ui.Image? _imageInfo;
  bool _imageLoaded = false;
  late AnimationController _animationController;
  final GlobalKey _imageKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..repeat(reverse: true);
    _loadImage();
    // 默认全选
    _selectedBlocks.addAll(
      List.generate(widget.ocrResult.blocks.length, (i) => i),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    _imageInfo?.dispose();
    super.dispose();
  }

  Future<void> _loadImage() async {
    final file = File(widget.imagePath);
    final bytes = await file.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    setState(() {
      _imageInfo = frame.image;
      _imageLoaded = true;
    });
  }

  void _toggleBlock(int index) {
    setState(() {
      if (_selectedBlocks.contains(index)) {
        _selectedBlocks.remove(index);
      } else {
        _selectedBlocks.add(index);
      }
    });
    widget.onSelectionChanged?.call(_selectedBlocks);
  }

  void _selectAll() {
    setState(() {
      _selectedBlocks.addAll(
        List.generate(widget.ocrResult.blocks.length, (i) => i),
      );
    });
    widget.onSelectionChanged?.call(_selectedBlocks);
  }

  void _deselectAll() {
    setState(() {
      _selectedBlocks.clear();
    });
    widget.onSelectionChanged?.call(_selectedBlocks);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(l10n.ocrSelectRegion),
        backgroundColor: Colors.black,
        actions: [
          TextButton(
            onPressed: _deselectAll,
            child: Text(
              '清空',
              style: TextStyle(color: theme.colorScheme.primary),
            ),
          ),
          TextButton(
            onPressed: _selectAll,
            child: Text(
              '全选',
              style: TextStyle(color: theme.colorScheme.primary),
            ),
          ),
        ],
      ),
      body: !_imageLoaded
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // 提示栏
                Container(
                  width: double.infinity,
                  color: theme.colorScheme.primaryContainer.withOpacity(0.9),
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.touch_app,
                        size: 20,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '点击选择文字区域 · 已选 ${_selectedBlocks.length}/${widget.ocrResult.blocks.length}',
                          style: TextStyle(
                            color: theme.colorScheme.onPrimaryContainer,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // 图片 + 文字块叠加
                Expanded(
                  child: InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 4.0,
                    child: Center(
                      child: CustomPaint(
                        painter: _TextBlockPainter(
                          imageInfo: _imageInfo!,
                          blocks: widget.ocrResult.blocks,
                          selectedIndices: _selectedBlocks,
                          animation: _animationController,
                        ),
                        child: GestureDetector(
                          key: _imageKey,
                          onTapUp: (details) =>
                              _handleTap(details.localPosition),
                          child: Image.file(
                            File(widget.imagePath),
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // 底部按钮
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 8,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: FilledButton.icon(
                    onPressed: _selectedBlocks.isEmpty
                        ? null
                        : () => Navigator.of(context).pop(_selectedBlocks),
                    icon: const Icon(Icons.check),
                    label: Text('确认选择 (${_selectedBlocks.length})'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  void _handleTap(Offset position) {
    if (_imageInfo == null) return;

    final RenderBox? renderBox =
        _imageKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final Size displayedSize = renderBox.size;
    final double scaleX = displayedSize.width / _imageInfo!.width;
    final double scaleY = displayedSize.height / _imageInfo!.height;

    // Convert tap position to image coordinates
    final double imageX = position.dx / scaleX;
    final double imageY = position.dy / scaleY;

    final Offset imagePosition = Offset(imageX, imageY);

    // 找到被点击的文字块
    for (int i = 0; i < widget.ocrResult.blocks.length; i++) {
      final block = widget.ocrResult.blocks[i];
      if (block.boundingBox.contains(imagePosition)) {
        _toggleBlock(i);
        return;
      }
    }
  }
}

/// 文字块绘制器
class _TextBlockPainter extends CustomPainter {
  final ui.Image imageInfo;
  final List<TextBlock> blocks;
  final Set<int> selectedIndices;
  final Animation<double> animation;

  _TextBlockPainter({
    required this.imageInfo,
    required this.blocks,
    required this.selectedIndices,
    required this.animation,
  }) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final imageSize = Size(
      imageInfo.width.toDouble(),
      imageInfo.height.toDouble(),
    );

    // 计算缩放比例
    final scaleX = size.width / imageSize.width;
    final scaleY = size.height / imageSize.height;

    for (int i = 0; i < blocks.length; i++) {
      final block = blocks[i];
      final isSelected = selectedIndices.contains(i);

      // 缩放边界框
      final scaledRect = Rect.fromLTRB(
        block.boundingBox.left * scaleX,
        block.boundingBox.top * scaleY,
        block.boundingBox.right * scaleX,
        block.boundingBox.bottom * scaleY,
      );

      // 绘制背景（半透明）
      final bgPaint = Paint()
        ..color = isSelected
            ? Colors.blue.withOpacity(0.3 + animation.value * 0.1)
            : Colors.grey.withOpacity(0.2)
        ..style = PaintingStyle.fill;

      canvas.drawRRect(
        RRect.fromRectAndRadius(scaledRect, const Radius.circular(4)),
        bgPaint,
      );

      // 绘制边框
      final borderPaint = Paint()
        ..color = isSelected
            ? Colors.blue.withOpacity(0.8 + animation.value * 0.2)
            : Colors.grey.withOpacity(0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSelected ? 2.5 : 1.5;

      canvas.drawRRect(
        RRect.fromRectAndRadius(scaledRect, const Radius.circular(4)),
        borderPaint,
      );

      // 选中状态：绘制角标
      if (isSelected) {
        final checkSize = 20.0;
        final checkRect = Rect.fromLTWH(
          scaledRect.right - checkSize - 4,
          scaledRect.top + 4,
          checkSize,
          checkSize,
        );

        // 绘制勾选圆圈
        final checkBgPaint = Paint()
          ..color = Colors.blue
          ..style = PaintingStyle.fill;

        canvas.drawCircle(
          checkRect.center,
          checkSize / 2,
          checkBgPaint,
        );

        // 绘制勾
        final checkPaint = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round;

        final checkPath = Path()
          ..moveTo(checkRect.left + 5, checkRect.center.dy)
          ..lineTo(checkRect.center.dx - 1, checkRect.bottom - 6)
          ..lineTo(checkRect.right - 5, checkRect.top + 5);

        canvas.drawPath(checkPath, checkPaint);
      }
    }
  }

  @override
  bool shouldRepaint(_TextBlockPainter oldDelegate) {
    return oldDelegate.selectedIndices != selectedIndices ||
        oldDelegate.blocks != blocks;
  }
}
