import 'dart:math';
import 'package:h3_flutter/h3_flutter.dart';

/// H3 Service provides Uber's hexagonal hierarchical spatial index operations.
/// This is the core service for converting coordinates to H3 cells and vice versa.
class H3Service {
  static final H3Service _instance = H3Service._internal();
  factory H3Service() => _instance;
  H3Service._internal();

  late final H3 _h3;
  bool _initialized = false;

  /// Resolution levels for H3:
  /// - 0-4: Coarse (country/region level)
  /// - 5-7: City level
  /// - 8-10: Neighborhood level
  /// - 11-15: Fine (street/building level)
  static const int defaultResolution =
      9; // ~174m edge length - good for routing
  static const int coarseResolution = 7; // ~1.2km - for regional analysis
  static const int fineResolution = 11; // ~24m - for precise events

  /// Initialize H3 library
  Future<void> initialize() async {
    if (_initialized) return;
    final h3Factory = const H3Factory();
    _h3 = h3Factory.load();
    _initialized = true;
  }

  /// Convert latitude/longitude to H3 cell index at given resolution
  BigInt latLngToCell(
    double lat,
    double lng, {
    int resolution = defaultResolution,
  }) {
    if (!_initialized) throw StateError('H3Service not initialized');
    return _h3.geoToCell(GeoCoord(lat: lat, lon: lng), resolution);
  }

  /// Convert H3 cell index to center coordinates
  GeoCoord cellToLatLng(BigInt h3Index) {
    if (!_initialized) throw StateError('H3Service not initialized');
    return _h3.cellToGeo(h3Index);
  }

  /// Get the boundary polygon of an H3 cell
  List<GeoCoord> getCellBoundary(BigInt h3Index) {
    if (!_initialized) throw StateError('H3Service not initialized');
    return _h3.cellToBoundary(h3Index);
  }

  /// Get all neighboring cells (k-ring) around a cell
  /// k=1 returns 7 cells (center + 6 neighbors)
  /// k=2 returns 19 cells, etc.
  List<BigInt> getKRing(BigInt h3Index, int k) {
    if (!_initialized) throw StateError('H3Service not initialized');
    return _h3.gridDisk(h3Index, k);
  }

  /// Get cells along a line between two points
  List<BigInt> getLineCells(
    double startLat,
    double startLng,
    double endLat,
    double endLng, {
    int resolution = defaultResolution,
  }) {
    if (!_initialized) throw StateError('H3Service not initialized');

    final startCell = latLngToCell(startLat, startLng, resolution: resolution);
    final endCell = latLngToCell(endLat, endLng, resolution: resolution);

    return _h3.gridPathCells(startCell, endCell);
  }

  /// Get all cells that cover a route path
  Set<BigInt> getRouteCells(
    List<({double lat, double lng})> routePath, {
    int resolution = defaultResolution,
  }) {
    if (!_initialized) throw StateError('H3Service not initialized');
    if (routePath.isEmpty) return {};

    final cells = <BigInt>{};

    for (int i = 0; i < routePath.length; i++) {
      // Add cell for this point
      cells.add(
        latLngToCell(
          routePath[i].lat,
          routePath[i].lng,
          resolution: resolution,
        ),
      );

      // Add cells between consecutive points
      if (i < routePath.length - 1) {
        try {
          final lineCells = getLineCells(
            routePath[i].lat,
            routePath[i].lng,
            routePath[i + 1].lat,
            routePath[i + 1].lng,
            resolution: resolution,
          );
          cells.addAll(lineCells);
        } catch (_) {
          // If line cells fail, just use point cells
        }
      }
    }

    return cells;
  }

  /// Get cells within a circular area
  Set<BigInt> getCellsInRadius(
    double centerLat,
    double centerLng,
    double radiusKm, {
    int resolution = defaultResolution,
  }) {
    if (!_initialized) throw StateError('H3Service not initialized');

    final centerCell = latLngToCell(
      centerLat,
      centerLng,
      resolution: resolution,
    );

    // Approximate k-ring size based on radius and resolution
    final edgeLength = getEdgeLengthKm(resolution);
    final k = (radiusKm / (edgeLength * 1.5)).ceil();

    return getKRing(centerCell, k).toSet();
  }

  /// Calculate distance between two H3 cells (in grid units)
  int gridDistance(BigInt h3Index1, BigInt h3Index2) {
    if (!_initialized) throw StateError('H3Service not initialized');
    return _h3.gridDistance(h3Index1, h3Index2);
  }

  /// Get the parent cell at a coarser resolution
  BigInt getParentCell(BigInt h3Index, int parentResolution) {
    if (!_initialized) throw StateError('H3Service not initialized');
    return _h3.cellToParent(h3Index, parentResolution);
  }

  /// Get child cells at a finer resolution
  List<BigInt> getChildCells(BigInt h3Index, int childResolution) {
    if (!_initialized) throw StateError('H3Service not initialized');
    return _h3.cellToChildren(h3Index, childResolution);
  }

  /// Get the resolution of an H3 index
  int getResolution(BigInt h3Index) {
    if (!_initialized) throw StateError('H3Service not initialized');
    return _h3.getResolution(h3Index);
  }

  /// Check if two cells are neighbors
  bool areNeighbors(BigInt h3Index1, BigInt h3Index2) {
    if (!_initialized) throw StateError('H3Service not initialized');
    return _h3.areNeighborCells(h3Index1, h3Index2);
  }

  /// Get approximate edge length in km for a given resolution
  double getEdgeLengthKm(int resolution) {
    // Approximate edge lengths for each resolution (in km)
    const edgeLengths = <int, double>{
      0: 1107.712591,
      1: 418.676005,
      2: 158.244655,
      3: 59.810857,
      4: 22.606379,
      5: 8.544408,
      6: 3.229482,
      7: 1.220629,
      8: 0.461354,
      9: 0.174375,
      10: 0.065907,
      11: 0.024910,
      12: 0.009415,
      13: 0.003559,
      14: 0.001348,
      15: 0.000509,
    };
    return edgeLengths[resolution] ?? 0.174375;
  }

  /// Calculate approximate area of a cell in km²
  double getCellAreaKm2(int resolution) {
    final edgeLength = getEdgeLengthKm(resolution);
    // Hexagon area = (3 * sqrt(3) / 2) * edge²
    return (3 * sqrt(3) / 2) * edgeLength * edgeLength;
  }

  /// Convert H3 index to string for storage/transmission
  String h3ToString(BigInt h3Index) {
    return h3Index.toRadixString(16);
  }

  /// Convert string back to H3 index
  BigInt stringToH3(String h3String) {
    return BigInt.parse(h3String, radix: 16);
  }

  bool get isInitialized => _initialized;
}
