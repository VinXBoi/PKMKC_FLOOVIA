import 'dart:async';
import 'package:floovia/providers/road_status_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

final RoadStatusProvider roadStatusProvider = RoadStatusProvider.instance;

class MapDataProvider with ChangeNotifier {
  // ==================== CONSTANTS ====================
  static const Duration _cacheDuration = Duration(seconds: 15);
  static const double _boundsToleranceKm = 2.0;
  static const int _maxRetries = 3;
  static const int _largeDatasetThreshold = 50;
  static const Duration _baseTimeout = Duration(seconds: 25);

  static const double _maxQueryRadiusKm = 1.0;
  static const int _maxSegmentLimit = 200;
  // ==================== STATE ====================
  bool _isLoading = false;
  String? _error;
  Set<Polyline> _polylines = {};
  bool _isDisposed = false;

  // ==================== CACHING ====================
  LatLngBounds? _lastFetchedBounds;
  DateTime? _lastFetchTimestamp;
  LatLng? _lastCenterPoint;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ==================== GETTERS ====================
  bool get isLoading => _isLoading;
  String? get error => _error;
  Set<Polyline> get polylines => Set.unmodifiable(_polylines);
  bool get hasData => _polylines.isNotEmpty;
  bool get hasCachedData => _lastFetchedBounds != null && _polylines.isNotEmpty;
  bool get hasAlertSegments {
    return _polylines.any((polyline) => polyline.color != Colors.green);
  }

  // ==================== SAVE POLYLINES FROM MAP ====================
  void savePolylines(Set<Polyline> newPolylines, LatLng center) {
    if (_isDisposed) return;

    _polylines = newPolylines;
    _lastCenterPoint = center;
    _lastFetchTimestamp = DateTime.now();

    debugPrint('💾 Provider: Saved ${_polylines.length} polylines from map');
    _notifyListenersSafely();
  }

  // ==================== CHECK IF CACHE IS VALID ====================
  bool isCacheValidForLocation(LatLng center) {
    if (_lastCenterPoint == null ||
        _lastFetchTimestamp == null ||
        _polylines.isEmpty) {
      return false;
    }

    final now = DateTime.now();
    if (now.difference(_lastFetchTimestamp!) > _cacheDuration) {
      debugPrint('🕐 Cache expired');
      return false;
    }

    final distance = _calculateDistance(_lastCenterPoint!, center);
    final isValid = distance <= _boundsToleranceKm;

    if (isValid) {
      debugPrint('✅ Cache valid (distance: ${distance.toStringAsFixed(2)} km)');
    } else {
      debugPrint(
          '❌ Cache invalid (distance: ${distance.toStringAsFixed(2)} km > $_boundsToleranceKm km)');
    }

    return isValid;
  }

  // ==================== EXISTING METHODS ====================

  Future<Set<Polyline>> loadSegments(
    LatLngBounds bounds, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _isCacheValid(bounds)) {
      debugPrint('📦 Using cached segments (${_polylines.length} polylines)');
      return _polylines;
    }

    _setLoadingState();

    try {
      final center = _calculateCenter(bounds);
      final limitedBounds = _createLimitedBounds(center, _maxQueryRadiusKm);
      final queryBounds = _expandBounds(limitedBounds, 0.01);

      debugPrint(
          '→ Query center: ${center.latitude.toStringAsFixed(4)}, ${center.longitude.toStringAsFixed(4)}');
      debugPrint('→ Query radius: $_maxQueryRadiusKm km');

      final snapshot = await _fetchSegmentsWithRetry(queryBounds);

      if (snapshot.docs.isEmpty) {
        debugPrint('⚠ No segments found in radius');
        _polylines = {};
        _updateCache(bounds, center);
        _setSuccessState();
        return _polylines;
      }

      final filteredDocs =
          _filterByDistance(snapshot.docs, center, _maxQueryRadiusKm);
      if (filteredDocs.isEmpty) {
        debugPrint('⚠ No segments within radius after filter');
        _polylines = {};
        _updateCache(bounds, center);
        _setSuccessState();
        return _polylines;
      }

      final fetchedPolylines = await _parseSegmentsAsync(filteredDocs);

      _polylines = fetchedPolylines;
      _updateCache(bounds, center);
      _setSuccessState();

      debugPrint('✔ Loaded ${_polylines.length} segments for map');
      return _polylines;
    } catch (e) {
      _setErrorState('Gagal memuat data peta');
      debugPrint('✗ Error loading segments: $e');
      return _polylines;
    }
  }

  // ==================== CLEAR CACHE ====================
  void clearCache() {
    _lastFetchedBounds = null;
    _lastFetchTimestamp = null;
    _lastCenterPoint = null;
    debugPrint('🗑️ Cache cleared');
  }

  // ==================== REFRESH DATA ====================
  /// Refresh data by clearing cache and optionally reloading
  Future<void> refreshData() async {
    if (_isDisposed) return;

    debugPrint('🔄 Refreshing map data...');
    clearCache();
    _setSuccessState();
    debugPrint('✅ Map data refreshed');
  }

  // ==================== UTILITIES ====================

  /// Calculate center point of bounds
  LatLng _calculateCenter(LatLngBounds bounds) {
    return LatLng(
      (bounds.southwest.latitude + bounds.northeast.latitude) / 2,
      (bounds.southwest.longitude + bounds.northeast.longitude) / 2,
    );
  }

  LatLngBounds _createLimitedBounds(LatLng center, double radiusKm) {
    final latDelta = radiusKm / 111.0;
    final lngDelta =
        radiusKm / (111.0 * (center.latitude * 3.14159 / 180).abs());
    return LatLngBounds(
      southwest:
          LatLng(center.latitude - latDelta, center.longitude - lngDelta),
      northeast:
          LatLng(center.latitude + latDelta, center.longitude + lngDelta),
    );
  }

  LatLngBounds _expandBounds(LatLngBounds bounds, double expansion) {
    return bounds; // Simplified, add expansion logic if needed
  }

  bool _isCacheValid(LatLngBounds newBounds) {
    if (_lastFetchedBounds == null ||
        _lastFetchTimestamp == null ||
        _lastCenterPoint == null) {
      return false;
    }

    final now = DateTime.now();
    if (now.difference(_lastFetchTimestamp!) > _cacheDuration) return false;

    final newCenter = _calculateCenter(newBounds);
    final distance = _calculateDistance(_lastCenterPoint!, newCenter);
    return distance <= _boundsToleranceKm;
  }

  double _calculateDistance(LatLng p1, LatLng p2) {
    const double earthRadiusKm = 6371.0;
    final dLat = (p2.latitude - p1.latitude) * 3.14159 / 180;
    final dLng = (p2.longitude - p1.longitude) * 3.14159 / 180;
    final a = (dLat / 2) * (dLat / 2) +
        (dLng / 2) *
            (dLng / 2) *
            (p1.latitude * 3.14159 / 180).abs() *
            (p2.latitude * 3.14159 / 180).abs();
    final c = 2 * (a < 1 ? a : (1 - a));
    return earthRadiusKm * c;
  }

  void _updateCache(LatLngBounds bounds, LatLng center) {
    _lastFetchedBounds = bounds;
    _lastCenterPoint = center;
    _lastFetchTimestamp = DateTime.now();
  }

  // Stub methods - implement based on your needs
  Future<QuerySnapshot> _fetchSegmentsWithRetry(LatLngBounds bounds) async {
    return await _firestore
        .collection('segments')
        .where('lat_max', isGreaterThan: bounds.southwest.latitude)
        .where('lat_min', isLessThan: bounds.northeast.latitude)
        .limit(_maxSegmentLimit)
        .get();
  }

  List<QueryDocumentSnapshot> _filterByDistance(
    List<QueryDocumentSnapshot> docs,
    LatLng center,
    double maxRadiusKm,
  ) {
    return docs; // Implement filtering logic
  }

  Future<Set<Polyline>> _parseSegmentsAsync(
      List<QueryDocumentSnapshot> docs) async {
    
    // Gunakan compute (isolate) jika datanya besar
    if (docs.length > _largeDatasetThreshold) {
      debugPrint('🏭 Menggunakan isolate untuk parsing ${docs.length} segmen...');
      return await compute(_parsePolylinesIsolate, docs);
    }

    debugPrint('Parsing ${docs.length} segmen di main thread...');
    return _parsePolylines(docs);
  }

  void _setLoadingState() {
    if (_isDisposed) return;
    _isLoading = true;
    _error = null;
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _notifyListenersSafely());
  }

  void _setSuccessState() {
    if (_isDisposed) return;
    _isLoading = false;
    _error = null;
    _notifyListenersSafely();
  }

  void _setErrorState(String message) {
    if (_isDisposed) return;
    _isLoading = false;
    _error = message;
    _notifyListenersSafely();
  }

  void _notifyListenersSafely() {
    if (!_isDisposed) notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    debugPrint('✔ MapDataProvider disposed');
    super.dispose();
  }
}

Future<Set<Polyline>> _parsePolylines(List<QueryDocumentSnapshot> docs) async {
  final Set<Polyline> polylines = {};
  for (final doc in docs) {
    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) continue;

    final List<dynamic>? rawPoints = data['points'];
    if (rawPoints == null) continue;

    final List<LatLng> polyPoints = rawPoints
        .whereType<Map>()
        .where((p) => p.containsKey('lat') && p.containsKey('lng'))
        .map((p) => LatLng(
              (p['lat'] as num).toDouble(),
              (p['lng'] as num).toDouble(),
            ))
        .toList();

    if (polyPoints.isEmpty) continue;
    final sensorId = data['sensor_id'];
    // Logika pewarnaan
    Color color;

    if (sensorId == null || sensorId == 'unknown') {
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
}

// BARU: Tambahkan fungsi ini di TOP-LEVEL (di luar class) untuk compute
Future<Set<Polyline>> _parsePolylinesIsolate(List<QueryDocumentSnapshot> docs) async {
  // Catatan: Ini mungkin gagal jika QueryDocumentSnapshot tidak bisa
  // dilempar antar isolate. Jika gagal, ubah argumen menjadi List<Map<String, dynamic>>
  return _parsePolylines(docs);
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