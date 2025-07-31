/// Constants for ThoughtEcho application

const String appName = 'ThoughtEcho';
const String appVersion = '1.0.0';
const int protocolVersion = 2;
const int defaultPort = 53317;

// Network constants
const Duration defaultTimeout = Duration(seconds: 30);
const Duration discoveryTimeout = Duration(seconds: 10);

// File constants
const int maxFileSize = 1024 * 1024 * 1024; // 1GB
const List<String> supportedImageTypes = ['jpg', 'jpeg', 'png', 'gif', 'webp'];
const List<String> supportedVideoTypes = ['mp4', 'mov', 'avi', 'mkv'];
const List<String> supportedDocumentTypes = ['pdf', 'doc', 'docx', 'txt', 'md'];