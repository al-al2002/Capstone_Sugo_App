import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import '../config/app_env.dart';

/// Knows, roughly, whether SUGO can reach its server right now.
///
/// ## Why this checks the server rather than the network interface
///
/// The usual approach is a plugin that reports whether Wi-Fi or mobile data is
/// switched on. That answers the wrong question. A phone on café Wi-Fi behind a
/// sign-in page, or on one bar of 3G, reports "connected" and still cannot load
/// a single booking - which is exactly the moment a "You're offline" banner
/// should appear. So this asks the thing the app actually depends on: can we
/// reach Supabase's auth health endpoint?
///
/// It also needs no new plugin (it uses the `http` package the app already
/// declares) and no extra permission, and it works the same on web.
///
/// ## Cost, and why it is acceptable
///
/// One `HEAD`-sized request every [_onlineInterval] while the app is in the
/// foreground, nothing while it is backgrounded. The response is a few bytes.
/// When offline it checks more often ([_offlineInterval]) so the banner clears
/// promptly once the connection returns.
///
/// ## Why two failures before "offline"
///
/// A single timed-out probe on a moving phone is noise. Flashing an offline
/// banner for one blip teaches people to ignore it, so the state flips to
/// offline only after [_failuresBeforeOffline] consecutive failures - and back
/// to online on the first success, because good news should not wait.
class ConnectivityMonitor extends ChangeNotifier with WidgetsBindingObserver {
  ConnectivityMonitor._();

  static final ConnectivityMonitor instance = ConnectivityMonitor._();

  static const Duration _onlineInterval = Duration(seconds: 20);
  static const Duration _offlineInterval = Duration(seconds: 6);
  static const Duration _timeout = Duration(seconds: 6);
  static const int _failuresBeforeOffline = 2;

  bool _online = true;
  bool _started = false;
  int _failures = 0;
  Timer? _timer;

  bool get isOnline => _online;

  /// Begins probing. Safe to call more than once.
  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    unawaited(check());
  }

  /// Something else just failed on the network - a list load, a send. Check
  /// now rather than waiting for the next scheduled probe, so the banner
  /// appears while the user is still looking at the failure.
  void reportFailure() => unawaited(check());

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(check());
    } else if (state == AppLifecycleState.paused) {
      _timer?.cancel();
    }
  }

  /// One probe. Public so pull-to-refresh can force a re-check.
  Future<void> check() async {
    _timer?.cancel();
    bool reachable;
    try {
      final http.Response response = await http
          .get(Uri.parse('${AppEnv.supabaseUrl}/auth/v1/health'),
              headers: <String, String>{'apikey': AppEnv.supabaseAnonKey})
          .timeout(_timeout);
      // Any answer at all means the server is reachable. A 401 or 404 is a
      // configuration matter, not a connectivity one.
      reachable = response.statusCode < 500;
    } catch (_) {
      reachable = false;
    }

    if (reachable) {
      _failures = 0;
      _set(true);
    } else {
      _failures++;
      if (_failures >= _failuresBeforeOffline) _set(false);
    }

    if (_started) {
      _timer = Timer(
        _online && _failures == 0 ? _onlineInterval : _offlineInterval,
        () => unawaited(check()),
      );
    }
  }

  void _set(bool online) {
    if (_online == online) return;
    _online = online;
    notifyListeners();
  }

  /// Tests only: force a state without touching the network.
  @visibleForTesting
  void debugSet(bool online) => _set(online);
}
