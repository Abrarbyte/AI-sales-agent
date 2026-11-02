import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sales_tracker_app/api.dart';
import 'package:sales_tracker_app/config.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('a refused duplicate keeps the server\'s details for the link',
      () async {
    SharedPreferences.setMockInitialValues({});
    // What the server says when a number is already on an open lead (#30).
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      await req.drain<void>();
      req.response
        ..statusCode = 400
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'phone': [
            'This number is already on an open lead: Sharma Tuition, with '
                'Priya More. Work that lead instead of adding another.'
          ],
          'duplicate': {
            'kind': 'lead',
            'name': 'Sharma Tuition',
            'owner': 'Priya More',
            'id': '42',
          },
        }));
      await req.response.close();
    });
    Config.debugOverrideBase('http://127.0.0.1:${server.port}');

    try {
      await Api.instance.post('/api/crm/leads/', {'name': 'x'});
      fail('The server refused; post should throw.');
    } on ApiException catch (e) {
      expect(e.statusCode, 400);
      // The sentence a rep reads...
      expect(e.message, startsWith('This number is already on an open lead'));
      // ...and what the Add Lead sheet needs for "Open that lead".
      expect(e.body?['duplicate']['id'], '42');
    } finally {
      await server.close(force: true);
    }
  });
}
