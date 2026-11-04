part of '../app_state.dart';

/// Owns direct-server discovery, redirect caching and probe HTTP clients.
/// It never changes account credentials or the selected application session.
class _AppConnectionResolver {
  _AppConnectionResolver({
    required SharedPreferences? Function() preferences,
    required this.textForLocale,
    required VoidCallback onChanged,
  })  : _preferences = preferences,
        _onChanged = onChanged;

  final SharedPreferences? Function() _preferences;
  final String Function(String, String) textForLocale;
  final VoidCallback _onChanged;
  SharedPreferences? get _prefs => _preferences();
  Map<String, String> _redirectCache = {};
  final Map<Dio, CancelToken> _activeProbes = {};
  RedirectResolution? lastRedirectResolution;
  bool resolvingRedirect = false;
  bool _disposed = false;

  void _checkActive() {
    if (_disposed) throw const _StartupCancelled();
  }

  void dispose() {
    _disposed = true;
    for (final entry in _activeProbes.entries) {
      final token = entry.value;
      if (!token.isCancelled) token.cancel('Server discovery disposed');
      entry.key.close(force: true);
    }
    _activeProbes.clear();
    _redirectCache.clear();
  }

  Future<RedirectResolution> resolveServerUrl(
    String source, {
    bool force = false,
  }) async {
    final normalizedSource = ApiClient.normalizeServerUrl(source);
    _checkActive();
    final cached = _redirectCache[normalizedSource];
    if (!force && cached != null) {
      final result = RedirectResolution(
        sourceUrl: normalizedSource,
        resolvedUrl: cached,
        fromCache: true,
      );
      lastRedirectResolution = result;
      _onChanged();
      return result;
    }

    resolvingRedirect = true;
    _onChanged();
    try {
      final resolved = await _probeRedirectTarget(normalizedSource);
      _checkActive();
      if (resolved == null) {
        throw StateError(textForLocale(
          '无法连接服务器',
          'Unable to connect to server',
        ));
      }
      _redirectCache[normalizedSource] = resolved;
      await _saveRedirectCache();
      final result = RedirectResolution(
        sourceUrl: normalizedSource,
        resolvedUrl: resolved,
        fromCache: false,
      );
      lastRedirectResolution = result;
      return result;
    } finally {
      resolvingRedirect = false;
      _onChanged();
    }
  }

  Future<RedirectResolution> resolveBestServerUrl({
    required String server,
    required String localServer,
    bool force = false,
    bool quick = false,
    CancelToken? cancelToken,
  }) async {
    _checkActive();
    void checkCancelled() {
      _checkActive();
      if (cancelToken?.isCancelled ?? false) {
        throw const _StartupCancelled();
      }
    }

    final candidates = await _serverCandidates(
      server: server,
      localServer: localServer,
    );
    checkCancelled();
    if (candidates.isEmpty) {
      throw StateError(textForLocale(
        '请填写广域网地址或局域网地址',
        'Enter a WAN or LAN server address',
      ));
    }

    resolvingRedirect = true;
    _onChanged();
    try {
      // 局域网与外网并行探测，谁先通就用谁、其余立刻放弃。
      //
      // 原实现按候选顺序串行探测：内网不通时要把 connectTimeout 走满
      // 才开始试外网，登录因此被拖慢十几秒。
      final winner = Completer<RedirectResolution?>();
      final loserToken = CancelToken();
      void cancelLosers() {
        if (!loserToken.isCancelled) loserToken.cancel('route resolved');
      }

      final probeTokens = <CancelToken>[];
      final running = <Future<void>>[];
      for (final candidate in candidates) {
        final combined = CancelToken();
        probeTokens.add(combined);
        // 外部取消（用户取消启动）要能同时打断所有分支。
        cancelToken?.whenCancel.then((_) {
          if (!combined.isCancelled) combined.cancel('startup cancelled');
        });
        loserToken.whenCancel.then((_) {
          if (!combined.isCancelled) combined.cancel('route resolved');
        });
        running.add(() async {
          try {
            checkCancelled();
            final resolution = await _resolveReachableServerUrl(
              candidate,
              force: force,
              quick: quick,
              cancelToken: combined,
            );
            checkCancelled();
            if (resolution != null && !winner.isCompleted) {
              winner.complete(resolution);
              cancelLosers();
            }
          } on _StartupCancelled {
            // 用户取消启动：把取消信号交回调用方，不要吞掉。
            if (!winner.isCompleted) {
              winner.completeError(const _StartupCancelled());
            }
            cancelLosers();
          } catch (_) {
            // 这个候选不可达，交给其他分支。
          }
        }());
      }
      unawaited(Future.wait(running).then((_) {
        if (!winner.isCompleted) winner.complete(null);
      }));

      final resolved = await winner.future;
      if (resolved != null) {
        lastRedirectResolution = resolved;
        return resolved;
      }
      throw StateError(textForLocale(
        '无法连接服务器',
        'Unable to connect to server',
      ));
    } finally {
      resolvingRedirect = false;
      _onChanged();
    }
  }

  void _loadRedirectCache() {
    final raw = _prefs?.getString('redirect_cache');
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        _redirectCache = decoded.map(
          (key, value) => MapEntry(key.toString(), value.toString()),
        );
      }
    } catch (_) {
      _redirectCache = {};
    }
  }

  Future<void> _saveRedirectCache() async {
    await _prefs?.setString('redirect_cache', jsonEncode(_redirectCache));
  }

  Future<List<String>> _serverCandidates({
    required String server,
    required String localServer,
  }) async {
    final wideArea = _normalizeOptionalServerUrl(server);
    final localArea = _normalizeOptionalServerUrl(localServer);
    if (localArea.isEmpty) return wideArea.isEmpty ? const [] : [wideArea];
    if (wideArea.isEmpty) return [localArea];
    if (wideArea == localArea) return [localArea];

    final sameSubnet = await isServerOnCurrentIpv4Subnet(localArea);
    return sameSubnet == false ? [wideArea, localArea] : [localArea, wideArea];
  }

  String _normalizeOptionalServerUrl(String input) {
    final trimmed = input.trim();
    return trimmed.isEmpty ? '' : ApiClient.normalizeServerUrl(trimmed);
  }

  Future<RedirectResolution?> _resolveReachableServerUrl(
    String normalizedSource, {
    required bool force,
    bool quick = false,
    CancelToken? cancelToken,
  }) async {
    void checkCancelled() {
      _checkActive();
      if (cancelToken?.isCancelled ?? false) {
        throw const _StartupCancelled();
      }
    }

    if (normalizedSource.isEmpty) return null;

    final cached = _redirectCache[normalizedSource];
    if (!force && cached != null && cached.isNotEmpty) {
      final resolved = await _probeRedirectTarget(
        normalizedSource,
        quick: quick,
        cancelToken: cancelToken,
      );
      checkCancelled();
      if (resolved != null) {
        _redirectCache[normalizedSource] = resolved;
        await _saveRedirectCache();
        return RedirectResolution(
          sourceUrl: normalizedSource,
          resolvedUrl: resolved,
          fromCache: resolved == cached,
        );
      }

      if (cached != normalizedSource) {
        final reachable = await _probeRedirectTarget(
          cached,
          quick: quick,
          cancelToken: cancelToken,
        );
        checkCancelled();
        if (reachable != null) {
          return RedirectResolution(
            sourceUrl: normalizedSource,
            resolvedUrl: cached,
            fromCache: true,
          );
        }
      }

      _redirectCache.remove(normalizedSource);
      await _saveRedirectCache();
      return null;
    }

    final resolved = await _probeRedirectTarget(
      normalizedSource,
      quick: quick,
      cancelToken: cancelToken,
    );
    checkCancelled();
    if (resolved == null) return null;
    _redirectCache[normalizedSource] = resolved;
    await _saveRedirectCache();
    return RedirectResolution(
      sourceUrl: normalizedSource,
      resolvedUrl: resolved,
      fromCache: false,
    );
  }

  Future<String?> _probeRedirectTarget(
    String sourceUrl, {
    bool quick = false,
    CancelToken? cancelToken,
  }) async {
    _checkActive();
    if (cancelToken?.isCancelled ?? false) {
      throw const _StartupCancelled();
    }
    final dio = Dio(
      BaseOptions(
        connectTimeout:
            quick ? const Duration(seconds: 3) : const Duration(seconds: 8),
        receiveTimeout:
            quick ? const Duration(seconds: 4) : const Duration(seconds: 12),
        followRedirects: true,
        maxRedirects: 8,
        validateStatus: (_) => true,
      ),
    );

    final probeToken = cancelToken ?? CancelToken();
    _activeProbes[dio] = probeToken;
    try {
      for (final path in ['/api/health', '/api/me']) {
        try {
          final response = await dio.getUri<dynamic>(
            Uri.parse('$sourceUrl$path'),
            options: Options(responseType: ResponseType.plain),
            cancelToken: probeToken,
          );
          if (_isBackendProbeResponse(path, response)) {
            return ApiClient.originFromUri(response.realUri);
          }
        } on DioException catch (error) {
          if (CancelToken.isCancel(error)) rethrow;
          // Try the next probe path.
        } catch (_) {
          // Try the next probe path.
        }
      }
    } finally {
      _activeProbes.remove(dio);
      dio.close(force: true);
    }

    return null;
  }

  bool _isBackendProbeResponse(String path, Response<dynamic> response) {
    final status = response.statusCode ?? 0;
    if (path == '/api/health') {
      if (status < 200 || status >= 300) return false;
      final data = response.data;
      if (data is Map) {
        return data['status']?.toString().toLowerCase() == 'healthy';
      }
      final text = data?.toString() ?? '';
      return text.contains('"status"') && text.contains('healthy');
    }
    return status == 401 || status == 403;
  }
}
