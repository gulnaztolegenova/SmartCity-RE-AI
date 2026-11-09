import 'dart:js_interop';

import 'package:web/web.dart' as web;

Future<void> performAuthHardRefresh() async {
  try {
    final registrations = await web.window.navigator.serviceWorker
        .getRegistrations()
        .toDart;
    await Future.wait(
      registrations.toDart.map(
        (registration) => registration.unregister().toDart,
      ),
    );
  } catch (_) {}

  try {
    final keys = await web.window.caches.keys().toDart;
    await Future.wait(
      keys.toDart.map((key) => web.window.caches.delete(key.toDart).toDart),
    );
  } catch (_) {}

  web.window.location.reload();
}
