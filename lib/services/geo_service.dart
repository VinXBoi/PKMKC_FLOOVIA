import 'dart:async';
import 'dart:convert';
import 'package:floovia/config/config.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Production-ready GeoService with timeout, retry, and error handling
class GeoService {
  // ==================== CONSTANTS ====================
  static const Duration _defaultTimeout = Duration(seconds: 60);
  static const Duration _connectionTimeout = Duration(seconds: 60);
  static const int _maxRetries = 2;
  static const int _maxBatchSize = 100; // Prevent overwhelming API
  
  final String _baseUrl = AppConfig.baseUrl;
  final http.Client _client;
  
  // Cache to reduce redundant API calls
  final Map<String, String> _cache = {};
  static const Duration _cacheExpiration = Duration(minutes: 10);
  DateTime? _lastCacheReset;

  GeoService({http.Client? client}) : _client = client ?? http.Client();

  // ==================== PUBLIC API ====================

  /// Batch fetch nearest segments for multiple coordinates
  /// Returns Map<coordinate, "roadName::segmentId"> or empty string if not found
  Future<Map<String, String>> batchGetSegments(
    Set<String> coords, {
    Duration? timeout,
    bool useCache = true,
  }) async {
    if (coords.isEmpty) {
      debugPrint('✓ GeoService: No coordinates to process');
      return {};
    }

    // Clean expired cache
    _cleanCacheIfNeeded();

    // Split into cached and uncached
    final uncachedCoords = <String>{};
    final results = <String, String>{};

    if (useCache) {
      for (final coord in coords) {
        if (_cache.containsKey(coord)) {
          results[coord] = _cache[coord]!;
        } else {
          uncachedCoords.add(coord);
        }
      }
      
      if (uncachedCoords.isEmpty) {
        debugPrint('✓ GeoService: All ${coords.length} coords from cache');
        return results;
      }
      
      debugPrint('→ GeoService: ${uncachedCoords.length}/${coords.length} coords need fetching');
    } else {
      uncachedCoords.addAll(coords);
    }

    // Split into batches if needed
    final batches = _splitIntoBatches(uncachedCoords.toList(), _maxBatchSize);
    
    for (int i = 0; i < batches.length; i++) {
      debugPrint('→ GeoService: Processing batch ${i + 1}/${batches.length} (${batches[i].length} coords)');
      
      try {
        final batchResults =  await _fetchBatchWithRetry(
          batches[i].toSet(),
          timeout: timeout ?? _defaultTimeout,
        );
        
        results.addAll(batchResults);
        
        // Update cache
        if (useCache) {
          _cache.addAll(batchResults);
        }
      } catch (e) {
        debugPrint('✗ GeoService: Batch ${i + 1} failed: $e');
        // Add empty results for failed batch
        for (final coord in batches[i]) {
          results[coord] = '';
        }
      }
    }

    debugPrint('✓ GeoService: Completed ${results.length}/${coords.length} coords');
    return results;
  }

  /// Clear the internal cache
  void clearCache() {
    _cache.clear();
    _lastCacheReset = DateTime.now();
    debugPrint('✓ GeoService: Cache cleared');
  }

  /// Dispose resources
  void dispose() {
    _client.close();
    _cache.clear();
  }

  // ==================== PRIVATE METHODS ====================

  Future<Map<String, String>> _fetchBatchWithRetry(
    Set<String> coords, {
    required Duration timeout,
    int attempt = 1,
  }) async {
    try {
      return await _fetchBatch(coords).timeout(
        timeout,
        onTimeout: () {
          throw TimeoutException(
            'Request timed out after ${timeout.inSeconds}s',
            timeout,
          );
        },
      );
    } on TimeoutException catch (e) {
      if (attempt < _maxRetries) {
        debugPrint('⚠ GeoService: Timeout (attempt $attempt/$_maxRetries), retrying...');
        await Future.delayed(Duration(milliseconds: 500 * attempt)); // Exponential backoff
        return _fetchBatchWithRetry(coords, timeout: timeout, attempt: attempt + 1);
      }
      debugPrint('✗ GeoService: Max retries reached after timeout');
      throw GeoServiceException('Request timed out after $_maxRetries attempts: ${e.message}');
    } on http.ClientException catch (e) {
      if (attempt < _maxRetries) {
        debugPrint('⚠ GeoService: Network error (attempt $attempt/$_maxRetries), retrying...');
        await Future.delayed(Duration(milliseconds: 500 * attempt));
        return _fetchBatchWithRetry(coords, timeout: timeout, attempt: attempt + 1);
      }
      throw GeoServiceException('Network error after $_maxRetries attempts: ${e.message}');
    } catch (e) {
      // Don't retry on other errors (invalid data, parsing errors, etc.)
      rethrow;
    }
  }

  Future<Map<String, String>> _fetchBatch(Set<String> coords) async {
    // Validate coordinates before sending
    final validCoords = <String>[];
    final coordList = coords.toList();
    
    for (final coord in coordList) {
      if (_isValidCoordinate(coord)) {
        validCoords.add(coord);
      } else {
        debugPrint('⚠ GeoService: Invalid coordinate format: $coord');
      }
    }

    if (validCoords.isEmpty) {
      throw GeoServiceException('No valid coordinates to process');
    }

    final url = Uri.parse('$_baseUrl/nearest_segment');

    // Build request body
    final body = validCoords.map((coord) {
      final parts = coord.split(',');
      return {
        'lng': double.parse(parts[1].trim()),
        'lat': double.parse(parts[0].trim()),
      };
    }).toList();

    debugPrint('→ GeoService: POST ${url.toString()}');
    debugPrint('→ GeoService: Sending ${body.length} coordinates');

    final response = await _client.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode(body),
    ).timeout(
      _connectionTimeout,
      onTimeout: () => throw TimeoutException(
        'Connection timeout after ${_connectionTimeout.inSeconds}s',
        _connectionTimeout,
      ),
    );

    if (response.statusCode != 200) {
      debugPrint('✗ GeoService: HTTP ${response.statusCode}');
      debugPrint('  Response: ${response.body}');
      throw GeoServiceException(
        'API returned status ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }

    // Parse response
    final Map<String, dynamic> data;
    try {
      data = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      throw GeoServiceException('Invalid JSON response: $e');
    }

    if (data['code'] != 'Ok') {
      debugPrint('✗ GeoService: API error code: ${data['code']}');
      throw GeoServiceException(
        'API returned error: ${data['code']} - ${data['message'] ?? 'Unknown error'}',
      );
    }

    final List<dynamic>? resultList = data['segments'] as List<dynamic>?;
    if (resultList == null) {
      throw GeoServiceException('Missing segments in response');
    }

    if (resultList.length != validCoords.length) {
      debugPrint('⚠ GeoService: Result count mismatch (expected ${validCoords.length}, got ${resultList.length})');
    }

    // Build results map
    final results = <String, String>{};
    
    for (int i = 0; i < validCoords.length && i < resultList.length; i++) {
      final coord = validCoords[i];
      final result = resultList[i] as Map<String, dynamic>?;
      
      if (result == null) {
        results[coord] = '';
        continue;
      }

      final segmentId = result['segment_id'];
      if (segmentId != null && segmentId.toString().isNotEmpty) {
        final roadName = result['road_name']?.toString() ?? '';
        results[coord] = '$roadName::$segmentId';
      } else {
        results[coord] = '';
      }
    }

    // Add empty results for any original coords not in validCoords
    for (final coord in coordList) {
      if (!results.containsKey(coord)) {
        results[coord] = '';
      }
    }

    debugPrint('✓ GeoService: ${results.values.where((v) => v.isNotEmpty).length}/${results.length} segments found');
    return results;
  }

  List<List<String>> _splitIntoBatches(List<String> items, int batchSize) {
    final batches = <List<String>>[];
    for (int i = 0; i < items.length; i += batchSize) {
      final end = (i + batchSize < items.length) ? i + batchSize : items.length;
      batches.add(items.sublist(i, end));
    }
    return batches;
  }

  bool _isValidCoordinate(String coord) {
    try {
      final parts = coord.split(',');
      if (parts.length != 2) return false;
      
      final lat = double.parse(parts[0].trim());
      final lng = double.parse(parts[1].trim());
      
      return lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180;
    } catch (e) {
      return false;
    }
  }

  void _cleanCacheIfNeeded() {
    final now = DateTime.now();
    
    if (_lastCacheReset == null || 
        now.difference(_lastCacheReset!) > _cacheExpiration) {
      if (_cache.isNotEmpty) {
        debugPrint('→ GeoService: Cleaning expired cache (${_cache.length} entries)');
        _cache.clear();
      }
      _lastCacheReset = now;
    }
  }
}

// ==================== CUSTOM EXCEPTION ====================

class GeoServiceException implements Exception {
  final String message;
  final int? statusCode;

  const GeoServiceException(this.message, {this.statusCode});

  @override
  String toString() => 'GeoServiceException: $message${statusCode != null ? ' (HTTP $statusCode)' : ''}';
}