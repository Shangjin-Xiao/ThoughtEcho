import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_quill_extensions/flutter_quill_extensions.dart';

import '../widgets/media_player_widget.dart';

/// Quill编辑器扩展配置
/// 为音频、视频等媒体类型提供自定义渲染器
class QuillEditorExtensions {
  /// 获取自定义的嵌入构建器
  static List<quill.EmbedBuilder> getEmbedBuilders() {
    return [...FlutterQuillEmbeds.editorBuilders(), AudioEmbedBuilder()];
  }
}

/// 音频嵌入构建器
class AudioEmbedBuilder extends quill.EmbedBuilder {
  @override
  String get key => 'audio';

  @override
  Widget build(BuildContext context, quill.EmbedContext embedContext) {
    final audioPath = embedContext.node.value.data as String;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: MediaPlayerWidget(
        filePath: audioPath,
        mediaType: MediaType.audio,
        width: double.infinity,
        height: 80,
      ),
    );
  }
}
