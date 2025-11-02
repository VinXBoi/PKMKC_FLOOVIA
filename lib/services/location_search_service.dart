// lib/services/location_search_service.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../providers/user_location_provider.dart';
import '../providers/flood_data_provider.dart';
import '../providers/map_data_provider.dart';

/// Service class that orchestrates suggestion tap handling
/// Separates business logic from UI layer
class LocationSearchService {
  // Prevent concurrent updates
  bool _isProcessing = false;
  Completer<void>? _currentOperation;

  /// Handle suggestion tap with proper coordination
  Future<SearchResult> handleSuggestionTap({
    required BuildContext context,
    required String placeId,
    required String address,
    required UserLocationProvider locationProvider,
    required FloodDataProvider floodProvider,
    required MapDataProvider mapProvider,
  }) async {
    // Prevent duplicate concurrent calls
    if (_isProcessing) {
      debugPrint('⚠️ Operation already in progress, ignoring tap');
      return SearchResult.alreadyProcessing();
    }

    // Guard against rapid taps
    if (_currentOperation != null && !_currentOperation!.isCompleted) {
      debugPrint('⚠️ Waiting for previous operation to complete');
      await _currentOperation!.future;
    }

    _isProcessing = true;
    _currentOperation = Completer<void>();

    try {
      // Step 1: Update location provider
      await _updateLocation(
        locationProvider: locationProvider,
        placeId: placeId,
        address: address,
      );

      final newLocation = locationProvider.activeLocation;

      // Step 2: Fetch flood details in parallel with map data
      await Future.wait([
        _updateFloodData(
          floodProvider: floodProvider,
          location: newLocation,
        ),
        _updateMapData(
          mapProvider: mapProvider,
          location: newLocation,
        ),
      ]);

      debugPrint('✅ All providers updated successfully');
      return SearchResult.success(address);

    } on TimeoutException catch (e) {
      debugPrint('⏱️ Timeout during update: $e');
      return SearchResult.timeout();
      
    } on LocationUpdateException catch (e) {
      debugPrint('❌ Location update failed: $e');
      return SearchResult.error('Gagal memperbarui lokasi: ${e.message}');
      
    } catch (e, stackTrace) {
      debugPrint('❌ Unexpected error: $e');
      debugPrint('Stack trace: $stackTrace');
      return SearchResult.error('Terjadi kesalahan: ${e.toString()}');
      
    } finally {
      _isProcessing = false;
      _currentOperation?.complete();
      _currentOperation = null;
    }
  }

  /// Update location provider with timeout
  Future<void> _updateLocation({
    required UserLocationProvider locationProvider,
    required String placeId,
    required String address,
  }) async {
    await locationProvider
        .setActiveLocationFromSearch(placeId, address)
        .timeout(
          const Duration(seconds: 10),
          onTimeout: () => throw TimeoutException('Location update timeout'),
        );
  }

  /// Update flood data with retry logic
  Future<void> _updateFloodData({
    required FloodDataProvider floodProvider,
    required LatLng location,
  }) async {
    const maxRetries = 2;
    
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        await floodProvider.fetchFloodDetails(
          location,
          forceRefresh: true,
        ).timeout(const Duration(seconds: 30));
        
        debugPrint('✅ Flood data updated (attempt $attempt)');
        return;
        
      } on TimeoutException {
        if (attempt == maxRetries) {
          debugPrint('⚠️ Flood data timeout after $maxRetries attempts');
          throw TimeoutException('Flood data fetch timeout');
        }
        debugPrint('⚠️ Flood data timeout, retrying...');
        await Future.delayed(Duration(seconds: attempt));
      }
    }
  }

  /// Update map data with bounds calculation
  Future<void> _updateMapData({
    required MapDataProvider mapProvider,
    required LatLng location,
  }) async {
    // Clear cache to force fresh data
    mapProvider.clearCache();

    // Calculate bounds around location
    final bounds = _calculateBounds(location, radiusKm: 1.0);

    await mapProvider
        .loadSegments(bounds, forceRefresh: true)
        .timeout(const Duration(seconds: 30));

    debugPrint('✅ Map data updated');
  }

  /// Calculate bounds for map data loading
  LatLngBounds _calculateBounds(LatLng center, {required double radiusKm}) {
    final latDelta = radiusKm / 111.0;
    final lngDelta = radiusKm / (111.0 * (center.latitude * 3.14159 / 180).abs());

    return LatLngBounds(
      southwest: LatLng(
        center.latitude - latDelta,
        center.longitude - lngDelta,
      ),
      northeast: LatLng(
        center.latitude + latDelta,
        center.longitude + lngDelta,
      ),
    );
  }

  /// Handle GPS button tap
  Future<SearchResult> handleGpsButtonTap({
    required BuildContext context,
    required UserLocationProvider locationProvider,
    required FloodDataProvider floodProvider,
    required MapDataProvider mapProvider,
  }) async {
    if (_isProcessing) {
      return SearchResult.alreadyProcessing();
    }

    _isProcessing = true;
    _currentOperation = Completer<void>();

    try {
      // Refresh GPS location
      await locationProvider.refreshGpsLocation().timeout(
        const Duration(seconds: 15),
      );

      final gpsLocation = locationProvider.activeLocation;

      // Update flood and map data
      await Future.wait([
        _updateFloodData(
          floodProvider: floodProvider,
          location: gpsLocation,
        ),
        _updateMapData(
          mapProvider: mapProvider,
          location: gpsLocation,
        ),
      ]);

      return SearchResult.success('Lokasi GPS');

    } on TimeoutException {
      return SearchResult.timeout();
    } catch (e) {
      return SearchResult.error('Gagal memuat lokasi GPS: ${e.toString()}');
    } finally {
      _isProcessing = false;
      _currentOperation?.complete();
      _currentOperation = null;
    }
  }

  /// Check if currently processing
  bool get isProcessing => _isProcessing;

  /// Dispose resources
  void dispose() {
    _currentOperation?.complete();
  }
}

/// Result class for search operations
class SearchResult {
  final SearchStatus status;
  final String? message;

  const SearchResult._({
    required this.status,
    this.message,
  });

  factory SearchResult.success(String locationName) => SearchResult._(
    status: SearchStatus.success,
    message: '✅ Data berhasil dimuat untuk $locationName',
  );

  factory SearchResult.error(String errorMessage) => SearchResult._(
    status: SearchStatus.error,
    message: errorMessage,
  );

  factory SearchResult.timeout() => SearchResult._(
    status: SearchStatus.timeout,
    message: '⏱️ Waktu habis, silakan coba lagi',
  );

  factory SearchResult.alreadyProcessing() => SearchResult._(
    status: SearchStatus.processing,
    message: '⚠️ Sedang memproses permintaan sebelumnya',
  );

  bool get isSuccess => status == SearchStatus.success;
  bool get isError => status == SearchStatus.error;
}

enum SearchStatus {
  success,
  error,
  timeout,
  processing,
}

/// Custom exception for location updates
class LocationUpdateException implements Exception {
  final String message;
  const LocationUpdateException(this.message);

  @override
  String toString() => message;
}