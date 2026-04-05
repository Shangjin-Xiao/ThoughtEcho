class Platform {
  static bool get isWindows => false;
  static bool get isAndroid => false;
}

Never exit(int code) {
  throw UnsupportedError('exit is not supported on this platform');
}

class Directory {
  Directory(this.path);

  final String path;

  Future<Directory> create({bool recursive = false}) async {
    return this;
  }

  Future<bool> exists() async {
    return false;
  }

  bool existsSync() {
    return false;
  }
}

class File {
  File(this.path);

  final String path;

  Future<bool> exists() async {
    return false;
  }

  bool existsSync() {
    return false;
  }

  Future<File> copy(String newPath) async {
    return File(newPath);
  }
}
