import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import '../../gen_l10n/app_localizations.dart';
import '../../services/local_ai/local_ocr_service.dart';
import '../../utils/app_logger.dart';

/// OCR 拍照页面 - 集成实际相机和 OCR 功能
///
/// 提供相机预览和拍照功能，并使用 Google ML Kit 进行文字识别
class OCRCapturePage extends StatefulWidget {
  const OCRCapturePage({super.key});

  @override
  State<OCRCapturePage> createState() => _OCRCapturePageState();
}

class _OCRCapturePageState extends State<OCRCapturePage> {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isInitializing = true;
  bool _isCapturing = false;
  String? _error;
  final LocalOCRService _ocrService = LocalOCRService();

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _initializeOCR();
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        setState(() {
          _error = '未找到可用的相机';
          _isInitializing = false;
        });
        return;
      }

      _cameraController = CameraController(
        _cameras![0],
        ResolutionPreset.high,
        enableAudio: false,
      );

      await _cameraController!.initialize();
      
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
    } catch (e) {
      logDebug('Camera initialization error: $e');
      if (mounted) {
        setState(() {
          _error = '相机初始化失败: $e';
          _isInitializing = false;
        });
      }
    }
  }

  Future<void> _initializeOCR() async {
    try {
      await _ocrService.initialize();
      logDebug('OCR service initialized');
    } catch (e) {
      logDebug('OCR initialization error: $e');
    }
  }

  Future<void> _captureAndRecognize() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    if (_isCapturing) {
      return;
    }

    setState(() {
      _isCapturing = true;
    });

    try {
      HapticFeedback.mediumImpact();

      // 拍照
      final XFile image = await _cameraController!.takePicture();
      
      // OCR 识别
      final recognizedText = await _ocrService.recognizeFromFile(image.path);
      
      if (recognizedText != null && recognizedText.text.isNotEmpty) {
        // 返回识别结果
        if (mounted) {
          Navigator.of(context).pop(recognizedText.text);
        }
      } else {
        // 未识别到文字
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).ocrNoTextDetected),
              behavior: SnackBarBehavior.floating,
            ),
          );
          setState(() {
            _isCapturing = false;
          });
        }
      }
    } catch (e) {
      logDebug('Capture and recognize error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('识别失败: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        setState(() {
          _isCapturing = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _ocrService.dispose();
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
          // 相机预览或错误信息
          if (_isInitializing)
            const Center(
              child: CircularProgressIndicator(),
            )
          else if (_error != null)
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
                      Icons.error_outline,
                      size: 64,
                      color: Colors.white.withOpacity(0.7),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else if (_cameraController != null && _cameraController!.value.isInitialized)
            Center(
              child: AspectRatio(
                aspectRatio: _cameraController!.value.aspectRatio,
                child: CameraPreview(_cameraController!),
              ),
            ),

          // 拍照提示
          if (!_isInitializing && _error == null)
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
                    shadows: [
                      Shadow(
                        color: Colors.black54,
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // 拍照按钮
          if (!_isInitializing && _error == null)
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
                      onTap: _isCapturing ? null : _captureAndRecognize,
                      child: Container(
                        width: 78,
                        height: 78,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _isCapturing ? Colors.grey : Colors.white,
                          border: Border.all(
                            color: primary,
                            width: 4,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: primary.withOpacity(0.3),
                              blurRadius: 15,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: _isCapturing
                            ? const Padding(
                                padding: EdgeInsets.all(20),
                                child: CircularProgressIndicator(
                                  strokeWidth: 3,
                                ),
                              )
                            : Icon(
                                Icons.camera_alt,
                                size: 36,
                                color: primary,
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
