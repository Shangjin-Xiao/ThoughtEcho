import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../gen_l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../services/local_ai/local_speech_recognition_service.dart';
import '../../services/settings_service.dart';

/// 语音录制浮层组件 - 集成实际语音识别功能
///
/// 长按 FAB 时显示，提供录音状态显示和手势交互
class VoiceInputOverlay extends StatefulWidget {
  final VoidCallback? onSwipeUpForOCR;
  final Function(String text)? onRecordComplete;
  final String? transcribedText;

  const VoiceInputOverlay({
    super.key,
    this.onSwipeUpForOCR,
    this.onRecordComplete,
    this.transcribedText,
  });

  @override
  State<VoiceInputOverlay> createState() => _VoiceInputOverlayState();
}

class _VoiceInputOverlayState extends State<VoiceInputOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  double _swipeOffset = 0.0;
  bool _ocrTriggered = false;
  
  // Speech recognition state
  final LocalSpeechRecognitionService _speechService = LocalSpeechRecognitionService();
  String _recognizedText = '';
  bool _isListening = false;
  bool _isInitializing = true;

  static const double _ocrTriggerDistance = 120.0;
  static const double _maxDragDistance = 180.0;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    
    _initializeSpeechService();
  }

  Future<void> _initializeSpeechService() async {
    try {
      await _speechService.initialize();
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
        _startListening();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('语音识别初始化失败: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _startListening() async {
    if (!_speechService.isInitialized) {
      return;
    }

    try {
      setState(() {
        _isListening = true;
        _recognizedText = '';
      });

      await _speechService.startListening(
        onResult: (text, isFinal) {
          if (mounted) {
            setState(() {
              _recognizedText = text;
            });
          }
        },
        locale: 'zh_CN',
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isListening = false;
        });
      }
    }
  }

  Future<void> _stopListening() async {
    if (_isListening) {
      await _speechService.stopListening();
      if (mounted) {
        setState(() {
          _isListening = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _speechService.stopListening();
    _speechService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    final drag = (-_swipeOffset).clamp(0.0, _maxDragDistance);
    final willTriggerOCR = drag >= _ocrTriggerDistance;

    return GestureDetector(
      onVerticalDragUpdate: (details) {
        setState(() {
          _swipeOffset += details.delta.dy;
          if (!_ocrTriggered && _swipeOffset <= -_ocrTriggerDistance) {
            _ocrTriggered = true;
            HapticFeedback.mediumImpact();
          }
        });
      },
      onVerticalDragEnd: (details) async {
        final shouldTriggerOCR = _swipeOffset <= -_ocrTriggerDistance;
        setState(() {
          _swipeOffset = 0.0;
          _ocrTriggered = false;
        });

        await _stopListening();

        if (shouldTriggerOCR) {
          widget.onSwipeUpForOCR?.call();
          return;
        }
        
        // 返回识别的文本
        if (_recognizedText.isNotEmpty) {
          widget.onRecordComplete?.call(_recognizedText);
        } else {
          Navigator.of(context).maybePop();
        }
      },
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            // 背景模糊
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Container(
                  color: Colors.black.withOpacity(0.6),
                ),
              ),
            ),
            
            // 主要内容
            SafeArea(
              child: Column(
                children: [
                  // 顶部关闭按钮
                  Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: IconButton(
                        onPressed: () async {
                          await _stopListening();
                          if (mounted) {
                            Navigator.of(context).maybePop();
                          }
                        },
                        icon: const Icon(Icons.close),
                        color: Colors.white,
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white.withOpacity(0.1),
                          highlightColor: Colors.white.withOpacity(0.2),
                        ),
                        tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                      ),
                    ),
                  ),
                  
                  const Spacer(flex: 2),

                  // 麦克风动画区域
                  AnimatedBuilder(
                    animation: _animationController,
                    builder: (context, child) {
                      final t = _animationController.value;
                      final scale = 1.0 + (t * 0.1);
                      final opacity = 0.3 - (t * 0.15);
                      
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          // 扩散波纹
                          if (_isListening)
                            Transform.scale(
                              scale: 1.0 + (t * 0.5),
                              child: Container(
                                width: 120,
                                height: 120,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: colorScheme.primary.withOpacity(opacity),
                                    width: 2,
                                  ),
                                ),
                              ),
                            ),
                          // 内部光晕
                          Container(
                            width: 100 * scale,
                            height: 100 * scale,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: colorScheme.primary.withOpacity(0.2),
                              boxShadow: [
                                BoxShadow(
                                  color: colorScheme.primary.withOpacity(0.4),
                                  blurRadius: 20,
                                  spreadRadius: 5,
                                ),
                              ],
                            ),
                          ),
                          // 核心图标
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: colorScheme.primary,
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  colorScheme.primary,
                                  colorScheme.primaryContainer,
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: colorScheme.primary.withOpacity(0.5),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.mic_rounded,
                              size: 40,
                              color: colorScheme.onPrimary,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  
                  const SizedBox(height: 32),

                  // 状态文本
                  Text(
                    _isInitializing
                        ? '初始化中...'
                        : _isListening
                            ? l10n.listening
                            : '准备就绪',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  
                  const SizedBox(height: 16),

                  // 识别的文字
                  if (_recognizedText.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 32),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _recognizedText,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  
                  const Spacer(flex: 1),

                  // OCR 提示 (上划手势)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    curve: Curves.easeOut,
                    margin: EdgeInsets.only(bottom: 100 + drag),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.arrow_upward_rounded,
                          color: willTriggerOCR
                              ? colorScheme.primary
                              : Colors.white.withOpacity(0.5),
                          size: 32,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          l10n.swipeUpForOcr,
                          style: TextStyle(
                            color: willTriggerOCR
                                ? colorScheme.primary
                                : Colors.white.withOpacity(0.7),
                            fontSize: 14,
                            fontWeight: willTriggerOCR
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // 录音提示 (松开手势)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 48.0),
                    child: Text(
                      l10n.releaseToFinish,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
