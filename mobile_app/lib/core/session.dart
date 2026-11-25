import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'config.dart';
import 'models.dart';

enum AuthState { loading, signedOut, signedIn }

/// Holds the signed-in user, the API client and cached lookup data.
class Session extends ChangeNotifier {
  static const _kToken = 'ss_token';
  static const _kBaseUrl = 'ss_base_url';
  static const _kUsername = 'ss_last_username';
  static const _kUser = 'ss_user';
  static const _kCaps = 'ss_caps';

  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  late final ApiClient api = ApiClient(baseUrl: AppConfig.defaultBaseUrl, onUnauthorized: _handleUnauthorized);

  AuthState state = AuthState.loading;
  AppUser? user;
  Capabilities caps = const Capabilities();
  String lastUsername = '';
  String? signOutReason;
  MetaData? _meta;

  String get baseUrl => api.baseUrl;
  bool get isManager => caps.isManager;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    api.baseUrl = prefs.getString(_kBaseUrl) ?? AppConfig.defaultBaseUrl;
    lastUsername = prefs.getString(_kUsername) ?? '';
    String? token;
    try {
      token = await _secure.read(key: _kToken);
    } catch (_) {
      token = null; // keystore problem -> just ask to sign in again
    }
    if (token == null || token.isEmpty) {
      state = AuthState.signedOut;
      notifyListeners();
      return;
    }
    api.token = token;
    // show the cached profile immediately, then refresh it from the server
    final cachedUser = prefs.getString(_kUser);
    final cachedCaps = prefs.getString(_kCaps);
    if (cachedUser != null && cachedCaps != null) {
      try {
        user = AppUser.fromJson(asMap(jsonDecode(cachedUser)));
        caps = Capabilities.fromJson(asMap(jsonDecode(cachedCaps)));
        state = AuthState.signedIn;
      } catch (_) {
        user = null;
      }
    }
    try {
      await refreshMe();
    } on ApiException catch (e) {
      if (e.isUnauthorized || user == null) {
        await _clear(reason: e.isUnauthorized ? e.message : null);
        return;
      }
      // offline: keep the cached profile, screens will show their own errors
    }
    notifyListeners();
  }

  Future<void> refreshMe() async {
    final data = asMap(await api.get('/auth/me/'));
    await _storeProfile(data);
    state = AuthState.signedIn;
    notifyListeners();
  }

  Future<void> login(String username, String password) async {
    api.token = null;
    final data = asMap(await api.post('/auth/login/', {'username': username.trim(), 'password': password}));
    final token = asString(data['token']);
    if (token.isEmpty) throw ApiException('Unexpected response from the server.');
    api.token = token;
    await _secure.write(key: _kToken, value: token);
    final prefs = await SharedPreferences.getInstance();
    lastUsername = username.trim();
    await prefs.setString(_kUsername, lastUsername);
    await _storeProfile(data);
    signOutReason = null;
    _meta = null;
    state = AuthState.signedIn;
    notifyListeners();
  }

  Future<void> _storeProfile(Map<String, dynamic> data) async {
    user = AppUser.fromJson(asMap(data['user']));
    caps = Capabilities.fromJson(asMap(data['capabilities']));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kUser, jsonEncode(user!.toJson()));
    await prefs.setString(_kCaps, jsonEncode(caps.toJson()));
  }

  Future<void> changePassword(String oldPassword, String newPassword) async {
    final data = asMap(await api.post('/auth/change-password/', {
      'old_password': oldPassword,
      'new_password': newPassword,
    }));
    final token = asString(data['token']);
    if (token.isNotEmpty) {
      api.token = token;
      await _secure.write(key: _kToken, value: token);
    }
  }

  Future<void> setServer(String url) async {
    var clean = url.trim();
    while (clean.endsWith('/')) {
      clean = clean.substring(0, clean.length - 1);
    }
    api.baseUrl = clean;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kBaseUrl, clean);
    notifyListeners();
  }

  Future<MetaData> meta({bool force = false}) async {
    final cached = _meta;
    if (cached != null && !force) return cached;
    final m = MetaData.fromJson(asMap(await api.get('/meta/')));
    _meta = m;
    return m;
  }

  Future<void> logout() => _clear();

  Future<void> _clear({String? reason}) async {
    api.token = null;
    user = null;
    caps = const Capabilities();
    _meta = null;
    signOutReason = reason;
    try {
      await _secure.delete(key: _kToken);
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kUser);
    await prefs.remove(_kCaps);
    state = AuthState.signedOut;
    notifyListeners();
  }

  void _handleUnauthorized(String message) {
    if (state == AuthState.signedIn) {
      _clear(reason: message);
    }
  }
}
