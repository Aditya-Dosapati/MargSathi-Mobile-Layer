import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:http/http.dart' as http;
import '../../shared/theme/app_theme.dart';
import '../models/smart_route_plan.dart';
import '../models/h3_event.dart';
import '../services/h3_service.dart';
import '../services/h3_route_optimizer.dart';
import '../services/h3_event_relevance_detector.dart';
import '../services/h3_event_stream_manager.dart';
import '../services/h3_mock_event_dataset.dart';

class SmartRoutingPage extends StatefulWidget {
  const SmartRoutingPage({super.key});

  @override
  State<SmartRoutingPage> createState() => _SmartRoutingPageState();
}

class _SmartRoutingPageState extends State<SmartRoutingPage> {
  final TextEditingController fromController = TextEditingController();
  final TextEditingController toController = TextEditingController();
  bool includeEvents = true;
  SmartRoutePlan? plan;
  _LngLat? _lastOrigin;
  _LngLat? _lastDestination;
  MapboxMap? _mapboxMap;
  PolylineAnnotationManager? _routeLineManager;
  CircleAnnotationManager? _circleManager;
  PointAnnotationManager? _labelManager;
  late final Widget _mapView;
  bool _isRouting = false;
  bool _mapReady = false;
  String? _nextInstruction;

  // H3 Services
  late final H3Service _h3Service;
  late final H3RouteOptimizer _h3RouteOptimizer;
  late final H3EventRelevanceDetector _h3RelevanceDetector;
  late final H3EventStreamManager _h3EventStreamManager;
  late final H3MockEventDataset _h3MockDataset;
  bool _h3Initialized = false;

  // H3 Events on current route
  List<H3Event> _relevantEvents = [];
  List<({double lat, double lng})> _currentRoutePath = [];
  H3Event?
  _triggeredDemoEvent; // Store triggered event to ensure it's displayed

  // Use token from dart-define
  static const String _mapboxToken = String.fromEnvironment(
    'MAPBOX_ACCESS_TOKEN',
    defaultValue:
        'pk.eyJ1IjoidGVqYTEyMzQ1Njc4IiwiYSI6ImNtam55Y2pieDBpbW4zY3NkMThydWY1YXcifQ.m_RPJfnP6TEgRI0tiZTnmw',
  );

  static final Point _defaultCenter = Point(
    coordinates: Position(83.2185, 17.6868), // Visakhapatnam
  );
  static const double _defaultZoom = 12.5;

  @override
  void initState() {
    super.initState();
    _initializeH3Services();
    _mapView = MapWidget(
      key: const ValueKey('mapbox-view'),
      cameraOptions: CameraOptions(center: _defaultCenter, zoom: _defaultZoom),
      styleUri: MapboxStyles.MAPBOX_STREETS,
      onMapCreated: _onMapCreated,
    );
  }

  Future<void> _initializeH3Services() async {
    try {
      debugPrint('🔷 Starting H3 Services initialization...');
      _h3Service = H3Service();
      await _h3Service.initialize();
      debugPrint('🔷 H3Service initialized');

      _h3RelevanceDetector = H3EventRelevanceDetector(_h3Service);
      _h3RouteOptimizer = H3RouteOptimizer(_h3Service);
      _h3EventStreamManager = H3EventStreamManager(
        _h3Service,
        _h3RouteOptimizer,
      );
      _h3MockDataset = H3MockEventDataset(_h3Service, _h3RelevanceDetector);

      // Listen for reroute events from H3 optimizer
      _h3RouteOptimizer.addRerouteListener(_onH3RerouteTriggered);

      if (mounted) {
        setState(() => _h3Initialized = true);
      }
      debugPrint('🔷 H3 Services fully initialized!');
    } catch (e, stackTrace) {
      debugPrint('❌ H3 Services initialization failed: $e');
      debugPrint('Stack trace: $stackTrace');
    }
  }

  void _onH3RerouteTriggered(RerouteResult result) {
    if (!mounted) return;
    debugPrint('🔄 H3 Reroute triggered: ${result.reason}');
    debugPrint('   Affected events: ${result.affectedEvents.length}');

    if (result.isRequired && _lastOrigin != null && _lastDestination != null) {
      // Use WidgetsBinding to ensure we're in a valid frame with valid context
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        try {
          final ctx = context;
          _showMapSnack(
            ctx,
            '⚠️ ${result.reason} - Finding alternate route...',
          );

          // If we have an affected event, use its location for exclusion
          if (result.affectedEvents.isNotEmpty) {
            final event = result.affectedEvents.first;
            _triggeredDemoEvent = event;
            _planRouteWithExclusion(
              ctx,
              excludePoint: (lat: event.latitude, lng: event.longitude),
            );
          } else {
            _planRoute(ctx, forceAlternate: true);
          }
        } catch (e, stackTrace) {
          debugPrint('❌ Reroute callback error: $e');
          debugPrint('Stack: $stackTrace');
        }
      });
    }
  }

  @override
  void dispose() {
    fromController.dispose();
    toController.dispose();
    _h3EventStreamManager.stopEventSimulation();
    _h3RouteOptimizer.stopMonitoring();
    super.dispose();
  }

  Future<void> _onMapCreated(MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    _routeLineManager =
        await mapboxMap.annotations.createPolylineAnnotationManager();
    _circleManager =
        await mapboxMap.annotations.createCircleAnnotationManager();
    _labelManager = await mapboxMap.annotations.createPointAnnotationManager();
    setState(() => _mapReady = true);
  }

  Future<void> _planRoute(
    BuildContext context, {
    bool forceAlternate = false,
  }) async {
    if (!_mapReady) {
      _showMapSnack(context, 'Map is still loading');
      return;
    }
    if (!_h3Initialized) {
      _showMapSnack(context, 'H3 services initializing...');
      return;
    }

    // Clear triggered event if this is a fresh route (not a reroute)
    if (!forceAlternate) {
      _triggeredDemoEvent = null;
    }

    setState(() => _isRouting = true);

    try {
      final origin = await _geocodePlace(fromController.text.trim(), context);
      final destination = await _geocodePlace(
        toController.text.trim(),
        context,
      );

      if (origin == null || destination == null) {
        setState(() => _isRouting = false);
        return;
      }

      final primaryRoute = await _fetchRoute(
        origin: origin,
        destination: destination,
        context: context,
        preferAlternate: forceAlternate,
      );
      if (primaryRoute == null) {
        setState(() => _isRouting = false);
        return;
      }

      // Convert route to H3 cells and cache for event relevance detection
      _currentRoutePath =
          primaryRoute.path.map((p) => (lat: p.lat, lng: p.lng)).toList();
      _h3RelevanceDetector.cacheRouteCells(_currentRoutePath);

      // Set route in H3 optimizer for monitoring
      await _h3RouteOptimizer.setRoute(
        _currentRoutePath,
        (lat: origin.lat, lng: origin.lng),
        (lat: destination.lat, lng: destination.lng),
      );

      var route = primaryRoute;
      List<H3Event> relevantH3Events = [];

      // Check for H3 events on route if events are enabled
      if (includeEvents) {
        // If there's a triggered demo event, add it first
        if (_triggeredDemoEvent != null) {
          relevantH3Events.add(_triggeredDemoEvent!);
          debugPrint(
            '🚨 Including triggered demo event: ${_triggeredDemoEvent!.type.displayName}',
          );
        }

        // Get mock events and check their relevance using H3
        final mockEvents = _h3MockDataset.generateEventsNearRoute(
          _currentRoutePath,
        );

        for (final event in mockEvents) {
          // Skip if it's the same as triggered event
          if (_triggeredDemoEvent != null &&
              event.id == _triggeredDemoEvent!.id)
            continue;

          final relevance = _h3RelevanceDetector.checkEventRelevance(event);
          if (relevance.isRelevant) {
            relevantH3Events.add(event);
            debugPrint(
              '🎯 H3 Event relevant: ${event.description} (${relevance.matchType})',
            );

            // Add event to optimizer for tracking
            await _h3RouteOptimizer.addEvent(event);
          }
        }

        // Check if any relevant event requires rerouting
        final needsReroute = relevantH3Events.any((e) => e.requiresReroute);

        if (needsReroute && !forceAlternate) {
          _showMapSnack(
            context,
            '⚠️ H3 detected blocking event - rerouting...',
          );
          final alternate = await _fetchRoute(
            origin: origin,
            destination: destination,
            context: context,
            preferAlternate: true,
            mustBeAlternate: true,
          );
          if (alternate != null) {
            route = alternate;
            // Update H3 cache with new route
            _currentRoutePath =
                alternate.path.map((p) => (lat: p.lat, lng: p.lng)).toList();
            _h3RelevanceDetector.cacheRouteCells(_currentRoutePath);
          }
        }
      }

      final distanceKm = route.distanceMeters / 1000;
      final eta = _formatDuration(Duration(seconds: route.durationSeconds));
      final co2 = '${(distanceKm * 0.12).toStringAsFixed(2)} kg';

      // Generate event descriptions from H3 events
      final eventDescriptions =
          relevantH3Events
              .map((e) => '${e.type.displayName}: ${e.description}')
              .toList();

      if (relevantH3Events.any((e) => e.requiresReroute) && forceAlternate) {
        eventDescriptions.insert(0, '🔄 H3-based dynamic reroute applied');
      }

      debugPrint(
        '📊 Preparing to draw route with ${relevantH3Events.length} events',
      );
      for (final evt in relevantH3Events) {
        debugPrint(
          '   - ${evt.type.displayName} at (${evt.latitude}, ${evt.longitude})',
        );
      }

      final isRerouted =
          forceAlternate || relevantH3Events.any((e) => e.requiresReroute);
      await _drawRoute(route, relevantH3Events, isRerouted: isRerouted);
      await _focusRoute(route, events: relevantH3Events);

      // Note: Event simulation removed - incidents are only triggered manually via "Trigger H3 Demo Reroute" button

      setState(() {
        plan = SmartRoutePlan(
          distance: '${distanceKm.toStringAsFixed(1)} km',
          eta: eta,
          co2Savings: co2,
          congestionScore: route.congestionLabel,
          events: includeEvents ? eventDescriptions : [],
          instructions: route.steps,
          h3Events: relevantH3Events,
          routeCells: _h3RelevanceDetector.convertRouteToH3Cells(
            _currentRoutePath,
          ),
          isRerouted:
              forceAlternate || relevantH3Events.any((e) => e.requiresReroute),
          rerouteReason:
              relevantH3Events.any((e) => e.requiresReroute)
                  ? 'H3 detected ${relevantH3Events.where((e) => e.requiresReroute).first.type.displayName}'
                  : null,
        );
        _relevantEvents = relevantH3Events;
        _nextInstruction = route.steps.isNotEmpty ? route.steps.first : null;
      });

      // Store origin/destination OUTSIDE setState for use in rerouting
      _lastOrigin = origin;
      _lastDestination = destination;
      debugPrint(
        '✅ Route planned. Origin: (${origin.lat}, ${origin.lng}), Dest: (${destination.lat}, ${destination.lng})',
      );
      debugPrint('✅ Route path has ${_currentRoutePath.length} points');
    } catch (e) {
      _showMapSnack(context, 'Could not plan route: $e');
    } finally {
      if (mounted) setState(() => _isRouting = false);
    }
  }

  Future<void> _triggerDemoReroute() async {
    debugPrint('🔄 _triggerDemoReroute called');
    debugPrint(
      '   _mapReady: $_mapReady, _lastOrigin: $_lastOrigin, _lastDestination: $_lastDestination',
    );
    debugPrint('   _currentRoutePath length: ${_currentRoutePath.length}');

    if (_mapboxMap == null || !_mapReady) {
      _showMapSnack(context, 'Map is not ready');
      return;
    }

    if (_lastOrigin == null ||
        _lastDestination == null ||
        _currentRoutePath.isEmpty) {
      _showMapSnack(context, 'Plan a route first to demo reroute');
      return;
    }

    // Store current route path before creating event
    final routePathForEvent = List<({double lat, double lng})>.from(
      _currentRoutePath,
    );
    debugPrint(
      '   Creating event on route with ${routePathForEvent.length} points',
    );

    // Trigger a mock event from H3 dataset - force it ON the route
    final mockEvent = _h3MockDataset.triggerRandomEvent(
      routePath: routePathForEvent,
      forceOnRoute: true,
    );

    if (mockEvent == null) {
      _showMapSnack(context, 'Failed to create demo event');
      return;
    }

    _triggeredDemoEvent = mockEvent; // Store for display
    final relevance = _h3RelevanceDetector.checkEventRelevance(mockEvent);

    debugPrint('🚨 Demo event created successfully:');
    debugPrint('   Type: ${mockEvent.type.displayName}');
    debugPrint('   Location: (${mockEvent.latitude}, ${mockEvent.longitude})');
    debugPrint('   Relevance: ${relevance.matchType.name}');
    debugPrint('   Requires reroute: ${mockEvent.requiresReroute}');

    _showMapSnack(
      context,
      '🚨 ${mockEvent.type.displayName} detected! Finding alternate route...',
    );

    // Add to optimizer
    await _h3RouteOptimizer.addEvent(mockEvent);

    // Force reroute with alternate route, passing event location to exclude
    await _planRouteWithExclusion(
      context,
      excludePoint: (lat: mockEvent.latitude, lng: mockEvent.longitude),
    );
  }

  /// Plan route while excluding a specific point (for rerouting around events)
  Future<void> _planRouteWithExclusion(
    BuildContext context, {
    required ({double lat, double lng}) excludePoint,
  }) async {
    if (!_mapReady || !_h3Initialized) return;

    setState(() => _isRouting = true);

    try {
      // Use cached origin/destination for rerouting
      final origin = _lastOrigin;
      final destination = _lastDestination;

      if (origin == null || destination == null) {
        _showMapSnack(context, 'No previous route to reroute from');
        setState(() => _isRouting = false);
        return;
      }

      debugPrint(
        '🔄 Fetching alternate route excluding (${excludePoint.lat}, ${excludePoint.lng})',
      );

      // Fetch route with exclusion
      final route = await _fetchRouteWithExclusion(
        origin: origin,
        destination: destination,
        context: context,
        excludePoint: excludePoint,
      );

      if (route == null) {
        // Fallback to regular alternate route if exclusion fails
        debugPrint('⚠️ Exclusion route failed, trying regular alternate');
        final alternateRoute = await _fetchRoute(
          origin: origin,
          destination: destination,
          context: context,
          preferAlternate: true,
        );
        if (alternateRoute == null) {
          _showMapSnack(context, 'Could not find alternate route');
          setState(() => _isRouting = false);
          return;
        }
        await _finishRouteUpdate(alternateRoute, origin, destination);
        return;
      }

      await _finishRouteUpdate(route, origin, destination);
    } catch (e) {
      debugPrint('❌ Route exclusion error: $e');
      _showMapSnack(context, 'Could not plan alternate route: $e');
    } finally {
      if (mounted) setState(() => _isRouting = false);
    }
  }

  Future<void> _finishRouteUpdate(
    _RouteResult route,
    _LngLat origin,
    _LngLat destination,
  ) async {
    // Update route path cache
    _currentRoutePath =
        route.path.map((p) => (lat: p.lat, lng: p.lng)).toList();
    _h3RelevanceDetector.cacheRouteCells(_currentRoutePath);

    // Update optimizer
    await _h3RouteOptimizer.setRoute(
      _currentRoutePath,
      (lat: origin.lat, lng: origin.lng),
      (lat: destination.lat, lng: destination.lng),
    );

    // Collect events for display
    List<H3Event> relevantH3Events = [];
    if (_triggeredDemoEvent != null) {
      relevantH3Events.add(_triggeredDemoEvent!);
    }

    final distanceKm = route.distanceMeters / 1000;
    final eta = _formatDuration(Duration(seconds: route.durationSeconds));
    final co2 = '${(distanceKm * 0.12).toStringAsFixed(2)} kg';

    final eventDescriptions =
        relevantH3Events
            .map((e) => '${e.type.displayName}: ${e.description}')
            .toList();
    eventDescriptions.insert(0, '🔄 Route updated to avoid incident');

    debugPrint(
      '📊 Drawing updated route with ${relevantH3Events.length} events',
    );

    await _drawRoute(route, relevantH3Events, isRerouted: true);

    // For reroutes, zoom to the event area to show the avoidance, not the full route
    if (relevantH3Events.isNotEmpty) {
      await _zoomToEventArea(relevantH3Events.first, route);
    } else {
      await _focusRoute(route, events: relevantH3Events);
    }

    setState(() {
      plan = SmartRoutePlan(
        distance: '${distanceKm.toStringAsFixed(1)} km',
        eta: eta,
        co2Savings: co2,
        congestionScore: route.congestionLabel,
        events: eventDescriptions,
        instructions: route.steps,
        h3Events: relevantH3Events,
        routeCells: _h3RelevanceDetector.convertRouteToH3Cells(
          _currentRoutePath,
        ),
        isRerouted: true,
        rerouteReason:
            relevantH3Events.isNotEmpty
                ? 'Avoiding ${relevantH3Events.first.type.displayName}'
                : 'Route updated',
      );
      _relevantEvents = relevantH3Events;
      _nextInstruction = route.steps.isNotEmpty ? route.steps.first : null;
    });

    debugPrint('✅ Route update complete!');
  }

  Future<_RouteResult?> _fetchRouteWithExclusion({
    required _LngLat origin,
    required _LngLat destination,
    required BuildContext context,
    required ({double lat, double lng}) excludePoint,
  }) async {
    // Mapbox doesn't support point exclusion directly, so we use a waypoint
    // to route around the event by adding an avoidance waypoint perpendicular
    // to the direct path at a safe distance from the event.

    // Calculate an avoidance waypoint - offset perpendicular to the event
    final avoidanceWaypoint = _calculateAvoidanceWaypoint(
      origin: origin,
      destination: destination,
      eventLat: excludePoint.lat,
      eventLng: excludePoint.lng,
      offsetKm: 1.5, // 1.5km offset to ensure we route around
    );

    debugPrint(
      '🛣️ Calculated avoidance waypoint: (${avoidanceWaypoint.lat}, ${avoidanceWaypoint.lng})',
    );

    // Build route with waypoint: origin -> avoidance waypoint -> destination
    final path =
        '/directions/v5/mapbox/driving-traffic/${origin.lng},${origin.lat};${avoidanceWaypoint.lng},${avoidanceWaypoint.lat};${destination.lng},${destination.lat}';
    final uri = Uri.https('api.mapbox.com', path, {
      'alternatives': 'false', // Single route through waypoint
      'geometries': 'geojson',
      'overview': 'full',
      'steps': 'true',
      'access_token': _mapboxToken,
    });

    debugPrint('🛣️ Fetching route with avoidance waypoint');

    final response = await http.get(uri);
    if (response.statusCode != 200) {
      debugPrint(
        '⚠️ Route with avoidance waypoint failed: ${response.statusCode}',
      );
      debugPrint('Response: ${response.body}');
      return null;
    }

    final body = json.decode(response.body) as Map<String, dynamic>;
    final routes = body['routes'] as List<dynamic>?;
    if (routes == null || routes.isEmpty) {
      debugPrint('⚠️ No routes returned with avoidance waypoint');
      return null;
    }

    debugPrint('🛣️ Got ${routes.length} route(s) with avoidance waypoint');

    // Use the first route (routed through waypoint)
    final route = routes[0] as Map<String, dynamic>;
    final distance = (route['distance'] as num?)?.toDouble();
    final duration = (route['duration'] as num?)?.toDouble();
    if (distance == null || duration == null) {
      return null;
    }

    final legs = (route['legs'] as List<dynamic>?) ?? [];
    final steps = <String>[];
    for (final leg in legs) {
      final legSteps = (leg as Map<String, dynamic>)['steps'] as List<dynamic>?;
      if (legSteps == null) continue;
      for (final step in legSteps) {
        final name = (step as Map<String, dynamic>)['name'] as String?;
        final maneuver = step['maneuver'] as Map<String, dynamic>?;
        final instruction =
            maneuver != null ? maneuver['instruction'] as String? : null;
        if (instruction != null && instruction.isNotEmpty) {
          steps.add(instruction);
        } else if (name != null && name.isNotEmpty) {
          steps.add('Continue on $name');
        }
      }
    }

    final congestion = _congestionFromRoute(route);

    final geometry = route['geometry'] as Map<String, dynamic>?;
    final coords =
        (geometry?['coordinates'] as List<dynamic>? ?? [])
            .whereType<List<dynamic>>()
            .where((c) => c.length >= 2)
            .map(
              (c) => _LngLat(
                lng: (c[0] as num).toDouble(),
                lat: (c[1] as num).toDouble(),
              ),
            )
            .toList();

    if (coords.isEmpty) {
      return null;
    }

    return _RouteResult(
      distanceMeters: distance,
      durationSeconds: duration.round(),
      congestionLabel: congestion,
      steps: steps.isEmpty ? const ['Follow on-screen guidance.'] : steps,
      path: coords,
      origin: origin,
      destination: destination,
    );
  }

  Future<void> _drawRoute(
    _RouteResult route,
    List<H3Event> events, {
    bool isRerouted = false,
  }) async {
    if (_routeLineManager == null || _circleManager == null) return;

    await _routeLineManager!.deleteAll();
    await _circleManager!.deleteAll();
    await _labelManager?.deleteAll();

    if (route.path.isEmpty) return;

    final line = route.path
        .map((p) => Position(p.lng, p.lat))
        .toList(growable: false);

    // Draw route line - use orange/amber for rerouted paths, blue for normal
    final routeColor =
        isRerouted
            ? const Color(0xFFFF9800)
                .value // Orange for rerouted
            : const Color(0xFF2D6AA7).value; // Blue for normal

    await _routeLineManager!.create(
      PolylineAnnotationOptions(
        geometry: LineString(coordinates: line),
        lineColor: routeColor,
        lineWidth: isRerouted ? 7.0 : 6.0, // Slightly thicker for rerouted
      ),
    );

    // Draw origin marker (green)
    await _circleManager!.create(
      CircleAnnotationOptions(
        geometry: route.origin.toPoint(),
        circleColor: const Color(0xFF4CAF50).value,
        circleRadius: 12.0,
        circleStrokeWidth: 3.0,
        circleStrokeColor: Colors.white.value,
      ),
    );

    // Draw destination marker (red flag)
    await _circleManager!.create(
      CircleAnnotationOptions(
        geometry: route.destination.toPoint(),
        circleColor: const Color(0xFFF44336).value,
        circleRadius: 12.0,
        circleStrokeWidth: 3.0,
        circleStrokeColor: Colors.white.value,
      ),
    );

    // Draw H3 event markers - IMPORTANT: Draw these last so they're on top
    debugPrint('🎯 Drawing ${events.length} event markers on map');
    for (final event in events) {
      debugPrint(
        '  📍 Event at lat=${event.latitude}, lng=${event.longitude}: ${event.type.displayName}',
      );

      // Large outer pulse effect (warning area) - RED with high visibility
      await _circleManager!.create(
        CircleAnnotationOptions(
          geometry: Point(
            coordinates: Position(event.longitude, event.latitude),
          ),
          circleColor: const Color(0xFFFF0000).value,
          circleRadius: 50.0, // Much larger for visibility
          circleOpacity: 0.35,
          circleStrokeWidth: 4.0,
          circleStrokeColor: const Color(0xFFFF0000).value,
          circleStrokeOpacity: 0.8,
        ),
      );

      // Middle ring (warning)
      await _circleManager!.create(
        CircleAnnotationOptions(
          geometry: Point(
            coordinates: Position(event.longitude, event.latitude),
          ),
          circleColor: const Color(0xFFFF5722).value,
          circleRadius: 30.0,
          circleOpacity: 0.5,
          circleStrokeWidth: 3.0,
          circleStrokeColor: Colors.white.value,
        ),
      );

      // Inner solid marker (center point) - very visible
      await _circleManager!.create(
        CircleAnnotationOptions(
          geometry: Point(
            coordinates: Position(event.longitude, event.latitude),
          ),
          circleColor: const Color(0xFFFF1744).value, // Bright red accent
          circleRadius: 16.0,
          circleStrokeWidth: 5.0,
          circleStrokeColor: Colors.white.value,
        ),
      );

      // Add text label showing what's happening at this incident
      if (_labelManager != null) {
        await _labelManager!.create(
          PointAnnotationOptions(
            geometry: Point(
              coordinates: Position(event.longitude, event.latitude),
            ),
            textField: '⚠️ ${event.type.displayName}\n${event.description}',
            textSize: 12.0,
            textColor: Colors.white.value,
            textHaloColor: const Color(0xFFD32F2F).value,
            textHaloWidth: 2.0,
            textOffset: [0, 3.5], // Offset below the marker
            textAnchor: TextAnchor.TOP,
            textMaxWidth: 15.0,
          ),
        );
      }
    }
  }

  /// Zoom to a specific event location on the map
  Future<void> _zoomToEvent(H3Event event) async {
    if (_mapboxMap == null) return;

    debugPrint(
      '📍 Zooming to event: ${event.type.displayName} at (${event.latitude}, ${event.longitude})',
    );

    // Draw a highlight marker at the event location
    if (_circleManager != null) {
      // Add a pulsing highlight at the event
      await _circleManager!.create(
        CircleAnnotationOptions(
          geometry: Point(
            coordinates: Position(event.longitude, event.latitude),
          ),
          circleColor: const Color(0xFFFFEB3B).value,
          circleRadius: 50.0,
          circleOpacity: 0.3,
          circleStrokeWidth: 3.0,
          circleStrokeColor: const Color(0xFFFFEB3B).value,
        ),
      );
    }

    await _mapboxMap!.flyTo(
      CameraOptions(
        center: Point(coordinates: Position(event.longitude, event.latitude)),
        zoom: 16.0,
        bearing: 0,
      ),
      MapAnimationOptions(duration: 800, startDelay: 0),
    );

    _showMapSnack(
      context,
      '📍 ${event.type.displayName}: ${event.description}',
    );
  }

  /// Zoom to show the event and the rerouted path around it
  Future<void> _zoomToEventArea(H3Event event, _RouteResult route) async {
    if (_mapboxMap == null) return;

    // Find route points near the event to show context of the avoidance
    final nearbyRoutePoints =
        route.path.where((p) {
          final dist = _haversineDistance(
            p.lat,
            p.lng,
            event.latitude,
            event.longitude,
          );
          return dist < 5.0; // Within 5km of event
        }).toList();

    if (nearbyRoutePoints.isEmpty) {
      // Fallback to just zooming to event
      await _mapboxMap!.flyTo(
        CameraOptions(
          center: Point(coordinates: Position(event.longitude, event.latitude)),
          zoom: 14.0,
          bearing: 0,
        ),
        MapAnimationOptions(duration: 800, startDelay: 0),
      );
      return;
    }

    // Calculate bounds that include event and nearby route
    List<double> allLats = nearbyRoutePoints.map((p) => p.lat).toList();
    List<double> allLngs = nearbyRoutePoints.map((p) => p.lng).toList();
    allLats.add(event.latitude);
    allLngs.add(event.longitude);

    final minLat = allLats.reduce(min);
    final maxLat = allLats.reduce(max);
    final minLng = allLngs.reduce(min);
    final maxLng = allLngs.reduce(max);

    // Add some padding to the bounds
    final latPadding = (maxLat - minLat) * 0.2;
    final lngPadding = (maxLng - minLng) * 0.2;

    final bounds = CoordinateBounds(
      southwest: Point(
        coordinates: Position(minLng - lngPadding, minLat - latPadding),
      ),
      northeast: Point(
        coordinates: Position(maxLng + lngPadding, maxLat + latPadding),
      ),
      infiniteBounds: false,
    );

    final camera = await _mapboxMap!.cameraForCoordinateBounds(
      bounds,
      MbxEdgeInsets(top: 100, left: 40, bottom: 280, right: 40),
      null,
      null,
      null,
      null,
    );

    // Ensure minimum zoom level so we can see details
    final adjustedCamera = CameraOptions(
      center: camera.center,
      zoom: max(camera.zoom ?? 14.0, 13.0), // At least zoom 13
      bearing: camera.bearing,
    );

    await _mapboxMap!.flyTo(
      adjustedCamera,
      MapAnimationOptions(duration: 1000, startDelay: 0),
    );

    debugPrint('📍 Zoomed to event area showing reroute avoidance');
  }

  int _getEventColor(H3EventType type) {
    switch (type) {
      case H3EventType.accident:
      case H3EventType.roadClosure:
      case H3EventType.flooding:
        return const Color(0xFFE53935).value;
      case H3EventType.heavyTraffic:
      case H3EventType.construction:
        return const Color(0xFFFF9800).value;
      case H3EventType.weather:
      case H3EventType.event:
        return const Color(0xFF2196F3).value;
      default:
        return const Color(0xFFFFC107).value;
    }
  }

  Future<void> _focusRoute(_RouteResult route, {List<H3Event>? events}) async {
    if (_mapboxMap == null || route.path.isEmpty) return;

    // Collect all points: route + event locations
    List<double> allLats = route.path.map((p) => p.lat).toList();
    List<double> allLngs = route.path.map((p) => p.lng).toList();

    // Include event locations in bounds calculation
    if (events != null) {
      for (final event in events) {
        allLats.add(event.latitude);
        allLngs.add(event.longitude);
      }
    }

    final minLat = allLats.reduce(min);
    final maxLat = allLats.reduce(max);
    final minLng = allLngs.reduce(min);
    final maxLng = allLngs.reduce(max);

    final bounds = CoordinateBounds(
      southwest: Point(coordinates: Position(minLng, minLat)),
      northeast: Point(coordinates: Position(maxLng, maxLat)),
      infiniteBounds: false,
    );

    final camera = await _mapboxMap!.cameraForCoordinateBounds(
      bounds,
      MbxEdgeInsets(top: 80, left: 20, bottom: 260, right: 20),
      null,
      null,
      null,
      null,
    );

    await _mapboxMap!.flyTo(
      camera,
      MapAnimationOptions(duration: 900, startDelay: 0),
    );
  }

  Future<void> _recenterMap(BuildContext context) async {
    if (_mapboxMap == null) {
      _showMapSnack(context, 'Map is still loading');
      return;
    }
    await _mapboxMap!.flyTo(
      CameraOptions(center: _defaultCenter, zoom: _defaultZoom, bearing: 0),
      MapAnimationOptions(duration: 800, startDelay: 0),
    );
  }

  Future<void> _changeZoom(BuildContext context, double delta) async {
    if (_mapboxMap == null) {
      _showMapSnack(context, 'Map is still loading');
      return;
    }
    final camera = await _mapboxMap!.getCameraState();
    final double nextZoom = (camera.zoom + delta).clamp(3.0, 20.0);
    await _mapboxMap!.flyTo(
      CameraOptions(
        center: camera.center,
        zoom: nextZoom,
        bearing: camera.bearing,
      ),
      MapAnimationOptions(duration: 500, startDelay: 0),
    );
  }

  Future<_LngLat?> _geocodePlace(String query, BuildContext context) async {
    if (query.isEmpty) {
      _showMapSnack(context, 'Enter a place name');
      return null;
    }

    final uri = Uri.https(
      'api.mapbox.com',
      '/geocoding/v5/mapbox.places/${Uri.encodeComponent(query)}.json',
      {'limit': '1', 'access_token': _mapboxToken},
    );

    final response = await http.get(uri);
    if (response.statusCode != 200) {
      _showMapSnack(context, 'Geocoding failed (${response.statusCode})');
      return null;
    }

    final body = json.decode(response.body) as Map<String, dynamic>;
    final features = body['features'] as List<dynamic>?;
    if (features == null || features.isEmpty) {
      _showMapSnack(context, 'No results for "$query"');
      return null;
    }

    final center =
        (features.first as Map<String, dynamic>)['center'] as List<dynamic>;
    if (center.length < 2) {
      _showMapSnack(context, 'Invalid coordinates for "$query"');
      return null;
    }

    return _LngLat(
      lng: (center[0] as num).toDouble(),
      lat: (center[1] as num).toDouble(),
    );
  }

  Future<_RouteResult?> _fetchRoute({
    required _LngLat origin,
    required _LngLat destination,
    required BuildContext context,
    bool preferAlternate = false,
    bool mustBeAlternate = false,
  }) async {
    final path =
        '/directions/v5/mapbox/driving-traffic/${origin.lng},${origin.lat};${destination.lng},${destination.lat}';
    final uri = Uri.https('api.mapbox.com', path, {
      'alternatives': 'true',
      'geometries': 'geojson',
      'overview': 'full',
      'steps': 'true',
      'access_token': _mapboxToken,
    });

    final response = await http.get(uri);
    if (response.statusCode != 200) {
      _showMapSnack(context, 'Routing failed (${response.statusCode})');
      return null;
    }

    final body = json.decode(response.body) as Map<String, dynamic>;
    final routes = body['routes'] as List<dynamic>?;
    if (routes == null || routes.isEmpty) {
      _showMapSnack(context, 'No route found');
      return null;
    }

    routes.sort((a, b) {
      final ad =
          ((a as Map<String, dynamic>)['duration'] as num?)?.toDouble() ??
          double.infinity;
      final bd =
          ((b as Map<String, dynamic>)['duration'] as num?)?.toDouble() ??
          double.infinity;
      return ad.compareTo(bd);
    });

    debugPrint(
      '🛣️ Mapbox returned ${routes.length} route(s). preferAlternate=$preferAlternate',
    );

    if (mustBeAlternate && routes.length < 2) {
      debugPrint('⚠️ No alternate route available');
      return null;
    }

    final chosenIndex = preferAlternate && routes.length > 1 ? 1 : 0;
    debugPrint('🛣️ Using route index $chosenIndex');

    final route = routes[chosenIndex] as Map<String, dynamic>;
    final distance = (route['distance'] as num?)?.toDouble();
    final duration = (route['duration'] as num?)?.toDouble();
    if (distance == null || duration == null) {
      _showMapSnack(context, 'Route data incomplete');
      return null;
    }

    final legs = (route['legs'] as List<dynamic>?) ?? [];
    final steps = <String>[];
    for (final leg in legs) {
      final legSteps = (leg as Map<String, dynamic>)['steps'] as List<dynamic>?;
      if (legSteps == null) continue;
      for (final step in legSteps) {
        final name = (step as Map<String, dynamic>)['name'] as String?;
        final maneuver = step['maneuver'] as Map<String, dynamic>?;
        final instruction =
            maneuver != null ? maneuver['instruction'] as String? : null;
        if (instruction != null && instruction.isNotEmpty) {
          steps.add(instruction);
        } else if (name != null && name.isNotEmpty) {
          steps.add('Continue on $name');
        }
      }
    }

    final congestion = _congestionFromRoute(route);

    final geometry = route['geometry'] as Map<String, dynamic>?;
    final coords =
        (geometry?['coordinates'] as List<dynamic>? ?? [])
            .whereType<List<dynamic>>()
            .where((c) => c.length >= 2)
            .map(
              (c) => _LngLat(
                lng: (c[0] as num).toDouble(),
                lat: (c[1] as num).toDouble(),
              ),
            )
            .toList();

    if (coords.isEmpty) {
      _showMapSnack(context, 'Route geometry missing');
      return null;
    }

    return _RouteResult(
      distanceMeters: distance,
      durationSeconds: duration.round(),
      congestionLabel: congestion,
      steps: steps.isEmpty ? const ['Follow on-screen guidance.'] : steps,
      path: coords,
      origin: origin,
      destination: destination,
    );
  }

  String _congestionFromRoute(Map<String, dynamic> route) {
    final typical = (route['duration_typical'] as num?)?.toDouble();
    final duration = (route['duration'] as num?)?.toDouble();
    if (duration == null || typical == null || typical == 0) return '—';
    final ratio = duration / typical;
    if (ratio < 1.05) return 'Low';
    if (ratio < 1.25) return 'Moderate';
    return 'High';
  }

  /// Calculate an avoidance waypoint that routes AROUND the event
  /// The waypoint is placed perpendicular to the route direction,
  /// offset from the event location to force routing around it
  _LngLat _calculateAvoidanceWaypoint({
    required _LngLat origin,
    required _LngLat destination,
    required double eventLat,
    required double eventLng,
    required double offsetKm,
  }) {
    // Calculate the bearing from origin to destination
    final routeBearing = _calculateBearing(
      origin.lat,
      origin.lng,
      destination.lat,
      destination.lng,
    );

    // Calculate perpendicular bearings (90 degrees offset from route)
    final perpBearing1 = (routeBearing + 90) % 360;
    final perpBearing2 = (routeBearing - 90 + 360) % 360;

    // Calculate both potential avoidance points - offset FROM the event
    final avoidPoint1 = _offsetPoint(
      eventLat,
      eventLng,
      perpBearing1,
      offsetKm,
    );
    final avoidPoint2 = _offsetPoint(
      eventLat,
      eventLng,
      perpBearing2,
      offsetKm,
    );

    // For each avoidance point, calculate a waypoint that's:
    // 1. At the same "progress" along the route as the event
    // 2. But offset perpendicular to avoid the event

    // Find how far along the route the event is (0 = origin, 1 = destination)
    final totalDist = _haversineDistance(
      origin.lat,
      origin.lng,
      destination.lat,
      destination.lng,
    );
    final distToEvent = _haversineDistance(
      origin.lat,
      origin.lng,
      eventLat,
      eventLng,
    );
    final progress = (distToEvent / totalDist).clamp(
      0.2,
      0.8,
    ); // Keep waypoint between 20-80% of route

    // Calculate point along direct route at same progress
    final routePointLat =
        origin.lat + (destination.lat - origin.lat) * progress;
    final routePointLng =
        origin.lng + (destination.lng - origin.lng) * progress;

    // Now offset this point perpendicular to the route to create waypoint
    // Use larger offset (2x) to ensure we go around, not through
    final waypoint1 = _offsetPoint(
      routePointLat,
      routePointLng,
      perpBearing1,
      offsetKm * 2,
    );
    final waypoint2 = _offsetPoint(
      routePointLat,
      routePointLng,
      perpBearing2,
      offsetKm * 2,
    );

    // Choose waypoint that is FARTHER from the event (to ensure avoidance)
    final distFromEvent1 = _haversineDistance(
      waypoint1.lat,
      waypoint1.lng,
      eventLat,
      eventLng,
    );
    final distFromEvent2 = _haversineDistance(
      waypoint2.lat,
      waypoint2.lng,
      eventLat,
      eventLng,
    );

    final chosenWaypoint =
        distFromEvent1 > distFromEvent2 ? waypoint1 : waypoint2;

    debugPrint('🧭 Event at ($eventLat, $eventLng)');
    debugPrint('🧭 Route progress: ${(progress * 100).toStringAsFixed(0)}%');
    debugPrint(
      '🧭 Waypoint distances from event: ${distFromEvent1.toStringAsFixed(2)}km vs ${distFromEvent2.toStringAsFixed(2)}km',
    );
    debugPrint(
      '🧭 Chosen waypoint: (${chosenWaypoint.lat}, ${chosenWaypoint.lng})',
    );

    return chosenWaypoint;
  }

  /// Calculate bearing between two points in degrees
  double _calculateBearing(double lat1, double lng1, double lat2, double lng2) {
    final dLng = _toRadians(lng2 - lng1);
    final lat1Rad = _toRadians(lat1);
    final lat2Rad = _toRadians(lat2);

    final x = sin(dLng) * cos(lat2Rad);
    final y =
        cos(lat1Rad) * sin(lat2Rad) - sin(lat1Rad) * cos(lat2Rad) * cos(dLng);

    final bearing = atan2(x, y);
    return (_toDegrees(bearing) + 360) % 360;
  }

  /// Offset a point by distance (km) along a bearing (degrees)
  _LngLat _offsetPoint(
    double lat,
    double lng,
    double bearing,
    double distanceKm,
  ) {
    const earthRadiusKm = 6371.0;
    final bearingRad = _toRadians(bearing);
    final latRad = _toRadians(lat);
    final lngRad = _toRadians(lng);

    final newLatRad = asin(
      sin(latRad) * cos(distanceKm / earthRadiusKm) +
          cos(latRad) * sin(distanceKm / earthRadiusKm) * cos(bearingRad),
    );

    final newLngRad =
        lngRad +
        atan2(
          sin(bearingRad) * sin(distanceKm / earthRadiusKm) * cos(latRad),
          cos(distanceKm / earthRadiusKm) - sin(latRad) * sin(newLatRad),
        );

    return _LngLat(lat: _toDegrees(newLatRad), lng: _toDegrees(newLngRad));
  }

  /// Haversine distance between two points in km
  double _haversineDistance(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const earthRadiusKm = 6371.0;
    final dLat = _toRadians(lat2 - lat1);
    final dLng = _toRadians(lng2 - lng1);

    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(dLng / 2) *
            sin(dLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return earthRadiusKm * c;
  }

  double _toRadians(double degrees) => degrees * pi / 180;
  double _toDegrees(double radians) => radians * 180 / pi;

  String _formatDuration(Duration d) {
    if (d.inHours > 0) {
      return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
    }
    return '${d.inMinutes}m';
  }

  void _showMapSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final SmartRoutePlan effectivePlan =
        plan ?? SmartRoutePlan.placeholder(includeEvents: includeEvents);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'Smart Routing',
          style: TextStyle(
            color: Color.fromARGB(255, 0, 0, 0),
            fontWeight: FontWeight.w800,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Stack(
        children: [
          Positioned.fill(child: _mapView),
          // H3 Status indicator
          if (_h3Initialized)
            Positioned(
              top: 100,
              left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(color: Color(0x1A000000), blurRadius: 4),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFF4CAF50),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'H3 Active',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // Next instruction overlay
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 12, top: 50, right: 90),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child:
                      _nextInstruction == null
                          ? const SizedBox.shrink()
                          : Container(
                            key: const ValueKey('next-instruction'),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x14000000),
                                  blurRadius: 10,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.navigation,
                                  color: Color(0xFF2D6AA7),
                                ),
                                const SizedBox(width: 10),
                                Flexible(
                                  child: Text(
                                    _nextInstruction!,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: Colors.black87,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                ),
              ),
            ),
          ),
          // Map controls
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 12, top: 50),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _FloatingControlButton(
                      icon: Icons.my_location,
                      onTap: () => _recenterMap(context),
                      tooltip: 'Recenter',
                    ),
                    const SizedBox(height: 10),
                    _FloatingControlButton(
                      icon: Icons.add,
                      onTap: () => _changeZoom(context, 1),
                      tooltip: 'Zoom in',
                    ),
                    const SizedBox(height: 10),
                    _FloatingControlButton(
                      icon: Icons.remove,
                      onTap: () => _changeZoom(context, -1),
                      tooltip: 'Zoom out',
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Bottom sheet
          Align(
            alignment: Alignment.bottomCenter,
            child: DraggableScrollableSheet(
              initialChildSize: 0.38,
              minChildSize: 0.20,
              maxChildSize: 0.92,
              builder: (context, controller) {
                return Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(22),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x1A000000),
                        blurRadius: 12,
                        offset: Offset(0, -4),
                      ),
                    ],
                  ),
                  child: SingleChildScrollView(
                    controller: controller,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 38,
                            height: 4,
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: Colors.black26,
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                        Text(
                          'H3-Powered Smart Routing',
                          style: Theme.of(
                            context,
                          ).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: AppTheme.primary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Uber H3 hexagonal indexing for precise event detection and intelligent rerouting.',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: Colors.black54),
                        ),
                        const SizedBox(height: 14),
                        // Input card
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
                                    hintText: 'Enter starting point',
                                    prefixIcon: Icon(
                                      Icons.trip_origin,
                                      color: Colors.green,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: toController,
                                  decoration: const InputDecoration(
                                    labelText: 'To',
                                    hintText: 'Enter ending point',
                                    prefixIcon: Icon(
                                      Icons.flag,
                                      color: Colors.red,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                SwitchListTile(
                                  value: includeEvents,
                                  onChanged:
                                      (value) =>
                                          setState(() => includeEvents = value),
                                  title: const Text(
                                    'Enable H3 event detection',
                                  ),
                                  subtitle: const Text(
                                    'Detect and avoid events using hexagonal spatial indexing',
                                  ),
                                ),
                                const SizedBox(height: 10),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed:
                                        _isRouting || !_h3Initialized
                                            ? null
                                            : () => _planRoute(context),
                                    icon: const Icon(Icons.play_circle_fill),
                                    label: Text(
                                      _isRouting ? 'Planning…' : 'Plan Route',
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    onPressed:
                                        _isRouting || !_h3Initialized
                                            ? null
                                            : _triggerDemoReroute,
                                    icon: const Icon(Icons.alt_route),
                                    label: const Text(
                                      'Trigger H3 Demo Reroute',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        // Stats row
                        _InsightRow(plan: effectivePlan),
                        const SizedBox(height: 12),
                        // H3 Events card
                        if (includeEvents)
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.hexagon,
                                        color: AppTheme.primary,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'H3 Events on Route',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const Spacer(),
                                      if (_relevantEvents.isNotEmpty)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.orange.shade100,
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                          child: Text(
                                            '${_relevantEvents.length}',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: Colors.orange.shade800,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  if (_relevantEvents.isEmpty)
                                    const Text(
                                      'No H3 events detected on route.',
                                    )
                                  else
                                    ..._relevantEvents
                                        .map(
                                          (event) => _H3EventTile(
                                            event: event,
                                            onTap: () => _zoomToEvent(event),
                                          ),
                                        )
                                        .toList(),
                                ],
                              ),
                            ),
                          ),
                        const SizedBox(height: 12),
                        // Live monitoring card
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Live Monitoring',
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
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
                        // Eco impact card
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Eco Impact',
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 10),
                                const Text(
                                  'CO₂ savings compared to typical route',
                                ),
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
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
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
          Text(
            label,
            style: const TextStyle(color: Colors.black54, fontSize: 12),
          ),
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

class _LngLat {
  const _LngLat({required this.lng, required this.lat});

  final double lng;
  final double lat;

  Point toPoint() => Point(coordinates: Position(lng, lat));
}

class _RouteResult {
  const _RouteResult({
    required this.distanceMeters,
    required this.durationSeconds,
    required this.congestionLabel,
    required this.steps,
    required this.path,
    required this.origin,
    required this.destination,
  });

  final double distanceMeters;
  final int durationSeconds;
  final String congestionLabel;
  final List<String> steps;
  final List<_LngLat> path;
  final _LngLat origin;
  final _LngLat destination;
}

class _FloatingControlButton extends StatelessWidget {
  const _FloatingControlButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Tooltip(
            message: tooltip,
            child: Icon(icon, color: const Color(0xFF2D6AA7)),
          ),
        ),
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
                  const Text('ETA', style: TextStyle(fontSize: 12)),
                  const SizedBox(height: 6),
                  Text(
                    plan.eta,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Includes live traffic',
                    style: TextStyle(fontSize: 11),
                  ),
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
                  const Text('Distance', style: TextStyle(fontSize: 12)),
                  const SizedBox(height: 6),
                  Text(
                    plan.distance,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'H3 optimized route',
                    style: TextStyle(fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _H3EventTile extends StatelessWidget {
  const _H3EventTile({required this.event, this.onTap});

  final H3Event event;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _getEventColor().withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _getEventColor().withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(_getEventIcon(), color: _getEventColor(), size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.type.displayName,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: _getEventColor(),
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        event.description,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _getSeverityColor().withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _getSeverityLabel(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: _getSeverityColor(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.location_on,
                          size: 12,
                          color: Colors.grey.shade500,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          'Tap to locate',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _getEventColor() {
    switch (event.type) {
      case H3EventType.accident:
      case H3EventType.roadClosure:
      case H3EventType.flooding:
        return Colors.red;
      case H3EventType.heavyTraffic:
      case H3EventType.construction:
        return Colors.orange;
      case H3EventType.weather:
      case H3EventType.event:
        return Colors.blue;
      default:
        return Colors.amber;
    }
  }

  IconData _getEventIcon() {
    switch (event.type) {
      case H3EventType.accident:
        return Icons.car_crash;
      case H3EventType.roadClosure:
        return Icons.block;
      case H3EventType.heavyTraffic:
        return Icons.traffic;
      case H3EventType.construction:
        return Icons.construction;
      case H3EventType.weather:
        return Icons.cloud;
      case H3EventType.flooding:
        return Icons.water;
      case H3EventType.event:
        return Icons.event;
      case H3EventType.hazard:
        return Icons.warning;
      case H3EventType.laneRestriction:
        return Icons.remove_road;
      case H3EventType.police:
        return Icons.local_police;
    }
  }

  Color _getSeverityColor() {
    if (event.severity >= 0.7) return Colors.red;
    if (event.severity >= 0.4) return Colors.orange;
    return Colors.green;
  }

  String _getSeverityLabel() {
    if (event.severity >= 0.7) return 'High';
    if (event.severity >= 0.4) return 'Medium';
    return 'Low';
  }
}
