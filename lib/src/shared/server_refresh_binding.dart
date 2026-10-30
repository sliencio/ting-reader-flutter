import 'dart:async';
import 'package:flutter/foundation.dart';

class ServerRefreshBinding {
  ServerRefreshBinding({required this.visible, required this.refresh});
  final bool Function() visible;
  final Future<void> Function() refresh;
  ValueListenable<int>? _source;
  Timer? _timer;
  bool _dirty = false;
  bool _running = false;
  bool _disposed = false;

  void bind(ValueListenable<int> source) {
    if (identical(source, _source)) return;
    _source?.removeListener(_changed);
    _source = source..addListener(_changed);
  }

  void _changed() {
    _dirty = true;
    resume();
  }

  void resume() {
    if (_disposed || !_dirty || !visible() || _timer != null || _running) {
      return;
    }
    _timer = Timer(const Duration(milliseconds: 250), () async {
      _timer = null;
      if (_disposed || !_dirty || !visible()) return;
      _dirty = false;
      _running = true;
      try {
        await refresh();
      } finally {
        _running = false;
        resume();
      }
    });
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _source?.removeListener(_changed);
  }
}
