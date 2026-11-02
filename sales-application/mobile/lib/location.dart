import 'package:geolocator/geolocator.dart';

/// Getting the phone's position, with the refusals spelled out.
///
/// A field-sales app lives or dies on this: if location fails the person is
/// standing outside a customer's shop unable to check in, so every failure
/// needs a message that says what to do about it.
class LocationService {
  static Future<Position> current() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw 'Location is turned off. Switch it on and try again.';
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw 'Location permission is needed to check in.';
    }
    if (permission == LocationPermission.deniedForever) {
      throw 'Location is blocked. Enable it for this app in settings.';
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        // Outdoors with a weak signal this can hang; better to fail with a
        // clear message than to leave someone staring at a spinner.
        timeLimit: Duration(seconds: 20),
      ),
    );
  }
}
