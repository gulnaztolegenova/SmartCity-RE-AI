import 'package:cloud_firestore/cloud_firestore.dart';

class EnergySite {
  const EnergySite({
    required this.id,
    required this.ownerUid,
    required this.name,
    required this.city,
    required this.address,
    required this.geo,
    required this.solarCapacityKw,
    required this.tiltDeg,
    required this.azimuthDeg,
    required this.windCapacityKw,
    required this.windHubHeightM,
    required this.batteryCapacityKwh,
    this.notes,
    this.createdAt,
    this.updatedAt,
    this.isActive = true,
  });

  final String id;
  final String ownerUid;
  final String name;
  final String city;
  final String address;
  final GeoPoint geo;
  final double solarCapacityKw;
  final double tiltDeg;
  final double azimuthDeg;
  final double windCapacityKw;
  final double windHubHeightM;
  final double batteryCapacityKwh;
  final String? notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final bool isActive;

  double get latitude => geo.latitude;
  double get longitude => geo.longitude;

  // A changed installation must never reuse the previous installation's data.
  String get forecastKey => [
    id,
    latitude,
    longitude,
    solarCapacityKw,
    tiltDeg,
    azimuthDeg,
    windCapacityKw,
    windHubHeightM,
    batteryCapacityKwh,
    updatedAt?.millisecondsSinceEpoch,
  ].join(':');

  Map<String, dynamic> toFirestore() {
    return <String, dynamic>{
      'ownerUid': ownerUid,
      'name': name.trim(),
      'city': city.trim(),
      'address': address.trim(),
      'geo': geo,
      'solarCapacityKw': solarCapacityKw,
      'tiltDeg': tiltDeg,
      'azimuthDeg': azimuthDeg,
      'windCapacityKw': windCapacityKw,
      'windHubHeightM': windHubHeightM,
      'batteryCapacityKwh': batteryCapacityKwh,
      'notes': notes?.trim(),
      'isActive': isActive,
      'updatedAt': FieldValue.serverTimestamp(),
      if (createdAt == null) 'createdAt': FieldValue.serverTimestamp(),
    };
  }

  EnergySite copyWith({
    String? id,
    String? ownerUid,
    String? name,
    String? city,
    String? address,
    GeoPoint? geo,
    double? solarCapacityKw,
    double? tiltDeg,
    double? azimuthDeg,
    double? windCapacityKw,
    double? windHubHeightM,
    double? batteryCapacityKwh,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isActive,
  }) {
    return EnergySite(
      id: id ?? this.id,
      ownerUid: ownerUid ?? this.ownerUid,
      name: name ?? this.name,
      city: city ?? this.city,
      address: address ?? this.address,
      geo: geo ?? this.geo,
      solarCapacityKw: solarCapacityKw ?? this.solarCapacityKw,
      tiltDeg: tiltDeg ?? this.tiltDeg,
      azimuthDeg: azimuthDeg ?? this.azimuthDeg,
      windCapacityKw: windCapacityKw ?? this.windCapacityKw,
      windHubHeightM: windHubHeightM ?? this.windHubHeightM,
      batteryCapacityKwh: batteryCapacityKwh ?? this.batteryCapacityKwh,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isActive: isActive ?? this.isActive,
    );
  }

  factory EnergySite.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? <String, dynamic>{};
    return EnergySite(
      id: snapshot.id,
      ownerUid: (data['ownerUid'] as String?) ?? '',
      name: (data['name'] as String?)?.trim() ?? '',
      city: (data['city'] as String?)?.trim() ?? 'Astana',
      address: (data['address'] as String?)?.trim() ?? '',
      geo: (data['geo'] as GeoPoint?) ?? const GeoPoint(51.1694, 71.4491),
      solarCapacityKw: (data['solarCapacityKw'] as num?)?.toDouble() ?? 5.0,
      tiltDeg: (data['tiltDeg'] as num?)?.toDouble() ?? 35.0,
      azimuthDeg: (data['azimuthDeg'] as num?)?.toDouble() ?? 180.0,
      windCapacityKw: (data['windCapacityKw'] as num?)?.toDouble() ?? 3.0,
      windHubHeightM: (data['windHubHeightM'] as num?)?.toDouble() ?? 80.0,
      batteryCapacityKwh:
          (data['batteryCapacityKwh'] as num?)?.toDouble() ?? 20.0,
      notes: (data['notes'] as String?)?.trim(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      isActive: (data['isActive'] as bool?) ?? true,
    );
  }
}
