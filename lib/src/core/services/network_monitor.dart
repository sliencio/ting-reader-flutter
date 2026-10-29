import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';

enum NetworkAccess { unknown, wifi, ethernet, mobile, offline }

class NetworkMonitor extends ChangeNotifier with WidgetsBindingObserver {
  NetworkMonitor(
      {this.access = NetworkAccess.unknown, this.usePlatform = true});

  NetworkAccess access;
  final bool usePlatform;
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _started = false;
  bool _disposed = false;
  bool get unmetered =>
      access == NetworkAccess.wifi || access == NetworkAccess.ethernet;
  bool get offline => access == NetworkAccess.offline;

  Future<void> start() async {
    if (_started || _disposed || !usePlatform) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    try {
      _subscription = Connectivity()
          .onConnectivityChanged
          .listen(_apply, onError: (Object _) => update(NetworkAccess.unknown));
      await refresh();
    } catch (_) {
      update(NetworkAccess.unknown);
    }
  }

  Future<void> refresh() async {
    if (_disposed || !usePlatform) return;
    try {
      _apply(await Connectivity().checkConnectivity());
    } catch (_) {
      update(NetworkAccess.unknown);
    }
  }

  void _apply(List<ConnectivityResult> results) {
    update(results.contains(ConnectivityResult.mobile)
        ? NetworkAccess.mobile
        : results.contains(ConnectivityResult.wifi)
            ? NetworkAccess.wifi
            : results.contains(ConnectivityResult.ethernet)
                ? NetworkAccess.ethernet
                : results.contains(ConnectivityResult.none)
                    ? NetworkAccess.offline
                    : NetworkAccess.unknown);
  }

  void update(NetworkAccess next) {
    if (_disposed || next == access) return;
    access = next;
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refresh());
  }

  @override
  void dispose() {
    _disposed = true;
    if (_started) WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    super.dispose();
  }
}
