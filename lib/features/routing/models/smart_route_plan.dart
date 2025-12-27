class SmartRoutePlan {
  SmartRoutePlan({
    required this.distance,
    required this.eta,
    required this.co2Savings,
    required this.congestionScore,
    required this.events,
    required this.instructions,
  });

  final String distance;
  final String eta;
  final String co2Savings;
  final String congestionScore;
  final List<String> events;
  final List<String> instructions;

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
}
