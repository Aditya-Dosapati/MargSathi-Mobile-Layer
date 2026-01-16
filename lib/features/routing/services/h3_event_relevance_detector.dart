import 'package:flutter/foundation.dart';
import 'h3_service.dart';
import '../models/h3_event.dart';

/// H3-based Event Relevance Detection Service
///
/// This service determines whether an event is relevant to the current route
/// using Uber H3 hexagonal spatial indexing. An event is considered relevant
/// only if its H3 cell matches or is adjacent to any H3 cell along the route.
///
/// Resolution 9 (~174m edge length) is used for city-level routing precision.
class H3EventRelevanceDetector {
  final H3Service _h3Service;

  // Cache for route H3 cells to avoid recomputation
  Set<BigInt> _routeCellsCache = {};
  Set<BigInt> _routeCellsWithNeighborsCache = {};
  bool _cacheValid = false;

  H3EventRelevanceDetector(this._h3Service);

  /// Convert a route polyline to H3 hexagon IDs
  ///
  /// Returns a set of H3 cell indices that cover the entire route path.
  /// Uses resolution 9 for city-level routing accuracy.
  Set<BigInt> convertRouteToH3Cells(
    List<({double lat, double lng})> routePath, {
    int resolution = H3Service.defaultResolution,
  }) {
    if (routePath.isEmpty) return {};

    return _h3Service.getRouteCells(routePath, resolution: resolution);
  }

  /// Convert event coordinates to H3 hexagon ID
  ///
  /// Returns the H3 cell index for the given event location.
  BigInt convertEventToH3Cell(
    double latitude,
    double longitude, {
    int resolution = H3Service.defaultResolution,
  }) {
    return _h3Service.latLngToCell(latitude, longitude, resolution: resolution);
  }

  /// Get H3 cell for an H3Event object
  BigInt getEventH3Cell(
    H3Event event, {
    int resolution = H3Service.defaultResolution,
  }) {
    return convertEventToH3Cell(
      event.latitude,
      event.longitude,
      resolution: resolution,
    );
  }

  /// Cache route cells for efficient relevance checking
  ///
  /// Call this when a new route is set to precompute and cache
  /// the H3 cells and their neighbors for fast lookup.
  void cacheRouteCells(
    List<({double lat, double lng})> routePath, {
    int resolution = H3Service.defaultResolution,
  }) {
    _routeCellsCache = convertRouteToH3Cells(routePath, resolution: resolution);

    // Precompute neighboring cells for adjacency checking
    _routeCellsWithNeighborsCache = Set<BigInt>.from(_routeCellsCache);
    for (final cell in _routeCellsCache) {
      final neighbors = _h3Service.getKRing(cell, 1);
      _routeCellsWithNeighborsCache.addAll(neighbors);
    }

    _cacheValid = true;
    debugPrint(
      '🔷 H3 Route cache updated: ${_routeCellsCache.length} cells, '
      '${_routeCellsWithNeighborsCache.length} with neighbors',
    );
  }

  /// Clear the route cache
  void clearCache() {
    _routeCellsCache.clear();
    _routeCellsWithNeighborsCache.clear();
    _cacheValid = false;
  }

  /// Check if an event is relevant to the current cached route
  ///
  /// Returns true if the event's H3 cell:
  /// 1. Matches any H3 cell along the route (direct hit), OR
  /// 2. Falls within neighboring H3 hexagons of the route (adjacency)
  ///
  /// If no H3 overlap or adjacency exists, returns false and the event
  /// should be ignored (no rerouting triggered).
  H3RelevanceResult checkEventRelevance(H3Event event) {
    if (!_cacheValid || _routeCellsCache.isEmpty) {
      return H3RelevanceResult(
        isRelevant: false,
        reason: 'No route cached for relevance check',
        matchType: H3MatchType.noMatch,
      );
    }

    final eventCell = event.h3Cell;

    // Check for direct hit (event cell is on the route)
    if (_routeCellsCache.contains(eventCell)) {
      debugPrint(
        '🎯 H3 DIRECT HIT: Event ${event.id} cell $eventCell is ON the route',
      );
      return H3RelevanceResult(
        isRelevant: true,
        reason: 'Event is directly on route',
        matchType: H3MatchType.directHit,
        matchingCell: eventCell,
      );
    }

    // Check for adjacency (event cell is a neighbor of route cells)
    if (_routeCellsWithNeighborsCache.contains(eventCell)) {
      debugPrint(
        '📍 H3 ADJACENT: Event ${event.id} cell $eventCell is ADJACENT to route',
      );
      return H3RelevanceResult(
        isRelevant: true,
        reason: 'Event is adjacent to route',
        matchType: H3MatchType.adjacent,
        matchingCell: eventCell,
      );
    }

    // No match - event is not relevant to this route
    debugPrint(
      '❌ H3 NO MATCH: Event ${event.id} cell $eventCell is NOT relevant to route',
    );
    return H3RelevanceResult(
      isRelevant: false,
      reason: 'Event H3 cell does not overlap or adjoin route',
      matchType: H3MatchType.noMatch,
    );
  }

  /// Check event relevance with route path (without using cache)
  ///
  /// Use this for one-off checks when cache is not set up.
  H3RelevanceResult checkEventRelevanceForRoute(
    H3Event event,
    List<({double lat, double lng})> routePath, {
    int resolution = H3Service.defaultResolution,
  }) {
    if (routePath.isEmpty) {
      return H3RelevanceResult(
        isRelevant: false,
        reason: 'Empty route path',
        matchType: H3MatchType.noMatch,
      );
    }

    final routeCells = convertRouteToH3Cells(routePath, resolution: resolution);
    final eventCell = event.h3Cell;

    // Check direct hit
    if (routeCells.contains(eventCell)) {
      return H3RelevanceResult(
        isRelevant: true,
        reason: 'Event is directly on route',
        matchType: H3MatchType.directHit,
        matchingCell: eventCell,
      );
    }

    // Check adjacency
    for (final routeCell in routeCells) {
      final neighbors = _h3Service.getKRing(routeCell, 1);
      if (neighbors.contains(eventCell)) {
        return H3RelevanceResult(
          isRelevant: true,
          reason: 'Event is adjacent to route',
          matchType: H3MatchType.adjacent,
          matchingCell: eventCell,
        );
      }
    }

    return H3RelevanceResult(
      isRelevant: false,
      reason: 'Event H3 cell does not overlap or adjoin route',
      matchType: H3MatchType.noMatch,
    );
  }

  /// Get all H3 cells affected by an event (including its radius)
  ///
  /// Returns a set of H3 cells that should be avoided during reroute
  /// computation. This includes the event's primary cell and all cells
  /// within its effect radius.
  Set<BigInt> getEventAffectedCells(
    H3Event event, {
    int resolution = H3Service.defaultResolution,
  }) {
    return _h3Service.getCellsInRadius(
      event.latitude,
      event.longitude,
      event.radiusKm,
      resolution: resolution,
    );
  }

  /// Check if a proposed route avoids all event-affected H3 cells
  ///
  /// Use this to validate that a rerouted path doesn't pass through
  /// any cells affected by active events.
  bool routeAvoidsEvents(
    List<({double lat, double lng})> routePath,
    List<H3Event> eventsToAvoid, {
    int resolution = H3Service.defaultResolution,
  }) {
    if (routePath.isEmpty || eventsToAvoid.isEmpty) return true;

    final routeCells = convertRouteToH3Cells(routePath, resolution: resolution);

    for (final event in eventsToAvoid) {
      final affectedCells = getEventAffectedCells(
        event,
        resolution: resolution,
      );
      if (routeCells.intersection(affectedCells).isNotEmpty) {
        debugPrint('⚠️ Route intersects with event ${event.id} affected cells');
        return false;
      }
    }

    return true;
  }

  /// Get cached route cells (for external use)
  Set<BigInt> get cachedRouteCells => Set.unmodifiable(_routeCellsCache);

  /// Get cached route cells with neighbors (for external use)
  Set<BigInt> get cachedRouteCellsWithNeighbors =>
      Set.unmodifiable(_routeCellsWithNeighborsCache);

  /// Check if cache is valid
  bool get isCacheValid => _cacheValid;
}

/// Result of H3 event relevance check
class H3RelevanceResult {
  /// Whether the event is relevant to the route
  final bool isRelevant;

  /// Human-readable reason for the result
  final String reason;

  /// Type of match found
  final H3MatchType matchType;

  /// The H3 cell that matched (if relevant)
  final BigInt? matchingCell;

  const H3RelevanceResult({
    required this.isRelevant,
    required this.reason,
    required this.matchType,
    this.matchingCell,
  });

  @override
  String toString() {
    return 'H3RelevanceResult(isRelevant: $isRelevant, matchType: $matchType, reason: $reason)';
  }
}

/// Type of H3 match between event and route
enum H3MatchType {
  /// Event cell is directly on the route
  directHit,

  /// Event cell is adjacent (neighbor) to route cells
  adjacent,

  /// No spatial relationship with route
  noMatch,
}
