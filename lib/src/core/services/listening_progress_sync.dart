import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../models/models.dart';

class PendingListeningProgress {
  const PendingListeningProgress(
      {required this.bookId,
      required this.chapterId,
      required this.position,
      required this.duration,
      required this.updatedAt,
      this.unsyncedSince});
  final String bookId;
  final String chapterId;
  final double position;
  final double duration;
  final DateTime updatedAt;
  final DateTime? unsyncedSince;
  Map<String, dynamic> toJson() => {
        'book_id': bookId,
        'chapter_id': chapterId,
        'position': position,
        'duration': duration,
        'updated_at': updatedAt.toUtc().toIso8601String(),
        'unsynced_since':
            (unsyncedSince ?? updatedAt).toUtc().toIso8601String(),
      };
  factory PendingListeningProgress.fromJson(Map<String, dynamic> json) =>
      PendingListeningProgress(
          bookId: json['book_id'] as String,
          chapterId: json['chapter_id'] as String,
          position: (json['position'] as num).toDouble(),
          duration: (json['duration'] as num).toDouble(),
          updatedAt: DateTime.parse(json['updated_at'] as String),
          unsyncedSince:
              DateTime.tryParse(json['unsynced_since']?.toString() ?? ''));
}

class ListeningProgressSync extends ChangeNotifier {
  ListeningProgressSync(
      {required this.api, required this.identity, required this.canSync});
  final ApiClient api;
  final String Function() identity;
  final bool Function() canSync;
  final Map<String, Map<String, PendingListeningProgress>> _pending = {};
  final Map<String, Map<String, ProgressItem>> _acknowledged = {};
  final Map<String, Map<String, ProgressItem>> _conflicts = {};
  Future<void> _writes = Future<void>.value();
  Future<void>? _flushing;
  bool _disposed = false;
  String? error;
  String? _deviceId;
  bool versioned(String book) =>
      _acknowledged[identity()]?[book]?.revision != null;
  bool get syncing => _flushing != null;
  int get pendingCount => _pending[identity()]?.length ?? 0;
  Map<String, ProgressItem> get conflicts =>
      Map.unmodifiable(_conflicts[identity()] ?? {});
  bool hasPending(String bookId) =>
      _pending[identity()]?.containsKey(bookId) ?? false;
  String _key(String owner) =>
      'listening_progress:${base64Url.encode(utf8.encode(owner))}';

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _load(String owner) async {
    if (_pending.containsKey(owner)) return;
    final prefs = await SharedPreferences.getInstance();
    _deviceId ??= prefs.getString('listening_device_id');
    if (_deviceId == null) {
      _deviceId = base64Url
          .encode(List.generate(24, (_) => Random.secure().nextInt(256)));
      await prefs.setString('listening_device_id', _deviceId!);
    }
    final items = <String, PendingListeningProgress>{};
    final ack = <String, ProgressItem>{};
    try {
      final json = asMap(jsonDecode(prefs.getString(_key(owner)) ?? '{}'));
      for (final value in asMapList(json['pending'])) {
        final item = PendingListeningProgress.fromJson(value);
        if (item.position.isFinite &&
            item.duration.isFinite &&
            item.bookId.isNotEmpty &&
            item.chapterId.isNotEmpty) {
          items[item.bookId] = item;
        }
      }
      for (final value in asMapList(json['acknowledged'])) {
        final item = ProgressItem.fromJson(value);
        ack[item.bookId] = item;
      }
    } catch (_) {
      // 损坏的旧记录不影响本次收听。
    }
    _pending[owner] = items;
    _acknowledged[owner] = ack;
    _notify();
  }

  Future<void> _persist(String owner) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key(owner),
        jsonEncode({
          'pending':
              _pending[owner]!.values.map((item) => item.toJson()).toList(),
          'acknowledged': _acknowledged[owner]!
              .values
              .map((item) => {
                    'book_id': item.bookId,
                    'chapter_id': item.chapterId,
                    'position': item.position,
                    'duration': item.duration,
                    'updated_at': item.updatedAt,
                    'revision': item.revision,
                  })
              .toList(),
        }));
  }

  Future<void> _serialize(Future<void> Function() action) {
    final result = _writes.catchError((_) {}).then((_) => action());
    _writes = result.catchError((Object failure) {
      error = failure.toString();
      _notify();
    });
    return result;
  }

  Future<void> initialize() => _serialize(() => _load(identity()));

  Future<void> observeRemote(Map<String, dynamic> data,
      {bool Function()? applyRemote}) {
    final owner = identity();
    final remote = ProgressItem.fromJson(data);
    return _serialize(() async {
      await _load(owner);
      if (_disposed || owner != identity()) return;
      final acknowledged = _acknowledged[owner]![remote.bookId];
      if (remote.revision != null &&
          acknowledged?.revision != null &&
          remote.revision! < acknowledged!.revision!) {
        return;
      }
      final pending = _pending[owner]![remote.bookId];
      if (data['device_id'] == _deviceId) {
        _acknowledged[owner]![remote.bookId] = remote;
        if (pending != null &&
            remote.chapterId == pending.chapterId &&
            (remote.position - pending.position).abs() < 1) {
          _pending[owner]!.remove(remote.bookId);
        }
        await _persist(owner);
        _notify();
        return;
      }
      if (_conflicts[owner]?.containsKey(remote.bookId) ?? false) return;
      if (pending != null && _remoteConflicts(owner, pending, remote)) {
        _conflicts.putIfAbsent(owner, () => {})[remote.bookId] = remote;
        _notify();
        return;
      }
      if (pending != null &&
          remote.chapterId == pending.chapterId &&
          (remote.position - pending.position).abs() < 1) {
        _acknowledged[owner]![remote.bookId] = remote;
        _pending[owner]!.remove(remote.bookId);
        await _persist(owner);
        _notify();
        applyRemote?.call();
      } else if (pending == null && (applyRemote?.call() ?? false)) {
        _acknowledged[owner]![remote.bookId] = remote;
        await _persist(owner);
      }
    });
  }

  Future<bool> prepareRealtime(String bookId) async {
    final owner = identity();
    if (_disposed || !canSync()) return false;
    await initialize();
    try {
      final remote = await _remote(bookId);
      if (_disposed || identity() != owner || !canSync()) return false;
      final pending = _pending[owner]![bookId];
      if (pending != null &&
          remote != null &&
          _remoteConflicts(owner, pending, remote)) {
        _conflicts.putIfAbsent(owner, () => {})[bookId] = remote;
        _notify();
        return false;
      }
      if (remote != null && !_acknowledged[owner]!.containsKey(bookId)) {
        _acknowledged[owner]![bookId] = remote;
        await _persist(owner);
      }
      return !conflicts.containsKey(bookId);
    } catch (failure) {
      error = failure.toString();
      _notify();
      return false;
    }
  }

  Future<void> record(PendingListeningProgress value) {
    final owner = identity();
    return _serialize(() async {
      await _load(owner);
      final previous = _pending[owner]![value.bookId];
      if (previous != null && previous.updatedAt.isAfter(value.updatedAt)) {
        return;
      }
      _pending[owner]![value.bookId] = PendingListeningProgress(
          bookId: value.bookId,
          chapterId: value.chapterId,
          position: value.position,
          duration: value.duration,
          updatedAt: value.updatedAt,
          unsyncedSince: previous?.unsyncedSince ??
              previous?.updatedAt ??
              value.updatedAt);
      await _persist(owner);
      _notify();
    });
  }

  Future<ProgressItem?> _remote(String bookId) async {
    try {
      final response =
          await api.get('/api/progress/${Uri.encodeComponent(bookId)}');
      final data = asMap(response.data);
      return data['book_id'] == null ? null : ProgressItem.fromJson(data);
    } on DioException catch (failure) {
      if (failure.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  bool _same(ProgressItem? a, ProgressItem b) =>
      a != null &&
      (a.revision == null || b.revision == null || a.revision == b.revision) &&
      a.chapterId == b.chapterId &&
      (a.position - b.position).abs() < 1 &&
      (a.updatedAt == b.updatedAt ||
          (DateTime.tryParse(a.updatedAt ?? '') != null &&
              DateTime.tryParse(b.updatedAt ?? '') != null &&
              DateTime.parse(a.updatedAt!)
                      .difference(DateTime.parse(b.updatedAt!))
                      .inMilliseconds
                      .abs() <=
                  2000));

  bool _remoteConflicts(
      String owner, PendingListeningProgress value, ProgressItem remote) {
    if (remote.chapterId == value.chapterId &&
        (remote.position - value.position).abs() < 1) {
      return false;
    }
    if (_same(_acknowledged[owner]![value.bookId], remote)) return false;
    final acknowledged = _acknowledged[owner]![value.bookId];
    if (acknowledged?.revision != null && remote.revision != null) {
      return acknowledged!.revision != remote.revision;
    }
    final remoteAt = DateTime.tryParse(remote.updatedAt ?? '');
    return remoteAt != null &&
        remoteAt.isAfter((value.unsyncedSince ?? value.updatedAt)
            .add(const Duration(seconds: 2)));
  }

  Future<void> flush() {
    if (_disposed || !canSync()) return Future.value();
    return _flushing ??= _flush().catchError((Object failure) {
      error = failure.toString();
      _notify();
    }).whenComplete(() {
      _flushing = null;
    });
  }

  Future<void> _flush() async {
    final owner = identity();
    final revision = api.authRevision;
    bool active() =>
        !_disposed &&
        owner == identity() &&
        revision == api.authRevision &&
        canSync();
    await initialize();
    if (!active()) return;
    final entries = _pending[owner]!.values.toList()
      ..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
    for (final value in entries) {
      if (!active()) return;
      if (_conflicts[owner]?.containsKey(value.bookId) ?? false) continue;
      try {
        final remote = await _remote(value.bookId);
        if (!active()) return;
        if (remote != null && _remoteConflicts(owner, value, remote)) {
          _conflicts.putIfAbsent(owner, () => {})[value.bookId] = remote;
          _notify();
          continue;
        }
        // 每次请求前再次核对账号和待上传快照，切服或新进度不能串到旧请求里。
        if (!identical(_pending[owner]![value.bookId], value)) continue;
        final response = await api.post('/api/progress', data: {
          'book_id': value.bookId,
          'chapter_id': value.chapterId,
          'position': value.position,
          'duration': value.duration,
          if (remote?.revision != null) 'base_revision': remote!.revision,
          if (remote?.revision != null) 'device_id': _deviceId,
        });
        if (!active()) return;
        final ackData = asMap(response.data);
        final accepted = ProgressItem.fromJson(
            ackData['book_id'] != null ? ackData : value.toJson());
        await _serialize(() async {
          _acknowledged[owner]![value.bookId] = accepted;
          if (identical(_pending[owner]![value.bookId], value)) {
            _pending[owner]!.remove(value.bookId);
          }
          await _persist(owner);
        });
        error = null;
        _notify();
      } catch (failure) {
        if (!active()) return;
        if (failure is DioException && failure.response?.statusCode == 409) {
          final current = asMap(asMap(failure.response?.data)['current']);
          if (current['book_id'] == value.bookId) {
            _conflicts.putIfAbsent(owner, () => {})[value.bookId] =
                ProgressItem.fromJson(current);
            error = '其他设备已更新进度，请选择续播位置';
            _notify();
            continue;
          }
        }
        error = failure.toString();
        _notify();
        return;
      }
    }
  }

  Future<ProgressItem?> resolve(String bookId,
      {required bool useRemote}) async {
    final owner = identity();
    if (useRemote) {
      if (!canSync()) throw StateError('请联网后再采用其他设备的进度');
      final remote = await _remote(bookId);
      if (_disposed || owner != identity()) return null;
      if (remote == null) throw StateError('其他设备的进度已不存在');
      await _serialize(() async {
        await _load(owner);
        _pending[owner]!.remove(bookId);
        _acknowledged[owner]![bookId] = remote;
        _conflicts[owner]?.remove(bookId);
        await _persist(owner);
      });
      _notify();
      return remote;
    }
    final latest = canSync() ? await _remote(bookId) : null;
    if (_disposed || owner != identity()) return null;
    // 明确选择本机后，以刚读取的远端版本为基线；并发更新仍由服务端拒绝。
    await _serialize(() async {
      await _load(owner);
      final current = _pending[owner]![bookId];
      if (latest != null) _acknowledged[owner]![bookId] = latest;
      if (current != null) {
        _pending[owner]![bookId] = PendingListeningProgress(
            bookId: current.bookId,
            chapterId: current.chapterId,
            position: current.position,
            duration: current.duration,
            updatedAt: DateTime.now());
      }
      _conflicts[owner]?.remove(bookId);
      await _persist(owner);
    });
    _notify();
    await flush();
    return null;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
