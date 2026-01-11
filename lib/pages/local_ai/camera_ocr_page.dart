/// 相机 OCR 识别页面
///
/// 拍照后使用 MLKit/VLM 进行文字识别，支持用户选择文字区域
library;


import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../gen_l10n/app_localizations.dart';
import '../../services/local_ai/hybrid_ocr_service.dart';
import '../../widgets/local_ai/text_block_overlay.dart';

/// 相机 OCR 页面
class CameraOCRPage extends StatefulWidget {
  /// OCR 引擎类型（可选）
  final OCREngineType? engineType;

  const CameraOCRPage({
    super.key,
    this.engineType,
  });

  @override
  State<CameraOCRPage> createState() => _CameraOCRPageState();
}

class _CameraOCRPageState extends State<CameraOCRPage> {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;
  bool _isProcessing = false;
  final _hybridOCRService = HybridOCRService.instance;
  final _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras != null && _cameras!.isNotEmpty) {
        _cameraController = CameraController(
          _cameras!.first,
          ResolutionPreset.high,
          enableAudio: false,
        );

        await _cameraController!.initialize();

        if (mounted) {
          setState(() {
            _isCameraInitialized = true;
          });
        }
      }
    } catch (e) {
      debugPrint('相机初始化失败: $e');
    }
  }

  Future<void> _takePicture() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      // 拍照
      final image = await _cameraController!.takePicture();
      await _processImage(image.path);
    } catch (e) {
      debugPrint('拍照失败: $e');
      if (mounted) {
        _showError('拍照失败: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _pickImageFromGallery() async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      final pickedFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
      );

      if (pickedFile != null) {
        await _processImage(pickedFile.path);
      }
    } catch (e) {
      debugPrint('选择图片失败: $e');
      if (mounted) {
        _showError('选择图片失败: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _processImage(String imagePath) async {
    final l10n = AppLocalizations.of(context);

    try {
      // 显示加载对话框
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(l10n.ocrProcessing),
            ],
          ),
        ),
      );

      // 执行 OCR 识别
      final result = await _hybridOCRService.recognizeFromFile(
        imagePath,
        engineType: widget.engineType,
      );

      // 关闭加载对话框
      if (!mounted) return;
      Navigator.of(context).pop();

      if (result.isEmpty || result.blocks.isEmpty) {
        _showError(l10n.ocrNoTextDetected);
        return;
      }

      // 显示文字区域选择页面
      final selectedIndices = await Navigator.of(context).push<Set<int>>(
        MaterialPageRoute(
          builder: (context) => TextBlockOverlay(
            imagePath: imagePath,
            ocrResult: result,
          ),
        ),
      );

      if (selectedIndices != null && selectedIndices.isNotEmpty) {
        // 用户选择了区域，返回选中的文本
        final selectedBlocks = selectedIndices
            .map((i) => result.blocks[i])
            .toList();

        final selectedText = selectedBlocks
            .map((b) => b.text)
            .join('\n')
            .trim();

        if (mounted) {
          Navigator.of(context).pop(selectedText);
        }
      }
    } catch (e) {
      debugPrint('OCR 识别失败: $e');
      if (mounted) {
        // 关闭可能存在的加载对话框
        Navigator.of(context).pop();
        _showError('识别失败: $e');
      }
    }
  }

  void _showError(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(l10n.ocrTakePhoto),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          // 相机预览
          if (_isCameraInitialized && _cameraController != null)
            Center(
              child: CameraPreview(_cameraController!),
            )
          else
            const Center(
              child: CircularProgressIndicator(),
            ),

          // 底部按钮栏
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withOpacity(0.8),
                    Colors.transparent,
                  ],
                ),
              ),
              child: SafeArea(
                top: false,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // 相册选择
                    _ControlButton(
                      icon: Icons.photo_library,
                      label: l10n.ocrSelectImage,
                      onPressed: _isProcessing ? null : _pickImageFromGallery,
                    ),

                    // 拍照按钮
                    _CaptureButton(
                      onPressed: _isProcessing ? null : _takePicture,
                      isProcessing: _isProcessing,
                    ),

                    // 占位（保持对称）
                    const SizedBox(width: 64),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 拍照按钮
class _CaptureButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool isProcessing;

  const _CaptureButton({
    required this.onPressed,
    this.isProcessing = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(0.3),
          border: Border.all(
            color: Colors.white,
            width: 4,
          ),
        ),
        child: isProcessing
            ? const Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Center(
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                  ),
                ),
              ),
      ),
    );
  }
}

/// 控制按钮
class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  const _ControlButton({
    required this.icon,
    required this.label,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: onPressed,
          icon: Icon(icon),
          iconSize: 32,
          color: Colors.white,
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
