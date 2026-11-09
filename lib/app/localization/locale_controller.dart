import 'dart:async';
import 'dart:ui';

import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';
import '../../core/extensions/async_value_x.dart';
import '../../data/models/user_profile.dart';
import '../../core/providers/app_providers.dart';

final localeControllerProvider =
    StateNotifierProvider<LocaleController, Locale>((ref) {
      return LocaleController(ref.read);
    });

class LocaleController extends StateNotifier<Locale> {
  LocaleController(this._read) : super(const Locale('kk')) {
    unawaited(_restore());
  }

  final T Function<T>(ProviderListenable<T>) _read;

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(AppConstants.localeStorageKey);
    final code = _sanitize(stored) ?? AppConstants.defaultLanguageCode;
    state = Locale(code);
  }

  Future<void> syncWithProfile(UserProfile? profile) async {
    final preferred = _sanitize(profile?.preferredLanguageCode);
    if (preferred == null || preferred == state.languageCode) {
      return;
    }
    state = Locale(preferred);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.localeStorageKey, preferred);
  }

  Future<void> setLocale(Locale locale) async {
    final code = _sanitize(locale.languageCode);
    if (code == null) {
      return;
    }
    state = Locale(code);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.localeStorageKey, code);

    final user = _read(firebaseUserProvider).valueOrNull;
    if (user != null) {
      await _read(
        firestoreRepositoryProvider,
      ).patchPreferredLanguage(uid: user.uid, languageCode: code);
    }
  }

  String? _sanitize(String? code) {
    switch (code) {
      case 'kk':
      case 'ru':
      case 'en':
        return code;
      default:
        return null;
    }
  }
}
