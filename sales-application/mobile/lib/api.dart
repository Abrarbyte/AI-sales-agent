import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'cache.dart';
import 'config.dart';

/// Thrown when the backend refuses a request. Carries the message the API
/// actually sent, so screens can show something specific rather than
/// "something went wrong".
class ApiException implements Exception {
  ApiException(this.statusCode, this.message, {this.body});

  final int statusCode;
  final String message;

  /// The server's error as JSON, for refusals that carry more than a
  /// sentence - like which lead a duplicate number is already on (#30).
  final Map<String, dynamic>? body;

  /// The request never reached the server: no signal, DNS, or a timeout.
  bool get isNetwork => statusCode == 0;

  @override
  String toString() => message;
}

/// How long a JSON call may take before it is treated as unreachable. Long
/// enough for a slow 3G round trip, short enough that a spinner never sits
/// for a minute.
const Duration kRequestTimeout = Duration(seconds: 15);

/// Photo uploads on a weak signal legitimately take longer.
const Duration kUploadTimeout = Duration(seconds: 60);

const String kOfflineMessage =
    'Cannot reach the server. Check your connection and try again.';

/// One place that talks to Django.
///
/// Holds the tokens, attaches them to every request, and retries once after
/// refreshing when the access token has expired — so no screen has to think
/// about authentication.
class Api {
  Api._();
  static final Api instance = Api._();

  static const _accessKey = 'access_token';
  static const _refreshKey = 'refresh_token';

  String? _access;
  String? _refresh;

  /// One client for the whole app, so requests reuse an open connection.
  /// The top-level http.get/post make a new client - and a new TCP + TLS
  /// handshake through the tunnel, ~1 s - for every single call (#88).
  final http.Client _client = http.Client();

  bool get isLoggedIn => _access != null;

  /// True from the moment a GET has to fall back to its cached copy until
  /// the next request that reaches the server. Screens show a banner.
  final ValueNotifier<bool> offline = ValueNotifier<bool>(false);

  /// When the data on screen was last fetched, if it came from the cache.
  DateTime? cachedAt;

  Future<void> loadSavedTokens() async {
    final prefs = await SharedPreferences.getInstance();
    _access = prefs.getString(_accessKey);
    _refresh = prefs.getString(_refreshKey);
  }

  Future<void> _saveTokens(String access, String? refresh) async {
    _access = access;
    if (refresh != null) _refresh = refresh;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accessKey, access);
    if (refresh != null) await prefs.setString(_refreshKey, refresh);
  }

  /// Ends the session on the server first, so a copy of either token is
  /// refused from now on - then forgets them here. Best effort: offline, the
  /// local sign-out still happens and the tokens simply run out.
  Future<void> logout() async {
    if (_access != null) {
      try {
        await post('/api/auth/logout/', {'refresh': _refresh});
      } catch (_) {}
    }
    _access = null;
    _refresh = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessKey);
    await prefs.remove(_refreshKey);
    await ResponseCache.instance.clear();
  }

  /// Runs one HTTP call with the timeout, turning every "never got there"
  /// failure into a single [ApiException] the screens already handle.
  Future<http.Response> _guard(Future<http.Response> call, Duration limit) async {
    try {
      return await call.timeout(limit);
    } on TimeoutException {
      throw ApiException(0, 'The server is taking too long. Try again.');
    } on SocketException {
      throw ApiException(0, kOfflineMessage);
    } on http.ClientException {
      throw ApiException(0, kOfflineMessage);
    }
  }

  Future<void> login(String username, String password) async {
    final response = await _guard(
      _client.post(
        Uri.parse('${Config.apiBase}/api/auth/login/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username, 'password': password}),
      ),
      kRequestTimeout,
    );

    if (response.statusCode != 200) {
      throw ApiException(response.statusCode,
          _readError(response.body, fallback: 'Incorrect username or password.'));
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    await _saveTokens(data['access'] as String, data['refresh'] as String?);
  }

  /// Swaps the long-lived refresh token for a new access token.
  /// Returns false when the refresh token itself has expired — time to log in.
  Future<bool> _refreshAccess() async {
    if (_refresh == null) return false;
    final http.Response response;
    try {
      response = await _guard(
        _client.post(
          Uri.parse('${Config.apiBase}/api/auth/refresh/'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'refresh': _refresh}),
        ),
        kRequestTimeout,
      );
    } on ApiException {
      return false; // offline: keep the tokens, the caller falls back
    }
    if (response.statusCode != 200) return false;
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    await _saveTokens(data['access'] as String, data['refresh'] as String?);
    return true;
  }

  Future<dynamic> get(String path) => _send('GET', path);

  /// The last saved copy of a GET, or null. Never touches the network, so a
  /// screen can show it instantly and then refresh from the server (#90).
  Future<dynamic> cached(String path) async {
    final saved = await ResponseCache.instance.get(path);
    if (saved == null || saved.body.isEmpty) return null;
    try {
      return jsonDecode(saved.body);
    } catch (_) {
      return null;
    }
  }

  /// Saved copies of several GETs, in order - or null unless every one is
  /// saved, since a screen built from half its data would be wrong.
  Future<List<dynamic>?> cachedAll(List<String> paths) async {
    final saved = await Future.wait(paths.map(cached));
    return saved.contains(null) ? null : saved;
  }

  /// Partial update. Used for editing a lead's fields, a negotiation's
  /// status, a customer's support flag - anything that already exists.
  Future<dynamic> patch(String path, [Map<String, dynamic>? body]) =>
      _send('PATCH', path, body);

  Future<dynamic> post(String path, [Map<String, dynamic>? body]) =>
      _send('POST', path, body);

  /// POSTs form fields plus one file, for endpoints that take an upload —
  /// `/api/visits/` accepts a visit and its photograph together.
  ///
  /// Kept separate from [_send] rather than folded into it: multipart carries
  /// no JSON body, every value goes over as a string, and the request has to be
  /// rebuilt from scratch to retry, since a sent stream cannot be replayed.
  Future<dynamic> postMultipart(
    String path, {
    required Map<String, String> fields,
    String? filePath,
    List<int>? fileBytes,
    String fileField = 'photo',
    String fileName = 'photo.jpg',
    bool isRetry = false,
  }) async {
    final request = http.MultipartRequest(
      'POST', Uri.parse('${Config.apiBase}$path'))
      ..fields.addAll(fields);
    if (_access != null) {
      request.headers['Authorization'] = 'Bearer $_access';
    }
    if (fileBytes != null) {
      request.files.add(http.MultipartFile.fromBytes(fileField, fileBytes,
          filename: fileName));
    } else if (filePath != null) {
      request.files
          .add(await http.MultipartFile.fromPath(fileField, filePath));
    }

    final response = await _guard(
      _client.send(request).then(http.Response.fromStream),
      kUploadTimeout,
    );

    if (response.statusCode == 401 && !isRetry && await _refreshAccess()) {
      return postMultipart(path,
          fields: fields,
          filePath: filePath,
          fileBytes: fileBytes,
          fileField: fileField,
          fileName: fileName,
          isRetry: true);
    }

    if (response.statusCode >= 400) {
      throw ApiException(response.statusCode, _readError(response.body),
          body: _errorBody(response.body));
    }
    if (response.body.isEmpty) return null;
    return jsonDecode(response.body);
  }

  Future<dynamic> _send(String method, String path,
      [Map<String, dynamic>? body, bool isRetry = false]) async {
    final uri = Uri.parse('${Config.apiBase}$path');
    final headers = {
      'Content-Type': 'application/json',
      if (_access != null) 'Authorization': 'Bearer $_access',
    };

    final http.Response response;
    try {
      response = await _guard(
        switch (method) {
          'GET' => _client.get(uri, headers: headers),
          'PATCH' => _client.patch(uri,
              headers: headers, body: jsonEncode(body ?? const {})),
          _ => _client.post(uri,
              headers: headers, body: jsonEncode(body ?? const {})),
        },
        kRequestTimeout,
      );
    } on ApiException catch (e) {
      // Reads fall back to the last good copy; writes cannot.
      if (method == 'GET' && e.isNetwork) {
        final cached = await ResponseCache.instance.get(path);
        if (cached != null) {
          cachedAt = cached.savedAt;
          offline.value = true;
          return cached.body.isEmpty ? null : jsonDecode(cached.body);
        }
      }
      rethrow;
    }
    if (offline.value) offline.value = false;

    // The access token lasts 8 hours, so this is rare — but when it does
    // expire mid-session the user should never see it happen.
    if (response.statusCode == 401 && !isRetry && await _refreshAccess()) {
      return _send(method, path, body, true);
    }

    if (response.statusCode >= 400) {
      throw ApiException(response.statusCode, _readError(response.body),
          body: _errorBody(response.body));
    }
    if (method == 'GET') {
      cachedAt = null;
      // Not awaited: the screen gets its data now, the file lands after.
      unawaited(ResponseCache.instance.put(path, response.body));
    }
    if (response.body.isEmpty) return null;
    return jsonDecode(response.body);
  }

  static Map<String, dynamic>? _errorBody(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  /// DRF reports errors in a few shapes: {"detail": "..."} for permissions,
  /// {"field": ["..."]} for validation. Pull out something a person can read.
  String _readError(String body, {String fallback = 'Something went wrong.'}) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        if (decoded['detail'] != null) return decoded['detail'].toString();
        final first = decoded.values.first;
        if (first is List && first.isNotEmpty) return first.first.toString();
        return first.toString();
      }
    } catch (_) {
      // Not JSON — fall through to the generic message.
    }
    return fallback;
  }
}
