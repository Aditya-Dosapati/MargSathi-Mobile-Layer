import 'h3_event.dart';

class SmartRoutePlan {
  SmartRoutePlan({
    required this.distance,
    required this.eta,
    required this.co2Savings,
    required this.congestionScore,
    required this.events,
    required this.instructions,
    this.h3Events = const [],
    this.routeCells = const {},
    this.isRerouted = false,
    this.rerouteReason,
  });

  final String distance;
  final String eta;
  final String co2Savings;
  final String congestionScore;
  final List<String> events;
  final List<String> instructions;
  final List<H3Event> h3Events;
  final Set<BigInt> routeCells;
  final bool isRerouted;
  final String? rerouteReason;

  factory SmartRoutePlan.placeholder({required bool includeEvents}) {
    return SmartRoutePlan(
      distance: '-',
      eta: '-',
      co2Savings: '-',
      congestionScore: 'Awaiting input',
      events: includeEvents ? [] : [],
      instructions: const [
        'Add points above to generate turn-by-turn guidance.',
      ],
    );
  }

  SmartRoutePlan copyWith({
    String? distance,
    String? eta,
    String? co2Savings,
    String? congestionScore,
    List<String>? events,
    List<String>? instructions,
    List<H3Event>? h3Events,
    Set<BigInt>? routeCells,
    bool? isRerouted,
    String? rerouteReason,
  }) {
    return SmartRoutePlan(
      distance: distance ?? this.distance,
      eta: eta ?? this.eta,
      co2Savings: co2Savings ?? this.co2Savings,
      congestionScore: congestionScore ?? this.congestionScore,
      events: events ?? this.events,
      instructions: instructions ?? this.instructions,
      h3Events: h3Events ?? this.h3Events,
      routeCells: routeCells ?? this.routeCells,
      isRerouted: isRerouted ?? this.isRerouted,
      rerouteReason: rerouteReason ?? this.rerouteReason,
    );
  }
}
