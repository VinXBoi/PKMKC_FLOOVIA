// lib/widgets/flood_map_card.dart

import 'dart:async';
import 'package:floovia/providers/road_status_provider.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../providers/user_location_provider.dart';
import '../providers/map_data_provider.dart';

class FloodMapCard extends StatefulWidget {
  final VoidCallback onTap;

  const FloodMapCard({
    super.key,
    required this.onTap,
  });

  @override
  State<FloodMapCard> createState() => _FloodMapCardState();
}

class _FloodMapCardState extends State<FloodMapCard> {
  final Completer<GoogleMapController> _mapController = Completer();
  Set<Polyline> _polylines = {};
  bool _isLoading = true;
  bool _hasError = false;
  bool _hasLoadedInitial = false;
  LatLng? _lastKnownLocation;
  final RoadStatusProvider roadStatusProvider = RoadStatusProvider.instance;

  @override
  void initState() {
    super.initState();
    // Start with not loading - will check cache after frame is built
    _isLoading = false;
    // Check if we have cached data in provider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkProviderCache();
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
    super.dispose();
  }

  /// Check if provider has cached polylines we can use
  void _checkProviderCache() {
    if (!mounted) return;

    final mapProvider = context.read<MapDataProvider>();
    final locationProvider = context.read<UserLocationProvider>();
    final currentLocation = locationProvider.activeLocation;

    if (mapProvider.hasCachedData &&
        mapProvider.isCacheValidForLocation(currentLocation)) {
      debugPrint(
          '🎯 FloodMapCard: Using cached polylines from provider (${mapProvider.polylines.length})');
      setState(() {
        _polylines = mapProvider.polylines;
        _isLoading = false;
        _hasError = false;
        _hasLoadedInitial = true;
      });
    } else {
      debugPrint('📍 FloodMapCard: No valid cache available');
      // Don't show loading yet - wait for map to be created
      setState(() {
        _isLoading = false; // Changed from true to false
        _hasLoadedInitial = false;
      });
    }
  }

  Future<void> _moveCameraToLocation(LatLng location) async {
    if (!_mapController.isCompleted) return;
    
    try {
      final controller = await _mapController.future;
      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(location, 17),
      );
      await _loadSegmentsForView();
      debugPrint('📍 Camera moved to: ${location.latitude.toStringAsFixed(4)}, ${location.longitude.toStringAsFixed(4)}');
    } catch (e) {
      debugPrint('❌ Error moving camera: $e');
    }
  }

  /// Load segments based on visible map bounds
  Future<void> _loadSegmentsForView() async {
    if (!_mapController.isCompleted || !mounted) return;

    // Check provider cache first
    final mapProvider = context.read<MapDataProvider>();
    final locationProvider = context.read<UserLocationProvider>();
    final currentLocation = locationProvider.activeLocation;

    if (mapProvider.hasCachedData &&
        mapProvider.isCacheValidForLocation(currentLocation)) {
      debugPrint('🎯 Preview: Using cached polylines from provider');
      setState(() {
        _polylines = mapProvider.polylines;
        _isLoading = false;
        _hasLoadedInitial = true;
      });
      return;
    }

    // Only show loading on first load
    if (!_hasLoadedInitial) {
      setState(() {
        _isLoading = true;
        _hasError = false;
      });
    }

    try {
      final controller = await _mapController.future;
      final bounds = await controller.getVisibleRegion();

      debugPrint('🗺️ Loading preview segments for bounds:');
      debugPrint(
          '   SW: ${bounds.southwest.latitude.toStringAsFixed(5)}, ${bounds.southwest.longitude.toStringAsFixed(5)}');
      debugPrint(
          '   NE: ${bounds.northeast.latitude.toStringAsFixed(5)}, ${bounds.northeast.longitude.toStringAsFixed(5)}');

      final polylines = await _fetchSegmentsFromFirestore(bounds);

      if (mounted) {
        setState(() {
          _polylines = polylines;
          _isLoading = false;
          _hasError = false;
          _hasLoadedInitial = true;
        });
        debugPrint('✅ Preview loaded: ${polylines.length} segments');
      }
    } catch (e) {
      debugPrint('❌ Error loading preview: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
          _isLoading = false;
          _hasLoadedInitial = true;
        });
      }
    }
  }

  /// Fetch segments from Firestore with proper filtering
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
          .get()
          .timeout(
            const Duration(seconds: 120),
            onTimeout: () => throw TimeoutException('Query timeout'),
          );

      debugPrint('🔥 Received ${snapshot.docs.length} documents for preview');

      if (snapshot.docs.isEmpty) {
        return {};
      }

      final Set<Polyline> polylines = {};
      int skippedCount = 0;

      for (final doc in snapshot.docs) {
        try {
          final data = doc.data();

          if (data['points'] == null) continue;

          // CRITICAL: Filter by longitude (Firestore limitation)
          final lngMin = data['lng_min'] as num?;
          final lngMax = data['lng_max'] as num?;

          if (lngMin == null || lngMax == null) {
            skippedCount++;
            continue;
          }

          // Check longitude overlap
          if (lngMax < swLng || lngMin > neLng) {
            skippedCount++;
            continue;
          }

          // Parse points
          final List<dynamic> rawPoints = data['points'] as List;
          final List<LatLng> polyPoints = [];

          for (var p in rawPoints) {
            if (p is Map && p.containsKey('lat') && p.containsKey('lng')) {
              polyPoints.add(LatLng(
                (p['lat'] as num).toDouble(),
                (p['lng'] as num).toDouble(),
              ));
            }
          }

          if (polyPoints.isEmpty) continue;

          // Determine color based on sensor status
          final sensorId = data['sensor_id'];
          
          Color lineColor;
          debugPrint('Sensor ID : $sensorId');
          if (sensorId == 'null' || sensorId == 'unknown') {
            lineColor = Colors.green;
          } else {
            final dataHeight = await roadStatusProvider.getStatus(sensorId);
            debugPrint('SensorId : $sensorId , Height : $dataHeight');
            lineColor = _polylineColor(dataHeight);
          }

          polylines.add(
            Polyline(
              polylineId: PolylineId(data['segment_id'] ?? doc.id),
              points: polyPoints,
              color: lineColor,
              width: 6,
              startCap: Cap.roundCap,
              endCap: Cap.roundCap,
            ),
          );
        } catch (e) {
          debugPrint('⚠️ Error parsing segment: $e');
        }
      }

      if (skippedCount > 0) {
        debugPrint('📊 Skipped $skippedCount segments (out of bounds)');
      }

      return polylines;
    } on FirebaseException catch (e) {
      debugPrint('❌ Firebase error: ${e.code} - ${e.message}');
      throw Exception('Gagal memuat data peta');
    } on TimeoutException {
      debugPrint('❌ Timeout loading segments');
      throw Exception('Koneksi timeout');
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

  @override
  Widget build(BuildContext context) {
    return Selector<UserLocationProvider, LatLng>(
      selector: (_, provider) => provider.activeLocation,
      builder: (context, location, _) {
        return GestureDetector(
          onTap: widget.onTap,
          child: Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                _buildMapPreview(location),
                _buildFooter(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.map, color: Colors.blue[700], size: 20),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Peta Banjir',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Lihat status banjir real-time',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey[400]),
        ],
      ),
    );
  }

  Widget _buildMapPreview(LatLng center) {
    return SizedBox(
      height: 200,
      child: Stack(
        children: [
          // Map (non-interactive preview)
          if (_hasError)
            _buildError()
          else
            GoogleMap(
              initialCameraPosition: CameraPosition(
                target: center,
                zoom: 17.0,
              ),
              polylines: _polylines,

              onMapCreated: (controller) {
                if (!_mapController.isCompleted) {
                  _mapController.complete(controller);
                  debugPrint('🗺️ FloodMapCard: Preview map created');

                  // Load segments after map is ready (with a small delay)
                  Future.delayed(const Duration(milliseconds: 500), () {
                    if (mounted) {
                      _loadSegmentsForView();
                    }
                  });
                }
              },

              // Non-interactive (static preview)
              zoomControlsEnabled: false,
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
              scrollGesturesEnabled: false,
              zoomGesturesEnabled: false,
              tiltGesturesEnabled: false,
              rotateGesturesEnabled: false,

              compassEnabled: false,
              mapToolbarEnabled: false,
              buildingsEnabled: false,
              liteModeEnabled: true,
            ),

          // Loading overlay (shown while fetching)
          if (_isLoading)
            Positioned(
              top: 8,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.blue[700]!,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Memuat...',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Cache indicator badge
          if (_polylines.isNotEmpty && !_isLoading)
            Positioned(
              top: 8,
              left: 8,
              child: Consumer<MapDataProvider>(
                builder: (context, mapProvider, _) {
                  final userLocation =
                      context.read<UserLocationProvider>().activeLocation;
                  final isFromCache = mapProvider.hasCachedData &&
                      mapProvider.isCacheValidForLocation(userLocation);

                  if (!isFromCache) return const SizedBox.shrink();

                  return Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green[700],
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 4,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.check_circle, color: Colors.white, size: 12),
                        SizedBox(width: 4),
                        Text(
                          'Cached',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

          // Tap overlay with gradient
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.onTap,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withOpacity(0.1),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Tap indicator
          Positioned(
            right: 12,
            bottom: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.touch_app, color: Colors.white, size: 14),
                  SizedBox(width: 6),
                  Text(
                    'Ketuk untuk buka',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoading() {
    return Container(
      color: Colors.grey[200],
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.blue[700]!),
            ),
            const SizedBox(height: 12),
            Text(
              'Memuat peta...',
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Container(
      color: Colors.grey[100],
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: Colors.grey[400], size: 48),
            const SizedBox(height: 12),
            Text(
              'Gagal memuat peta',
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _loadSegmentsForView,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Coba Lagi'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.blue[700],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        border: Border(top: BorderSide(color: Colors.grey[200]!)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                const Text('Banjir',
                    style: TextStyle(fontSize: 11, color: Colors.grey)),
                const SizedBox(width: 16),
                Container(
                  width: 12,
                  height: 12,
                  decoration: const BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                const Text('Aman',
                    style: TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ),
          if (_polylines.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_polylines.length} segmen',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.blue[700],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
