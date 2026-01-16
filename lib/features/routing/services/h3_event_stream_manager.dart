import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';

import 'h3_service.dart';
import 'h3_route_optimizer.dart';
import '../models/h3_event.dart';

/// Callback type for new events
typedef EventCallback = void Function(H3Event event);

/// Manages streaming events and distributes them to H3 grid cells.
/// Supports real-time event feeds and simulation for demo purposes.
class H3EventStreamManager {
  final H3Service _h3Service;
  final H3RouteOptimizer _routeOptimizer;

  // Event streams
  final StreamController<H3Event> _eventController =
      StreamController<H3Event>.broadcast();

  // Simulation state
  Timer? _simulationTimer;
  bool _isSimulating = false;
  final Random _random = Random();

  // Event listeners
  final List<EventCallback> _eventCallbacks = [];

  // Demo event pool
  static const List<_DemoEventTemplate> _demoTemplates = [
    _DemoEventTemplate(
      type: H3EventType.accident,
      descriptions: [
        'Multi-vehicle collision reported',
        'Minor fender bender, lane blocked',
        'Accident with injuries, emergency response active',
      ],
      severityRange: (min: 0.5, max: 0.9),
      durationMinutes: (min: 15, max: 60),
    ),
    _DemoEventTemplate(
      type: H3EventType.heavyTraffic,
      descriptions: [
        'Heavy congestion due to rush hour',
        'Traffic buildup near major intersection',
        'Slow moving traffic, expect delays',
      ],
      severityRange: (min: 0.3, max: 0.7),
      durationMinutes: (min: 20, max: 90),
    ),
    _DemoEventTemplate(
      type: H3EventType.construction,
      descriptions: [
        'Road construction, lane closures ahead',
        'Utility work in progress',
        'Bridge maintenance, reduced speed',
      ],
      severityRange: (min: 0.3, max: 0.6),
      durationMinutes: (min: 120, max: 480),
    ),
    _DemoEventTemplate(
      type: H3EventType.roadClosure,
      descriptions: [
        'Road closed for emergency repair',
        'Street closure due to gas leak',
        'Road blocked by fallen tree',
      ],
      severityRange: (min: 0.9, max: 1.0),
      durationMinutes: (min: 30, max: 180),
    ),
    _DemoEventTemplate(
      type: H3EventType.weather,
      descriptions: [
        'Heavy rain reducing visibility',
        'Fog advisory in effect',
        'Strong winds affecting high-profile vehicles',
      ],
      severityRange: (min: 0.2, max: 0.5),
      durationMinutes: (min: 30, max: 120),
    ),
    _DemoEventTemplate(
      type: H3EventType.event,
      descriptions: [
        'Concert ending, expect crowds',
        'Sports event traffic nearby',
        'Festival causing road diversions',
      ],
      severityRange: (min: 0.3, max: 0.6),
      durationMinutes: (min: 60, max: 240),
    ),
    _DemoEventTemplate(
      type: H3EventType.laneRestriction,
      descriptions: [
        'Lane restriction for road marking',
        'Temporary lane closure for inspection',
        'Reduced lanes due to breakdown',
      ],
      severityRange: (min: 0.2, max: 0.4),
      durationMinutes: (min: 15, max: 60),
    ),
    _DemoEventTemplate(
      type: H3EventType.flooding,
      descriptions: [
        'Road flooded, avoid if possible',
        'Water logging after heavy rain',
        'Underpasses submerged',
      ],
      severityRange: (min: 0.7, max: 1.0),
      durationMinutes: (min: 60, max: 360),
    ),
  ];

  H3EventStreamManager(this._h3Service, this._routeOptimizer);

  /// Stream of all events
  Stream<H3Event> get eventStream => _eventController.stream;

  /// Add a new event to the system
  Future<RerouteCheckResult> addEvent(H3Event event) async {
    debugPrint(
      '📥 addEvent called: ${event.type.displayName} at (${event.latitude}, ${event.longitude}), cell=${event.h3Cell}',
    );

    // Add to optimizer
    final result = await _routeOptimizer.addEvent(event);
    debugPrint('📊 Optimizer result: needsReroute=${result.needsReroute}');

    // Broadcast to listeners
    _eventController.add(event);
    debugPrint('📡 Event broadcast to stream listeners');

    // Notify callbacks
    for (final callback in _eventCallbacks) {
      callback(event);
    }
    debugPrint('📞 Notified ${_eventCallbacks.length} callbacks');

    return result;
  }

  /// Create and add a new event
  Future<RerouteCheckResult> createEvent({
    required H3EventType type,
    required double latitude,
    required double longitude,
    required double severity,
    required String description,
    Duration? duration,
    double radiusKm = 0.5,
    Map<String, dynamic>? metadata,
  }) async {
    final h3Cell = _h3Service.latLngToCell(
      latitude,
      longitude,
      resolution: H3Service.defaultResolution,
    );

    final event = H3Event(
      id:
          'evt_${DateTime.now().millisecondsSinceEpoch}_${_random.nextInt(10000)}',
      type: type,
      latitude: latitude,
      longitude: longitude,
      h3Cell: h3Cell,
      severity: severity,
      timestamp: DateTime.now(),
      expiresAt: duration != null ? DateTime.now().add(duration) : null,
      description: description,
      radiusKm: radiusKm,
      metadata: metadata,
    );

    return addEvent(event);
  }

  /// Remove an event
  void removeEvent(String eventId) {
    _routeOptimizer.removeEvent(eventId);
  }

  /// Start simulating events near a route for demo purposes
  void startEventSimulation({
    required List<({double lat, double lng})> routePath,
    Duration interval = const Duration(seconds: 8),
    double nearRouteChance = 0.7, // Chance event is near route vs random
  }) {
    if (_isSimulating || routePath.isEmpty) return;

    _isSimulating = true;
    _simulationTimer = Timer.periodic(interval, (_) {
      _generateSimulatedEvent(routePath, nearRouteChance);
    });
  }

  /// Stop event simulation
  void stopEventSimulation() {
    _isSimulating = false;
    _simulationTimer?.cancel();
    _simulationTimer = null;
  }

  void _generateSimulatedEvent(
    List<({double lat, double lng})> routePath,
    double nearRouteChance,
  ) {
    // Pick a template
    final template = _demoTemplates[_random.nextInt(_demoTemplates.length)];

    // Decide location
    late double lat, lng;

    if (_random.nextDouble() < nearRouteChance && routePath.isNotEmpty) {
      // Pick a point along the route
      final point = routePath[_random.nextInt(routePath.length)];
      // Add some random offset (within ~500m)
      lat = point.lat + (_random.nextDouble() - 0.5) * 0.01;
      lng = point.lng + (_random.nextDouble() - 0.5) * 0.01;
    } else {
      // Random point in Bangalore area (for demo)
      lat = 12.9 + _random.nextDouble() * 0.15;
      lng = 77.55 + _random.nextDouble() * 0.15;
    }

    // Generate event
    final severity =
        template.severityRange.min +
        _random.nextDouble() *
            (template.severityRange.max - template.severityRange.min);

    final durationMinutes =
        template.durationMinutes.min +
        _random.nextInt(
          template.durationMinutes.max - template.durationMinutes.min,
        );

    final description =
        template.descriptions[_random.nextInt(template.descriptions.length)];

    createEvent(
      type: template.type,
      latitude: lat,
      longitude: lng,
      severity: severity,
      description: description,
      duration: Duration(minutes: durationMinutes),
      radiusKm: 0.3 + _random.nextDouble() * 0.4,
    );
  }

  /// Generate a specific event for demo/testing
  Future<RerouteCheckResult> triggerDemoEvent({
    required H3EventType type,
    required double latitude,
    required double longitude,
    double? severity,
    String? description,
  }) async {
    final template = _demoTemplates.firstWhere(
      (t) => t.type == type,
      orElse: () => _demoTemplates.first,
    );

    debugPrint(
      '🔔 triggerDemoEvent called: type=${type.displayName}, lat=$latitude, lng=$longitude',
    );

    // Use high severity for demo to ensure reroute triggers
    final effectiveSeverity = severity ?? template.severityRange.max;

    final result = await createEvent(
      type: type,
      latitude: latitude,
      longitude: longitude,
      severity: effectiveSeverity,
      description:
          description ??
          template.descriptions[_random.nextInt(template.descriptions.length)],
      duration: Duration(minutes: 30),
    );

    debugPrint(
      '✅ Event created with severity=$effectiveSeverity, result: needsReroute=${result.needsReroute}, reason=${result.reason}',
    );
    return result;
  }

  /// Add event listener
  void addEventListener(EventCallback callback) {
    _eventCallbacks.add(callback);
  }

  /// Remove event listener
  void removeEventListener(EventCallback callback) {
    _eventCallbacks.remove(callback);
  }

  /// Get active events count
  int get activeEventCount {
    int count = 0;
    for (final events in _routeOptimizer.gridState.eventsByCell.values) {
      count += events.where((e) => e.isActive).length;
    }
    return count;
  }

  /// Check if simulation is running
  bool get isSimulating => _isSimulating;

  /// Dispose resources
  void dispose() {
    stopEventSimulation();
    _eventController.close();
    _eventCallbacks.clear();
  }
}

/// Template for generating demo events
class _DemoEventTemplate {
  final H3EventType type;
  final List<String> descriptions;
  final ({double min, double max}) severityRange;
  final ({int min, int max}) durationMinutes;

  const _DemoEventTemplate({
    required this.type,
    required this.descriptions,
    required this.severityRange,
    required this.durationMinutes,
  });
}
