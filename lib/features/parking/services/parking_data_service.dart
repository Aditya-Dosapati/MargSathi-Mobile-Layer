import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import '../models/parking_record.dart';

class ParkingDataService {
  Future<List<ParkingRecord>> loadParkingStream() async {
    final raw = await rootBundle.loadString('assets/data/parkingStream.csv');
    final lines = const LineSplitter().convert(raw);
    if (lines.length <= 1) return [];

    final records = <ParkingRecord>[];
    for (var i = 1; i < lines.length; i++) {
      final line = lines[i];
      if (line.trim().isEmpty) continue;
      final parts = line.split(',');
      if (parts.length < 11) continue;
      final id = int.tryParse(parts[0]) ?? i;
      final system = parts[1].trim();
      final capacity = int.tryParse(parts[2]) ?? 0;
      final occupancy = int.tryParse(parts[5]) ?? 0;
      final vehicleType = parts[6].trim();
      final timestamp = parts[10].trim();
      records.add(
        ParkingRecord(
          id: id,
          systemCode: system,
          capacity: capacity,
          occupancy: occupancy,
          vehicleType: vehicleType,
          timestamp: timestamp,
        ),
      );
    }
    return records;
  }
}
