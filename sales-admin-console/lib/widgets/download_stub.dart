import 'dart:typed_data';

/// Non-web build of the console (the widget tests run on the Dart VM):
/// there is no browser to hand a file to.
void saveBytes(Uint8List bytes, String filename, {String mime = 'application/octet-stream'}) {
  throw UnsupportedError('Downloads are only available in the browser.');
}
