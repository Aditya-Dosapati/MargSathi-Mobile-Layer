import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'h3_service.dart';
import 'h3_event_relevance_detector.dart';
import '../models/h3_event.dart';

/// Mock Event Dataset for Demo/Testing
///
/// This provides a fake dataset of traffic events that can be triggered
/// after a delay (default 10 seconds) to demonstrate H3-based relevance
/// detection and intelligent rerouting.
class H3MockEventDataset {
  final H3Service _h3Service;
  final H3EventRelevanceDetector _relevanceDetector;

  Timer? _eventTriggerTimer;
  final Random _random = Random();

  // Callbacks for event handling
  final List<void Function(H3Event event, H3RelevanceResult relevance)>
  _eventTriggeredCallbacks = [];

  H3MockEventDataset(this._h3Service, this._relevanceDetector);

  /// Fake dataset of mock events - these simulate real-world traffic incidents
  /// Each event has predefined location patterns that may or may not intersect
  /// with a given route based on H3 spatial analysis.
  static final List<MockEventTemplate> fakeEventDataset = [
    // Events likely to be ON typical Bangalore routes
    MockEventTemplate(
      type: H3EventType.accident,
      description: 'Multi-vehicle collision on main road',
      // Near Phoenix Mall area
      baseLatitude: 12.9716,
      baseLongitude: 77.5946,
      radiusKm: 0.3,
      severity: 0.8,
    ),
    MockEventTemplate(
      type: H3EventType.roadClosure,
      description: 'Road closed for emergency repairs',
      // Near MG Road
      baseLatitude: 12.9758,
      baseLongitude: 77.6068,
      radiusKm: 0.2,
      severity: 1.0,
    ),
    MockEventTemplate(
      type: H3EventType.heavyTraffic,
      description: 'Heavy congestion due to peak hour traffic',
      // Koramangala junction
      baseLatitude: 12.9352,
      baseLongitude: 77.6245,
      radiusKm: 0.4,
      severity: 0.6,
    ),
    MockEventTemplate(
      type: H3EventType.construction,
      description: 'Metro construction causing lane closure',
      // Near Electronic City
      baseLatitude: 12.8399,
      baseLongitude: 77.6770,
      radiusKm: 0.5,
      severity: 0.5,
    ),
    // Events likely to be OFF route (for testing NO MATCH scenarios)
    MockEventTemplate(
      type: H3EventType.flooding,
      description: 'Waterlogging reported in low-lying area',
      // Far from typical routes - Yelahanka
      baseLatitude: 13.1005,
      baseLongitude: 77.5963,
      radiusKm: 0.3,
      severity: 0.7,
    ),
    MockEventTemplate(
      type: H3EventType.accident,
      description: 'Minor accident on side road',
      // Far from typical routes - Whitefield outskirts
      baseLatitude: 12.9698,
      baseLongitude: 77.7499,
      radiusKm: 0.2,
      severity: 0.4,
    ),
    MockEventTemplate(
      type: H3EventType.event,
      description: 'Concert traffic causing delays',
      // Palace Grounds area
      baseLatitude: 12.9987,
      baseLongitude: 77.5929,
      radiusKm: 0.6,
      severity: 0.5,
    ),
    MockEventTemplate(
      type: H3EventType.hazard,
      description: 'Pothole causing traffic slowdown',
      // Near Indiranagar
      baseLatitude: 12.9719,
      baseLongitude: 77.6412,
      radiusKm: 0.15,
      severity: 0.3,
    ),
  ];

  /// Schedule a mock event to trigger after the specified delay
  ///
  /// The event is picked from the fake dataset. After triggering,
  /// H3 relevance is checked against the cached route.
  ///
  /// Returns a Future that completes when the event triggers.
  Future<void> scheduleEventAfterDelay({
    Duration delay = const Duration(seconds: 10),
    MockEventTemplate? specificEvent,
  }) async {
    debugPrint(
      '⏱️ Scheduling mock event to trigger in ${delay.inSeconds} seconds',
    );

    _eventTriggerTimer?.cancel();

    final completer = Completer<void>();

    _eventTriggerTimer = Timer(delay, () {
      final event = _createMockEvent(specificEvent);
      _triggerEvent(event);
      completer.complete();
    });

    return completer.future;
  }

  /// Trigger a mock event immediately (for testing)
  H3Event triggerEventNow({MockEventTemplate? specificEvent}) {
    final event = _createMockEvent(specificEvent);
    _triggerEvent(event);
    return event;
  }

  /// Cancel any scheduled event trigger
  void cancelScheduledEvent() {
    _eventTriggerTimer?.cancel();
    _eventTriggerTimer = null;
    debugPrint('🚫 Scheduled mock event cancelled');
  }

  /// Create an H3Event from a mock template
  H3Event _createMockEvent(MockEventTemplate? template) {
    final selectedTemplate =
        template ?? fakeEventDataset[_random.nextInt(fakeEventDataset.length)];

    // Add small random offset to make events feel more natural
    final latOffset = (_random.nextDouble() - 0.5) * 0.005; // ~500m
    final lngOffset = (_random.nextDouble() - 0.5) * 0.005;

    final latitude = selectedTemplate.baseLatitude + latOffset;
    final longitude = selectedTemplate.baseLongitude + lngOffset;

    final h3Cell = _h3Service.latLngToCell(
      latitude,
      longitude,
      resolution: H3Service.defaultResolution,
    );

    return H3Event(
      id:
          'mock_${DateTime.now().millisecondsSinceEpoch}_${_random.nextInt(10000)}',
      type: selectedTemplate.type,
      latitude: latitude,
      longitude: longitude,
      h3Cell: h3Cell,
      severity: selectedTemplate.severity,
      timestamp: DateTime.now(),
      expiresAt: DateTime.now().add(const Duration(minutes: 30)),
      description: selectedTemplate.description,
      radiusKm: selectedTemplate.radiusKm,
    );
  }

  /// Internal method to trigger an event and check relevance
  void _triggerEvent(H3Event event) {
    debugPrint('🔴 MOCK EVENT TRIGGERED: ${event.type.displayName}');
    debugPrint(
      '   📍 Location: (${event.latitude.toStringAsFixed(5)}, ${event.longitude.toStringAsFixed(5)})',
    );
    debugPrint('   🔷 H3 Cell: ${event.h3Cell}');

    // Check relevance using H3 spatial analysis
    final relevance = _relevanceDetector.checkEventRelevance(event);

    debugPrint('   📊 H3 Relevance Check: ${relevance.matchType.name}');
    debugPrint('   ℹ️ ${relevance.reason}');

    if (relevance.isRelevant) {
      debugPrint('   ✅ EVENT IS RELEVANT - Rerouting may be triggered');
    } else {
      debugPrint('   ❌ EVENT IS NOT RELEVANT - Will be IGNORED (no rerouting)');
    }

    // Notify listeners
    for (final callback in _eventTriggeredCallbacks) {
      callback(event, relevance);
    }
  }

  /// Register a callback for when events are triggered
  void addEventTriggeredListener(
    void Function(H3Event event, H3RelevanceResult relevance) callback,
  ) {
    _eventTriggeredCallbacks.add(callback);
  }

  /// Remove an event triggered listener
  void removeEventTriggeredListener(
    void Function(H3Event event, H3RelevanceResult relevance) callback,
  ) {
    _eventTriggeredCallbacks.remove(callback);
  }

  /// Create an event specifically ON the route (for guaranteed relevance)
  H3Event createEventOnRoute(
    List<({double lat, double lng})> routePath, {
    H3EventType type = H3EventType.accident,
    String description = 'Incident on your route',
    double severity = 0.8,
  }) {
    if (routePath.isEmpty) {
      throw ArgumentError('Route path cannot be empty');
    }

    // Pick a random point along the route (prefer middle section)
    final startIdx = (routePath.length * 0.2).toInt();
    final endIdx = (routePath.length * 0.8).toInt();
    final targetIdx =
        startIdx +
        _random.nextInt((endIdx - startIdx).clamp(1, routePath.length));
    final point = routePath[targetIdx.clamp(0, routePath.length - 1)];

    // Add tiny offset to be slightly off exact route point
    final latOffset = (_random.nextDouble() - 0.5) * 0.001;
    final lngOffset = (_random.nextDouble() - 0.5) * 0.001;

    final latitude = point.lat + latOffset;
    final longitude = point.lng + lngOffset;

    final h3Cell = _h3Service.latLngToCell(
      latitude,
      longitude,
      resolution: H3Service.defaultResolution,
    );

    return H3Event(
      id: 'onroute_${DateTime.now().millisecondsSinceEpoch}',
      type: type,
      latitude: latitude,
      longitude: longitude,
      h3Cell: h3Cell,
      severity: severity,
      timestamp: DateTime.now(),
      expiresAt: DateTime.now().add(const Duration(minutes: 30)),
      description: description,
      radiusKm: 0.3,
    );
  }

  /// Create an event OFF the route (for testing ignored scenarios)
  H3Event createEventOffRoute(
    List<({double lat, double lng})> routePath, {
    H3EventType type = H3EventType.accident,
    String description = 'Incident away from your route',
    double severity = 0.5,
  }) {
    // Create event far from route - shift significantly
    final baseLat = routePath.isNotEmpty ? routePath.first.lat : 12.9716;
    final baseLng = routePath.isNotEmpty ? routePath.first.lng : 77.5946;

    // Move 5-10km away from route
    final direction = _random.nextDouble() * 2 * pi;
    final distance = 0.05 + _random.nextDouble() * 0.05; // ~5-10km in degrees

    final latitude = baseLat + distance * cos(direction);
    final longitude = baseLng + distance * sin(direction);

    final h3Cell = _h3Service.latLngToCell(
      latitude,
      longitude,
      resolution: H3Service.defaultResolution,
    );

    return H3Event(
      id: 'offroute_${DateTime.now().millisecondsSinceEpoch}',
      type: type,
      latitude: latitude,
      longitude: longitude,
      h3Cell: h3Cell,
      severity: severity,
      timestamp: DateTime.now(),
      expiresAt: DateTime.now().add(const Duration(minutes: 30)),
      description: description,
      radiusKm: 0.2,
    );
  }

  /// Dispose resources
  void dispose() {
    cancelScheduledEvent();
    _eventTriggeredCallbacks.clear();
  }

  /// Generate events near a route path for demo purposes
  /// Returns a list of H3 events that may or may not be on the route
  List<H3Event> generateEventsNearRoute(
    List<({double lat, double lng})> routePath, {
    int maxEvents = 3,
  }) {
    if (routePath.isEmpty) return [];

    final events = <H3Event>[];
    final usedTemplates = <int>{};

    // Try to generate some events
    for (
      int i = 0;
      i < maxEvents && usedTemplates.length < fakeEventDataset.length;
      i++
    ) {
      int templateIdx;
      do {
        templateIdx = _random.nextInt(fakeEventDataset.length);
      } while (usedTemplates.contains(templateIdx) &&
          usedTemplates.length < fakeEventDataset.length);

      usedTemplates.add(templateIdx);
      final template = fakeEventDataset[templateIdx];

      // Check if this template is near the route
      bool isNearRoute = false;
      for (final point in routePath) {
        final distance = _calculateDistance(
          point.lat,
          point.lng,
          template.baseLatitude,
          template.baseLongitude,
        );
        if (distance < template.radiusKm + 1.0) {
          isNearRoute = true;
          break;
        }
      }

      // Only add events that are reasonably near the route (within ~2km)
      if (isNearRoute || _random.nextDouble() < 0.3) {
        events.add(_createMockEvent(template));
      }
    }

    return events;
  }

  /// Trigger a random event, optionally forcing it to be on the route
  H3Event? triggerRandomEvent({
    List<({double lat, double lng})>? routePath,
    bool forceOnRoute = false,
  }) {
    if (forceOnRoute && routePath != null && routePath.isNotEmpty) {
      final event = createEventOnRoute(routePath);
      _triggerEvent(event);
      return event;
    }

    final template = fakeEventDataset[_random.nextInt(fakeEventDataset.length)];
    final event = _createMockEvent(template);
    _triggerEvent(event);
    return event;
  }

  /// Calculate distance between two points in km (Haversine approximation)
  double _calculateDistance(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const earthRadius = 6371.0; // km
    final dLat = _toRadians(lat2 - lat1);
    final dLng = _toRadians(lng2 - lng1);
    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(dLng / 2) *
            sin(dLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  double _toRadians(double degrees) => degrees * pi / 180;
}

/// Template for mock events in the fake dataset
class MockEventTemplate {
  final H3EventType type;
  final String description;
  final double baseLatitude;
  final double baseLongitude;
  final double radiusKm;
  final double severity;

  const MockEventTemplate({
    required this.type,
    required this.description,
    required this.baseLatitude,
    required this.baseLongitude,
    required this.radiusKm,
    required this.severity,
  });
}
