import 'dart:convert';
import 'dart:async';
import 'package:floovia/config/config.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../models/lstm_prediction_model.dart';

class LSTMService {
  static const String baseUrl = AppConfig.baseUrl;
  static const Duration _requestTimeout = Duration(seconds: 30);
  
  /// Fetch LSTM prediction from sensor data
  /// Automatically fetches historical data and makes prediction
  Future<LSTMPredictionResponse?> fetchPredictionFromSensor({
    required String sensorId,
    int hoursBack = 24,
    bool useDummyRainfall = true,
  }) async {
    try {
      final url = Uri.parse('$baseUrl/predict/lstm/from-sensor');
      
      debugPrint('🔮 Fetching LSTM prediction for sensor: $sensorId');
      
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'sensor_id': sensorId,
          'hours_back': hoursBack,
          'use_dummy_rainfall': useDummyRainfall,
        }),
      ).timeout(_requestTimeout);

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        final prediction = LSTMPredictionResponse.fromJson(jsonResponse);
        
        if (prediction.success) {
          debugPrint('✅ LSTM Prediction: ${prediction.waktuSurutJam} jam');
          debugPrint('   Estimasi selesai: ${prediction.estimasiWaktuSelesai}');
          debugPrint('   Confidence: ${prediction.confidence}');
        } else {
          debugPrint('⚠️ LSTM Prediction failed: ${prediction.message}');
        }
        
        return prediction;
      } else {
        debugPrint('❌ LSTM API Error: ${response.statusCode}');
        debugPrint('Response: ${response.body}');
        return null;
      }
    } on TimeoutException catch (e) {
      debugPrint('⏱️ LSTM API Timeout: $e');
      return null;
    } catch (e) {
      debugPrint('❌ Error fetching LSTM prediction: $e');
      return null;
    }
  }
  
  /// Fetch LSTM prediction with custom data
  /// [requestData] contains the data points for prediction
  Future<LSTMPredictionResponse?> fetchPrediction({
    Map<String, dynamic>? requestData,
  }) async {
    try {
      final List<dynamic> dataWaterLevel = requestData!['batch_data'];
      final List<dynamic> dataXYLevel = requestData['batch_data_xy'];
      // --- Build combined data ---
      final List<Map<String, dynamic>> dataList = [];

      // Ensure we only map the first 5 items safely
      final int limit = dataXYLevel.length < 5 ? dataXYLevel.length : 5;

      for (int i = 0; i < limit; i++) {
        final suhu = dataXYLevel[i]['suhu'] ?? 0;
        final featureX = dataXYLevel[i]['curah_hujan'] ?? 0;

        // Use corresponding water level or safe default
        final featureY = (i + 7 < dataWaterLevel.length)
            ? dataWaterLevel[i + 7]
            : 0;

        dataList.add({
          'suhu_celsius': suhu,
          'featureX': featureX,
          'featureY': featureY,
        });
      }

      // --- Final request body ---
      final Map<String, dynamic> bodyData = {'data': dataList};
      debugPrint('Body : $bodyData');
      final url = Uri.parse('$baseUrl/predict/lstm');
      
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(bodyData),
      );

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        return LSTMPredictionResponse.fromJson(jsonResponse);
      } else {
        debugPrint('❌ LSTM API Error: ${response.statusCode}');
        debugPrint('Response: ${response.body}');
        return null;
      }
    } on TimeoutException catch (e) {
      debugPrint('⏱️ LSTM API Timeout: $e');
      return null;
    } catch (e) {
      debugPrint('❌ Error fetching LSTM prediction: $e');
      return null;
    }
  }

  /// Fetch prediction with retry mechanism
  Future<LSTMPredictionResponse?> fetchPredictionWithRetry({
    String? sensorId,
    Map<String, dynamic>? requestData,
    int maxRetries = 3,
    int hoursBack = 24,
  }) async {
    for (int i = 0; i < maxRetries; i++) {
      LSTMPredictionResponse? result;
      
      if (sensorId != null) {
        result = await fetchPredictionFromSensor(
          sensorId: sensorId,
          hoursBack: hoursBack,
        );
      } else {
        result = await fetchPrediction(requestData: requestData);
      }
      
      if (result != null && result.success) return result;
      
      // Wait before retry (exponential backoff)
      if (i < maxRetries - 1) {
        final delay = Duration(seconds: (i + 1) * 2);
        debugPrint('🔄 Retry ${i + 1}/$maxRetries in ${delay.inSeconds}s...');
        await Future.delayed(delay);
      }
    }
    
    debugPrint('❌ All retry attempts failed');
    return null;
  }
  
  /// Health check
  Future<bool> checkHealth() async {
    try {
      final url = Uri.parse('$baseUrl/health');
      final response = await http.get(url).timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('⚠️ Health check failed: $e');
      return false;
    }
  }
}