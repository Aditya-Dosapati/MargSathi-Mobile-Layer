import 'package:flutter/material.dart';
import '../../shared/theme/app_theme.dart';
import '../models/parking_prediction.dart';

class ParkingPredictionPage extends StatefulWidget {
  const ParkingPredictionPage({super.key});

  @override
  State<ParkingPredictionPage> createState() => _ParkingPredictionPageState();
}

class _ParkingPredictionPageState extends State<ParkingPredictionPage> {
  final TextEditingController areaController = TextEditingController(
    text: 'Downtown Tech Park',
  );
  String areaType = 'Commercial';
  String timeOfDay = 'Evening (5-9 PM)';
  List<ParkingPrediction> predictions = const [];

  @override
  void dispose() {
    areaController.dispose();
    super.dispose();
  }

  void _predict() {
    final String area =
        areaController.text.trim().isEmpty
            ? 'Requested area'
            : areaController.text.trim();
    setState(() {
      predictions = [
        ParkingPrediction(
          name: '$area - Zone A',
          available: areaType == 'Residential' ? 18 : 42,
          confidence: 'High',
          eta: 'Walk: 4 min',
        ),
        ParkingPrediction(
          name: '$area - Zone B',
          available: areaType == 'Mixed' ? 26 : 31,
          confidence: 'Medium',
          eta: 'Walk: 7 min',
        ),
        ParkingPrediction(
          name: '$area - Roof Deck',
          available: timeOfDay.contains('Evening') ? 9 : 21,
          confidence: 'Medium',
          eta: 'Walk: 3 min',
        ),
      ];
    });
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
          else
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
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
