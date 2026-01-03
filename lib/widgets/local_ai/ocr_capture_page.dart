import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../../gen_l10n/app_localizations.dart';
import '../../services/local_ai/ocr_service.dart';

/// OCR 拍照页面
///
/// 提供相机预览和拍照功能
class OCRCapturePage extends StatefulWidget {
  const OCRCapturePage({super.key});

  @override
  State<OCRCapturePage> createState() => _OCRCapturePageState();
}

class _OCRCapturePageState extends State<OCRCapturePage> {
  bool _isProcessing = false;

  Future<void> _pickAndRecognize() async {
    if (_isProcessing) return;

    final l10n = AppLocalizations.of(context);
    final picker = ImagePicker();

    try {
      // camera 在部分平台/权限场景下可能不可用；失败则回退到相册选择。
      XFile? file;
      try {
        file = await picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 92,
        );
      } catch (_) {
        file = await picker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 92,
        );
      }

      if (!mounted || file == null) return;

      setState(() {
        _isProcessing = true;
      });

      final ocr = OCRService();
      await ocr.initialize();
      final result = await ocr.recognizeFromFile(file.path);

      if (!mounted) return;

      if (result.isEmpty) {
        setState(() {
          _isProcessing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.ocrNoTextDetected),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      Navigator.of(context).pop(result.text);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.getDataFailed),
          behavior: SnackBarBehavior.floating,
        ),
      );
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
          // 轻量实现：不做实时相机预览，直接调用系统相机/相册选择图片进行 OCR。
          if (_isProcessing)
            Center(
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      l10n.ocrProcessing,
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
                      _pickAndRecognize();
                    },
                    child: Container(
                      width: 78,
                      height: 78,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
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
