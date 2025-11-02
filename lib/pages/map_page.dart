// lib/pages/map_page.dart

import 'dart:async';
import 'dart:math' show sin, cos, sqrt, atan2, pi;
import 'package:floovia/providers/road_status_provider.dart';
import 'package:floovia/widgets/location_search_bar.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../providers/user_location_provider.dart';
import '../providers/map_data_provider.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final Completer<GoogleMapController> _mapController = Completer();
  Set<Polyline> _polylines = {};

  bool _isLoading = false;
  String? _errorMessage;

  DateTime? _lastFetchTime;
  LatLng? _lastFetchCenter;
  LatLng? _lastKnownLocation;

  static const Duration _cacheValidDuration = Duration(seconds: 30);
  static const double _cacheDistanceThresholdKm = 0.5;
  static const Duration _debounceDelay = Duration(milliseconds: 600);

  Timer? _debounceTimer;
  final RoadStatusProvider roadStatusProvider = RoadStatusProvider.instance;

  @override
  void initState() {
    super.initState();
    // Initialize with current location
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final location = context.read<UserLocationProvider>().activeLocation;
      _lastKnownLocation = location;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Listen for location changes and update camera
    final currentLocation =
        context.watch<UserLocationProvider>().activeLocation;

    if (_lastKnownLocation != currentLocation) {
      _lastKnownLocation = currentLocation;
      _moveCameraToLocation(currentLocation);
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  /// Move camera to new location with animation
  Future<void> _moveCameraToLocation(LatLng location) async {
    if (!_mapController.isCompleted) return;

    try {
      final controller = await _mapController.future;
      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(location, 17),
      );
      debugPrint(
          '📍 Camera moved to: ${location.latitude.toStringAsFixed(4)}, ${location.longitude.toStringAsFixed(4)}');
    } catch (e) {
      debugPrint('❌ Error moving camera: $e');
    }
  }

  /// Haversine distance (accurate)
  double _calculateDistance(LatLng p1, LatLng p2) {
    const R = 6371; // km
    final dLat = (p2.latitude - p1.latitude) * (pi / 180);
    final dLon = (p2.longitude - p1.longitude) * (pi / 180);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(p1.latitude * pi / 180) *
            cos(p2.latitude * pi / 180) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  bool _isCacheValid(LatLng currentCenter) {
    if (_lastFetchTime == null || _lastFetchCenter == null) return false;
    final now = DateTime.now();

    if (now.difference(_lastFetchTime!) > _cacheValidDuration) return false;
    final distanceMoved = _calculateDistance(_lastFetchCenter!, currentCenter);
    return distanceMoved < _cacheDistanceThresholdKm;
  }

  void _loadSegmentsDebounced([LatLngBounds? bounds]) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDelay, () {
      if (mounted && bounds != null) _loadSegments(bounds);
    });
  }

  Future<void> _loadSegments(LatLngBounds bounds) async {
    if (_isLoading || !_mapController.isCompleted) return;

    final center = LatLng(
      (bounds.southwest.latitude + bounds.northeast.latitude) / 2,
      (bounds.southwest.longitude + bounds.northeast.longitude) / 2,
    );

    if (_isCacheValid(center)) {
      debugPrint('📦 Using cached segments (${_polylines.length})');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final newPolylines = await _fetchSegmentsFromFirestore(bounds);

      if (!mounted) return;
      setState(() {
        _polylines = newPolylines;
        _isLoading = false;
        _lastFetchTime = DateTime.now();
        _lastFetchCenter = center;
      });

      // 🆕 SAVE TO PROVIDER
      context.read<MapDataProvider>().savePolylines(newPolylines, center);

      debugPrint('✅ Loaded ${_polylines.length} segments');
    } catch (e, st) {
      debugPrint('❌ Failed to load segments: $e\n$st');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Gagal memuat data peta';
      });
      _showErrorSnackbar(_errorMessage!);
    }
  }

  Future<Set<Polyline>> _fetchSegmentsFromFirestore(LatLngBounds bounds) async {
    final swLat = bounds.southwest.latitude;
    final neLat = bounds.northeast.latitude;
    final swLng = bounds.southwest.longitude;
    final neLng = bounds.northeast.longitude;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('segments')
          .where('lat_max', isGreaterThan: swLat)
          .where('lat_min', isLessThan: neLat)
          .get();

      debugPrint('🔥 Fetched ${snapshot.docs.length} docs');

      final Set<Polyline> polylines = {};

      for (final doc in snapshot.docs) {
        final data = doc.data();

        final List<dynamic>? rawPoints = data['points'];
        if (rawPoints == null) continue;

        final lngMin = data['lng_min'] as num?;
        final lngMax = data['lng_max'] as num?;
        if (lngMin == null || lngMax == null) continue;

        if (lngMax < swLng || lngMin > neLng) continue;

        final List<LatLng> polyPoints = rawPoints
            .whereType<Map>()
            .where((p) => p.containsKey('lat') && p.containsKey('lng'))
            .map((p) => LatLng(
                  (p['lat'] as num).toDouble(),
                  (p['lng'] as num).toDouble(),
                ))
            .toList();

        if (polyPoints.isEmpty) continue;

        dynamic color;
        final sensorId = data['sensor_id'];
        debugPrint('Sensor ID : $sensorId');
        if (sensorId == 'null' || sensorId == 'unknown') {
          color = Colors.green;
        } else {
          final dataHeight = await roadStatusProvider.getStatus(sensorId);
          color = _polylineColor(dataHeight);
        }

        polylines.add(Polyline(
          polylineId: PolylineId(data['segment_id'] ?? doc.id),
          points: polyPoints,
          color: color,
          width: 7,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
        ));
      }

      return polylines;
    } on FirebaseException catch (e) {
      debugPrint('🔥 Firestore error: ${e.code}');
      throw Exception(_getFirebaseErrorMessage(e));
    } on TimeoutException {
      throw Exception('Koneksi timeout. Periksa internet Anda.');
    }
  }

  Color _polylineColor(double height) {
    if (height >= 30) {
      return Colors.red[600]!; // Critical
    } else if (height >= 20) {
      return Colors.orange[600]!; // Warning
    } else if (height >= 10) {
      return Colors.yellow[700]!; // Moderate
    } else if (height > 0) {
      return Colors.blue[500]!;
    } else {
      return Colors.green; // Normal
    }
  }

  String _getFirebaseErrorMessage(FirebaseException e) {
    switch (e.code) {
      case 'unavailable':
        return 'Server tidak tersedia. Periksa koneksi internet.';
      case 'permission-denied':
        return 'Akses ditolak. Hubungi administrator.';
      default:
        return 'Gagal memuat data peta';
    }
  }

  void _showErrorSnackbar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red[700],
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _goToMyLocation() async {
    final locationProvider = context.read<UserLocationProvider>();

    await locationProvider.refreshGpsLocation();

    if (!mounted || !_mapController.isCompleted) return;
    final controller = await _mapController.future;

    final currentGpsLocation = locationProvider.activeLocation;

    await controller
        .animateCamera(CameraUpdate.newLatLngZoom(currentGpsLocation, 17));
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<UserLocationProvider>(
      builder: (context, locationProvider, _) {
        final userLocation = locationProvider.activeLocation;

        if (locationProvider.isLoading && !locationProvider.hasInitialized) {
          return const Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Mendapatkan lokasi...'),
                ],
              ),
            ),
          );
        }

        return Scaffold(
          body: Stack(
            children: [
              GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: userLocation,
                  zoom: 17,
                ),
                onMapCreated: (controller) {
                  if (!_mapController.isCompleted) {
                    _mapController.complete(controller);
                  }
                },
                myLocationButtonEnabled: false,
                myLocationEnabled: true,
                zoomControlsEnabled: false,
                zoomGesturesEnabled: false,
                scrollGesturesEnabled: true,
                polylines: _polylines,
                onCameraIdle: () async {
                  final controller = await _mapController.future;
                  final bounds = await controller.getVisibleRegion();
                  _loadSegmentsDebounced(bounds);
                },
              ),
              Positioned(
                top: 16,
                left: 16,
                right: 16,
                child: const LocationSearchBar(),
              ),
              if (_isLoading)
                Positioned(
                  top: 90,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: _buildLoadingIndicator(),
                  ),
                ),
              Positioned(
                bottom: 20,
                right: 16,
                child: _buildMyLocationButton(),
              ),
              if (_polylines.isNotEmpty && !_isLoading)
                Positioned(
                  bottom: 20,
                  left: 16,
                  child: _buildSegmentCountIndicator(),
                ),
              Positioned(
                top: 330,
                right: 16,
                child: _buildLegend(),
              ),
              if (locationProvider.isUsingDefaultLocation)
                Positioned(
                  top: 600,
                  left: 16,
                  right: 16,
                  child: _buildDefaultLocationBanner(locationProvider),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLoadingIndicator() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(25),
          boxShadow: const [
            BoxShadow(
                color: Colors.black26, blurRadius: 8, offset: Offset(0, 2)),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            SizedBox(width: 12),
            Text('Memuat segmen...'),
          ],
        ),
      );

  Widget _buildMyLocationButton() => Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(12),
        color: Colors.white,
        child: InkWell(
          onTap: _goToMyLocation,
          borderRadius: BorderRadius.circular(12),
          child: const Padding(
            padding: EdgeInsets.all(12),
            child: Icon(Icons.my_location, size: 24, color: Colors.blue),
          ),
        ),
      );

  Widget _buildSegmentCountIndicator() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(
                color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.timeline, size: 16, color: Colors.blue),
            const SizedBox(width: 6),
            Text('${_polylines.length} segmen',
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      );

  Widget _buildLegend() => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [
            BoxShadow(
                color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
          ],
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _LegendRow(color: Colors.red, label: '> 30 cm'),
            SizedBox(height: 8),
            _LegendRow(color: Colors.orange, label: '21 - 30 cm'),
            SizedBox(height: 8),
            _LegendRow(color: Colors.yellow, label: '10 - 20 cm'),
            SizedBox(height: 8),
            _LegendRow(color: Colors.blue, label: '< 10 cm'),
            SizedBox(height: 8),
            _LegendRow(color: Colors.green, label: '0 cm'),
          ],
        ),
      );

  Widget _buildDefaultLocationBanner(UserLocationProvider provider) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.orange[100],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.orange[300]!, width: 1),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 18, color: Colors.orange[800]),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Menggunakan lokasi default',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
              ),
            ),
            TextButton(
              onPressed: provider.refreshGpsLocation,
              child: Text(
                'Refresh',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.orange[800]),
              ),
            ),
          ],
        ),
      );
}

class _LegendRow extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendRow({required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 20,
              height: 3,
              decoration: BoxDecoration(
                  color: color, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 6),
          Text(label,
              style:
                  const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
        ],
      );
}
