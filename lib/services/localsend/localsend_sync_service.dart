import 'package:common/model/cross_file.dart';
import 'package:common/model/device.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'provider/network/send_provider.dart';

/// ThoughtEcho的LocalSend同步服务
class LocalSendSyncService {
  final Ref _ref;

  LocalSendSyncService(this._ref);

  /// 发送笔记到目标设备
  Future<String> sendNote({
    required Device target,
    required String noteContent,
    String? noteTitle,
  }) async {
    // 将笔记内容转换为CrossFile
    final noteFile = CrossFile.fromData(
      data: noteContent.codeUnits,
      name: noteTitle ?? 'ThoughtEcho_Note_${DateTime.now().millisecondsSinceEpoch}.txt',
    );

    // 开始发送会话
    await _ref.read(sendProvider.notifier).startSession(
      target: target,
      files: [noteFile],
      background: true,
    );

    return 'Note sent successfully';
  }

  /// 获取发送状态
  Map<String, SendSessionState> getSendSessions() {
    return _ref.read(sendProvider);
  }

  /// 取消发送会话
  void cancelSendSession(String sessionId) {
    _ref.read(sendProvider.notifier).cancelSession(sessionId);
  }

  /// 清理所有会话
  void clearAllSessions() {
    _ref.read(sendProvider.notifier).clearAllSessions();
  }

  /// 检查服务是否可用
  bool get isAvailable => true;
}

/// CrossFile扩展，用于从字符串数据创建文件
extension CrossFileFromData on CrossFile {
  static CrossFile fromData({
    required List<int> data, 
    required String name
  }) {
    return CrossFile(
      name: name,
      size: data.length,
      bytes: data,
    );
  }
}