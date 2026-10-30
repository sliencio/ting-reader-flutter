part of '../player_state.dart';

typedef _ProgressSnapshot = ({
  Book book,
  Chapter chapter,
  double position,
  double duration,
});

/// Owns progress transport, timers and sockets; receives playback snapshots
/// without changing the audio source or chapter-selection state.
class _PlayerProgress {
  _PlayerProgress({
    required this.appState,
    required this.snapshot,
    required this.suspended,
    required this.needsHttpFallback,
    required this.onRemotePosition,
  }) {
    _retryTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!_blocked) unawaited(appState.chapterReadSync.flush());
      if (!_blocked && journal.pendingCount > 0) unawaited(journal.flush());
      if (_wantSocket && _socket == null) _scheduleReconnect();
    });
  }

  late final ListeningProgressSync journal = ListeningProgressSync(
    api: appState.api,
    identity: () =>
        '${appState.serverUrl}:${appState.fnId}:${appState.user?.id}',
    canSync: () => !_blocked,
  );

  Future<void> record(_ProgressSnapshot value) =>
      journal.record(PendingListeningProgress(
          bookId: value.book.id,
          chapterId: value.chapter.id,
          position: value.position,
          duration: value.duration > 0
              ? value.duration
              : value.chapter.duration.toDouble(),
          updatedAt: DateTime.now()));

  final AppState appState;
  final _ProgressSnapshot? Function() snapshot;
  final bool Function() suspended;
  final bool Function() needsHttpFallback;
  final void Function(String? bookId, String? chapterId, double position)
      onRemotePosition;
  WebSocket? _socket;
  StreamSubscription<dynamic>? _subscription;
  SocketHeartbeat? _heartbeat;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  int _socketAuthRevision = -1;
  bool _wantSocket = false;
  Timer? _webSocketTimer;
  Timer? _httpTimer;
  Timer? _retryTimer;
  bool _connecting = false;
  bool _disposed = false;
  int _generation = 0;
  final Set<String> _validatedBooks = {};

  bool get _blocked => _disposed || appState.offlineMode || suspended();

  Future<void> send() async {
    final value = snapshot();
    if (value == null) return;
    await record(value);
    if (_blocked) return;
    if (await _sendWebSocket(value)) return;
    if (!_blocked) await _sendHttp(value);
  }

  Future<void> _sendCurrentWebSocket() async {
    if (_blocked) return;
    final value = snapshot();
    if (value != null) {
      await record(value);
      if (!journal.conflicts.containsKey(value.book.id)) {
        await _sendWebSocket(value);
      }
    }
  }

  Future<void> _sendCurrentHttp() async {
    if (_blocked) {
      return;
    }
    final value = snapshot();
    if (value != null) await _sendHttp(value);
  }

  Future<void> _sendHttp(_ProgressSnapshot value) async {
    if (_blocked) return;
    try {
      await journal.flush();
    } catch (_) {
      // Background progress synchronization must not interrupt listening.
    }
  }

  Future<bool> _sendWebSocket(_ProgressSnapshot value) async {
    if (kIsWeb || _blocked || (appState.token?.isEmpty ?? true)) return false;
    if (journal.conflicts.containsKey(value.book.id)) return false;
    if (journal.syncing) return false;
    final owner = journal.identity();
    final revision = appState.api.authRevision;
    try {
      final socket = await _ensureSocket();
      if (socket == null || _blocked) return false;
      if (!_validatedBooks.contains(value.book.id)) {
        if (!await journal.prepareRealtime(value.book.id) || _blocked) {
          return false;
        }
        _validatedBooks.add(value.book.id);
      }
      if (_blocked ||
          journal.syncing ||
          owner != journal.identity() ||
          revision != appState.api.authRevision) {
        return false;
      }
      socket.add(jsonEncode({
        'type': 'progress_update',
        'book_id': value.book.id,
        'chapter_id': value.chapter.id,
        'position': value.position.floor(),
      }));
      return true;
    } catch (error) {
      if (_expiredSession(error)) _reauthenticate();
      _dropSocket();
      return false;
    }
  }

  Future<WebSocket?> _ensureSocket() async {
    if (_blocked) return null;
    _wantSocket = true;
    if (_socket != null && _socketAuthRevision == appState.api.authRevision) {
      return _socket;
    }
    if (_socket != null) closeSocket(reconnect: true);
    if (_connecting) return null;
    _connecting = true;
    final generation = _generation;
    final authRevision = appState.api.authRevision;
    var acceptConnection = true;
    try {
      final uri = _socketUri();
      if (uri == null) return null;
      final headers = appState.api.authHeaders;
      // A timed-out connect can still finish later. Close that late socket
      // instead of losing ownership of an open connection.
      final connection = WebSocket.connect(
        uri.toString(),
        headers: headers.isEmpty ? null : headers,
      ).then((socket) async {
        if (!acceptConnection ||
            _blocked ||
            generation != _generation ||
            authRevision != appState.api.authRevision) {
          await socket.close();
          return null;
        }
        return socket;
      });
      final socket = await connection.timeout(const Duration(seconds: 5));
      if (socket == null) return null;
      _socket = socket;
      _socketAuthRevision = authRevision;
      _reconnectAttempts = 0;
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      _subscription = socket.listen(
        (message) {
          if (identical(_socket, socket) &&
              authRevision == appState.api.authRevision) {
            _handleMessage(message);
          }
        },
        onDone: () {
          if (!identical(_socket, socket)) return;
          if (_expiredSession(socket.closeReason)) _reauthenticate();
          _dropSocket();
        },
        onError: (Object error) {
          if (!identical(_socket, socket)) return;
          if (_expiredSession(error)) _reauthenticate();
          _dropSocket();
        },
        cancelOnError: true,
      );
      _heartbeat = SocketHeartbeat(
        sendPing: () {
          if (identical(_socket, socket)) {
            socket.add(jsonEncode({'type': 'ping'}));
          }
        },
        onTimeout: () {
          if (identical(_socket, socket)) _dropSocket();
        },
      )..start();
      return socket;
    } catch (error) {
      if (!_disposed && generation == _generation) {
        if (_expiredSession(error)) _reauthenticate();
        _dropSocket();
      }
      return null;
    } finally {
      acceptConnection = false;
      _connecting = false;
    }
  }

  Uri? _socketUri() {
    final token = appState.token;
    if (token == null || token.isEmpty) return null;
    final base = Uri.tryParse(appState.activeUrl);
    if (base == null || base.host.isEmpty) return null;
    final path = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    return base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: '$path/api/ws',
      queryParameters: {'token': token},
    );
  }

  void _handleMessage(dynamic message) {
    if (_disposed || message == null) return;
    try {
      final raw = message is List<int>
          ? utf8.decode(message, allowMalformed: true)
          : message.toString();
      if (_expiredSession(raw)) {
        _reauthenticate();
        return;
      }
      final data = jsonDecode(raw);
      if (_expiredSession(data)) {
        _reauthenticate();
        return;
      }
      if (data is! Map) return;
      if (data['type'] == 'pong') {
        _heartbeat?.pong();
        return;
      }
      if (data['type'] != 'progress_updated') return;
      final position = _doubleValue(data['position']);
      if (position == null || !position.isFinite) return;
      unawaited(journal.observeRemote(Map<String, dynamic>.from(data)));
      if (journal.hasPending(data['book_id']?.toString() ?? '')) return;
      onRemotePosition(data['book_id']?.toString(),
          data['chapter_id']?.toString(), position);
    } catch (_) {
      // Malformed realtime packets must not affect playback.
    }
  }

  bool _expiredSession(Object? value) =>
      ApiClient.isInvalidGatewayTokenPayload(value) ||
      (value is WebSocketException &&
          RegExp(r'\bstatus(?:\s+code)?\s*:\s*401\b', caseSensitive: false)
              .hasMatch(value.message));

  void _reauthenticate() {
    closeSocket(reconnect: true);
    if (!_disposed) {
      unawaited(appState.recoverSession().then((_) {
        if (!_disposed) _scheduleReconnect();
      }));
    }
  }

  void _dropSocket() {
    closeSocket(reconnect: true);
    _scheduleReconnect();
  }

  void connectionChanged() {
    final wanted = _wantSocket;
    closeSocket(reconnect: wanted);
    _reconnectAttempts = 0;
    if (wanted) _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_blocked ||
        !_wantSocket ||
        _socket != null ||
        _reconnectTimer != null ||
        (appState.token?.isEmpty ?? true) ||
        appState.needsDirectLogin) {
      return;
    }
    final seconds = (1 << _reconnectAttempts.clamp(0, 5)).clamp(1, 30);
    _reconnectAttempts++;
    _reconnectTimer = Timer(Duration(seconds: seconds), () async {
      _reconnectTimer = null;
      if (_blocked || !_wantSocket) return;
      final socket = await _ensureSocket();
      if (socket == null) _scheduleReconnect();
    });
  }

  void start() {
    if (_blocked) return;
    stop();
    unawaited(send());
    _webSocketTimer = Timer.periodic(
        const Duration(seconds: 2), (_) => unawaited(_sendCurrentWebSocket()));
    _httpTimer = Timer.periodic(
        const Duration(seconds: 15), (_) => unawaited(_sendCurrentHttp()));
  }

  void stop() {
    _webSocketTimer?.cancel();
    _webSocketTimer = null;
    _httpTimer?.cancel();
    _httpTimer = null;
  }

  void closeSocket({bool reconnect = false}) {
    _generation++;
    if (!reconnect) _wantSocket = false;
    _validatedBooks.clear();
    _heartbeat?.stop();
    _heartbeat = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _socketAuthRevision = -1;
    unawaited(_subscription?.cancel());
    _subscription = null;
    final socket = _socket;
    _socket = null;
    if (socket != null) unawaited(socket.close());
  }

  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    stop();
    closeSocket();
    journal.dispose();
  }
}
