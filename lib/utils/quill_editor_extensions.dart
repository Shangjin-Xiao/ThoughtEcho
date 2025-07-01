import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_quill_extensions/flutter_quill_extensions.dart';
import '../widgets/media_player_widget.dart';

/// Quill编辑器扩展配置
/// 使用自定义MediaPlayerWidget提供更丰富的媒体播放功能
class QuillEditorExtensions {
  /// 获取编辑器的嵌入构建器
  static List<quill.EmbedBuilder> getEmbedBuilders() {
    // 获取官方的builders作为基础
    final builders = FlutterQuillEmbeds.editorBuilders();

    // 只移除官方的视频构建器，图片和音频继续使用官方实现
    builders.removeWhere((builder) => builder.key == 'video');

    // 只添加自定义的视频构建器
    builders.add(_CustomVideoEmbedBuilder());

    return builders;
  }

  /// 获取工具栏的嵌入按钮构建器
  static List<quill.EmbedButtonBuilder> getToolbarBuilders() {
    return FlutterQuillEmbeds.toolbarButtons();
  }
}

/// 自定义视频嵌入构建器
class _CustomVideoEmbedBuilder extends quill.EmbedBuilder {
  @override
  String get key => 'video';

  @override
  Widget build(BuildContext context, quill.EmbedContext embedContext) {
    final videoUrl = embedContext.node.value.data as String;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      child: MediaPlayerWidget(
        filePath: videoUrl,
        mediaType: MediaType.video,
        width: MediaQuery.of(context).size.width * 0.9,
        height: 200,
      ),
    );
  }
}
