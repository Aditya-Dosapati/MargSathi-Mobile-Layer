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
  final TextEditingController areaController = TextEditingController(
    text: 'Shopping',
  );
  String areaType = 'Commercial';
  String timeOfDay = 'Evening (5-9 PM)';
  List<ParkingPrediction> predictions = const [];
  List<bool> slotStatuses = const [];
  bool _loading = true;
  String? _error;
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
      final data = await _dataService.loadParkingStream();
      if (!mounted) return;
      setState(() {
        _records = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load parking data: $e';
        _loading = false;
      });
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
    // Default to 35% occupancy if no valid data (meaning 65% available)
    final double occupancyRate = totalCap > 0 ? (totalOcc / totalCap) : 0.35;

    final timeFactor = _timeFactor(timeOfDay);
    final areaFactor = _areaFactor(areaType);
    // Adjust occupancy rate by time/area factors (keep between 15% and 70%)
    // This ensures at least 30% slots are always shown as available
    final adjustedRate = (occupancyRate * timeFactor * areaFactor).clamp(
      0.15,
      0.70,
    );

    const int totalSlots = 30; // Fixed display slots for demo
    final int occupied = (totalSlots * adjustedRate).round();
    // Ensure at least 5 slots are available for better UX
    final int available = (totalSlots - occupied).clamp(5, totalSlots - 3);
    final int actualOccupied = totalSlots - available;

    final availabilityFraction = totalSlots == 0 ? 0.0 : available / totalSlots;
    final confidence =
        availabilityFraction > 0.6
            ? 'High'
            : availabilityFraction > 0.35
            ? 'Medium'
            : 'Low';

    // Create slots with random distribution of free/occupied
    final rng = Random();
    final slots = List<bool>.generate(totalSlots, (_) => false);
    final freeIndices = List<int>.generate(totalSlots, (i) => i)..shuffle(rng);
    for (var i = 0; i < available; i++) {
      slots[freeIndices[i]] = true;
    }

    setState(() {
      _error = null;
      predictions = [
        ParkingPrediction(
          name:
              matches.isNotEmpty ? matches.first.systemCode : 'Suggested area',
          available: available,
          confidence: confidence,
          eta: 'Based on dataset snapshot',
        ),
      ];
      slotStatuses = slots;
    });
  }

  double _timeFactor(String slot) {
    if (slot.startsWith('Morning')) return 0.9;
    if (slot.startsWith('Afternoon')) return 1.0;
    if (slot.startsWith('Evening')) return 1.15;
    return 0.85; // Late night
  }

  double _areaFactor(String type) {
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
      appBar: AppBar(title: const Text('Parking prediction')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        children: [
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
                      prefixIcon: Icon(Icons.place_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: areaType,
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
                    onChanged:
                        (value) => setState(() => areaType = value ?? areaType),
                    decoration: const InputDecoration(
                      labelText: 'Area type',
                      prefixIcon: Icon(Icons.layers),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: timeOfDay,
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
                    onChanged:
                        (value) =>
                            setState(() => timeOfDay = value ?? timeOfDay),
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
                    const Text(
                      'Slot view',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children:
                          slotStatuses
                              .asMap()
                              .entries
                              .map(
                                (entry) => _SlotChip(
                                  label: 'S${entry.key + 1}',
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
  const _SlotChip({required this.label, required this.isFree});

  final String label;
  final bool isFree;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isFree ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isFree ? const Color(0xFF2E7D32) : const Color(0xFFC62828),
          width: 1.2,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isFree ? Icons.check_circle : Icons.cancel,
            size: 16,
            color: isFree ? const Color(0xFF2E7D32) : const Color(0xFFC62828),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: isFree ? const Color(0xFF1B5E20) : const Color(0xFFB71C1C),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
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
