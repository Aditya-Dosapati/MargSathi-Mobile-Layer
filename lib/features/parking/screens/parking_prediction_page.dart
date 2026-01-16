import 'package:flutter/material.dart';
import 'dart:math';
import 'package:flutter/services.dart';
import '../../shared/theme/app_theme.dart';
import '../models/parking_prediction.dart';
import '../models/parking_record.dart';
import '../services/parking_data_service.dart';

class ParkingPredictionPage extends StatefulWidget {
  const ParkingPredictionPage({super.key});

  @override
  State<ParkingPredictionPage> createState() => _ParkingPredictionPageState();
}

class _ParkingPredictionPageState extends State<ParkingPredictionPage> {
  final TextEditingController areaController = TextEditingController();
  String? areaType;
  String? timeOfDay;
  List<ParkingPrediction> predictions = const [];
  List<bool> slotStatuses = const [];
  bool _loading = true;
  bool _migrating = false;
  String? _error;
  String _dataSource = 'Loading...';
  List<ParkingRecord> _records = const [];
  final ParkingDataService _dataService = ParkingDataService();

  @override
  void dispose() {
    areaController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      // Try Firestore first
      final firestoreData = await _dataService.loadFromFirestore(limit: 100);
      if (firestoreData.isNotEmpty) {
        if (!mounted) return;
        setState(() {
          _records = firestoreData;
          _dataSource = 'Firebase (${firestoreData.length} records)';
          _loading = false;
        });
        return;
      }

      // Fallback to CSV
      final csvData = await _dataService.loadFromCsv();
      if (!mounted) return;
      setState(() {
        _records = csvData;
        _dataSource = 'Local CSV (${csvData.length} records)';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load parking data: $e';
        _dataSource = 'Error';
        _loading = false;
      });
    }
  }

  Future<void> _migrateToFirebase() async {
    setState(() => _migrating = true);
    try {
      final count = await _dataService.migrateCsvToFirestore(batchSize: 500);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Migrated $count records to Firebase!'),
          backgroundColor: Colors.green,
        ),
      );
      // Reload data from Firestore
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Migration failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _migrating = false);
    }
  }

  void _predict() {
    if (_records.isEmpty) {
      setState(() {
        _error =
            'No parking data available. Add assets/data/parkingStream.csv.';
      });
      return;
    }

    final areaQuery = areaController.text.trim().toLowerCase();
    final matches =
        _records.where((r) {
          if (areaQuery.isEmpty) return true;
          return r.systemCode.toLowerCase().contains(areaQuery);
        }).toList();

    final pool = matches.isNotEmpty ? matches : _records.take(12).toList();

    // Calculate occupancy rate as percentage (0.0 to 1.0)
    double totalCap = 0;
    double totalOcc = 0;
    for (final r in pool) {
      if (r.capacity > 0) {
        totalCap += r.capacity;
        totalOcc += r.occupancy.clamp(0, r.capacity);
      }
    }

    final timeFactor = _timeFactor(timeOfDay);
    final areaFactor = _areaFactor(areaType);

    // Use actual capacity from dataset (cap display at 100 slots for UI, min 20)
    final int rawCapacity =
        matches.isNotEmpty ? matches.first.capacity : totalCap.round();
    // Ensure capacity is at least 1 to avoid division by zero
    final int actualCapacity = rawCapacity > 0 ? rawCapacity : 100;
    final int displaySlots = actualCapacity.clamp(20, 100);

    // Calculate actual occupancy from dataset
    final int actualOccupancy =
        matches.isNotEmpty ? matches.first.occupancy : totalOcc.round();

    // Apply time/area adjustments to real data
    final int adjustedOccupied = (actualOccupancy * timeFactor * areaFactor)
        .round()
        .clamp(0, actualCapacity);
    final int realAvailable = actualCapacity - adjustedOccupied;

    // Scale for display (proportionally map to displaySlots)
    final double scaleFactor =
        actualCapacity > 0 ? displaySlots / actualCapacity : 1.0;
    final int displayOccupied = (adjustedOccupied * scaleFactor).round().clamp(
      0,
      displaySlots,
    );
    final int displayAvailable = displaySlots - displayOccupied;

    final availabilityFraction =
        actualCapacity == 0 ? 0.0 : realAvailable / actualCapacity;
    final confidence =
        availabilityFraction > 0.6
            ? 'High'
            : availabilityFraction > 0.35
            ? 'Medium'
            : 'Low';

    // Create slots with random distribution of free/occupied for display
    final rng = Random();
    final slots = List<bool>.generate(displaySlots, (_) => false);
    final freeIndices = List<int>.generate(displaySlots, (i) => i)
      ..shuffle(rng);
    for (var i = 0; i < displayAvailable; i++) {
      slots[freeIndices[i]] = true;
    }

    setState(() {
      _error = null;
      predictions = [
        ParkingPrediction(
          name:
              matches.isNotEmpty ? matches.first.systemCode : 'Suggested area',
          available: realAvailable,
          confidence: confidence,
          eta: 'Capacity: $actualCapacity • Occupied: $adjustedOccupied',
        ),
      ];
      slotStatuses = slots;
    });
  }

  double _timeFactor(String? slot) {
    if (slot == null) return 1.0;
    if (slot.startsWith('Morning')) return 0.9;
    if (slot.startsWith('Afternoon')) return 1.0;
    if (slot.startsWith('Evening')) return 1.15;
    return 0.85; // Late night
  }

  double _areaFactor(String? type) {
    switch (type) {
      case 'Commercial':
        return 1.1;
      case 'Residential':
        return 0.8;
      case 'Mixed':
        return 1.0;
      case 'Campus':
        return 0.9;
      case 'Industrial':
        return 1.05;
      default:
        return 1.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Parking Manager',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: Color.fromARGB(207, 83, 149, 207),
        actions: [
          // Data source indicator
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color:
                      _dataSource.contains('Firebase')
                          ? Colors.green.withOpacity(0.2)
                          : Colors.orange.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _dataSource.contains('Firebase')
                          ? Icons.cloud_done
                          : Icons.storage,
                      size: 16,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _dataSource.contains('Firebase') ? 'Cloud' : 'Local',
                      style: const TextStyle(fontSize: 12, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        children: [
          // Data source info card
          Card(
            color:
                _dataSource.contains('Firebase')
                    ? Colors.green.shade50
                    : Colors.orange.shade50,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(
                    _dataSource.contains('Firebase')
                        ? Icons.cloud_done
                        : Icons.storage,
                    color:
                        _dataSource.contains('Firebase')
                            ? Colors.green
                            : Colors.orange,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Data Source: $_dataSource',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        if (!_dataSource.contains('Firebase'))
                          const Text(
                            'Migrate to Firebase for real-time sync',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (!_dataSource.contains('Firebase') && !_loading)
                    ElevatedButton.icon(
                      onPressed: _migrating ? null : _migrateToFirebase,
                      icon:
                          _migrating
                              ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                              : const Icon(Icons.cloud_upload, size: 18),
                      label: Text(_migrating ? 'Migrating...' : 'Migrate'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Predict parking before you arrive.',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Provide the area, type, and time to get a forecasted snapshot.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.black54),
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(top: 20),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.redAccent),
              ),
            ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  TextField(
                    controller: areaController,
                    decoration: const InputDecoration(
                      labelText: 'Area name',
                      hintText: 'Enter area name',
                      prefixIcon: Icon(Icons.place_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: areaType,
                    hint: const Text('Select area type'),
                    items:
                        const [
                              'Commercial',
                              'Residential',
                              'Mixed',
                              'Campus',
                              'Industrial',
                            ]
                            .map(
                              (type) => DropdownMenuItem(
                                value: type,
                                child: Text(type),
                              ),
                            )
                            .toList(),
                    onChanged: (value) => setState(() => areaType = value),
                    decoration: const InputDecoration(
                      labelText: 'Area type',
                      prefixIcon: Icon(Icons.layers),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: timeOfDay,
                    hint: const Text('Select time of day'),
                    items:
                        const [
                              'Morning (6-11 AM)',
                              'Afternoon (12-4 PM)',
                              'Evening (5-9 PM)',
                              'Late night (10 PM+)',
                            ]
                            .map(
                              (slot) => DropdownMenuItem(
                                value: slot,
                                child: Text(slot),
                              ),
                            )
                            .toList(),
                    onChanged: (value) => setState(() => timeOfDay = value),
                    decoration: const InputDecoration(
                      labelText: 'Time of day',
                      prefixIcon: Icon(Icons.access_time),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _predict,
                      icon: const Icon(Icons.insights),
                      label: const Text('Predict availability'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (predictions.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'No predictions yet',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Enter details above to view parking availability forecasts.',
                    ),
                  ],
                ),
              ),
            )
          else ...[
            ...predictions.map(
              (prediction) => Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFFE8F1FA),
                    child: Text(
                      prediction.available.toString(),
                      style: const TextStyle(
                        color: AppTheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Text(
                    prediction.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    'Confidence: ${prediction.confidence} • ${prediction.eta}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Slot view',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const Spacer(),
                        Text(
                          '${slotStatuses.where((s) => s).length} / ${slotStatuses.length} available',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF2E7D32),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children:
                          slotStatuses
                              .asMap()
                              .entries
                              .map(
                                (entry) => _SlotChip(
                                  slotNumber: entry.key + 1,
                                  isFree: entry.value,
                                ),
                              )
                              .toList(),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: const [
                        _Legend(color: Color(0xFF2E7D32), label: 'Available'),
                        SizedBox(width: 12),
                        _Legend(color: Color(0xFFC62828), label: 'Occupied'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class _SlotChip extends StatelessWidget {
  const _SlotChip({required this.slotNumber, required this.isFree});

  final int slotNumber;
  final bool isFree;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Slot $slotNumber - ${isFree ? "Available" : "Occupied"}',
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: isFree ? const Color(0xFF4CAF50) : const Color(0xFFE53935),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isFree ? const Color(0xFF2E7D32) : const Color(0xFFC62828),
            width: 1.5,
          ),
        ),
        child: Center(
          child: Text(
            '$slotNumber',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        const SizedBox(width: 6),
        Text(label),
      ],
    );
  }
}
