import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Small, device-local preferences that do not deserve a table.
///
/// ## What lives here, and why none of it is in Supabase
///
/// * **Favourite technicians** - the user chose on-device storage over a new
///   table (2026-09-22). A favourite that does not follow you to a new phone is
///   a small loss; a schema change for a convenience feature is not.
/// * **Recent searches** - private by nature, and useless on another device.
/// * **Notification read state** - the notification centre is *derived* from
///   job and message data rather than stored, so "which ones have I seen" has
///   nowhere on the server to live. See `NotificationFeedService`.
/// * **Notification preferences** - which in-app alerts to show.
///
/// Every key is scoped by user id where it is personal, so two people signing
/// in on one shared family phone do not see each other's favourites.
///
/// ## Failure mode
///
/// Every read falls back to an empty or default value and every write
/// swallows its error. These are conveniences: a preference that fails to save
/// must never surface as an error over the screen that tried to save it.
class LocalPrefs extends ChangeNotifier {
  LocalPrefs._();

  static final LocalPrefs instance = LocalPrefs._();

  SharedPreferences? _prefs;

  Future<SharedPreferences?> _store() async {
    try {
      return _prefs ??= await SharedPreferences.getInstance();
    } catch (error) {
      if (kDebugMode) debugPrint('LocalPrefs unavailable: $error');
      return null;
    }
  }

  /// Drops the cached store and caches, so the next read goes back to
  /// `SharedPreferences`.
  ///
  /// Tests only, and necessary rather than convenient: this is a singleton
  /// that holds a `SharedPreferences` instance, and that instance keeps its
  /// own in-memory copy of the values. `setMockInitialValues` between tests
  /// replaces the backing store but not that copy, so without this one test's
  /// favourites and read state leak into the next.
  @visibleForTesting
  void debugReset() {
    _prefs = null;
    _favCache.clear();
  }

  // ------------------------------------------------------------ keys

  static String _favKey(String uid) => 'fav_technicians.$uid';
  static String _recentKey(String uid) => 'recent_searches.$uid';
  static String _seenKey(String uid) => 'notifications_seen.$uid';
  static String _observedKey(String uid) => 'notifications_observed.$uid';
  static String _notifPrefKey(String uid, String channel) =>
      'notify.$channel.$uid';

  static const int maxRecentSearches = 8;

  /// How many seen-notification ids to remember. The feed is rebuilt from the
  /// last few weeks of activity, so older ids can be forgotten safely.
  static const int _maxSeenIds = 300;

  // -------------------------------------------------------- favourites

  final Map<String, Set<String>> _favCache = <String, Set<String>>{};

  Future<Set<String>> favoriteTechnicians(String uid) async {
    final Set<String>? cached = _favCache[uid];
    if (cached != null) return cached;
    final List<String> stored =
        (await _store())?.getStringList(_favKey(uid)) ?? const <String>[];
    return _favCache[uid] = stored.toSet();
  }

  Future<bool> isFavorite(String uid, String technicianId) async =>
      (await favoriteTechnicians(uid)).contains(technicianId);

  /// Flips a favourite and returns the new state.
  Future<bool> toggleFavorite(String uid, String technicianId) async {
    final Set<String> favs = Set<String>.of(await favoriteTechnicians(uid));
    final bool nowFavorite = !favs.remove(technicianId);
    if (nowFavorite) favs.add(technicianId);
    _favCache[uid] = favs;
    notifyListeners();
    try {
      await (await _store())?.setStringList(_favKey(uid), favs.toList());
    } catch (_) {}
    return nowFavorite;
  }

  // ---------------------------------------------------- recent searches

  Future<List<String>> recentSearches(String uid) async =>
      (await _store())?.getStringList(_recentKey(uid)) ?? const <String>[];

  Future<void> addRecentSearch(String uid, String query) async {
    final String trimmed = query.trim();
    if (trimmed.length < 2) return;
    final List<String> current = List<String>.of(await recentSearches(uid))
      ..removeWhere((String q) => q.toLowerCase() == trimmed.toLowerCase())
      ..insert(0, trimmed);
    try {
      await (await _store())?.setStringList(
        _recentKey(uid),
        current.take(maxRecentSearches).toList(),
      );
    } catch (_) {}
  }

  Future<void> clearRecentSearches(String uid) async {
    try {
      await (await _store())?.remove(_recentKey(uid));
    } catch (_) {}
  }

  // ------------------------------------------------- notification state

  Future<Set<String>> seenNotifications(String uid) async =>
      ((await _store())?.getStringList(_seenKey(uid)) ?? const <String>[])
          .toSet();

  Future<void> markNotificationsSeen(String uid, Iterable<String> ids) async {
    final List<String> merged = <String>{
      ...ids,
      ...await seenNotifications(uid),
    }.take(_maxSeenIds).toList();
    try {
      await (await _store())?.setStringList(_seenKey(uid), merged);
    } catch (_) {}
    notifyListeners();
  }

  /// When each derived notification was first noticed, as epoch milliseconds.
  ///
  /// Most job status changes carry no timestamp of their own - `jobs` has a
  /// `created_at` and nothing recording when it became confirmed - so the feed
  /// stamps a status the first time it sees it and keeps that stamp. Null
  /// means nothing has ever been stored, which the feed uses to recognise a
  /// first run and avoid presenting months-old history as brand new.
  Future<Map<String, int>?> notificationObservedTimes(String uid) async {
    final String? raw = (await _store())?.getString(_observedKey(uid));
    if (raw == null) return null;
    try {
      final Map<String, dynamic> decoded =
          jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map(
        (String k, dynamic v) => MapEntry<String, int>(k, (v as num).toInt()),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> saveNotificationObservedTimes(
    String uid,
    Map<String, int> times,
  ) async {
    // Newest first, capped, so the map cannot grow for the life of the app.
    final List<MapEntry<String, int>> entries = times.entries.toList()
      ..sort((MapEntry<String, int> a, MapEntry<String, int> b) =>
          b.value.compareTo(a.value));
    final Map<String, int> capped = Map<String, int>.fromEntries(
      entries.take(_maxSeenIds),
    );
    try {
      await (await _store())?.setString(_observedKey(uid), jsonEncode(capped));
    } catch (_) {}
  }

  /// In-app notification channels a user can mute. Defaults to on.
  Future<bool> notificationEnabled(String uid, String channel) async =>
      (await _store())?.getBool(_notifPrefKey(uid, channel)) ?? true;

  Future<void> setNotificationEnabled(
    String uid,
    String channel,
    bool enabled,
  ) async {
    try {
      await (await _store())?.setBool(_notifPrefKey(uid, channel), enabled);
    } catch (_) {}
    notifyListeners();
  }
}
