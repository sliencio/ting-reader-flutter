import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

/// Shared by shelf, details and player. Stores image bytes, never request headers.
class CoverCache {
  CoverCache({Future<Directory> Function()? directory})
      : _directory = directory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directory;
  final _pending = <String, Future<File?>>{};
  final _files = <String, File>{};
  final _listeners = <String, List<void Function(File)>>{};
  final _latestRequests = <String, String>{};
  Future<void>? _clearing;
  int _generation = 0;
  static const maxBytes = 200 * 1024 * 1024;
  static const maxAge = Duration(days: 30);
  int get generation => _generation;

  String key(String identity, String url, {required bool serverResource}) {
    final uri = Uri.parse(url);
    final params = Map<String, String>.of(uri.queryParameters);
    if (serverResource) params.remove('token');
    final source =
        uri.replace(queryParameters: params, fragment: '').toString();
    // Gateway relay/LAN addresses and renewed tokens identify the same cover.
    final resource = serverResource
        ? Uri(path: uri.path, queryParameters: params).toString()
        : source;
    return sha256.convert(utf8.encode('$identity|$resource')).toString();
  }

  File? peek(String key) => _files[key];

  Future<File?> load(String key, Future<List<int>> Function() fetch,
      {String version = '', void Function(File)? onCached}) {
    final requestKey = '$_generation:$key:$version';
    _latestRequests[key] = requestKey;
    if (onCached != null) {
      _listeners.putIfAbsent(key, () => []).add(onCached);
    }
    final pending = _pending.putIfAbsent(
      requestKey,
      () => _load(key, version, requestKey, fetch).whenComplete(() {
        _pending.remove(requestKey);
        if (_latestRequests[key] == requestKey) _latestRequests.remove(key);
      }),
    );
    return pending.whenComplete(() {
      if (onCached != null) {
        _listeners[key]?.remove(onCached);
        if (_listeners[key]?.isEmpty ?? false) _listeners.remove(key);
      }
    });
  }

  Future<File?> _load(String key, String version, String requestKey,
      Future<List<int>> Function() fetch) async {
    final generation = _generation;
    File? cached;
    try {
      await _clearing;
      if (generation != _generation || _latestRequests[key] != requestKey)
        return null;
      final root = Directory('${(await _directory()).path}/book_covers_v1');
      await root.create(recursive: true);
      final manifest = File('${root.path}/$key.json');
      try {
        final saved = jsonDecode(await manifest.readAsString()) as Map;
        final digest = saved['digest'] as String;
        if (RegExp(r'^[a-f0-9]{64}$').hasMatch(digest)) {
          final candidate = File('${root.path}/$key.$digest.img');
          if (await candidate.exists() && await candidate.length() > 0) {
            cached = candidate;
            if (generation != _generation) return null;
            _remember(key, candidate);
            final age =
                DateTime.now().difference(await manifest.lastModified());
            if (age < maxAge &&
                (version.isEmpty || saved['version'] == version)) {
              return candidate;
            }
          }
        }
      } catch (_) {/* Missing or corrupt cache: fetch a fresh image. */}
      try {
        final bytes = await fetch();
        if (bytes.isEmpty || bytes.length > 10 * 1024 * 1024) return cached;
        if (generation != _generation || _latestRequests[key] != requestKey)
          return null;
        final digest = sha256.convert(bytes).toString();
        final file = File('${root.path}/$key.$digest.img');
        if (!await file.exists()) {
          final temporary = File('${file.path}.$generation.tmp');
          await temporary.writeAsBytes(bytes, flush: true);
          if (generation != _generation || _latestRequests[key] != requestKey) {
            await temporary.delete();
            return null;
          }
          await temporary.rename(file.path);
        }
        await manifest
            .writeAsString(jsonEncode({'digest': digest, 'version': version}));
        if (generation != _generation || _latestRequests[key] != requestKey)
          return null;
        if (cached != null &&
            cached.path != file.path &&
            await cached.exists()) {
          await cached.delete();
        }
        _remember(key, file);
        try {
          await _trim(root);
        } catch (_) {
          // Concurrent downloads or cache clearing can remove a trim candidate.
        }
        return generation == _generation ? file : null;
      } catch (_) {
        // A stale cover is still useful when the NAS or STRM origin is offline.
        if (cached != null && await cached.exists()) {
          _remember(key, cached);
          return cached;
        }
        rethrow;
      }
    } catch (_) {
      return null;
    }
  }

  void _remember(String key, File file) {
    _files.remove(key);
    _files[key] = file;
    if (_files.length > 512) _files.remove(_files.keys.first);
    for (final listener
        in List.of(_listeners[key] ?? <void Function(File)>[])) {
      listener(file);
    }
  }

  Future<void> invalidate() {
    _generation++;
    _files.clear();
    _pending.clear();
    _listeners.clear();
    _latestRequests.clear();
    final previous = _clearing;
    final clearing = _clearDisk(previous);
    _clearing = clearing;
    return clearing.whenComplete(() {
      if (identical(_clearing, clearing)) _clearing = null;
    });
  }

  Future<void> _clearDisk(Future<void>? previous) async {
    await previous;
    try {
      final root = Directory('${(await _directory()).path}/book_covers_v1');
      if (await root.exists()) await root.delete(recursive: true);
    } catch (_) {
      // Cache cleanup must not block an explicit refresh.
    }
  }

  Future<void> _trim(Directory root) async {
    final files = <(File, FileStat)>[];
    var total = 0;
    await for (final entry in root.list()) {
      if (entry is! File || !entry.path.endsWith('.img')) continue;
      final stat = await entry.stat();
      total += stat.size;
      files.add((entry, stat));
    }
    files.sort((a, b) => a.$2.modified.compareTo(b.$2.modified));
    for (final entry in files) {
      if (total <= maxBytes) break;
      await entry.$1.delete();
      total -= entry.$2.size;
      final key = entry.$1.uri.pathSegments.last.split('.').first;
      _files.remove(key);
      final manifest = File('${root.path}/$key.json');
      if (await manifest.exists()) await manifest.delete();
    }
  }
}
