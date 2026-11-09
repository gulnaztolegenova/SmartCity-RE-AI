import 'package:cloud_firestore/cloud_firestore.dart';

class UserProfile {
  const UserProfile({
    required this.uid,
    required this.fullName,
    required this.phoneNumber,
    required this.city,
    required this.preferredLanguageCode,
    this.backupEmail,
    this.organization,
    this.defaultSiteId,
    this.createdAt,
    this.updatedAt,
  });

  final String uid;
  final String fullName;
  final String phoneNumber;
  final String city;
  final String preferredLanguageCode;
  final String? backupEmail;
  final String? organization;
  final String? defaultSiteId;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get firstName {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    return parts.isEmpty ? '' : parts.first;
  }

  Map<String, dynamic> toFirestore() {
    return <String, dynamic>{
      'fullName': fullName.trim(),
      'phoneNumber': phoneNumber.trim(),
      'backupEmail': backupEmail?.trim(),
      'organization': organization?.trim(),
      'city': city.trim(),
      'preferredLanguageCode': preferredLanguageCode,
      'defaultSiteId': defaultSiteId,
      'updatedAt': FieldValue.serverTimestamp(),
      if (createdAt == null) 'createdAt': FieldValue.serverTimestamp(),
    };
  }

  UserProfile copyWith({
    String? fullName,
    String? phoneNumber,
    String? city,
    String? preferredLanguageCode,
    String? backupEmail,
    String? organization,
    String? defaultSiteId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserProfile(
      uid: uid,
      fullName: fullName ?? this.fullName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      city: city ?? this.city,
      preferredLanguageCode:
          preferredLanguageCode ?? this.preferredLanguageCode,
      backupEmail: backupEmail ?? this.backupEmail,
      organization: organization ?? this.organization,
      defaultSiteId: defaultSiteId ?? this.defaultSiteId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory UserProfile.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? <String, dynamic>{};
    return UserProfile(
      uid: snapshot.id,
      fullName: (data['fullName'] as String?)?.trim() ?? '',
      phoneNumber: (data['phoneNumber'] as String?)?.trim() ?? '',
      backupEmail: (data['backupEmail'] as String?)?.trim(),
      organization: (data['organization'] as String?)?.trim(),
      city: (data['city'] as String?)?.trim() ?? 'Astana',
      preferredLanguageCode:
          (data['preferredLanguageCode'] as String?)?.trim() ?? 'kk',
      defaultSiteId: (data['defaultSiteId'] as String?)?.trim(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }
}
