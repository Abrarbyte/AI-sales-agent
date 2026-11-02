import 'package:flutter/foundation.dart';

import '../../data/api/api_client.dart';

/// Whether someone is signed in. The app root listens to this: false shows
/// the login screen, true shows the console. Flipped by the login form, the
/// sign-out button, and any screen that hits a 401 it cannot refresh past.
final ValueNotifier<bool> signedIn = ValueNotifier<bool>(
  ApiClient.instance.isLoggedIn,
);

/// Clears the tokens and drops back to the login screen.
Future<void> signOut() async {
  await ApiClient.instance.logout();
  signedIn.value = false;
}
