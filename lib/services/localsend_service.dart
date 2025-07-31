import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../models/quote.dart';
import '../models/localsend_device.dart';
import '../models/localsend_session_status.dart';
import '../models/localsend_file_status.dart';
import '../models/localsend_file_type.dart';
import '../utils/app_logger.dart';
import 'database_service.dart';
import 'media_file_service.dart';
import 'localsend/localsend_server.dart';
import 'localsend/localsend_send_provider.dart';

/// 统一的LocalSend服务，集成笔记和媒体文件同步功能
class LocalSendService extends ChangeNotifier {
  static LocalSendService? _instance;
  static LocalSendService get instance => _instance ??= LocalSendService._();
  
  LocalSendService._();

  // 服务依赖
  DatabaseService? _databaseService;
  MediaFileService? _mediaFileService;
  LocalSendServer? _server;
  LocalSendSendProvider? _sendProvider;

  // 状态管理
  bool _isServerRunning = false;
  bool _isScanning = false;
  LocalSendSessionStatus _sessionStatus = LocalSendSessionStatus.waiting;
  List<LocalSendDevice> _discoveredDevices = [];
  Map<String, LocalSendFileStatus> _fileStatuses = {};
  
  // 进度跟踪
  double _currentProgress = 0.0;
  String _currentOperationMessage = '';
  
  // Getters
  bool get isServerRunning => _isServerRunning;
  bool get isScanning => _isScanning;
  LocalSendSessionStatus get sessionStatus => _sessionStatus;
  List<LocalSendDevice> get discoveredDevices => _discoveredDevices;
  Map<String, LocalSendFileStatus> get fileStatuses => _fileStatuses;
  double get currentProgress => _currentProgress;
  String get currentOperationMessage => _currentOperationMessage;

  /// 初始化服务
  Future<void> initialize({
    required DatabaseService databaseService,
    required MediaFileService mediaFileService,
  }) async {
    try {
      _databaseService = databaseService;
      _mediaFileService = mediaFileService;
      
      // 初始化LocalSend服务器
      _server = LocalSendServer();
      _sendProvider = LocalSendSendProvider();
      
      await _server?.initialize();
      await _sendProvider?.initialize();
      
      logInfo('LocalSendService 初始化完成', source: 'LocalSendService');
    } catch (e) {
      logError('LocalSendService 初始化失败: $e', error: e, source: 'LocalSendService');
      rethrow;
    }
  }

  /// 启动LocalSend服务器
  Future<void> startServer() async {
    try {
      if (_server == null) {
        throw Exception('LocalSend服务器未初始化');
      }
      
      await _server!.start();
      _isServerRunning = true;
      _updateOperationMessage('LocalSend服务器已启动');
      notifyListeners();
      
      logInfo('LocalSend服务器启动成功', source: 'LocalSendService');
    } catch (e) {
      logError('启动LocalSend服务器失败: $e', error: e, source: 'LocalSendService');
      rethrow;
    }
  }

  /// 停止LocalSend服务器
  Future<void> stopServer() async {
    try {
      if (_server != null) {
        await _server!.stop();
      }
      _isServerRunning = false;
      _updateOperationMessage('LocalSend服务器已停止');
      notifyListeners();
      
      logInfo('LocalSend服务器停止成功', source: 'LocalSendService');
    } catch (e) {
      logError('停止LocalSend服务器失败: $e', error: e, source: 'LocalSendService');
    }
  }

  /// 扫描局域网设备
  Future<void> scanForDevices() async {
    try {
      _isScanning = true;
      _discoveredDevices.clear();
      _updateOperationMessage('正在扫描局域网设备...');
      notifyListeners();
      
      // 使用LocalSend的设备发现功能
      final devices = await _sendProvider?.discoverDevices() ?? [];
      _discoveredDevices = devices;
      
      _isScanning = false;
      _updateOperationMessage('发现 ${devices.length} 个设备');
      notifyListeners();
      
      logInfo('设备扫描完成，发现 ${devices.length} 个设备', source: 'LocalSendService');
    } catch (e) {
      _isScanning = false;
      _updateOperationMessage('设备扫描失败');
      notifyListeners();
      
      logError('扫描设备失败: $e', error: e, source: 'LocalSendService');
      rethrow;
    }
  }

  /// 发送笔记到指定设备
  Future<void> sendNotesToDevice({
    required LocalSendDevice device,
    required List<Quote> notes,
    Function(double progress)? onProgress,
  }) async {
    try {
      _sessionStatus = LocalSendSessionStatus.sending;
      _currentProgress = 0.0;
      _updateOperationMessage('正在准备发送笔记...');
      notifyListeners();

      // 1. 创建临时目录
      final tempDir = await _createTempDirectory();
      
      // 2. 导出笔记数据
      final notesData = await _exportNotesToJson(notes);
      final notesFile = File(path.join(tempDir.path, 'notes.json'));
      await notesFile.writeAsString(json.encode(notesData));
      
      // 3. 收集媒体文件
      final mediaFiles = await _collectMediaFiles(notes);
      
      // 4. 创建文件传输列表
      final filesToSend = <File>[notesFile];
      filesToSend.addAll(mediaFiles);
      
      // 5. 发送文件
      await _sendFilesToDevice(
        device: device,
        files: filesToSend,
        onProgress: (progress) {
          _currentProgress = progress;
          onProgress?.call(progress);
          _updateOperationMessage('发送进度: ${(progress * 100).toInt()}%');
          notifyListeners();
        },
      );
      
      // 6. 清理临时文件
      await _cleanupTempDirectory(tempDir);
      
      _sessionStatus = LocalSendSessionStatus.finished;
      _updateOperationMessage('笔记发送完成');
      notifyListeners();
      
      logInfo('成功发送 ${notes.length} 条笔记到设备: ${device.alias}', source: 'LocalSendService');
    } catch (e) {
      _sessionStatus = LocalSendSessionStatus.canceledBySender;
      _updateOperationMessage('发送失败: $e');
      notifyListeners();
      
      logError('发送笔记失败: $e', error: e, source: 'LocalSendService');
      rethrow;
    }
  }

  /// 接收文件并导入笔记
  Future<void> receiveAndImportNotes({
    required String receivedFilePath,
    Function(double progress)? onProgress,
  }) async {
    try {
      _sessionStatus = LocalSendSessionStatus.receiving;
      _currentProgress = 0.0;
      _updateOperationMessage('正在处理接收的文件...');
      notifyListeners();

      final file = File(receivedFilePath);
      if (!await file.exists()) {
        throw Exception('接收的文件不存在');
      }

      // 检查文件类型
      if (path.extension(receivedFilePath).toLowerCase() == '.json') {
        // JSON格式的笔记数据
        await _importNotesFromJson(file, onProgress);
      } else {
        // 其他类型文件，可能是媒体文件
        await _handleReceivedMediaFile(file, onProgress);
      }

      _sessionStatus = LocalSendSessionStatus.finished;
      _updateOperationMessage('文件接收并处理完成');
      notifyListeners();
      
      logInfo('成功接收并处理文件: $receivedFilePath', source: 'LocalSendService');
    } catch (e) {
      _sessionStatus = LocalSendSessionStatus.canceledByReceiver;
      _updateOperationMessage('接收处理失败: $e');
      notifyListeners();
      
      logError('接收处理文件失败: $e', error: e, source: 'LocalSendService');
      rethrow;
    }
  }

  /// 导出笔记为JSON格式
  Future<Map<String, dynamic>> _exportNotesToJson(List<Quote> notes) async {
    final notesData = <Map<String, dynamic>>[];
    
    for (final note in notes) {
      final noteData = note.toMap();
      notesData.add(noteData);
    }
    
    return {
      'version': '1.0',
      'timestamp': DateTime.now().toIso8601String(),
      'notes': notesData,
      'total_count': notes.length,
    };
  }

  /// 收集笔记中的媒体文件
  Future<List<File>> _collectMediaFiles(List<Quote> notes) async {
    final mediaFiles = <File>[];
    
    if (_mediaFileService == null) return mediaFiles;
    
    for (final note in notes) {
      // 从笔记内容中提取媒体文件路径
      final mediaPaths = _extractMediaPaths(note);
      
      for (final mediaPath in mediaPaths) {
        final file = File(mediaPath);
        if (await file.exists()) {
          mediaFiles.add(file);
        }
      }
    }
    
    return mediaFiles;
  }

  /// 从笔记内容中提取媒体文件路径
  List<String> _extractMediaPaths(Quote note) {
    final paths = <String>[];
    
    // 从deltaContent中提取图片/视频/音频路径
    if (note.deltaContent != null) {
      try {
        final delta = json.decode(note.deltaContent!);
        if (delta is Map && delta['ops'] is List) {
          for (final op in delta['ops']) {
            if (op is Map && op['insert'] is Map) {
              final insert = op['insert'];
              if (insert['image'] != null) {
                paths.add(insert['image']);
              }
              if (insert['video'] != null) {
                paths.add(insert['video']);
              }
              if (insert['audio'] != null) {
                paths.add(insert['audio']);
              }
            }
          }
        }
      } catch (e) {
        logWarning('解析笔记媒体内容失败: $e', source: 'LocalSendService');
      }
    }
    
    return paths;
  }

  /// 发送文件到设备
  Future<void> _sendFilesToDevice({
    required LocalSendDevice device,
    required List<File> files,
    Function(double progress)? onProgress,
  }) async {
    if (_sendProvider == null) {
      throw Exception('SendProvider未初始化');
    }
    
    // 实现文件发送逻辑
    // 这里需要根据LocalSend的具体API进行实现
    await _sendProvider!.sendFiles(
      targetDevice: device,
      files: files,
      onProgress: onProgress,
    );
  }

  /// 从JSON文件导入笔记
  Future<void> _importNotesFromJson(File jsonFile, Function(double progress)? onProgress) async {
    final content = await jsonFile.readAsString();
    final data = json.decode(content);
    
    if (data is! Map<String, dynamic> || data['notes'] is! List) {
      throw Exception('无效的笔记数据格式');
    }
    
    final notes = data['notes'] as List;
    var processed = 0;
    
    for (final noteData in notes) {
      if (noteData is Map<String, dynamic>) {
        final quote = Quote.fromMap(noteData);
        await _databaseService?.addQuote(quote);
      }
      
      processed++;
      final progress = processed / notes.length;
      onProgress?.call(progress);
      _currentProgress = progress;
      notifyListeners();
    }
  }

  /// 处理接收的媒体文件
  Future<void> _handleReceivedMediaFile(File mediaFile, Function(double progress)? onProgress) async {
    if (_mediaFileService == null) return;
    
    try {
      // 将媒体文件复制到应用的媒体目录
      final targetPath = await _mediaFileService!.saveReceivedMediaFile(mediaFile);
      onProgress?.call(1.0);
      
      logInfo('媒体文件已保存到: $targetPath', source: 'LocalSendService');
    } catch (e) {
      logError('处理接收媒体文件失败: $e', error: e, source: 'LocalSendService');
      // 如果saveReceivedMediaFile方法不存在，使用简单的文件复制
      final fileName = path.basename(mediaFile.path);
      final tempDir = await getTemporaryDirectory();
      final targetPath = path.join(tempDir.path, 'received_$fileName');
      await mediaFile.copy(targetPath);
      onProgress?.call(1.0);
      
      logInfo('媒体文件已复制到临时目录: $targetPath', source: 'LocalSendService');
    }
  }

  /// 创建临时目录
  Future<Directory> _createTempDirectory() async {
    final tempDir = await getTemporaryDirectory();
    final localSendTemp = Directory(path.join(tempDir.path, 'localsend_temp'));
    
    if (await localSendTemp.exists()) {
      await localSendTemp.delete(recursive: true);
    }
    
    await localSendTemp.create(recursive: true);
    return localSendTemp;
  }

  /// 清理临时目录
  Future<void> _cleanupTempDirectory(Directory tempDir) async {
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (e) {
      logWarning('清理临时目录失败: $e', source: 'LocalSendService');
    }
  }

  /// 更新操作消息
  void _updateOperationMessage(String message) {
    _currentOperationMessage = message;
    logDebug(message, source: 'LocalSendService');
  }

  /// 重置会话状态
  void resetSessionStatus() {
    _sessionStatus = LocalSendSessionStatus.waiting;
    _currentProgress = 0.0;
    _currentOperationMessage = '';
    _fileStatuses.clear();
    notifyListeners();
  }

  /// 获取服务器状态信息
  Map<String, dynamic> getServerInfo() {
    return {
      'isRunning': _isServerRunning,
      'isScanning': _isScanning,
      'deviceCount': _discoveredDevices.length,
      'sessionStatus': _sessionStatus.name,
      'currentProgress': _currentProgress,
    };
  }

  @override
  void dispose() {
    stopServer();
    super.dispose();
  }
}