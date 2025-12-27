import 'package:flutter/material.dart';
import '../../shared/theme/app_theme.dart';
import '../models/smart_route_plan.dart';

class SmartRoutingPage extends StatefulWidget {
  const SmartRoutingPage({super.key});

  @override
  State<SmartRoutingPage> createState() => _SmartRoutingPageState();
}

class _SmartRoutingPageState extends State<SmartRoutingPage> {
  final TextEditingController fromController = TextEditingController(
    text: 'Phoenix Mall',
  );
  final TextEditingController toController = TextEditingController(
    text: 'Airport T2',
  );
  bool includeEvents = true;
  SmartRoutePlan? plan;

  @override
  void dispose() {
    fromController.dispose();
    toController.dispose();
    super.dispose();
  }

  void _planRoute() {
    setState(() {
      plan = SmartRoutePlan(
        distance: '18.4 km',
        eta: '34 min',
        co2Savings: '1.8 kg',
        congestionScore: 'Low',
        events:
            includeEvents
                ? [
                  'Concert near Riverside Arena at 7:30 PM',
                  'Road work on Sector 9 until 6:00 PM',
                ]
                : [],
        instructions: const [
          'Head north on Central Ave for 1.2 km',
          'Merge onto Expressway 5 for 9 km',
          'Take exit 12 toward Airport Road',
          'Follow signage to Terminal 2 drop-off',
        ],
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final SmartRoutePlan effectivePlan =
        plan ?? SmartRoutePlan.placeholder(includeEvents: includeEvents);
    return Scaffold(
      appBar: AppBar(title: const Text('Smart routing')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        children: [
          Text(
            'Plan with live insights.',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Layer live events, eco impact, and guided steps on top of your route.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.black54),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: fromController,
                    decoration: const InputDecoration(
                      labelText: 'From',
                      prefixIcon: Icon(Icons.trip_origin),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: toController,
                    decoration: const InputDecoration(
                      labelText: 'To',
                      prefixIcon: Icon(Icons.flag),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    value: includeEvents,
                    onChanged: (value) => setState(() => includeEvents = value),
                    title: const Text('Include live events on route'),
                    subtitle: const Text(
                      'Detours for concerts, closures, and disruptions',
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _planRoute,
                      icon: const Icon(Icons.play_circle_fill),
                      label: const Text('Plan route'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _InsightRow(plan: effectivePlan),
          const SizedBox(height: 12),
          if (includeEvents)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Events on route',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (effectivePlan.events.isEmpty)
                      const Text('No major events detected.')
                    else
                      ...effectivePlan.events
                          .map(
                            (event) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(
                                Icons.emergency_share,
                                color: Color(0xFFF6A609),
                              ),
                              title: Text(event),
                            ),
                          )
                          .toList(),
                  ],
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
                  Text(
                    'Live monitoring',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _pill(
                          'Congestion',
                          effectivePlan.congestionScore,
                          AppTheme.accent,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _pill(
                          'ETA',
                          effectivePlan.eta,
                          AppTheme.primary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _pill(
                          'Distance',
                          effectivePlan.distance,
                          const Color(0xFFF6A609),
                        ),
                      ),
                    ],
                  ),
                ],
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
                  Text(
                    'Eco impact',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text('CO2 savings compared to typical route'),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: 0.62,
                    backgroundColor: const Color(0xFFE8F1FA),
                    color: AppTheme.accent,
                    minHeight: 10,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Estimated savings: ${effectivePlan.co2Savings}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
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
                  Text(
                    'Route instructions',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ...effectivePlan.instructions
                      .asMap()
                      .entries
                      .map(
                        (entry) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            radius: 16,
                            backgroundColor: AppTheme.primary,
                            child: Text(
                              '${entry.key + 1}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          title: Text(entry.value),
                        ),
                      )
                      .toList(),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _pill(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.black54)),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(color: color, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _InsightRow extends StatelessWidget {
  const _InsightRow({required this.plan});

  final SmartRoutePlan plan;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('ETA'),
                  const SizedBox(height: 6),
                  Text(
                    plan.eta,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text('Includes live traffic'),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Distance'),
                  const SizedBox(height: 6),
                  Text(
                    plan.distance,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text('Optimized for fewer stops'),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
