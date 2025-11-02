import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:floovia/models/batch_status_result.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../services/batch_status_service.dart';

class RoadStatusProvider {
  RoadStatusProvider._(); 
  static final RoadStatusProvider instance = RoadStatusProvider._();

  BatchStatusService? _batchStatusService;
  BatchStatusService get _service {
    _batchStatusService ??= BatchStatusService();
    return _batchStatusService!;
  }

  // --- Caching mechanism for the getStatus method ---
  final Map<String, _CacheItem> _cache = {};
  final Duration ttl = const Duration(minutes: 1);

  /// Fetches batch status data by delegating to the BatchStatusService.
  Future<Map<String, dynamic>> getBatchStatus(
      String sensorId, String kecamatanId) async {
    try {
      // Use lazy getter instead of field
      final BatchStatusResult result =
          await _service.getBatchStatus(sensorId, kecamatanId);
      debugPrint('Result : ${result.isDemo}');
      return result.toMap();
    } catch (e) {
      debugPrint('Error in RoadStatusProvider.getBatchStatus: $e');
      
      return BatchStatusResult(
        maxValue: 110.0,
        batchData: [110.0, 100.0, 90.0, 80.0, 70.0, 60.0, 50.0, 40.0, 30.0, 20.0, 10.0, 5.0],
        batchDataXY: [
          {'curah_hujan': 0, 'suhu': 29.07},
          {'curah_hujan': 0, 'suhu': 29.1},
          {'curah_hujan': 0, 'suhu': 29.7},
          {'curah_hujan': 0, 'suhu': 29.4},
          {'curah_hujan': 0, 'suhu': 29.3},
        ],
        labels: [],
        currentValue: 5.0,
        isFromCache: true,
        errorMessage: 'An unexpected error occurred: ${e.toString()}',
        isDemo: true
      ).toMap();
    }
  }

  Future<double> getStatus(String sensorId) async {
    final now = DateTime.now();

    // Check if the value is in the cache and still valid
    if (_cache.containsKey(sensorId)) {
      final item = _cache[sensorId]!;
      if (now.difference(item.timestamp) < ttl) {
        return item.value;
      }
    }

    double currHeight;

    if (sensorId == 'unknown') {
      currHeight = 0.0;
      debugPrint("Sensor not found for $sensorId");
    } else {
      final dateString = DateFormat('yyyy-MM-dd').format(now);
      final docId = '${sensorId}_$dateString';
      final timeString = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

      debugPrint('Checking $docId at $timeString');

      // ✅ Use lazy Firestore access
      final doc = await FirebaseFirestore.instance
          .collection('sensor_readings')
          .doc(docId)
          .get();

      if (doc.exists) {
        final data = doc.data();
        final timeMap = data?['readings'] as Map<String, dynamic>? ?? {};
        var reading = timeMap[timeString]?['tinggiBanjir'];

        if (reading == null && timeMap.isNotEmpty) {
          final sortedKeys = timeMap.keys.toList()..sort();
          final lastKey = sortedKeys.last;
          reading = timeMap[lastKey]['tinggiBanjir'];
        }

        debugPrint('Reading value: $reading');
        currHeight = (reading as num?)?.toDouble() ?? 0.0;
      } else {
        currHeight = 0.0;
      }
    }

    // Update Cache
    _cache[sensorId] = _CacheItem(value: currHeight, timestamp: now);

    return currHeight;
  }

  
}

class _CacheItem {
  final double value;
  final DateTime timestamp;
  _CacheItem({required this.value, required this.timestamp});
}