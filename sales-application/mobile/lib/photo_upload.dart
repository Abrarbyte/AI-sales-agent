import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

/// The longest side a field photo is taken at. Enough to read a shop sign or
/// a site board, and the camera does the shrinking before we ever see it.
const double kPhotoMaxSide = 1280;

/// JPEG quality the camera plugin saves at, before the WebP step. Kept high
/// so the image is only degraded once, by the WebP encoder, rather than twice.
const int kCameraQuality = 92;

/// WebP quality. At 1280px this lands around 60-80 KB for a typical site
/// photo, against roughly 240 KB for the JPEG the app used to send - which
/// matters on a salesman's mobile data and through the office tunnel.
const int kWebpQuality = 75;

/// What actually gets uploaded for one camera shot: the bytes and a file
/// name whose extension matches them.
typedef UploadPhoto = ({List<int> bytes, String name});

/// Turns a camera shot into the upload: WebP where the platform can make it,
/// the original JPEG where it cannot.
///
/// A failed conversion never costs the salesman his photo - it falls back to
/// sending the JPEG as it came from the camera, and the server converts that
/// on arrival instead. The web build has no native encoder, so it always
/// takes that path.
Future<UploadPhoto> photoForUpload(XFile shot, String baseName) async {
  if (!kIsWeb) {
    try {
      final webp = await FlutterImageCompress.compressWithFile(
        shot.path,
        format: CompressFormat.webp,
        quality: kWebpQuality,
        // Not "minimum" in the usual sense. The encoder divides both sides by
        // max(1, min(w / minWidth, h / minHeight)), so small values shrink
        // the photo to almost nothing - 1 and 1 would send a single pixel.
        // At kPhotoMaxSide the divisor is 1 for anything the camera already
        // capped, so this only re-encodes; if a camera ignored the cap, it
        // scales the short side down to kPhotoMaxSide.
        minWidth: kPhotoMaxSide.toInt(),
        minHeight: kPhotoMaxSide.toInt(),
      );
      if (webp != null && webp.isNotEmpty) {
        return (bytes: webp, name: '$baseName.webp');
      }
    } catch (e) {
      debugPrint('WebP conversion failed, sending the JPEG: $e');
    }
  }
  return (bytes: await shot.readAsBytes(), name: '$baseName.jpg');
}
