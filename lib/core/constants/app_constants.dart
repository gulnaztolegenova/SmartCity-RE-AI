class AppConstants {
  AppConstants._();

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue:
        '',
  );

  static const String colUsers = 'users';
  static const String colDevices = 'devices';

  static const String localeStorageKey = 'smart_city_locale';
  static const String defaultLanguageCode = 'kk';
  static const String defaultTimezone = 'Asia/Almaty';

  static const double defaultLatitude = 51.1694;
  static const double defaultLongitude = 71.4491;
  static const String defaultCity = 'Astana';
}
