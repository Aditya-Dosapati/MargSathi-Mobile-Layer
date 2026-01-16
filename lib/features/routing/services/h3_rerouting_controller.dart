import 'dart:async';
import 'package:flutter/foundation.dart';
import 'h3_service.dart';
import 'h3_event_relevance_detector.dart';
import 'h3_mock_event_dataset.dart';
import '../models/h3_event.dart';

/// Callback for when rerouting should occur
typedef H3RerouteCallback = void Function(H3RerouteRequest request);

/// H3-Aware Rerouting Controller
///
/// This controller manages the intelligent rerouting flow using Uber H3
/// spatial indexing. It ensures rerouting is ONLY triggered when events
/// are spatially relevant to the current route (direct hit or adjacent).
///
/// Key behaviors:
/// - Converts route polyline to H3 cells and caches them
/// - When events occur, checks H3 relevance before any rerouting
/// - If event is NOT relevant (no H3 overlap/adjacency), it is IGNORED
/// - If event IS relevant, triggers reroute with H3 avoidance constraints
/// - Ensures new route avoids all event-affected H3 cells
class H3ReroutingController {
  // ignore: unused_field
  final H3Service _h3Service;
  final H3EventRelevanceDetector _relevanceDetector;
  final H3MockEventDataset _mockEventDataset;

  // Current route state
  List<({double lat, double lng})> _currentRoutePath = [];
  ({double lat, double lng})? _currentOrigin;
  ({double lat, double lng})? _currentDestination;

  // Active events on route
  final List<H3Event> _activeRelevantEvents = [];

  // Reroute callbacks
  final List<H3RerouteCallback> _rerouteCallbacks = [];

  // Event tracking callbacks (for UI updates even when not rerouting)
  final List<void Function(H3Event event, bool isRelevant)>
  _eventTrackingCallbacks = [];

  H3ReroutingController(this._h3Service)
    : _relevanceDetector = H3EventRelevanceDetector(_h3Service),
      _mockEventDataset = H3MockEventDataset(
        _h3Service,
        H3EventRelevanceDetector(_h3Service),
      ) {
    // Listen for mock events
    _mockEventDataset.addEventTriggeredListener(_onMockEventTriggered);
  }

  /// Set the current route for monitoring
  ///
  /// This caches the route's H3 cells for efficient relevance checking.
  void setRoute(
    List<({double lat, double lng})> routePath,
    ({double lat, double lng}) origin,
    ({double lat, double lng}) destination,
  ) {
    _currentRoutePath = List.from(routePath);
    _currentOrigin = origin;
    _currentDestination = destination;

    // Cache H3 cells for fast relevance checking
    _relevanceDetector.cacheRouteCells(routePath);

    debugPrint(
      '🛣️ H3 Rerouting Controller: Route set with ${routePath.length} points',
    );
    debugPrint(
      '   🔷 Cached ${_relevanceDetector.cachedRouteCells.length} H3 cells',
    );
  }

  /// Clear the current route
  void clearRoute() {
    _currentRoutePath.clear();
    _currentOrigin = null;
    _currentDestination = null;
    _activeRelevantEvents.clear();
    _relevanceDetector.clearCache();
    debugPrint('🗑️ H3 Rerouting Controller: Route cleared');
  }

  /// Schedule a mock event to trigger after 10 seconds (default behavior)
  ///
  /// This simulates the "mock event triggered after 10 seconds from fake dataset"
  /// requirement. The event will be checked for H3 relevance before any rerouting.
  Future<void> scheduleMockEvent({
    Duration delay = const Duration(seconds: 10),
    MockEventTemplate? specificEvent,
  }) {
    return _mockEventDataset.scheduleEventAfterDelay(
      delay: delay,
      specificEvent: specificEvent,
    );
  }

  /// Cancel any scheduled mock event
  void cancelMockEvent() {
    _mockEventDataset.cancelScheduledEvent();
  }

  /// Trigger a mock event immediately for testing
  ///
  /// Returns the event and whether it was relevant to the route.
  ({H3Event event, bool isRelevant}) triggerMockEventNow({
    MockEventTemplate? template,
    bool forceOnRoute = false,
    bool forceOffRoute = false,
  }) {
    H3Event event;

    if (forceOnRoute && _currentRoutePath.isNotEmpty) {
      event = _mockEventDataset.createEventOnRoute(_currentRoutePath);
    } else if (forceOffRoute && _currentRoutePath.isNotEmpty) {
      event = _mockEventDataset.createEventOffRoute(_currentRoutePath);
    } else {
      event = _mockEventDataset.triggerEventNow(specificEvent: template);
    }

    final relevance = _relevanceDetector.checkEventRelevance(event);
    return (event: event, isRelevant: relevance.isRelevant);
  }

  /// Handle a mock event trigger
  void _onMockEventTriggered(H3Event event, H3RelevanceResult relevance) {
    debugPrint('🔔 H3 Controller received event: ${event.type.displayName}');

    // Notify tracking callbacks (for UI to show RED marker)
    for (final callback in _eventTrackingCallbacks) {
      callback(event, relevance.isRelevant);
    }

    // CRITICAL: Only process rerouting if event is H3-relevant
    if (!relevance.isRelevant) {
      debugPrint('🚫 Event IGNORED - No H3 overlap or adjacency with route');
      debugPrint('   ℹ️ Rerouting will NOT be triggered');
      return;
    }

    // Event is relevant - add to active events
    _activeRelevantEvents.add(event);

    debugPrint('✅ Event is H3-RELEVANT - Triggering reroute');

    // Create reroute request
    final rerouteRequest = H3RerouteRequest(
      triggeringEvent: event,
      affectedCells: _relevanceDetector.getEventAffectedCells(event),
      allAffectedEvents: List.from(_activeRelevantEvents),
      origin: _currentOrigin,
      destination: _currentDestination,
      previousRouteCells: _relevanceDetector.cachedRouteCells,
    );

    // Notify reroute callbacks
    for (final callback in _rerouteCallbacks) {
      callback(rerouteRequest);
    }
  }

  /// Process an external event (not from mock dataset)
  ///
  /// Returns the relevance result for the event.
  H3RelevanceResult processEvent(H3Event event) {
    final relevance = _relevanceDetector.checkEventRelevance(event);

    // Notify tracking callbacks
    for (final callback in _eventTrackingCallbacks) {
      callback(event, relevance.isRelevant);
    }

    if (relevance.isRelevant) {
      _activeRelevantEvents.add(event);

      final rerouteRequest = H3RerouteRequest(
        triggeringEvent: event,
        affectedCells: _relevanceDetector.getEventAffectedCells(event),
        allAffectedEvents: List.from(_activeRelevantEvents),
        origin: _currentOrigin,
        destination: _currentDestination,
        previousRouteCells: _relevanceDetector.cachedRouteCells,
      );

      for (final callback in _rerouteCallbacks) {
        callback(rerouteRequest);
      }
    }

    return relevance;
  }

  /// Validate that a new route avoids all event-affected H3 cells
  ///
  /// Use this to verify the rerouted path before applying it.
  bool validateReroute(List<({double lat, double lng})> newRoutePath) {
    if (_activeRelevantEvents.isEmpty) return true;

    final isValid = _relevanceDetector.routeAvoidsEvents(
      newRoutePath,
      _activeRelevantEvents,
    );

    if (isValid) {
      debugPrint(
        '✅ Reroute validation PASSED - New route avoids all H3 event cells',
      );
    } else {
      debugPrint(
        '❌ Reroute validation FAILED - New route still intersects event cells',
      );
    }

    return isValid;
  }

  /// Get H3 cells that must be avoided in rerouting
  ///
  /// Returns all cells affected by currently active relevant events.
  Set<BigInt> getCellsToAvoid() {
    final cellsToAvoid = <BigInt>{};

    for (final event in _activeRelevantEvents) {
      final affected = _relevanceDetector.getEventAffectedCells(event);
      cellsToAvoid.addAll(affected);
    }

    return cellsToAvoid;
  }

  /// Remove an event from tracking (e.g., when it expires)
  void removeEvent(String eventId) {
    _activeRelevantEvents.removeWhere((e) => e.id == eventId);
  }

  /// Clear all active events
  void clearEvents() {
    _activeRelevantEvents.clear();
  }

  /// Add reroute callback
  void addRerouteListener(H3RerouteCallback callback) {
    _rerouteCallbacks.add(callback);
  }

  /// Remove reroute callback
  void removeRerouteListener(H3RerouteCallback callback) {
    _rerouteCallbacks.remove(callback);
  }

  /// Add event tracking callback (called for all events, relevant or not)
  void addEventTrackingListener(
    void Function(H3Event event, bool isRelevant) callback,
  ) {
    _eventTrackingCallbacks.add(callback);
  }

  /// Remove event tracking callback
  void removeEventTrackingListener(
    void Function(H3Event event, bool isRelevant) callback,
  ) {
    _eventTrackingCallbacks.remove(callback);
  }

  /// Get relevance detector for direct access
  H3EventRelevanceDetector get relevanceDetector => _relevanceDetector;

  /// Get mock event dataset for direct access
  H3MockEventDataset get mockEventDataset => _mockEventDataset;

  /// Get current active relevant events
  List<H3Event> get activeRelevantEvents =>
      List.unmodifiable(_activeRelevantEvents);

  /// Check if route is set
  bool get hasRoute => _currentRoutePath.isNotEmpty;

  /// Dispose resources
  void dispose() {
    _mockEventDataset.dispose();
    _relevanceDetector.clearCache();
    _rerouteCallbacks.clear();
    _eventTrackingCallbacks.clear();
    _activeRelevantEvents.clear();
  }
}

/// Request object for H3-based rerouting
class H3RerouteRequest {
  /// The event that triggered the reroute
  final H3Event triggeringEvent;

  /// H3 cells affected by the triggering event (to be avoided)
  final Set<BigInt> affectedCells;

  /// All events currently affecting the route
  final List<H3Event> allAffectedEvents;

  /// Current origin
  final ({double lat, double lng})? origin;

  /// Current destination
  final ({double lat, double lng})? destination;

  /// H3 cells of the previous route (for comparison)
  final Set<BigInt> previousRouteCells;

  /// Timestamp of the request
  final DateTime timestamp;

  H3RerouteRequest({
    required this.triggeringEvent,
    required this.affectedCells,
    required this.allAffectedEvents,
    required this.origin,
    required this.destination,
    required this.previousRouteCells,
  }) : timestamp = DateTime.now();

  @override
  String toString() {
    return 'H3RerouteRequest(event: ${triggeringEvent.type.displayName}, '
        'affectedCells: ${affectedCells.length}, '
        'allEvents: ${allAffectedEvents.length})';
  }
}
