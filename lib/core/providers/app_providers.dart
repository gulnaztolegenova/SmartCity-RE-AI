import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../extensions/async_value_x.dart';
import '../../data/models/energy_site.dart';
import '../../data/models/user_profile.dart';
import '../../data/services/cloud_run_api.dart';
import '../../data/services/firebase_phone_auth_service.dart';
import '../../data/services/firestore_repository.dart';

final firebaseAuthProvider = Provider<FirebaseAuth>((ref) {
  return FirebaseAuth.instance;
});

final firebaseFirestoreProvider = Provider<FirebaseFirestore>((ref) {
  return FirebaseFirestore.instance;
});

final phoneAuthServiceProvider = Provider<FirebasePhoneAuthService>((ref) {
  return FirebasePhoneAuthService(ref.watch(firebaseAuthProvider));
});

final firestoreRepositoryProvider = Provider<FirestoreRepository>((ref) {
  return FirestoreRepository(ref.watch(firebaseFirestoreProvider));
});

final cloudRunApiProvider = Provider<CloudRunApi>((ref) {
  ref.watch(firebaseUserProvider.select((value) => value.valueOrNull?.uid));
  final api = CloudRunApi();
  ref.onDispose(api.close);
  return api;
});

final firebaseUserProvider = StreamProvider<User?>((ref) {
  return ref.watch(phoneAuthServiceProvider).authStateChanges();
});

final currentUserProfileProvider = StreamProvider<UserProfile?>((ref) {
  final user = ref.watch(firebaseUserProvider).valueOrNull;
  if (user == null) {
    return Stream<UserProfile?>.value(null);
  }
  return ref.watch(firestoreRepositoryProvider).watchUserProfile(user.uid);
});

final currentUserSitesProvider = StreamProvider<List<EnergySite>>((ref) {
  final user = ref.watch(firebaseUserProvider).valueOrNull;
  if (user == null) {
    return Stream<List<EnergySite>>.value(const <EnergySite>[]);
  }
  return ref.watch(firestoreRepositoryProvider).watchSites(user.uid);
});

final selectedSiteProvider = Provider<EnergySite?>((ref) {
  final profile = ref.watch(currentUserProfileProvider).valueOrNull;
  final sites =
      ref.watch(currentUserSitesProvider).valueOrNull ?? const <EnergySite>[];
  if (sites.isEmpty) {
    return null;
  }
  final preferredId = profile?.defaultSiteId;
  if (preferredId != null) {
    for (final site in sites) {
      if (site.id == preferredId) {
        return site;
      }
    }
  }
  return sites.first;
});

final serverHealthProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  return ref.watch(cloudRunApiProvider).getHealth();
});

final forecastMetaProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  return ref.watch(cloudRunApiProvider).fetchMeta();
});
