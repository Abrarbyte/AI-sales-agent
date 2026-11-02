/// `saveBytes(bytes, filename)`: hands the browser a file to save. The
/// console ships as a web app; the stub only exists so the Dart VM (widget
/// tests) can compile the import.
export 'download_stub.dart' if (dart.library.js_interop) 'download_web.dart';
