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

  Set<String> pendingFor(String book) => _owner == identity()
      ? Set.unmodifiable(_pending[book] ?? const <String>{})
      : {};
  Set<String> confirmedFor(String book) => _owner == identity()
      ? Set.unmodifiable(_confirmed[book] ?? const <String>{})
      : {};

  void acceptSnapshot(String book, Iterable<String> visibleIds) {
    // 成功回执只用于刷新前的即时显示，重新读取时以服务端章节为准。
    if (_owner == identity()) _confirmed[book]?.removeAll(visibleIds);
  }

  Future<void> _serial(Future<void> Function() action) {
    final next = _tail.then((_) => action());
    _tail = next.catchError((Object _) {});
    return next;
  }

  bool _active(String owner) => !_disposed && owner == identity();

  Future<void> _load(String owner) async {
    if (_owner == owner) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(owner));
    final data = raw == null
        ? <String, dynamic>{}
        : jsonDecode(raw) as Map<String, dynamic>;
    _pending.clear();
    _confirmed.clear();
    for (final entry in data.entries) {
      _pending[entry.key] = (entry.value as List).cast<String>().toSet();
    }
    _owner = owner;
    error = null;
  }

  Future<void> _save(String owner) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = await prefs.setString(
        _key(owner),
        jsonEncode({
          for (final entry in _pending.entries)
            if (entry.value.isNotEmpty) entry.key: entry.value.toList()..sort(),
        }));
    if (!saved) throw StateError('保存章节待同步记录失败');
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
