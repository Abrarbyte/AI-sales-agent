import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Hands the browser a file to save, the way a normal download link would:
/// a Blob URL on a temporary anchor, clicked, then revoked.
///
/// The console is web-only, so this has no native branch.
void saveBytes(Uint8List bytes, String filename, {String mime = 'application/octet-stream'}) {
  final web.Blob blob = web.Blob(
    <JSAny>[bytes.toJS].toJS,
    web.BlobPropertyBag(type: mime),
  );
  final String url = web.URL.createObjectURL(blob);
  final web.HTMLAnchorElement a = web.HTMLAnchorElement()
    ..href = url
    ..download = filename
    ..style.display = 'none';
  web.document.body!.append(a);
  a.click();
  a.remove();
  web.URL.revokeObjectURL(url);
}
