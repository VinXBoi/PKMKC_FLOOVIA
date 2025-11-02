// lib/providers/routes_provider.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/route_model.dart';
import '../services/geo_service.dart';
import 'road_status_provider.dart';

class RouteRiskAnalysis {
  final String floodStatus;
  final String floodRisk;
  final double riskScore;
  final Map<String, int> segmentStatusCount;
  final Map<String, double> segmentStatusDistance; // Jarak dalam km
  final double totalDistance; // Total jarak rute dalam km

  RouteRiskAnalysis({
    required this.floodStatus,
    required this.floodRisk,
    required this.riskScore,
    required this.segmentStatusCount,
    required this.segmentStatusDistance,
    required this.totalDistance,
  });
}

/// Routes Provider
class RoutesProvider with ChangeNotifier {
  // State
  bool _isLoading = false;
  String? _error;
  List<RouteModel> _routes = [];

  // Cache
  String? _lastOriginDestKey;
  DateTime? _lastFetchTime;
  static const Duration _cacheDuration = Duration(minutes: 5);

  // Configuration
  static const String _apiUrl =
      'https://floovia-api-334714569491.asia-southeast2.run.app';
  static const Duration _maxProcessingTime = Duration(seconds: 60);

  // Getters
  bool get isLoading => _isLoading;
  String? get error => _error;
  List<RouteModel> get routes => List.unmodifiable(_routes);
  bool get hasRoutes => _routes.isNotEmpty;
  int get safeRoutesCount =>
      _routes.where((r) => r.floodStatus == 'Aman').length;

  /// Fetch routes between origin and destination
  Future<void> fetchRoutes({
    required LatLng origin,
    required LatLng destination,
    bool forceRefresh = false,
  }) async {
    final cacheKey = '${origin.latitude},${origin.longitude}-'
        '${destination.latitude},${destination.longitude}';

    // Check cache
    if (!forceRefresh && _isCacheValid(cacheKey)) {
      debugPrint('📦 Using cached routes');
      return;
    }

    _isLoading = true;
    _error = null;
    _routes = [];
    notifyListeners();

    try {
      debugPrint('🔄 Fetching routes from $origin to $destination');

      final routes = await _computeRoutesInMain(origin, destination);

      if (routes.isEmpty) {
        _error = 'Tidak ada rute ditemukan';
        debugPrint('⚠️ No routes found');
      } else {
        _routes = routes;
        _lastOriginDestKey = cacheKey;
        _lastFetchTime = DateTime.now();
        debugPrint('✅ Loaded ${routes.length} routes, $safeRoutesCount safe');
      }
    } on TimeoutException catch (e) {
      _error = 'Waktu pemrosesan melebihi 1 menit. Silakan coba lagi.';
      debugPrint('⏱️ Timeout fetching routes: $e');
    } on http.ClientException catch (e) {
      _error = 'Gagal terhubung ke server. Periksa koneksi internet Anda.';
      debugPrint('🌐 Network error: $e');
    } catch (e) {
      _error = 'Terjadi kesalahan saat mencari rute: ${e.toString()}';
      debugPrint('❌ Error fetching routes: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Compute routes in main isolate (has Firebase access)
  Future<List<RouteModel>> _computeRoutesInMain(
    LatLng origin,
    LatLng destination,
  ) async {
    try {
      final geoService = GeoService();
      final statusCache = RoadStatusProvider.instance;

      // Build URL
      final url = Uri.parse(
        "$_apiUrl/routes"
        "?origin_lat=${origin.latitude}&origin_lng=${origin.longitude}"
        "&dest_lat=${destination.latitude}&dest_lng=${destination.longitude}",
      );

      // Fetch routes from API with timeout
      final response = await http.get(url).timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        debugPrint('❌ API returned status: ${response.statusCode}');
        throw Exception('Server error: ${response.statusCode}');
      }

      final data = jsonDecode(response.body);

      if (data['code'] != 'Ok') {
        debugPrint('❌ API returned error code: ${data['code']}');
        throw Exception('API error: ${data['code']}');
      }

      final apiRoutes = data['routes'] as List;
      if (apiRoutes.isEmpty) {
        return [];
      }

      final List<RouteModel> routeModels = [];

      // Process each route
      for (int i = 0; i < apiRoutes.length && i < 5; i++) {
        try {
          final routeData = apiRoutes[i];
          final leg = routeData['legs'][0];
          final steps = leg['steps'] as List;

          // Extract geographic data
          final startLocation = LatLng(
              leg['start_location']['lat'], leg['start_location']['lng']);
          final destinationLocation =
              LatLng(leg['end_location']['lat'], leg['end_location']['lng']);
          final waypoints = <LatLng>[];

          // Extract waypoints
          if (steps.length > 2) {
            const int maxWaypoints = 8;
            int stepCount = steps.length - 1;
            int interval = (stepCount / (maxWaypoints + 1)).ceil();
            for (int j = interval; j < stepCount; j += interval) {
              if (waypoints.length >= maxWaypoints) break;
              waypoints.add(LatLng(
                steps[j]['start_location']['lat'],
                steps[j]['start_location']['lng'],
              ));
            }
          }

          // Extract coordinates from steps
          final coords = <String>{};
          for (final step in steps) {
            final lat = step['start_location']['lat'];
            final lng = step['start_location']['lng'];
            coords.add("$lat,$lng");
          }

          // Batch get segments
          final coordToSegment = await geoService.batchGetSegments(coords);

          // Get unique segment IDs
          final allSegmentIds = coordToSegment.values
              .map((s) => s.split("::").elementAtOrNull(1))
              .where((id) => id != null && id != "Unknown")
              .cast<String>()
              .toSet()
              .toList();

          // Fetch segment data in batch
          final segmentDataMap = await _fetchSegmentsBatchInMain(allSegmentIds);

          // Build route segments WITH DISTANCE
          final seen = <String>{};
          final segments = <RouteSegment>[];

          for (final step in steps) {
            final key =
                "${step['start_location']['lat']},${step['start_location']['lng']}";
            final segString = coordToSegment[key] ?? "";

            if (segString.isEmpty) continue;

            final parts = segString.split("::");
            final name = (parts.isNotEmpty && parts[0].isNotEmpty)
                ? parts[0]
                : "Jalan Tidak Dikenal";

            final segmentId = parts.length > 1 ? parts[1] : "Unknown";
            if (segmentId == "Unknown" || seen.contains(segmentId)) continue;

            seen.add(segmentId);

            final docData = segmentDataMap[segmentId];
            final sensorId = docData?['sensor_id'] ?? "unknown";

            // Get flood status
            final currHeight = await statusCache.getStatus(sensorId);
            final statusText = _determineFloodStatus(currHeight);

            // ✅ PENTING: Ekstrak jarak dari step
            final distanceText = step['distance']['text'] as String;
            final distanceValue = step['distance']['value'] as int; // dalam meter

            segments.add(RouteSegment(
              name: name,
              status: statusText,
              id: segmentId,
              range: distanceText,
              distanceMeters: distanceValue, // Simpan jarak dalam meter
            ));
          }

          // ✅ Analyze route risk BERDASARKAN JARAK
          final riskAnalysis = _analyzeRouteRiskByDistance(segments, leg);

          routeModels.add(
            RouteModel(
              id: i + 1,
              name: 'Rute ${String.fromCharCode(65 + i)}',
              distance: leg['distance']['text'],
              duration: leg['duration']['text'],
              floodStatus: riskAnalysis.floodStatus,
              floodRisk: riskAnalysis.floodRisk,
              description: _generateRouteDescription(i + 1, riskAnalysis),
              segments: segments,
              polyline: apiRoutes[i]['overview_polyline']?['points'] ?? '',
              startLocation: startLocation,
              destinationLocation: destinationLocation,
              waypoints: waypoints,
            ),
          );
        } catch (e) {
          debugPrint('⚠️ Error processing route $i: $e');
          continue;
        }
      }

      return routeModels;
    } catch (e) {
      debugPrint('❌ Error in _computeRoutesInMain: $e');
      rethrow;
    }
  }

  /// ✅ ANALISIS RISIKO BERDASARKAN JARAK (bukan jumlah segmen)
  RouteRiskAnalysis _analyzeRouteRiskByDistance(
    List<RouteSegment> segments,
    Map<String, dynamic> leg,
  ) {
    if (segments.isEmpty) {
      return RouteRiskAnalysis(
        floodStatus: 'Aman',
        floodRisk: 'Rendah',
        riskScore: 0.0,
        segmentStatusCount: {'Aman': 0, 'Ringan': 0, 'Banjir': 0},
        segmentStatusDistance: {'Aman': 0.0, 'Ringan': 0.0, 'Banjir': 0.0},
        totalDistance: 0.0,
      );
    }

    // Total jarak rute dalam meter
    final totalDistanceMeters = (leg['distance']['value'] as int).toDouble();
    final totalDistanceKm = totalDistanceMeters / 1000;

    // Hitung jarak per status
    final statusCount = <String, int>{
      'Aman': 0,
      'Ringan': 0,
      'Banjir': 0,
    };

    final statusDistance = <String, double>{
      'Aman': 0.0,
      'Ringan': 0.0,
      'Banjir': 0.0,
    };

    for (final segment in segments) {
      statusCount[segment.status] = (statusCount[segment.status] ?? 0) + 1;
      
      // Tambahkan jarak (konversi ke km)
      final distanceKm = (segment.distanceMeters ?? 0) / 1000;
      statusDistance[segment.status] = 
          (statusDistance[segment.status] ?? 0.0) + distanceKm;
    }

    final floodDistanceKm = statusDistance['Banjir'] ?? 0.0;
    final ringanDistanceKm = statusDistance['Ringan'] ?? 0.0;
    final amanDistanceKm = statusDistance['Aman'] ?? 0.0;

    // Hitung persentase berdasarkan JARAK
    final floodPercentage = (floodDistanceKm / totalDistanceKm) * 100;
    final ringanPercentage = (ringanDistanceKm / totalDistanceKm) * 100;
    final affectedPercentage = floodPercentage + ringanPercentage;

    // ✅ Risk Score berbasis JARAK (0-100)
    // Banjir = 100 poin per km, Ringan = 50 poin per km
    final riskScore = ((floodDistanceKm * 100) + (ringanDistanceKm * 50)) / totalDistanceKm;

    debugPrint('📊 Risk Analysis:');
    debugPrint('   Total: ${totalDistanceKm.toStringAsFixed(2)} km');
    debugPrint('   Banjir: ${floodDistanceKm.toStringAsFixed(2)} km (${floodPercentage.toStringAsFixed(1)}%)');
    debugPrint('   Ringan: ${ringanDistanceKm.toStringAsFixed(2)} km (${ringanPercentage.toStringAsFixed(1)}%)');
    debugPrint('   Aman: ${amanDistanceKm.toStringAsFixed(2)} km');
    debugPrint('   Risk Score: ${riskScore.toStringAsFixed(1)}');

    // Determine flood status berdasarkan JARAK
    String floodStatus;
    if (floodDistanceKm > 0) {
      if (floodPercentage >= 50) {
        floodStatus = 'Banjir Parah'; // >50% jarak tergenang banjir
      } else if (floodPercentage >= 20) {
        floodStatus = 'Banjir'; // 20-50% jarak tergenang
      } else {
        floodStatus = 'Banjir Sebagian'; // <20% jarak tergenang
      }
    } else if (ringanDistanceKm > 0) {
      if (ringanPercentage >= 30) {
        floodStatus = 'Ringan Tersebar'; // >30% jarak genangan ringan
      } else {
        floodStatus = 'Ringan'; // <30% genangan ringan
      }
    } else {
      floodStatus = 'Aman';
    }

    // Determine risk level
    String floodRisk;
    if (riskScore >= 80) {
      floodRisk = 'Sangat Tinggi'; // >80% jarak berbahaya
    } else if (riskScore >= 60) {
      floodRisk = 'Tinggi'; // 60-80%
    } else if (riskScore >= 40) {
      floodRisk = 'Sedang'; // 40-60%
    } else if (riskScore >= 20) {
      floodRisk = 'Rendah'; // 20-40%
    } else {
      floodRisk = 'Sangat Rendah'; // <20%
    }

    // ✅ Pertimbangan tambahan berbasis JARAK
    if (floodDistanceKm > 0) {
      // Cek jika ada segmen panjang yang tergenang (>2km banjir berturut-turut)
      final hasLongFloodedSegment = _hasLongFloodedDistance(segments, 2.0);
      if (hasLongFloodedSegment) {
        if (floodRisk == 'Sedang') floodRisk = 'Tinggi';
        if (floodRisk == 'Rendah') floodRisk = 'Sedang';
      }

      // Cek jika banjir di awal perjalanan (dalam 1km pertama)
      final hasEarlyFlooding = _hasEarlyFlooding(segments, 1.0);
      if (hasEarlyFlooding) {
        if (floodRisk == 'Rendah') floodRisk = 'Sedang';
      }

      // Upgrade risk jika total jarak banjir >5km (walaupun persentasenya kecil)
      if (floodDistanceKm >= 5.0 && floodRisk == 'Rendah') {
        floodRisk = 'Sedang';
      }
    }

    return RouteRiskAnalysis(
      floodStatus: floodStatus,
      floodRisk: floodRisk,
      riskScore: riskScore,
      segmentStatusCount: statusCount,
      segmentStatusDistance: statusDistance,
      totalDistance: totalDistanceKm,
    );
  }

  /// Cek apakah ada segmen banjir panjang berturut-turut (dalam km)
  bool _hasLongFloodedDistance(List<RouteSegment> segments, double minKm) {
    double consecutiveDistance = 0.0;
    
    for (final segment in segments) {
      if (segment.status == 'Banjir') {
        consecutiveDistance += (segment.distanceMeters ?? 0) / 1000;
        if (consecutiveDistance >= minKm) return true;
      } else {
        consecutiveDistance = 0.0;
      }
    }
    
    return false;
  }

  /// Cek apakah ada banjir di awal perjalanan
  bool _hasEarlyFlooding(List<RouteSegment> segments, double withinKm) {
    double cumulativeDistance = 0.0;
    
    for (final segment in segments) {
      cumulativeDistance += (segment.distanceMeters ?? 0) / 1000;
      
      if (segment.status == 'Banjir') {
        return true; // Ada banjir dalam jarak withinKm pertama
      }
      
      if (cumulativeDistance >= withinKm) {
        break; // Sudah melewati batas pengecekan
      }
    }
    
    return false;
  }

  /// Generate descriptive text berdasarkan JARAK
  String _generateRouteDescription(int routeNumber, RouteRiskAnalysis analysis) {
    final floodKm = analysis.segmentStatusDistance['Banjir'] ?? 0.0;
    final ringanKm = analysis.segmentStatusDistance['Ringan'] ?? 0.0;
    final totalKm = analysis.totalDistance;
    
    if (floodKm == 0 && ringanKm == 0) {
      return 'Rute aman tanpa genangan air';
    } else if (floodKm > 0) {
      final percentage = ((floodKm / totalKm) * 100).toStringAsFixed(0);
      return 'Rute dengan ${floodKm.toStringAsFixed(1)} km tergenang banjir ($percentage% dari total ${totalKm.toStringAsFixed(1)} km)';
    } else {
      final percentage = ((ringanKm / totalKm) * 100).toStringAsFixed(0);
      return 'Rute dengan ${ringanKm.toStringAsFixed(1)} km genangan ringan ($percentage% dari total ${totalKm.toStringAsFixed(1)} km)';
    }
  }

  /// Get detailed risk information berbasis JARAK
  String getDetailedRiskInfo(RouteModel route) {
    // Hitung jarak per status
    final statusDistance = <String, double>{
      'Aman': 0.0,
      'Ringan': 0.0,
      'Banjir': 0.0,
    };

    double totalKm = 0.0;

    for (final segment in route.segments) {
      final distanceKm = (segment.distanceMeters ?? 0) / 1000;
      statusDistance[segment.status] = 
          (statusDistance[segment.status] ?? 0.0) + distanceKm;
      totalKm += distanceKm;
    }

    final floodKm = statusDistance['Banjir'] ?? 0.0;
    final ringanKm = statusDistance['Ringan'] ?? 0.0;
    final amanKm = statusDistance['Aman'] ?? 0.0;

    final floodCount = route.segments.where((s) => s.status == 'Banjir').length;
    final ringanCount = route.segments.where((s) => s.status == 'Ringan').length;
    final amanCount = route.segments.where((s) => s.status == 'Aman').length;
    
    return '''
Status Rute: ${route.floodStatus}
Tingkat Risiko: ${route.floodRisk}
Total Jarak: ${totalKm.toStringAsFixed(2)} km

Berdasarkan Jarak:
- Banjir: ${floodKm.toStringAsFixed(2)} km (${((floodKm/totalKm)*100).toStringAsFixed(1)}%)
- Ringan: ${ringanKm.toStringAsFixed(2)} km (${((ringanKm/totalKm)*100).toStringAsFixed(1)}%)
- Aman: ${amanKm.toStringAsFixed(2)} km (${((amanKm/totalKm)*100).toStringAsFixed(1)}%)

Berdasarkan Segmen:
- Banjir: $floodCount segmen
- Ringan: $ringanCount segmen
- Aman: $amanCount segmen
''';
  }

  /// Helper function for batching Firestore queries
  Future<Map<String, Map<String, dynamic>>> _fetchSegmentsBatchInMain(
    List<String> segmentIds,
  ) async {
    if (segmentIds.isEmpty) return {};

    final result = <String, Map<String, dynamic>>{};
    const chunkSize = 10;

    for (var i = 0; i < segmentIds.length; i += chunkSize) {
      final chunk = segmentIds.sublist(
        i,
        (i + chunkSize > segmentIds.length) ? segmentIds.length : i + chunkSize,
      );

      try {
        final query = await FirebaseFirestore.instance
            .collection('segments')
            .where(FieldPath.documentId, whereIn: chunk)
            .get()
            .timeout(const Duration(seconds: 10));

        for (var doc in query.docs) {
          result[doc.id] = doc.data();
        }
      } catch (e) {
        debugPrint('⚠️ Error fetching segment batch: $e');
        continue;
      }
    }

    return result;
  }

  /// Clear routes and cache
  void clearRoutes() {
    _routes = [];
    _error = null;
    _lastOriginDestKey = null;
    _lastFetchTime = null;
    notifyListeners();
  }

  /// Check if cache is valid
  bool _isCacheValid(String cacheKey) {
    if (_lastOriginDestKey != cacheKey || _lastFetchTime == null) {
      return false;
    }

    final now = DateTime.now();
    return now.difference(_lastFetchTime!) < _cacheDuration;
  }

  bool _isDisposed = false;

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}

/// Determine flood status based on water height
String _determineFloodStatus(double height) {
  if (height > 20) return 'Banjir';
  if (height > 10) return 'Ringan';
  return 'Aman';
}