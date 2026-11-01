import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../api/api_error.dart';
import 'chapter_read_marks.dart';

class ChapterReadSync extends ChangeNotifier {
  ChapterReadSync(
      {required this.api,
      required this.identity,
      required this.canSync,
      this.onSynced});

  final ApiClient api;
  final String Function() identity;
  final bool Function() canSync;
  final void Function(String book, Set<String> chapters)? onSynced;
  final Map<String, Set<String>> _pending = {};
  final Map<String, Set<String>> _confirmed = {};
  Future<void> _tail = Future.value();
  String? _owner;
  String? error;
  bool _disposed = false;

  String _key(String owner) =>
      'chapter_read_sync:${base64Url.encode(utf8.encode(owner))}';

  String _confirmedKey(String owner) =>
      'chapter_read_confirmed:${base64Url.encode(utf8.encode(owner))}';

  Set<String> pendingFor(String book) => _owner == identity()
      ? Set.unmodifiable(_pending[book] ?? const <String>{})
      : {};
  Set<String> confirmedFor(String book) => _owner == identity()
      ? Set.unmodifiable(_confirmed[book] ?? const <String>{})
      : {};

  /// 章节列表刷新后调用。
  ///
  /// 已同步成功的记录必须保留：服务端可能没有把 is_read 回填到章节列表
  /// （旧版本服务端、或列表接口不返回该字段），此前在这里清空本地记录，
  /// 会让用户重装或重启后看到已读标记凭空消失。
  void acceptSnapshot(String book, Iterable<String> visibleIds) {}

  Future<void> _serial(Future<void> Function() action) {
    final next = _tail.then((_) => action());
    _tail = next.catchError((Object _) {});
    return next;
  }

  bool _active(String owner) => !_disposed && owner == identity();

  Future<void> _load(String owner) async {
    if (_owner == owner) return;
    final prefs = await SharedPreferences.getInstance();
    _pending.clear();
    _confirmed.clear();
    final rawPending = prefs.getString(_key(owner));
    if (rawPending != null) {
      for (final entry
          in (jsonDecode(rawPending) as Map<String, dynamic>).entries) {
        _pending[entry.key] = (entry.value as List).cast<String>().toSet();
      }
    }
    // 已同步成功的记录同样落盘：章节列表接口不一定回填 is_read，
    // 只靠内存保存会让重装或重启后的已读标记凭空消失。
    final rawConfirmed = prefs.getString(_confirmedKey(owner));
    if (rawConfirmed != null) {
      for (final entry
          in (jsonDecode(rawConfirmed) as Map<String, dynamic>).entries) {
        _confirmed[entry.key] = (entry.value as List).cast<String>().toSet();
      }
    }
    _owner = owner;
    error = null;
  }

  Future<void> _save(String owner) async {
    final prefs = await SharedPreferences.getInstance();
    final pendingSaved = await prefs.setString(
        _key(owner),
        jsonEncode({
          for (final entry in _pending.entries)
            if (entry.value.isNotEmpty) entry.key: entry.value.toList()..sort(),
        }));
    final confirmedSaved = await prefs.setString(
        _confirmedKey(owner),
        jsonEncode({
          for (final entry in _confirmed.entries)
            if (entry.value.isNotEmpty) entry.key: entry.value.toList()..sort(),
        }));
    if (!pendingSaved || !confirmedSaved) {
      throw StateError('保存章节已读记录失败');
    }
  }

  Future<void> migrate(String book) {
    final owner = identity();
    return _serial(() async {
      if (!_active(owner)) return;
      await _load(owner);
      final legacy = ChapterReadMarksStore();
      final ids = await legacy.read('$owner:$book');
      if (!_active(owner) || ids.isEmpty) return;
      _pending.putIfAbsent(book, () => {}).addAll(ids);
      await _save(owner);
      await legacy.write('$owner:$book', {});
      _notify();
    });
  }

  Future<void> mark(String book, Iterable<String> chapters) {
    final owner = identity();
    final ids = chapters.toSet();
    return _serial(() async {
      if (!_active(owner) || ids.isEmpty) return;
      await _load(owner);
      if (!_active(owner)) return;
      _pending.putIfAbsent(book, () => {}).addAll(ids);
      await _save(owner);
      _notify();
    });
  }

  Future<void> flush() {
    final owner = identity();
    return _serial(() async {
      if (!_active(owner) || !canSync()) return;
      await _load(owner);
      for (final book in _pending.keys.toList()) {
        final ids = _pending[book]!.toList();
        for (var offset = 0; offset < ids.length; offset += 200) {
          if (!_active(owner) || !canSync()) return;
          final batch = ids.skip(offset).take(200).toList();
          try {
            await api.post(
                '/api/books/${Uri.encodeComponent(book)}/chapters/read-status',
                data: {'chapter_ids': batch, 'read': true});
          } catch (failure) {
            if (!_active(owner)) return;
            final status =
                failure is DioException ? failure.response?.statusCode : null;
            error = status == 404 || status == 405
                ? '章节已读尚未同步，请先升级服务端至 2.0.7 或更新版本'
                : ApiError.messageFor(failure);
            _notify();
            return;
          }
          if (!_active(owner)) return;
          _pending[book]!.removeAll(batch);
          _confirmed.putIfAbsent(book, () => {}).addAll(batch);
          await _save(owner);
          if (!_active(owner)) return;
          error = null;
          onSynced?.call(book, batch.toSet());
          _notify();
        }
      }
    }).catchError((Object failure) {
      if (_active(owner)) {
        error = ApiError.messageFor(failure);
        _notify();
      }
    });
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
