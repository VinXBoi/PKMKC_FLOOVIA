// ==================== REPOSITORY ====================
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class WeatherRepository {
  final FirebaseFirestore _firestore;
  
  WeatherRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Safely fetch a Firestore document with offline support
  Future<DocumentSnapshot?> _fetchDocument(
    String collection,
    String docId, {
    bool preferCache = false,
  }) async {
    try {
      final source = preferCache ? Source.cache : Source.serverAndCache;
      
      final doc = await _firestore
          .collection(collection)
          .doc(docId)
          .get(GetOptions(source: source));
      
      if (doc.exists) {
        return doc;
      }
      
      return null;
    } on FirebaseException catch (e) {
      if (e.code == 'unavailable') {
        // Network unavailable - try cache
        try {
          final cachedDoc = await _firestore
              .collection(collection)
              .doc(docId)
              .get(const GetOptions(source: Source.cache));
          
          if (cachedDoc.exists) {
            return cachedDoc;
          }
        } catch (_) {
          // Cache miss
        }
      }
      
      // Log error in production (use your logging service)
      debugPrint('Firestore fetch error [$collection/$docId]: ${e.code} - ${e.message}');
      return null;
    } catch (e) {
      debugPrint('Unexpected error fetching [$collection/$docId]: $e');
      return null;
    }
  }

  /// Fetch weather data for a kecamatan
  Future<Map<String, DocumentSnapshot?>> fetchKecamatanWeather(
    String kecamatanId,
    DateTime date,
  ) async {
    final todayString = DateFormat('yyyy-MM-dd').format(date);
    final yesterdayString = DateFormat('yyyy-MM-dd')
        .format(date.subtract(const Duration(days: 1)));

    final todayDocId = '${kecamatanId}_$todayString';
    final yesterdayDocId = '${kecamatanId}_$yesterdayString';

    final results = await Future.wait([
      _fetchDocument('weather_daily', todayDocId),
      _fetchDocument('weather_daily', yesterdayDocId),
    ]);

    return {
      'today': results[0],
      'yesterday': results[1],
    };
  }

  /// Fetch sensor readings
  Future<Map<String, DocumentSnapshot?>> fetchSensorReadings(
    String sensorId,
    DateTime date,
  ) async {
    final todayString = DateFormat('yyyy-MM-dd').format(date);
    final yesterdayString = DateFormat('yyyy-MM-dd')
        .format(date.subtract(const Duration(days: 1)));

    final todayDocId = '${sensorId}_$todayString';
    final yesterdayDocId = '${sensorId}_$yesterdayString';

    final results = await Future.wait([
      _fetchDocument('sensor_readings', todayDocId),
      _fetchDocument('sensor_readings', yesterdayDocId),
    ]);

    return {
      'today': results[0],
      'yesterday': results[1],
    };
  }
}