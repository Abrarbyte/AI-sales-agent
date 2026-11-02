import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config.dart';

/// Thrown when the backend refuses a request. Carries the message the API
/// actually sent, so screens can show something specific rather than
/// "something went wrong".
/// How long any call may take before it counts as unreachable.
const Duration kRequestTimeout = Duration(seconds: 20);

class ApiException implements Exception {
  ApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  /// Not signed in, or the refresh token has expired too.
  bool get isAuthFailure => statusCode == 401;

  /// The request never reached the server: offline, DNS, or a timeout.
  bool get isNetwork => statusCode == 0;

  /// Signed in, but this account may not see the resource. The console is a
  /// Super Admin tool, so this usually means the account is not one.
  bool get isForbidden => statusCode == 403;

  @override
  String toString() => message;
}

/// One place that talks to Django.
///
/// Holds the JWT pair, attaches it to every request, and retries once after
/// refreshing when the access token has expired - so no repository has to think
/// about authentication. Mirrors the mobile app's client, with the write verbs
/// the console needs on top: the phone only ever reads and creates, while an
/// admin edits and deactivates.
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  static const String _accessKey = 'access_token';
  static const String _refreshKey = 'refresh_token';

  String? _access;
  String? _refresh;

  bool get isLoggedIn => _access != null;

  Future<void> loadSavedTokens() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    _access = prefs.getString(_accessKey);
    _refresh = prefs.getString(_refreshKey);
  }

  Future<void> _saveTokens(String access, String? refresh) async {
    _access = access;
    if (refresh != null) _refresh = refresh;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accessKey, access);
    if (refresh != null) await prefs.setString(_refreshKey, refresh);
  }

  /// Ends the session on the server first, so a copy of either token is
  /// refused from now on - then forgets them here. Best effort: offline, the
  /// local sign-out still happens and the tokens simply run out.
  Future<void> logout() async {
    if (_access != null) {
      try {
        await post('/api/auth/logout/', <String, dynamic>{'refresh': _refresh});
      } catch (_) {}
    }
    _access = null;
    _refresh = null;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessKey);
    await prefs.remove(_refreshKey);
  }

  /// Runs one HTTP call with the timeout, turning every "never got there"
  /// failure into a single [ApiException] the screens already handle.
  Future<http.Response> _guard(Future<http.Response> call) async {
    try {
      return await call.timeout(kRequestTimeout);
    } on TimeoutException {
      throw ApiException(0, 'The server is taking too long. Try again.');
    } on http.ClientException {
      throw ApiException(0, 'Cannot reach the server. Check your connection.');
    }
  }

  Future<void> login(String username, String password) async {
    final http.Response response = await _guard(
      http.post(
        Uri.parse('${Config.apiBase}/api/auth/login/'),
        headers: const <String, String>{'Content-Type': 'application/json'},
        body: jsonEncode(<String, String>{
          'username': username,
          'password': password,
        }),
      ),
    );

    if (response.statusCode != 200) {
      throw ApiException(
        response.statusCode,
        _readError(response.body, fallback: 'Incorrect username or password.'),
      );
    }
    final Map<String, dynamic> data =
        jsonDecode(response.body) as Map<String, dynamic>;
    await _saveTokens(data['access'] as String, data['refresh'] as String?);
  }

  /// Swaps the long-lived refresh token for a new access token.
  /// Returns false when the refresh token itself has expired - time to log in.
  Future<bool> _refreshAccess() async {
    if (_refresh == null) return false;
    final http.Response response;
    try {
      response = await _guard(
        http.post(
          Uri.parse('${Config.apiBase}/api/auth/refresh/'),
          headers: const <String, String>{'Content-Type': 'application/json'},
          body: jsonEncode(<String, String?>{'refresh': _refresh}),
        ),
      );
    } on ApiException {
      return false; // offline: keep the tokens, surface the network error
    }
    if (response.statusCode != 200) return false;
    final Map<String, dynamic> data =
        jsonDecode(response.body) as Map<String, dynamic>;
    await _saveTokens(data['access'] as String, data['refresh'] as String?);
    return true;
  }

  Future<dynamic> get(String path, [Map<String, dynamic>? query]) =>
      _send('GET', path, query: query);

  Future<dynamic> post(String path, [Map<String, dynamic>? body]) =>
      _send('POST', path, body: body);

  Future<dynamic> patch(String path, [Map<String, dynamic>? body]) =>
      _send('PATCH', path, body: body);

  Future<dynamic> delete(String path) => _send('DELETE', path);

  /// A binary download - the Excel export. Same auth and refresh-on-401
  /// as JSON calls; returns the raw bytes and the server's filename.
  Future<(List<int>, String)> getBytes(String path, {bool isRetry = false}) async {
    final Uri uri = Uri.parse('${Config.apiBase}$path');
    final http.Response response = await _guard(
      http.get(uri, headers: <String, String>{
        if (_access != null) 'Authorization': 'Bearer $_access',
      }),
    );
    if (response.statusCode == 401 && !isRetry && await _refreshAccess()) {
      return getBytes(path, isRetry: true);
    }
    if (response.statusCode >= 400) {
      throw ApiException(response.statusCode, _readError(response.body));
    }
    final RegExpMatch? m = RegExp(r'filename="?([^";]+)"?')
        .firstMatch(response.headers['content-disposition'] ?? '');
    return (response.bodyBytes, m?.group(1) ?? 'export.xlsx');
  }

  /// Reads every page of a list endpoint.
  ///
  /// DRF returns either a bare list or {count, next, results} depending on
  /// whether the view paginates. Both are handled, and `next` is followed - a
  /// console table claiming "23 reps" must not silently stop at the page size.
  Future<List<Map<String, dynamic>>> getList(
    String path, [
    Map<String, dynamic>? query,
  ]) async {
    final List<Map<String, dynamic>> out = <Map<String, dynamic>>[];
    dynamic payload = await get(path, query);

    while (true) {
      if (payload is List) {
        out.addAll(payload.cast<Map<String, dynamic>>());
        return out;
      }
      if (payload is! Map<String, dynamic>) return out;

      final dynamic results = payload['results'];
      if (results is List) {
        out.addAll(results.cast<Map<String, dynamic>>());
      }
      final dynamic next = payload['next'];
      if (next is! String || next.isEmpty) return out;
      payload = await _sendAbsolute('GET', Uri.parse(next));
    }
  }

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, dynamic>? query,
  }) {
    Uri uri = Uri.parse('${Config.apiBase}$path');
    if (query != null && query.isNotEmpty) {
      uri = uri.replace(
        queryParameters: query.map<String, String>(
          (String k, dynamic v) => MapEntry<String, String>(k, '$v'),
        ),
      );
    }
    return _sendAbsolute(method, uri, body: body);
  }

  Future<dynamic> _sendAbsolute(
    String method,
    Uri uri, {
    Map<String, dynamic>? body,
    bool isRetry = false,
  }) async {
    final Map<String, String> headers = <String, String>{
      'Content-Type': 'application/json',
      if (_access != null) 'Authorization': 'Bearer $_access',
    };
    final String? encoded = body == null ? null : jsonEncode(body);

    final http.Response response = await _guard(switch (method) {
      'GET' => http.get(uri, headers: headers),
      'POST' => http.post(uri, headers: headers, body: encoded),
      'PATCH' => http.patch(uri, headers: headers, body: encoded),
      'DELETE' => http.delete(uri, headers: headers),
      _ => throw ArgumentError('Unsupported method $method'),
    });

    // The access token lasts 8 hours, so this is rare - but when it does
    // expire mid-session the admin should never see it happen.
    if (response.statusCode == 401 && !isRetry && await _refreshAccess()) {
      return _sendAbsolute(method, uri, body: body, isRetry: true);
    }

    if (response.statusCode >= 400) {
      throw ApiException(response.statusCode, _readError(response.body));
    }
    if (response.body.isEmpty) return null;
    return jsonDecode(response.body);
  }

  /// DRF reports errors in a few shapes: {"detail": "..."} for permissions,
  /// {"field": ["..."]} for validation. Pull out something a person can read.
  String _readError(String body, {String fallback = 'Something went wrong.'}) {
    try {
      final dynamic decoded = jsonDecode(body);
      if (decoded is Map) {
        if (decoded['detail'] != null) return decoded['detail'].toString();
        if (decoded.isEmpty) return fallback;
        final dynamic first = decoded.values.first;
        if (first is List && first.isNotEmpty) return first.first.toString();
        return first.toString();
      }
    } catch (_) {
      // Not JSON - fall through to the generic message.
    }
    return fallback;
  }
}
