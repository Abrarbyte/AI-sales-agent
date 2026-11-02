import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// The last good copy of every GET, so a salesman with no signal still sees
/// his leads, today's meetings and customer numbers.
///
/// One JSON file per URL under the app's support directory. Writes happen
/// after the response has already been handed to the screen, so caching
/// never slows a request down. On the web there is no file system worth
/// using, so it degrades to an in-memory map for the session.
class ResponseCache {
  ResponseCache._();
  static final ResponseCache instance = ResponseCache._();

  Directory? _dir;
  final Map<String, String> _memory = {};

  /// Tests: use a temp folder instead of the platform's support directory.
  void debugOverrideDirectory(Directory dir) => _dir = dir;

  Future<Directory?> _directory() async {
    if (kIsWeb) return null;
    if (_dir != null) return _dir;
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/apicache');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return _dir = dir;
  }

  String _key(String path) => md5.convert(utf8.encode(path)).toString();

  Future<void> put(String path, String body) async {
    if (kIsWeb) {
      _memory[path] = body;
      return;
    }
    try {
      final dir = await _directory();
      if (dir == null) return;
      await File('${dir.path}/${_key(path)}.json').writeAsString(body);
    } catch (_) {
      // Out of space or similar: the cache is a convenience, not the record.
    }
  }

  /// The saved body and when it was saved, or null when nothing is cached.
  Future<CachedResponse?> get(String path) async {
    if (kIsWeb) {
      final body = _memory[path];
      return body == null ? null : CachedResponse(body, DateTime.now());
    }
    try {
      final dir = await _directory();
      if (dir == null) return null;
      final file = File('${dir.path}/${_key(path)}.json');
      if (!file.existsSync()) return null;
      return CachedResponse(await file.readAsString(), file.lastModifiedSync());
    } catch (_) {
      return null;
    }
  }

  /// Wipes everything - on sign-out, so the next person on this phone
  /// cannot read the previous one's leads.
  Future<void> clear() async {
    _memory.clear();
    if (kIsWeb) return;
    try {
      final dir = await _directory();
      if (dir != null && dir.existsSync()) await dir.delete(recursive: true);
      _dir = null;
    } catch (_) {}
  }
}

class CachedResponse {
  const CachedResponse(this.body, this.savedAt);

  final String body;
  final DateTime savedAt;
}
