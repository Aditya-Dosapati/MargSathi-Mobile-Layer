/// Represents a traffic/routing event in the H3 grid system
class H3Event {
  final String id;
  final H3EventType type;
  final double latitude;
  final double longitude;
  final BigInt h3Cell;
  final double severity; // 0.0 to 1.0
  final DateTime timestamp;
  final DateTime? expiresAt;
  final String description;
  final double radiusKm;
  final Map<String, dynamic>? metadata;

  H3Event({
    required this.id,
    required this.type,
    required this.latitude,
    required this.longitude,
    required this.h3Cell,
    required this.severity,
    required this.timestamp,
    this.expiresAt,
    required this.description,
    this.radiusKm = 0.5,
    this.metadata,
  });

  /// Check if event is still active
  bool get isActive {
    if (expiresAt == null) return true;
    return DateTime.now().isBefore(expiresAt!);
  }

  /// Get the cost multiplier for routing (higher = worse)
  double get costMultiplier {
    switch (type) {
      case H3EventType.roadClosure:
        return double.infinity; // Avoid completely
      case H3EventType.accident:
        return 5.0 + (severity * 5.0); // 5x to 10x cost
      case H3EventType.heavyTraffic:
        return 2.0 + (severity * 3.0); // 2x to 5x cost
      case H3EventType.construction:
        return 1.5 + (severity * 2.5); // 1.5x to 4x cost
      case H3EventType.weather:
        return 1.2 + (severity * 1.8); // 1.2x to 3x cost
      case H3EventType.event:
        return 1.3 + (severity * 1.7); // 1.3x to 3x cost
      case H3EventType.hazard:
        return 2.0 + (severity * 3.0); // 2x to 5x cost
      case H3EventType.laneRestriction:
        return 1.2 + (severity * 0.8); // 1.2x to 2x cost
      case H3EventType.police:
        return 1.1 + (severity * 0.4); // 1.1x to 1.5x cost
      case H3EventType.flooding:
        return 3.0 + (severity * 7.0); // 3x to 10x cost
    }
  }

  /// Check if this event requires rerouting
  bool get requiresReroute {
    return type == H3EventType.roadClosure ||
        type == H3EventType.flooding ||
        type == H3EventType.accident ||
        type == H3EventType.construction ||
        severity >= 0.7;
  }

  factory H3Event.fromJson(Map<String, dynamic> json) {
    return H3Event(
      id: json['id'] as String,
      type: H3EventType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => H3EventType.hazard,
      ),
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      h3Cell: BigInt.parse(json['h3Cell'] as String, radix: 16),
      severity: (json['severity'] as num).toDouble(),
      timestamp: DateTime.parse(json['timestamp'] as String),
      expiresAt:
          json['expiresAt'] != null
              ? DateTime.parse(json['expiresAt'] as String)
              : null,
      description: json['description'] as String,
      radiusKm: (json['radiusKm'] as num?)?.toDouble() ?? 0.5,
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'latitude': latitude,
      'longitude': longitude,
      'h3Cell': h3Cell.toRadixString(16),
      'severity': severity,
      'timestamp': timestamp.toIso8601String(),
      'expiresAt': expiresAt?.toIso8601String(),
      'description': description,
      'radiusKm': radiusKm,
      'metadata': metadata,
    };
  }

  H3Event copyWith({
    String? id,
    H3EventType? type,
    double? latitude,
    double? longitude,
    BigInt? h3Cell,
    double? severity,
    DateTime? timestamp,
    DateTime? expiresAt,
    String? description,
    double? radiusKm,
    Map<String, dynamic>? metadata,
  }) {
    return H3Event(
      id: id ?? this.id,
      type: type ?? this.type,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      h3Cell: h3Cell ?? this.h3Cell,
      severity: severity ?? this.severity,
      timestamp: timestamp ?? this.timestamp,
      expiresAt: expiresAt ?? this.expiresAt,
      description: description ?? this.description,
      radiusKm: radiusKm ?? this.radiusKm,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  String toString() {
    return 'H3Event(id: $id, type: ${type.name}, severity: $severity, description: $description)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is H3Event && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}

/// Types of events that can affect routing
enum H3EventType {
  roadClosure,
  accident,
  heavyTraffic,
  construction,
  weather,
  event, // concerts, sports events, etc.
  hazard,
  laneRestriction,
  police,
  flooding,
}

/// Extension for event type display
extension H3EventTypeExtension on H3EventType {
  String get displayName {
    switch (this) {
      case H3EventType.roadClosure:
        return 'Road Closure';
      case H3EventType.accident:
        return 'Accident';
      case H3EventType.heavyTraffic:
        return 'Heavy Traffic';
      case H3EventType.construction:
        return 'Construction';
      case H3EventType.weather:
        return 'Weather Alert';
      case H3EventType.event:
        return 'Event';
      case H3EventType.hazard:
        return 'Hazard';
      case H3EventType.laneRestriction:
        return 'Lane Restriction';
      case H3EventType.police:
        return 'Police Activity';
      case H3EventType.flooding:
        return 'Flooding';
    }
  }

  String get icon {
    switch (this) {
      case H3EventType.roadClosure:
        return '🚧';
      case H3EventType.accident:
        return '🚗💥';
      case H3EventType.heavyTraffic:
        return '🚦';
      case H3EventType.construction:
        return '🏗️';
      case H3EventType.weather:
        return '⛈️';
      case H3EventType.event:
        return '🎉';
      case H3EventType.hazard:
        return '⚠️';
      case H3EventType.laneRestriction:
        return '🔀';
      case H3EventType.police:
        return '🚔';
      case H3EventType.flooding:
        return '🌊';
    }
  }
}

/// Represents cell congestion data for H3 grid
class H3CellCongestion {
  final BigInt h3Cell;
  final double congestionLevel; // 0.0 to 1.0
  final double speedRatio; // Current speed / Free flow speed
  final DateTime lastUpdated;

  H3CellCongestion({
    required this.h3Cell,
    required this.congestionLevel,
    required this.speedRatio,
    required this.lastUpdated,
  });

  /// Get cost multiplier based on congestion
  double get costMultiplier {
    if (speedRatio <= 0) return 10.0;
    return 1.0 / speedRatio;
  }

  factory H3CellCongestion.fromJson(Map<String, dynamic> json) {
    return H3CellCongestion(
      h3Cell: BigInt.parse(json['h3Cell'] as String, radix: 16),
      congestionLevel: (json['congestionLevel'] as num).toDouble(),
      speedRatio: (json['speedRatio'] as num).toDouble(),
      lastUpdated: DateTime.parse(json['lastUpdated'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'h3Cell': h3Cell.toRadixString(16),
      'congestionLevel': congestionLevel,
      'speedRatio': speedRatio,
      'lastUpdated': lastUpdated.toIso8601String(),
    };
  }
}

/// Aggregated grid state for routing decisions
class H3GridState {
  final Map<BigInt, List<H3Event>> eventsByCell;
  final Map<BigInt, H3CellCongestion> congestionByCell;
  final DateTime lastUpdated;

  H3GridState({
    required this.eventsByCell,
    required this.congestionByCell,
    required this.lastUpdated,
  });

  /// Get total cost multiplier for a cell
  double getCellCost(BigInt h3Cell) {
    double cost = 1.0;

    // Add event costs
    final events = eventsByCell[h3Cell];
    if (events != null) {
      for (final event in events) {
        if (event.isActive) {
          if (event.costMultiplier == double.infinity) {
            return double.infinity;
          }
          cost *= event.costMultiplier;
        }
      }
    }

    // Add congestion cost
    final congestion = congestionByCell[h3Cell];
    if (congestion != null) {
      cost *= congestion.costMultiplier;
    }

    return cost;
  }

  /// Check if a cell is passable
  bool isCellPassable(BigInt h3Cell) {
    final events = eventsByCell[h3Cell];
    if (events == null) return true;

    return !events.any(
      (e) => e.isActive && e.costMultiplier == double.infinity,
    );
  }

  /// Get all active events affecting a route
  List<H3Event> getEventsOnRoute(Set<BigInt> routeCells) {
    final events = <H3Event>[];
    for (final cell in routeCells) {
      final cellEvents = eventsByCell[cell];
      if (cellEvents != null) {
        events.addAll(cellEvents.where((e) => e.isActive));
      }
    }
    return events;
  }

  factory H3GridState.empty() {
    return H3GridState(
      eventsByCell: {},
      congestionByCell: {},
      lastUpdated: DateTime.now(),
    );
  }
}
