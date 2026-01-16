import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../models/parking_record.dart';

class ParkingDataService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _collectionName = 'parking_records';

  /// Load parking data from Firestore, fallback to CSV if empty
  Future<List<ParkingRecord>> loadParkingStream() async {
    try {
      // Try to load from Firestore first
      final records = await loadFromFirestore();
      if (records.isNotEmpty) {
        debugPrint(
          '📊 Loaded ${records.length} parking records from Firestore',
        );
        return records;
      }
    } catch (e) {
      debugPrint('⚠️ Firestore load failed: $e');
    }

    // Fallback to CSV
    debugPrint('📊 Loading parking data from CSV (Firestore empty or failed)');
    return loadFromCsv();
  }

  /// Load parking records from Firestore
  Future<List<ParkingRecord>> loadFromFirestore({int? limit}) async {
    Query<Map<String, dynamic>> query = _firestore.collection(_collectionName);

    if (limit != null) {
      query = query.limit(limit);
    }

    final snapshot = await query.get();
    return snapshot.docs
        .map((doc) => ParkingRecord.fromFirestore(doc))
        .toList();
  }

  /// Stream parking records in real-time
  Stream<List<ParkingRecord>> streamParkingRecords({int? limit}) {
    Query<Map<String, dynamic>> query = _firestore.collection(_collectionName);

    if (limit != null) {
      query = query.limit(limit);
    }

    return query.snapshots().map(
      (snapshot) =>
          snapshot.docs.map((doc) => ParkingRecord.fromFirestore(doc)).toList(),
    );
  }

  /// Upload a single parking record to Firestore
  Future<void> uploadRecord(ParkingRecord record) async {
    await _firestore
        .collection(_collectionName)
        .doc('${record.systemCode}_${record.id}')
        .set(record.toFirestore());
  }

  /// Upload multiple parking records to Firestore (batch)
  Future<void> uploadRecordsBatch(List<ParkingRecord> records) async {
    final batch = _firestore.batch();

    for (final record in records) {
      final docRef = _firestore
          .collection(_collectionName)
          .doc('${record.systemCode}_${record.id}');
      batch.set(docRef, record.toFirestore());
    }

    await batch.commit();
    debugPrint('✅ Uploaded ${records.length} records to Firestore');
  }

  /// Migrate CSV data to Firestore (one-time operation)
  Future<int> migrateCsvToFirestore({int batchSize = 500}) async {
    final csvRecords = await loadFromCsvWithLocation();

    int uploaded = 0;
    for (var i = 0; i < csvRecords.length; i += batchSize) {
      final end =
          (i + batchSize > csvRecords.length)
              ? csvRecords.length
              : i + batchSize;
      final batch = csvRecords.sublist(i, end);
      await uploadRecordsBatch(batch);
      uploaded += batch.length;
      debugPrint('📤 Uploaded $uploaded / ${csvRecords.length} records...');
    }

    return uploaded;
  }

  /// Load from CSV (original method)
  Future<List<ParkingRecord>> loadFromCsv() async {
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

  /// Load from CSV with full location data
  Future<List<ParkingRecord>> loadFromCsvWithLocation() async {
    final raw = await rootBundle.loadString('assets/data/parkingStream.csv');
    final lines = const LineSplitter().convert(raw);
    if (lines.length <= 1) return [];

    final records = <ParkingRecord>[];
    for (var i = 1; i < lines.length; i++) {
      final line = lines[i];
      if (line.trim().isEmpty) continue;
      final parts = line.split(',');
      if (parts.length < 11) continue;

      records.add(
        ParkingRecord(
          id: int.tryParse(parts[0]) ?? i,
          systemCode: parts[1].trim(),
          capacity: int.tryParse(parts[2]) ?? 0,
          latitude: double.tryParse(parts[3]),
          longitude: double.tryParse(parts[4]),
          occupancy: int.tryParse(parts[5]) ?? 0,
          vehicleType: parts[6].trim(),
          trafficCondition: parts[7].trim(),
          queueLength: int.tryParse(parts[8]),
          isSpecialDay: parts[9].trim() == '1',
          timestamp: parts[10].trim(),
        ),
      );
    }
    return records;
  }
}
