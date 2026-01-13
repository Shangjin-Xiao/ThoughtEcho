import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../../gen_l10n/app_localizations.dart';

/// OCR 拍照页面
///
/// 提供相机预览和拍照功能
class OCRCapturePage extends StatefulWidget {
  const OCRCapturePage({super.key});

  @override
  State<OCRCapturePage> createState() => _OCRCapturePageState();
}

class _OCRCapturePageState extends State<OCRCapturePage> {
  bool _isPicking = false;

  Future<void> _captureImage() async {
    if (_isPicking) return;
    final l10n = AppLocalizations.of(context);

    setState(() {
      _isPicking = true;
    });

    try {
      final picker = ImagePicker();
      XFile? image;

      // 在 Web/桌面端，相机能力可能不可用：优先相册；
      // 在移动端优先相机，失败再回退相册。
      if (kIsWeb) {
        image = await picker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 92,
        );
      } else {
        try {
          image = await picker.pickImage(
            source: ImageSource.camera,
            imageQuality: 92,
          );
        } catch (_) {
          image = await picker.pickImage(
            source: ImageSource.gallery,
            imageQuality: 92,
          );
        }
      }

      if (!mounted) return;
      if (image == null) return;

      Navigator.of(context).pop(image.path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.startFailed(e.toString())),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _isPicking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    final primary = theme.colorScheme.primary;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(l10n.ocrCapture),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Stack(
        children: [
          // TODO: 相机预览 - 后端实现后添加
          Center(
            child: Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.camera_alt,
                    size: 64,
                    color: Colors.white.withOpacity(0.7),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.ocrCaptureHint,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 拍照提示
          Positioned(
            left: 0,
            right: 0,
            bottom: 120,
            child: Center(
              child: Text(
                l10n.ocrCaptureHint,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                ),
              ),
            ),
          ),

          // 拍照按钮
          Positioned(
            left: 0,
            right: 0,
            bottom: 40,
            child: Center(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.85, end: 1.0),
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeOut,
                builder: (context, value, child) {
                  return Transform.scale(scale: value, child: child);
                },
                child: Material(
                  color: Colors.transparent,
                  child: InkResponse(
                    radius: 48,
                    splashColor: Colors.white.withOpacity(0.15),
                    highlightColor: Colors.white.withOpacity(0.06),
                    onTap: () {
                      HapticFeedback.selectionClick();
                      _captureImage();
                    },
                    child: Container(
                      width: 78,
                      height: 78,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isPicking ? Colors.white70 : Colors.white,
                        border: Border.all(
                          color: primary,
                          width: 4,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: primary.withOpacity(0.35),
                            blurRadius: 22,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black.withOpacity(0.06),
                          ),
                          child: const Icon(
                            Icons.camera_alt,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
