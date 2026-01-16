import 'package:cloud_firestore/cloud_firestore.dart';

class ParkingRecord {
  const ParkingRecord({
    required this.id,
    required this.systemCode,
    required this.capacity,
    required this.occupancy,
    required this.vehicleType,
    required this.timestamp,
    this.latitude,
    this.longitude,
    this.trafficCondition,
    this.queueLength,
    this.isSpecialDay,
  });

  final int id;
  final String systemCode;
  final int capacity;
  final int occupancy;
  final String vehicleType;
  final String timestamp;
  final double? latitude;
  final double? longitude;
  final String? trafficCondition;
  final int? queueLength;
  final bool? isSpecialDay;

  /// Create from Firestore document
  factory ParkingRecord.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ParkingRecord(
      id: data['id'] as int? ?? 0,
      systemCode: data['systemCode'] as String? ?? '',
      capacity: data['capacity'] as int? ?? 0,
      occupancy: data['occupancy'] as int? ?? 0,
      vehicleType: data['vehicleType'] as String? ?? 'car',
      timestamp: data['timestamp'] as String? ?? '',
      latitude: (data['latitude'] as num?)?.toDouble(),
      longitude: (data['longitude'] as num?)?.toDouble(),
      trafficCondition: data['trafficCondition'] as String?,
      queueLength: data['queueLength'] as int?,
      isSpecialDay: data['isSpecialDay'] as bool?,
    );
  }

  /// Convert to Firestore document
  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'systemCode': systemCode,
      'capacity': capacity,
      'occupancy': occupancy,
      'vehicleType': vehicleType,
      'timestamp': timestamp,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (trafficCondition != null) 'trafficCondition': trafficCondition,
      if (queueLength != null) 'queueLength': queueLength,
      if (isSpecialDay != null) 'isSpecialDay': isSpecialDay,
    };
  }
}
