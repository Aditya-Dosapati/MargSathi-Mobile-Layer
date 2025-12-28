import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:http/http.dart' as http;
import '../../shared/theme/app_theme.dart';
import '../models/smart_route_plan.dart';

class SmartRoutingPage extends StatefulWidget {
  const SmartRoutingPage({super.key});

  @override
  State<SmartRoutingPage> createState() => _SmartRoutingPageState();
}

class _SmartRoutingPageState extends State<SmartRoutingPage> {
  final TextEditingController fromController = TextEditingController(
    text: 'Phoenix Mall',
  );
  final TextEditingController toController = TextEditingController(
    text: 'Airport T2',
  );
  bool includeEvents = true;
  SmartRoutePlan? plan;
  _LngLat? _lastOrigin;
  _LngLat? _lastDestination;
  MapboxMap? _mapboxMap;
  PolylineAnnotationManager? _routeLineManager;
  CircleAnnotationManager? _circleManager;
  late final Widget _mapView;
  bool _isRouting = false;
  bool _mapReady = false;
  String? _nextInstruction;

  static const String _mapboxToken = String.fromEnvironment(
    'MAPBOX_ACCESS_TOKEN',
    defaultValue: 'REPLACE_WITH_MAPBOX_TOKEN',
  );

  static final Point _defaultCenter = Point(
    coordinates: Position(77.5946, 12.9716),
  );
  static const double _defaultZoom = 12.5;

  @override
  void initState() {
    super.initState();
    MapboxOptions.setAccessToken(_mapboxToken);
    _mapView = MapWidget(
      key: const ValueKey('mapbox-view'),
      cameraOptions: CameraOptions(center: _defaultCenter, zoom: _defaultZoom),
      styleUri: MapboxStyles.MAPBOX_STREETS,
      onMapCreated: _onMapCreated,
    );
  }

  @override
  void dispose() {
    fromController.dispose();
    toController.dispose();
    super.dispose();
  }

  Future<void> _onMapCreated(MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    _routeLineManager =
        await mapboxMap.annotations.createPolylineAnnotationManager();
    _circleManager =
        await mapboxMap.annotations.createCircleAnnotationManager();
    setState(() => _mapReady = true);
  }

  Future<void> _planRoute(BuildContext context) async {
    if (_mapboxToken.isEmpty || _mapboxToken == 'REPLACE_WITH_MAPBOX_TOKEN') {
      _showMapSnack(context, 'Add a valid Mapbox token to plan routes');
      return;
    }
    if (!_mapReady) {
      _showMapSnack(context, 'Map is still loading');
      return;
    }

    setState(() => _isRouting = true);

    try {
      final origin = await _geocodePlace(fromController.text.trim(), context);
      final destination = await _geocodePlace(
        toController.text.trim(),
        context,
      );

      if (origin == null || destination == null) {
        return;
      }

      final primaryRoute = await _fetchRoute(
        origin: origin,
        destination: destination,
        context: context,
      );
      if (primaryRoute == null) {
        return;
      }
      var route = primaryRoute;

      final eventsOnRoute = includeEvents ? _generateEvents() : <String>[];
      final needsDetour = eventsOnRoute.any(
        (e) =>
            e.toLowerCase().contains('closure') ||
            e.toLowerCase().contains('accident'),
      );

      if (needsDetour) {
        final alternate = await _fetchRoute(
          origin: origin,
          destination: destination,
          context: context,
          preferAlternate: true,
          mustBeAlternate: true,
        );
        if (alternate != null) {
          route = alternate;
          eventsOnRoute.insert(0, 'Dynamic reroute applied');
        }
      }

      final distanceKm = route.distanceMeters / 1000;
      final eta = _formatDuration(Duration(seconds: route.durationSeconds));
      final co2 = '${(distanceKm * 0.12).toStringAsFixed(2)} kg';

      await _drawRoute(route);
      await _focusRoute(route);

      setState(() {
        plan = SmartRoutePlan(
          distance: '${distanceKm.toStringAsFixed(1)} km',
          eta: eta,
          co2Savings: co2,
          congestionScore: route.congestionLabel,
          events: includeEvents ? eventsOnRoute : [],
          instructions: route.steps,
        );
        _nextInstruction = route.steps.isNotEmpty ? route.steps.first : null;
        _lastOrigin = origin;
        _lastDestination = destination;
      });
    } catch (e) {
      _showMapSnack(context, 'Could not plan route: $e');
    } finally {
      if (mounted) setState(() => _isRouting = false);
    }
  }

  List<String> _generateEvents() {
    final seed = DateTime.now().millisecondsSinceEpoch;
    final rng = Random(seed);
    final pool = <String>[
      'Accident reported ahead, suggesting detour.',
      'Pop-up event nearby, mild slowdown.',
      'Road closure detected, rerouting.',
      'Heavy rain pockets, adjusted ETA.',
      'Lane restriction in 2 km.',
    ];
    pool.shuffle(rng);
    final count = rng.nextInt(3) + 1; // 1..3 events
    return pool.take(count).toList();
  }

  Future<void> _triggerDemoReroute() async {
    if (_mapboxMap == null ||
        !_mapReady ||
        _lastOrigin == null ||
        _lastDestination == null) {
      _showMapSnack(context, 'Plan a route first to demo reroute');
      return;
    }

    final demoEvents = _generateEvents();
    demoEvents.insert(0, 'Demo disruption triggered, rerouting');

    final alternate = await _fetchRoute(
      origin: _lastOrigin!,
      destination: _lastDestination!,
      context: context,
      preferAlternate: true,
      mustBeAlternate: true,
    );

    if (alternate == null) {
      _showMapSnack(context, 'No alternate route available for this demo');
      return;
    }

    await _drawRoute(alternate);
    await _focusRoute(alternate);

    final distanceKm = alternate.distanceMeters / 1000;
    final eta = _formatDuration(Duration(seconds: alternate.durationSeconds));
    final co2 = '${(distanceKm * 0.12).toStringAsFixed(2)} kg';

    setState(() {
      plan = SmartRoutePlan(
        distance: '${distanceKm.toStringAsFixed(1)} km',
        eta: eta,
        co2Savings: co2,
        congestionScore: alternate.congestionLabel,
        events: includeEvents ? demoEvents : [],
        instructions: alternate.steps,
      );
      _nextInstruction =
          alternate.steps.isNotEmpty ? alternate.steps.first : null;
    });
  }

  Future<void> _drawRoute(_RouteResult route) async {
    if (_routeLineManager == null || _circleManager == null) return;

    await _routeLineManager!.deleteAll();
    await _circleManager!.deleteAll();

    if (route.path.isEmpty) return;

    final line = route.path
        .map((p) => Position(p.lng, p.lat))
        .toList(growable: false);

    await _routeLineManager!.create(
      PolylineAnnotationOptions(
        geometry: LineString(coordinates: line),
        lineColor: const Color(0xFF2D6AA7).value,
        lineWidth: 6.0,
      ),
    );

    await _circleManager!.create(
      CircleAnnotationOptions(
        geometry: route.origin.toPoint(),
        circleColor: Colors.white.value,
        circleRadius: 7.0,
        circleStrokeWidth: 3.0,
        circleStrokeColor: const Color(0xFF2D6AA7).value,
      ),
    );

    await _circleManager!.create(
      CircleAnnotationOptions(
        geometry: route.destination.toPoint(),
        circleColor: Colors.white.value,
        circleRadius: 7.0,
        circleStrokeWidth: 3.0,
        circleStrokeColor: const Color(0xFFF6A609).value,
      ),
    );
  }

  Future<void> _focusRoute(_RouteResult route) async {
    if (_mapboxMap == null || route.path.isEmpty) return;

    final lats = route.path.map((p) => p.lat);
    final lngs = route.path.map((p) => p.lng);
    final minLat = lats.reduce(min);
    final maxLat = lats.reduce(max);
    final minLng = lngs.reduce(min);
    final maxLng = lngs.reduce(max);

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
      'overview': 'simplified',
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

    // Pick the fastest route when alternatives are available.
    routes.sort((a, b) {
      final ad =
          ((a as Map<String, dynamic>)['duration'] as num?)?.toDouble() ??
          double.infinity;
      final bd =
          ((b as Map<String, dynamic>)['duration'] as num?)?.toDouble() ??
          double.infinity;
      return ad.compareTo(bd);
    });

    if (mustBeAlternate && routes.length < 2) {
      return null;
    }

    final chosenIndex = preferAlternate && routes.length > 1 ? 1 : 0;
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
    final bool tokenMissing =
        _mapboxToken.isEmpty || _mapboxToken == 'REPLACE_WITH_MAPBOX_TOKEN';

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'Smart routing',
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w800),
        ),
        backgroundColor: const Color.fromARGB(0, 255, 255, 255),
        elevation: 0,
      ),
      body: Stack(
        children: [
          Positioned.fill(child: _mapView),
          if (tokenMissing)
            Positioned(
              top: 20,
              left: 16,
              right: 16,
              child: SafeArea(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF6A609),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Add your Mapbox access token to enable the live map.',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 12, top: 8, right: 90),
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
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 12, top: 8),
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
                      icon: Icons.layers,
                      onTap:
                          () =>
                              _showMapSnack(context, 'Map layers coming soon'),
                      tooltip: 'Layers',
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
          Align(
            alignment: Alignment.bottomCenter,
            child: DraggableScrollableSheet(
              initialChildSize: 0.36,
              minChildSize: 0.24,
              maxChildSize: 0.9,
              builder: (context, controller) {
                return Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(22),
                    ),
                    boxShadow: const [
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
                        Container(
                          width: 38,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.black26,
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        Text(
                          'Plan with live insights.',
                          style: Theme.of(
                            context,
                          ).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: AppTheme.primary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Layer live events, eco impact, and guided steps on top of your route.',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: Colors.black54),
                        ),
                        const SizedBox(height: 14),
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
                                    prefixIcon: Icon(Icons.trip_origin),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: toController,
                                  decoration: const InputDecoration(
                                    labelText: 'To',
                                    prefixIcon: Icon(Icons.flag),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                SwitchListTile(
                                  value: includeEvents,
                                  onChanged:
                                      (value) =>
                                          setState(() => includeEvents = value),
                                  title: const Text(
                                    'Include live events on route',
                                  ),
                                  subtitle: const Text(
                                    'Detours for concerts, closures, and disruptions',
                                  ),
                                ),
                                const SizedBox(height: 10),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed:
                                        _isRouting || tokenMissing
                                            ? null
                                            : () => _planRoute(context),
                                    icon: const Icon(Icons.play_circle_fill),
                                    label: Text(
                                      _isRouting ? 'Planning…' : 'Plan route',
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                OutlinedButton.icon(
                                  onPressed:
                                      _isRouting ? null : _triggerDemoReroute,
                                  icon: const Icon(Icons.alt_route),
                                  label: const Text('Trigger demo reroute'),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        _InsightRow(plan: effectivePlan),
                        const SizedBox(height: 12),
                        if (includeEvents)
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Events on route',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 8),
                                  if (effectivePlan.events.isEmpty)
                                    const Text('No major events detected.')
                                  else
                                    ...effectivePlan.events
                                        .map(
                                          (event) => ListTile(
                                            contentPadding: EdgeInsets.zero,
                                            leading: const Icon(
                                              Icons.emergency_share,
                                              color: Color(0xFFF6A609),
                                            ),
                                            title: Text(event),
                                          ),
                                        )
                                        .toList(),
                                ],
                              ),
                            ),
                          ),
                        const SizedBox(height: 12),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Live monitoring',
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
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Eco impact',
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 10),
                                const Text(
                                  'CO2 savings compared to typical route',
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
                        const SizedBox(height: 12),
                        // Route instructions UI hidden on request.
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
          Text(label, style: const TextStyle(color: Colors.black54)),
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
                  const Text('ETA'),
                  const SizedBox(height: 6),
                  Text(
                    plan.eta,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text('Includes live traffic'),
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
                  const Text('Distance'),
                  const SizedBox(height: 6),
                  Text(
                    plan.distance,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text('Optimized for fewer stops'),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
