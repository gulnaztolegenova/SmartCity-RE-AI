import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../data/models/user_profile.dart';
import '../../data/services/firebase_phone_auth_service.dart';
import '../../data/services/firestore_repository.dart';

class RouterNotifier extends ChangeNotifier {
  RouterNotifier({
    required FirebasePhoneAuthService authService,
    required FirestoreRepository firestoreRepository,
  }) : _authService = authService,
       _firestoreRepository = firestoreRepository {
    _authSubscription = _authService.authStateChanges().listen(_handleUser);
    _handleUser(_authService.currentUser);
  }

  final FirebasePhoneAuthService _authService;
  final FirestoreRepository _firestoreRepository;

  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<UserProfile?>? _profileSubscription;

  User? _user;
  UserProfile? _profile;
  bool _initialized = false;
  bool _profileResolved = false;

  bool get isLoading => !_initialized || (_user != null && !_profileResolved);
  bool get isAuthenticated => _user != null;
  bool get needsProfile =>
      _user != null && _profileResolved && _profile == null;
  User? get user => _user;
  UserProfile? get profile => _profile;

  void _handleUser(User? user) {
    _user = user;
    _profile = null;
    _initialized = true;
    _profileResolved = user == null;
    unawaited(_profileSubscription?.cancel());
    _profileSubscription = null;

    if (user != null) {
      _profileSubscription = _firestoreRepository
          .watchUserProfile(user.uid)
          .listen((profile) {
            _profile = profile;
            _profileResolved = true;
            notifyListeners();
          });
    }

    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_authSubscription?.cancel());
    unawaited(_profileSubscription?.cancel());
    super.dispose();
  }
}
