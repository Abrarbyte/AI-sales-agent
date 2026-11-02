import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracker_app/api.dart';
import 'package:sales_tracker_app/cache.dart';
import 'package:sales_tracker_app/config.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A stand-in server: answers once, then goes away.
Future<HttpServer> serve(String body) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) {
    req.response.headers.contentType = ContentType.json;
    req.response.write(body);
    req.response.close();
  });
  return server;
}

void main() {
  test('GET falls back to the cached copy when the server is gone', () async {
    SharedPreferences.setMockInitialValues({});
    final dir = Directory.systemTemp.createTempSync('apicache');
    ResponseCache.instance.debugOverrideDirectory(dir);

    final server = await serve('[{"id":1,"name":"Cached Lead"}]');
    Config.debugOverrideBase('http://127.0.0.1:${server.port}');

    final live = await Api.instance.get('/api/crm/leads/');
    expect((live as List).length, 1);
    expect(Api.instance.offline.value, isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 200));

    await server.close(force: true);

    final stale = await Api.instance.get('/api/crm/leads/');
    expect(jsonEncode(stale), jsonEncode(live));
    expect(Api.instance.offline.value, isTrue);
    expect(Api.instance.cachedAt, isNotNull);

    // A write while offline fails fast with the network message.
    expect(
      () => Api.instance.post('/api/crm/leads/', {'name': 'x'}),
      throwsA(isA<ApiException>().having((e) => e.isNetwork, 'isNetwork', true)),
    );

    // Nothing cached for an unknown path -> the same clean error.
    expect(
      () => Api.instance.get('/api/never/'),
      throwsA(isA<ApiException>().having((e) => e.isNetwork, 'isNetwork', true)),
    );
  });

  test('cached() reads the saved copy without the network (#90)', () async {
    final dir = Directory.systemTemp.createTempSync('apicache');
    ResponseCache.instance.debugOverrideDirectory(dir);
    // Nothing is listening here: any network call would fail.
    Config.debugOverrideBase('http://127.0.0.1:9');

    await ResponseCache.instance.put('/api/a/', '[{"id":1}]');
    await ResponseCache.instance.put('/api/b/', '{"unread":3}');

    expect(await Api.instance.cached('/api/a/'), [
      {'id': 1}
    ]);
    expect(await Api.instance.cached('/api/missing/'), isNull);

    // All saved: every body, in order.
    final both = await Api.instance.cachedAll(['/api/b/', '/api/a/']);
    expect((both![0] as Map)['unread'], 3);
    // One missing: nothing, so a screen is never built from half its data.
    expect(await Api.instance.cachedAll(['/api/a/', '/api/missing/']), isNull);
  });
}
