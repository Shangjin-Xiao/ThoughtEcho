import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
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
  Future<void>? _initializeFuture;
  bool _isCapturing = false;

  @override
  void initState() {
    super.initState();
    _initializeFuture = _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      throw Exception('camera_not_available');
    }

    final back = cameras.where((c) => c.lensDirection == CameraLensDirection.back);
    final selected = back.isNotEmpty ? back.first : cameras.first;

    final controller = CameraController(
      selected,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    await controller.initialize();
    if (!mounted) {
      await controller.dispose();
      return;
    }

    setState(() {
      _controller = controller;
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _takePicture() async {
    if (_isCapturing) return;
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    setState(() {
      _isCapturing = true;
    });

    try {
      HapticFeedback.selectionClick();
      final file = await controller.takePicture();
      if (!mounted) return;
      Navigator.of(context).pop(file.path);
    } catch (_) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.featureNotAvailable),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isCapturing = false;
        });
      }
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
          // 相机预览
          Positioned.fill(
            child: FutureBuilder<void>(
              future: _initializeFuture,
              builder: (context, snapshot) {
                final controller = _controller;

                if (snapshot.connectionState == ConnectionState.waiting ||
                    controller == null ||
                    !controller.value.isInitialized) {
                  return const Center(
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        l10n.featureNotAvailable,
                        style: const TextStyle(color: Colors.white70),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                return CameraPreview(controller);
              },
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
                    onTap: _isCapturing ? null : _takePicture,
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
                          child: _isCapturing
                              ? const Padding(
                                  padding: EdgeInsets.all(14),
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(
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
