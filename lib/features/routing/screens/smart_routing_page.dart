import 'dart:convert';

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
  MapboxMap? _mapboxMap;
  bool _isRouting = false;

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
  }

  @override
  void dispose() {
    fromController.dispose();
    toController.dispose();
    super.dispose();
  }

  Future<void> _planRoute(BuildContext context) async {
    if (_mapboxToken.isEmpty || _mapboxToken == 'REPLACE_WITH_MAPBOX_TOKEN') {
      _showMapSnack(context, 'Add a valid Mapbox token to plan routes');
      return;
    }

    setState(() => _isRouting = true);

    try {
      final origin = await _geocodePlace(fromController.text.trim(), context);
      final destination =
          await _geocodePlace(toController.text.trim(), context);

      if (origin == null || destination == null) {
        return;
      }

      final route =
          await _fetchRoute(origin: origin, destination: destination, context: context);
      if (route == null) {
        return;
      }

      final distanceKm = route.distanceMeters / 1000;
      final eta = _formatDuration(Duration(seconds: route.durationSeconds));
      final co2 = '${(distanceKm * 0.12).toStringAsFixed(2)} kg';

      setState(() {
        plan = SmartRoutePlan(
          distance: '${distanceKm.toStringAsFixed(1)} km',
          eta: eta,
          co2Savings: co2,
          congestionScore: route.congestionLabel,
          events: includeEvents ? route.events : [],
          instructions: route.steps,
        );
      });

      // Focus map near the origin of the route.
      await _mapboxMap?.flyTo(
        CameraOptions(center: origin.toPoint(), zoom: 12.5),
        MapAnimationOptions(duration: 800, startDelay: 0),
      );
    } catch (e) {
      _showMapSnack(context, 'Could not plan route: $e');
    } finally {
      if (mounted) setState(() => _isRouting = false);
    }
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
      {
        'limit': '1',
        'access_token': _mapboxToken,
      },
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

    final center = (features.first as Map<String, dynamic>)['center'] as List<dynamic>;
    if (center.length < 2) {
      _showMapSnack(context, 'Invalid coordinates for "$query"');
      return null;
    }

    return _LngLat(lng: (center[0] as num).toDouble(), lat: (center[1] as num).toDouble());
  }

  Future<_RouteResult?> _fetchRoute({
    required _LngLat origin,
    required _LngLat destination,
    required BuildContext context,
  }) async {
    final path =
        '/directions/v5/mapbox/driving-traffic/${origin.lng},${origin.lat};${destination.lng},${destination.lat}';
    final uri = Uri.https('api.mapbox.com', path, {
      'alternatives': 'false',
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

    final route = routes.first as Map<String, dynamic>;
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
        final instruction = maneuver != null ? maneuver['instruction'] as String? : null;
        if (instruction != null && instruction.isNotEmpty) {
          steps.add(instruction);
        } else if (name != null && name.isNotEmpty) {
          steps.add('Continue on $name');
        }
      }
    }

    final congestion = _congestionFromRoute(route);

    return _RouteResult(
      distanceMeters: distance,
      durationSeconds: duration.round(),
      congestionLabel: congestion,
      steps: steps.isEmpty ? const ['Follow on-screen guidance.'] : steps,
      events: const ['Live traffic from Mapbox applied'],
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
    return Scaffold(
      appBar: AppBar(title: const Text('Smart routing')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        children: [
          Text(
            'Plan with live insights.',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Layer live events, eco impact, and guided steps on top of your route.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.black54),
          ),
          const SizedBox(height: 14),
          _MapboxView(
            accessToken: _mapboxToken,
            initialCamera: CameraOptions(
              center: _defaultCenter,
              zoom: _defaultZoom,
            ),
            onMapCreated: (map) => _mapboxMap = map,
            onRecenter: () => _recenterMap(context),
            onLayers: () => _showMapSnack(context, 'Map layers coming soon'),
            onZoomIn: () => _changeZoom(context, 1),
            onZoomOut: () => _changeZoom(context, -1),
          ),
          const SizedBox(height: 16),
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
                    onChanged: (value) => setState(() => includeEvents = value),
                    title: const Text('Include live events on route'),
                    subtitle: const Text(
                      'Detours for concerts, closures, and disruptions',
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed:
                          _isRouting ? null : () => _planRoute(context),
                      icon: const Icon(Icons.play_circle_fill),
                      label: Text(_isRouting ? 'Planning…' : 'Plan route'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
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
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
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
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
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
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text('CO2 savings compared to typical route'),
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
                    style: const TextStyle(fontWeight: FontWeight.w700),
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
                    'Route instructions',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ...effectivePlan.instructions
                      .asMap()
                      .entries
                      .map(
                        (entry) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            radius: 16,
                            backgroundColor: AppTheme.primary,
                            child: Text(
                              '${entry.key + 1}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          title: Text(entry.value),
                        ),
                      )
                      .toList(),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
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

class _MapboxView extends StatelessWidget {
  const _MapboxView({
    required this.accessToken,
    required this.initialCamera,
    required this.onMapCreated,
    required this.onRecenter,
    required this.onLayers,
    required this.onZoomIn,
    required this.onZoomOut,
  });

  final String accessToken;
  final CameraOptions initialCamera;
  final ValueChanged<MapboxMap> onMapCreated;
  final VoidCallback onRecenter;
  final VoidCallback onLayers;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  @override
  Widget build(BuildContext context) {
    final bool tokenMissing =
        accessToken.isEmpty || accessToken == 'REPLACE_WITH_MAPBOX_TOKEN';

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: 360,
        child: Stack(
          children: [
            Positioned.fill(
              child: MapWidget(
                key: const ValueKey('mapbox-view'),
                cameraOptions: initialCamera,
                styleUri: MapboxStyles.MAPBOX_STREETS,
                onMapCreated: onMapCreated,
              ),
            ),
            if (tokenMissing)
              Positioned(
                top: 12,
                left: 12,
                right: 12,
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
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ),
            if (!tokenMissing)
              Positioned(
                bottom: 12,
                left: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x14000000),
                        blurRadius: 8,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: const [
                      Icon(Icons.traffic, color: Color(0xFF2D6AA7)),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Live traffic applied to routing',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Positioned(
              top: 16,
              right: 16,
              child: Column(
                children: [
                  _FloatingControlButton(
                    icon: Icons.my_location,
                    onTap: onRecenter,
                    tooltip: 'Recenter',
                  ),
                  const SizedBox(height: 10),
                  _FloatingControlButton(
                    icon: Icons.layers,
                    onTap: onLayers,
                    tooltip: 'Layers',
                  ),
                  const SizedBox(height: 10),
                  _FloatingControlButton(
                    icon: Icons.add,
                    onTap: onZoomIn,
                    tooltip: 'Zoom in',
                  ),
                  const SizedBox(height: 10),
                  _FloatingControlButton(
                    icon: Icons.remove,
                    onTap: onZoomOut,
                    tooltip: 'Zoom out',
                  ),
                ],
              ),
            ),
          ],
        ),
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
    required this.events,
  });

  final double distanceMeters;
  final int durationSeconds;
  final String congestionLabel;
  final List<String> steps;
  final List<String> events;
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
