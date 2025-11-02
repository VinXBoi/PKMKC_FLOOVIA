// ==================== SERVICE LAYER ====================
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:floovia/models/batch_status_result.dart';
import 'package:floovia/repositories/weather_repositories.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class BatchStatusService {
  final WeatherRepository _repository;

  BatchStatusService({WeatherRepository? repository})
      : _repository = repository ?? WeatherRepository();

  /// Get batch status data with comprehensive error handling
  Future<BatchStatusResult> getBatchStatus(
    String sensorId,
    String kecamatanId,
  ) async {
    final now = DateTime.now();
    
    try {
      // Fetch kecamatan weather data
      final kecamatanData = await _repository.fetchKecamatanWeather(
        kecamatanId,
        now,
      );

      final batchDataXY = _buildKecamatanBatch(
        kecamatanData,
        now,
      );

      // Handle unknown sensor (demo mode)
      if (sensorId == "unknown") {
        return _buildDemoData(now, batchDataXY);
      }

      // Fetch sensor readings
      final sensorData = await _repository.fetchSensorReadings(sensorId, now);

      // Check if data is available
      if (sensorData['today']?.data() == null ||
          sensorData['yesterday']?.data() == null) {
        return _buildFallbackData(now, batchDataXY);
      }

      // Build real data
      return _buildRealData(sensorData, now, batchDataXY);
      
    } catch (e) {
      debugPrint('Error in getBatchStatus: $e');
      return _buildFallbackData(
        now,
        [],
        errorMessage: 'Failed to load data: ${e.toString()}',
      );
    }
  }

  /// Build kecamatan weather batch data
  List<Map<String, dynamic>> _buildKecamatanBatch(
    Map<String, DocumentSnapshot?> kecamatanData,
    DateTime now,
  ) {
    final startKecamatan = now.subtract(const Duration(hours: 4));
    final todayString = DateFormat('yyyy-MM-dd').format(now);
    final batchDataXY = <Map<String, dynamic>>[];

    for (int i = 0; i < 5; i++) {
      final t = startKecamatan.add(Duration(hours: i));
      final dateStr = DateFormat('yyyy-MM-dd').format(t);
      final key = DateFormat('HH:00').format(t);

      Map<String, dynamic>? rawValue;

      if (dateStr == todayString && kecamatanData['today']?.exists == true) {
        rawValue = kecamatanData['today']!.data() as Map<String, dynamic>?;
        rawValue = rawValue?[key];
      } else if (kecamatanData['yesterday']?.exists == true) {
        rawValue = kecamatanData['yesterday']!.data() as Map<String, dynamic>?;
        rawValue = rawValue?[key];
      }

      batchDataXY.add(rawValue ?? _getDefaultWeatherData());
    }

    return batchDataXY;
  }

  /// Build demo/test data
  BatchStatusResult _buildDemoData(
    DateTime now,
    List<Map<String, dynamic>> batchDataXY,
  ) {
    final start = now.subtract(const Duration(hours: 11));
    final batchData = <double>[110.0, 100.0, 90.0, 80.0, 70.0, 60.0, 50.0, 40.0, 30.0, 20.0, 10.0, 5.0];
    final maxValue = 110.0;
    final labels = <String>[];

    for (int i = 0; i < 12; i++) {
      final t = start.add(Duration(hours: i));
      labels.add(DateFormat('HH:00').format(t));
    }
    final currentValue = 5.0;

    return BatchStatusResult(
      maxValue: maxValue,
      batchData: batchData,
      batchDataXY: batchDataXY,
      labels: labels,
      currentValue: currentValue,
      isFromCache: false,
      isDemo : true
    );
  }

  /// Build fallback data when sensor data is unavailable
  BatchStatusResult _buildFallbackData(
    DateTime now,
    List<Map<String, dynamic>> batchDataXY, {
    String? errorMessage,
  }) {
    final start = now.subtract(const Duration(hours: 11));
    final batchData = [110.0, 100.0, 90.0, 80.0, 70.0, 60.0, 50.0, 40.0, 30.0, 20.0, 10.0, 5.0]
        .map((e) => e.toDouble())
        .toList();
    final labels = <String>[];

    for (int i = 0; i < 12; i++) {
      final t = start.add(Duration(hours: i));
      labels.add(DateFormat('HH:00').format(t));
    }

    return BatchStatusResult(
      maxValue: 110,
      batchData: batchData,
      batchDataXY: batchDataXY,
      labels: labels,
      currentValue: 5.0,
      isFromCache: true,
      errorMessage: errorMessage,
      isDemo: true
    );
  }

  /// Build real data from sensor readings
  BatchStatusResult _buildRealData(
    Map<String, DocumentSnapshot?> sensorData,
    DateTime now,
    List<Map<String, dynamic>> batchDataXY,
  ) {
    final start = now.subtract(const Duration(hours: 11));
    final todayString = DateFormat('yyyy-MM-dd').format(start);
    
    final todayRaw = sensorData['today']!.data() as Map<String, dynamic>;
    final yesterdayRaw = sensorData['yesterday']!.data() as Map<String, dynamic>;
    
    final todayData = Map<String, dynamic>.from(todayRaw['readings'] ?? {});
    final yesterdayData = Map<String, dynamic>.from(yesterdayRaw['readings'] ?? {});

    // Get current value
    final waktu = '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}';
    final rawCurrent = todayData[waktu]?['tinggiBanjir'];
    debugPrint('Raw Current Batch Status : $rawCurrent');
    final currentValue = (rawCurrent as num?)?.toDouble() ?? 0.0;
    debugPrint('Curr : $currentValue');

    // Build hourly batch data
    final batchData = <double>[];
    final labels = <String>[];
    double maxValue = -1;

    for (int i = 0; i < 11; i++) {
      final t = start.add(Duration(hours: i));
      final dateStr = DateFormat('yyyy-MM-dd').format(t);
      final key = DateFormat('HH:00').format(t);

      num? rawValue;
      if (dateStr == todayString) {
        rawValue = todayData[key]?['tinggiBanjir'] ?? 0.0;
      } else {
        rawValue = yesterdayData[key]?['tinggiBanjir'] ?? 0.0;
      }

      final value = rawValue?.toDouble() ?? 0.0;
      batchData.add(value);
      labels.add(key);
      maxValue = max(maxValue, value);
    }

    // Add current value
    batchData.add(currentValue);
    labels.add(waktu);
    maxValue = max(maxValue, currentValue);

    return BatchStatusResult(
      maxValue: maxValue,
      batchData: batchData,
      batchDataXY: batchDataXY,
      labels: labels,
      currentValue: currentValue,
      isFromCache: false,
      isDemo: false
    );
  }

  /// Default weather data structure
  Map<String, dynamic> _getDefaultWeatherData() {
    return {
      'temperature': 0.0,
      'humidity': 0.0,
      'rainfall': 0.0,
      'wind_speed': 0.0,
      'weather_condition': 'unknown',
    };
  }
}
