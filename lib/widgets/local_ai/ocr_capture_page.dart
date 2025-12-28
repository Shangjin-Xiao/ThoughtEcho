import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:thoughtecho/services/ocr_service.dart';
import 'package:thoughtecho/widgets/local_ai/ocr_result_sheet.dart';
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
  CameraController? _controller;
  Future<void>? _initializeControllerFuture;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    final firstCamera = cameras.first;

    _controller = CameraController(
      firstCamera,
      ResolutionPreset.high,
      enableAudio: false,
    );

    _initializeControllerFuture = _controller!.initialize();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
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
          FutureBuilder<void>(
            future: _initializeControllerFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.done) {
                return Center(child: CameraPreview(_controller!));
              } else {
                return const Center(child: CircularProgressIndicator());
              }
            },
          ),

          if (_isProcessing)
             Container(
                color: Colors.black54,
                child: const Center(child: CircularProgressIndicator()),
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
                  shadows: [Shadow(blurRadius: 2, color: Colors.black)],
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
                    onTap: _isProcessing ? null : () async {
                      HapticFeedback.selectionClick();
                      try {
                        setState(() => _isProcessing = true);

                        await _initializeControllerFuture;
                        final image = await _controller!.takePicture();

                        if (!mounted) return;

                        final text = await OCRService.instance.recognizeFromFile(image.path);

                        if (!mounted) return;
                        setState(() => _isProcessing = false);

                        Navigator.of(context).pop(); // Close camera

                        // Show result sheet
                        // We need a way to show result sheet from here or pass back result.
                        // Currently HomePage handles opening OCRResultSheet.
                        // Ideally we should push a result page or return result.
                        // Let's modify logic to return the text to the caller, OR show sheet here.
                        // Showing sheet here might be weird if we popped.
                        // But wait, the previous flow was Home -> OCRFlow -> ResultSheet.
                        // Home calls: await Navigator.of(context).push(OCRPage)
                        // then shows sheet.
                        // So we should pop with result?
                        // But `_openOCRFlow` in home_page uses showModalBottomSheet AFTER push returns?
                        // Actually let's look at `home_page.dart` again.
                        // It pushes OCRCapturePage, then shows OCRResultSheet with "Feature Coming Soon".
                        // So I should probably return the text when popping.

                        // Wait, home_page currently ignores the pop result.
                        // I need to update home_page to use the result.
                        // But here, I can pop with result.
                        // However, let's just show the sheet here for better UX flow?
                        // Or stick to home_page logic?
                        // Let's pop(text).

                        // Wait, I can't easily change home_page signature expectation without checking it.
                        // In home_page:
                        // await Navigator.of(context).push(...)
                        // final l10n = ...
                        // String resultText = l10n.featureComingSoon;

                        // So home_page doesn't read result.
                        // I will update home_page to read the result.

                        Navigator.of(context).pop(text);

                      } catch (e) {
                        if (mounted) {
                          setState(() => _isProcessing = false);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error: $e')),
                          );
                        }
                      }
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
