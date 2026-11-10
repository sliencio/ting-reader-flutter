import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 按账号隔离的整块 JSON 文档，落在应用支持目录下的独立文件里。
///
/// 桌面端的 shared_preferences 每次 `setString` 都会把**整张偏好表**重新
/// `json.encode` 再同步写盘。播放进度保护点这类数据动辄十几 MB，于是每次
/// 写入都要在主 isolate 上卡几百毫秒——点一下暂停，连按钮上的菊花都会跟着
/// 顿一下。把体积大、写入频繁的文档挪到单独的文件后，偏好表里只剩小键值，
/// 写入开销与文档体积脱钩。
///
/// Web 没有文件系统，仍然读写真偏好表；旧版本存在偏好表里的数据会在首次
/// 读取时搬进文件，搬完立刻删除旧键，否则桌面端每次写偏好还是要背着它。
class AccountDocumentStore {
  AccountDocumentStore({Future<Directory?> Function()? directory})
      : _directory = directory ?? _defaultDirectory;

  static Future<Directory?> _defaultDirectory() async {
    if (kIsWeb) return null;
    // 测试进程里 path_provider 是纯 Dart 实现，方法通道的 mock 拦不住它，
    // 会落到真实的用户目录，使同一文件里的用例互相看到对方的记录。测试
    // 本来就用内存版偏好表隔离状态，这里跟着退回偏好表即可。
    if (Platform.environment['FLUTTER_TEST'] == 'true') return null;
    try {
      final base = await getApplicationSupportDirectory();
      final directory =
          Directory('${base.path}${Platform.pathSeparator}account_state');
      if (!directory.existsSync()) directory.createSync(recursive: true);
      return directory;
    } catch (_) {
      // 测试环境与只读容器里拿不到目录，退回偏好表。
      return null;
    }
  }

  final Future<Directory?> Function() _directory;
  Future<Directory?>? _resolved;

  Future<Directory?> _ensureDirectory() => _resolved ??= _directory();

  /// 键里有 `:` 和 base64url 字符，Windows 文件名不接受冒号，统一换掉。
  String _fileName(String key) =>
      '${key.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}.json';

  Future<File?> _file(String key) async {
    final directory = await _ensureDirectory();
    if (directory == null) return null;
    return File('${directory.path}${Platform.pathSeparator}${_fileName(key)}');
  }

  Future<String?> read(String key) async {
    final file = await _file(key);
    if (file == null) return _legacy(key);
    try {
      if (await file.exists()) return await file.readAsString();
    } catch (_) {
      // 文件损坏时继续尝试偏好表里的旧记录。
    }
    final legacy = await _legacy(key);
    if (legacy == null) return null;
    try {
      await _writeFile(file, legacy);
      await _removeLegacy(key);
    } catch (_) {
      // 迁移失败就先用着旧记录，下次启动再试。
    }
    return legacy;
  }

  Future<void> write(String key, String value) async {
    final file = await _file(key);
    if (file != null) {
      try {
        await _writeFile(file, value);
        return;
      } catch (_) {
        // 落到下面的偏好表兜底，至少不丢数据。
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  /// 先写临时文件再改名，避免写到一半崩溃留下半个 JSON。
  Future<void> _writeFile(File file, String value) async {
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(value);
    await temporary.rename(file.path);
  }

  Future<String?> _legacy(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(key);
    } catch (_) {
      return null;
    }
  }

  Future<void> _removeLegacy(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.containsKey(key)) await prefs.remove(key);
    } catch (_) {
      // 删不掉只是继续背着旧数据，不影响正确性。
    }
  }
}
