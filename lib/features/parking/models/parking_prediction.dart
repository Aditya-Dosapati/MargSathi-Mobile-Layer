class ParkingPrediction {
  const ParkingPrediction({
    required this.name,
    required this.available,
    required this.confidence,
    required this.eta,
  });

  final String name;
  final int available;
  final String confidence;
  final String eta;
}
