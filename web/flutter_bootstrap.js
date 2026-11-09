{{flutter_js}}
{{flutter_build_config}}

async function clearLegacyFlutterCaches() {
  if ('serviceWorker' in navigator) {
    const registrations = await navigator.serviceWorker.getRegistrations();
    await Promise.allSettled(
      registrations.map((registration) => registration.unregister()),
    );
  }

  if ('caches' in window) {
    const cacheKeys = await caches.keys();
    await Promise.allSettled(cacheKeys.map((key) => caches.delete(key)));
  }
}

async function bootstrapApplication() {
  await clearLegacyFlutterCaches();

  return _flutter.loader.load({
    serviceWorkerSettings: null,
    config: {
      canvasKitBaseUrl: "canvaskit/",
    },
  });
}

bootstrapApplication();
