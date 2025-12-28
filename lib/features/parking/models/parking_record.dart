class ParkingRecord {
  const ParkingRecord({
    required this.id,
    required this.systemCode,
    required this.capacity,
    required this.occupancy,
    required this.vehicleType,
    required this.timestamp,
  });

  final int id;
  final String systemCode;
  final int capacity;
  final int occupancy;
  final String vehicleType;
  final String timestamp;
}
