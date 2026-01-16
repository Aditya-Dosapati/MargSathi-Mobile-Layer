import 'dart:async';
import 'dart:math';

import 'h3_service.dart';
import '../models/h3_event.dart';

/// Callback type for route rerouting events
typedef RerouteCallback = void Function(RerouteResult result);

/// H3 Route Optimizer uses the hexagonal grid to analyze routes,
/// detect events, and trigger dynamic rerouting when needed.
class H3RouteOptimizer {
  final H3Service _h3Service;

  // Current route state
  Set<BigInt> _currentRouteCells = {};
  // ignore: unused_field
  List<({double lat, double lng})> _currentRoutePath = [];
  // ignore: unused_field
  ({double lat, double lng})? _origin;
  ({double lat, double lng})? _destination;

  // Grid state
  H3GridState _gridState = H3GridState.empty();

  // Reroute listeners
  final List<RerouteCallback> _rerouteCallbacks = [];

  // Monitoring state
  Timer? _monitoringTimer;
  bool _isMonitoring = false;

  H3RouteOptimizer(this._h3Service);

  /// Set the current route to monitor
  Future<void> setRoute(
    List<({double lat, double lng})> routePath,
    ({double lat, double lng}) origin,
    ({double lat, double lng}) destination,
  ) async {
    _currentRoutePath = routePath;
    _origin = origin;
    _destination = destination;

    // Convert route to H3 cells
    _currentRouteCells = _h3Service.getRouteCells(
      routePath,
      resolution: H3Service.defaultResolution,
    );

    // Also add buffer cells around route for early warning
    final bufferCells = <BigInt>{};
    for (final cell in _currentRouteCells) {
      final neighbors = _h3Service.getKRing(cell, 1);
      bufferCells.addAll(neighbors);
    }
    _currentRouteCells.addAll(bufferCells);
  }

  /// Clear the current route
  void clearRoute() {
    _currentRouteCells = {};
    _currentRoutePath = [];
    _origin = null;
    _destination = null;
  }

  /// Add an event to the grid state
  Future<RerouteCheckResult> addEvent(H3Event event) async {
    final cell = event.h3Cell;

    // Update grid state
    final events = _gridState.eventsByCell[cell] ?? [];
    events.add(event);
    _gridState.eventsByCell[cell] = events;

    // Also add to affected cells within radius
    final affectedCells = _h3Service.getCellsInRadius(
      event.latitude,
      event.longitude,
      event.radiusKm,
      resolution: H3Service.defaultResolution,
    );

    for (final affectedCell in affectedCells) {
      if (affectedCell != cell) {
        final cellEvents = _gridState.eventsByCell[affectedCell] ?? [];
        cellEvents.add(event);
        _gridState.eventsByCell[affectedCell] = cellEvents;
      }
    }

    // Check if reroute is needed
    final result = _checkRerouteNeeded(event);

    // IMPORTANT: Actually trigger reroute if needed!
    if (result.needsReroute) {
      _notifyReroute(
        RerouteResult(
          isRequired: true,
          reason: result.reason,
          affectedEvents: result.affectedEvents,
          suggestedWaypoint:
              result.affectedEvents.isNotEmpty
                  ? findAvoidanceWaypoint(result.affectedEvents.first)
                  : null,
        ),
      );
    }

    return result;
  }

  /// Remove an event from the grid state
  void removeEvent(String eventId) {
    for (final entry in _gridState.eventsByCell.entries) {
      entry.value.removeWhere((e) => e.id == eventId);
    }
    // Clean up empty entries
    _gridState.eventsByCell.removeWhere((_, events) => events.isEmpty);
  }

  /// Update congestion for a cell
  void updateCongestion(H3CellCongestion congestion) {
    _gridState.congestionByCell[congestion.h3Cell] = congestion;
  }

  /// Check if current route is affected by events
  RerouteCheckResult _checkRerouteNeeded(H3Event? triggeringEvent) {
    if (_currentRouteCells.isEmpty) {
      return RerouteCheckResult(
        needsReroute: false,
        reason: 'No active route',
        affectedEvents: [],
      );
    }

    // Get events affecting the route
    final affectingEvents = _gridState.getEventsOnRoute(_currentRouteCells);

    if (affectingEvents.isEmpty) {
      return RerouteCheckResult(
        needsReroute: false,
        reason: 'No events on route',
        affectedEvents: [],
      );
    }

    // Check for blocking events
    final blockingEvents =
        affectingEvents
            .where(
              (e) => e.requiresReroute || !_gridState.isCellPassable(e.h3Cell),
            )
            .toList();

    if (blockingEvents.isNotEmpty) {
      return RerouteCheckResult(
        needsReroute: true,
        reason: 'Route blocked by ${blockingEvents.first.type.displayName}',
        affectedEvents: blockingEvents,
        triggeringEvent: triggeringEvent,
      );
    }

    // Check cumulative delay impact
    double totalCostIncrease = 0;
    for (final event in affectingEvents) {
      totalCostIncrease += (event.costMultiplier - 1.0);
    }

    // Suggest reroute if delay impact is significant (> 30% increase)
    if (totalCostIncrease > 0.3) {
      return RerouteCheckResult(
        needsReroute: true,
        reason:
            'Significant delays detected (${(totalCostIncrease * 100).toStringAsFixed(0)}% increase)',
        affectedEvents: affectingEvents,
        triggeringEvent: triggeringEvent,
      );
    }

    return RerouteCheckResult(
      needsReroute: false,
      reason: 'Minor impact only',
      affectedEvents: affectingEvents,
    );
  }

  /// Calculate route cost through H3 grid
  double calculateRouteCost(List<({double lat, double lng})> routePath) {
    final routeCells = _h3Service.getRouteCells(
      routePath,
      resolution: H3Service.defaultResolution,
    );

    double totalCost = 0;
    for (final cell in routeCells) {
      final cellCost = _gridState.getCellCost(cell);
      if (cellCost == double.infinity) {
        return double.infinity;
      }
      totalCost += cellCost;
    }

    return totalCost;
  }

  /// Find optimal waypoint to avoid an event
  ({double lat, double lng})? findAvoidanceWaypoint(H3Event event) {
    // Get cells around the event
    final eventCells = _h3Service.getCellsInRadius(
      event.latitude,
      event.longitude,
      event.radiusKm * 2, // Double radius for buffer
      resolution: H3Service.defaultResolution,
    );

    // Find cells adjacent to blocked area that are passable
    final candidateCells = <BigInt>[];
    for (final cell in eventCells) {
      if (_gridState.isCellPassable(cell)) {
        // Check if it's on the edge of the affected area
        final neighbors = _h3Service.getKRing(cell, 1);
        final hasBlockedNeighbor = neighbors.any(
          (n) => !_gridState.isCellPassable(n),
        );
        if (hasBlockedNeighbor) {
          candidateCells.add(cell);
        }
      }
    }

    if (candidateCells.isEmpty) return null;

    // Pick the candidate closest to the destination
    if (_destination == null) return null;

    BigInt? bestCell;
    double bestDistance = double.infinity;

    for (final cell in candidateCells) {
      final center = _h3Service.cellToLatLng(cell);
      final distance = _calculateDistance(
        center.lat,
        center.lon,
        _destination!.lat,
        _destination!.lng,
      );

      if (distance < bestDistance) {
        bestDistance = distance;
        bestCell = cell;
      }
    }

    if (bestCell == null) return null;

    final waypoint = _h3Service.cellToLatLng(bestCell);
    return (lat: waypoint.lat, lng: waypoint.lon);
  }

  /// Calculate haversine distance between two points (in km)
  double _calculateDistance(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const R = 6371.0; // Earth's radius in km
    final dLat = _toRadians(lat2 - lat1);
    final dLng = _toRadians(lng2 - lng1);

    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(dLng / 2) *
            sin(dLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return R * c;
  }

  double _toRadians(double degrees) => degrees * pi / 180;

  /// Start monitoring for events
  void startMonitoring({Duration checkInterval = const Duration(seconds: 10)}) {
    if (_isMonitoring) return;

    _isMonitoring = true;
    _monitoringTimer = Timer.periodic(checkInterval, (_) {
      _performMonitoringCheck();
    });
  }

  /// Stop monitoring
  void stopMonitoring() {
    _isMonitoring = false;
    _monitoringTimer?.cancel();
    _monitoringTimer = null;
  }

  void _performMonitoringCheck() {
    // Clean up expired events
    _cleanupExpiredEvents();

    // Check if reroute is needed
    final result = _checkRerouteNeeded(null);

    if (result.needsReroute) {
      _notifyReroute(
        RerouteResult(
          isRequired: true,
          reason: result.reason,
          affectedEvents: result.affectedEvents,
          suggestedWaypoint:
              result.affectedEvents.isNotEmpty
                  ? findAvoidanceWaypoint(result.affectedEvents.first)
                  : null,
        ),
      );
    }
  }

  void _cleanupExpiredEvents() {
    for (final entry in _gridState.eventsByCell.entries) {
      entry.value.removeWhere((e) => !e.isActive);
    }
    _gridState.eventsByCell.removeWhere((_, events) => events.isEmpty);
  }

  /// Register a callback for reroute events
  void addRerouteListener(RerouteCallback callback) {
    _rerouteCallbacks.add(callback);
  }

  /// Remove a reroute callback
  void removeRerouteListener(RerouteCallback callback) {
    _rerouteCallbacks.remove(callback);
  }

  void _notifyReroute(RerouteResult result) {
    for (final callback in _rerouteCallbacks) {
      callback(result);
    }
  }

  /// Get current grid state
  H3GridState get gridState => _gridState;

  /// Get current route cells
  Set<BigInt> get currentRouteCells => _currentRouteCells;

  /// Check if optimizer is monitoring
  bool get isMonitoring => _isMonitoring;

  /// Get all active events on current route
  List<H3Event> get eventsOnRoute {
    return _gridState.getEventsOnRoute(_currentRouteCells);
  }

  /// Get all active events in the grid (for display purposes)
  List<H3Event> get allActiveEvents {
    final events = <H3Event>[];
    final seenIds = <String>{};
    for (final cellEvents in _gridState.eventsByCell.values) {
      for (final event in cellEvents) {
        if (event.isActive && !seenIds.contains(event.id)) {
          seenIds.add(event.id);
          events.add(event);
        }
      }
    }
    return events;
  }

  /// Dispose resources
  void dispose() {
    stopMonitoring();
    _rerouteCallbacks.clear();
  }
}

/// Result of checking if reroute is needed
class RerouteCheckResult {
  final bool needsReroute;
  final String reason;
  final List<H3Event> affectedEvents;
  final H3Event? triggeringEvent;

  RerouteCheckResult({
    required this.needsReroute,
    required this.reason,
    required this.affectedEvents,
    this.triggeringEvent,
  });
}

/// Result passed to reroute callbacks
class RerouteResult {
  final bool isRequired;
  final String reason;
  final List<H3Event> affectedEvents;
  final ({double lat, double lng})? suggestedWaypoint;
  final DateTime timestamp;

  RerouteResult({
    required this.isRequired,
    required this.reason,
    required this.affectedEvents,
    this.suggestedWaypoint,
  }) : timestamp = DateTime.now();

  @override
  String toString() {
    return 'RerouteResult(isRequired: $isRequired, reason: $reason, events: ${affectedEvents.length})';
  }
}
