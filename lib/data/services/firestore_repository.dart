import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/app_constants.dart';
import '../models/energy_site.dart';
import '../models/user_profile.dart';

class FirestoreRepository {
  FirestoreRepository(this._firestore);

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> userRef(String uid) {
    return _firestore.collection(AppConstants.colUsers).doc(uid);
  }

  CollectionReference<Map<String, dynamic>> get devicesRef {
    return _firestore.collection(AppConstants.colDevices);
  }

  Stream<UserProfile?> watchUserProfile(String uid) {
    return userRef(uid).snapshots().map((snapshot) {
      if (!snapshot.exists) {
        return null;
      }
      return UserProfile.fromSnapshot(snapshot);
    });
  }

  Future<UserProfile?> getUserProfile(String uid) async {
    final snapshot = await userRef(uid).get();
    if (!snapshot.exists) {
      return null;
    }
    return UserProfile.fromSnapshot(snapshot);
  }

  Future<void> saveUserProfile(UserProfile profile) async {
    await userRef(
      profile.uid,
    ).set(profile.toFirestore(), SetOptions(merge: true));
  }

  Future<void> patchPreferredLanguage({
    required String uid,
    required String languageCode,
  }) async {
    await userRef(uid).set(<String, dynamic>{
      'preferredLanguageCode': languageCode,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> setDefaultSiteForUser({
    required String uid,
    required String siteId,
  }) async {
    await userRef(uid).set(<String, dynamic>{
      'defaultSiteId': siteId,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Stream<List<EnergySite>> watchSites(String ownerUid) {
    return devicesRef.where('ownerUid', isEqualTo: ownerUid).snapshots().map((
      snapshot,
    ) {
      final sites = snapshot.docs.map(EnergySite.fromSnapshot).toList();
      sites.sort((a, b) {
        final aTime =
            a.updatedAt ??
            a.createdAt ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bTime =
            b.updatedAt ??
            b.createdAt ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return bTime.compareTo(aTime);
      });
      return List<EnergySite>.unmodifiable(sites);
    });
  }

  Future<List<EnergySite>> getSites(String ownerUid) async {
    final snapshot = await devicesRef
        .where('ownerUid', isEqualTo: ownerUid)
        .get();
    final sites = snapshot.docs.map(EnergySite.fromSnapshot).toList();
    sites.sort((a, b) {
      final aTime =
          a.updatedAt ?? a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime =
          b.updatedAt ?? b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime);
    });
    return List<EnergySite>.unmodifiable(sites);
  }

  Future<String> saveSite(EnergySite site) async {
    if (site.id.isEmpty) {
      final ref = await devicesRef.add(site.toFirestore());
      return ref.id;
    }
    await devicesRef
        .doc(site.id)
        .set(site.toFirestore(), SetOptions(merge: true));
    return site.id;
  }

  Future<void> deleteSite(String siteId) async {
    await devicesRef.doc(siteId).delete();
  }
}
