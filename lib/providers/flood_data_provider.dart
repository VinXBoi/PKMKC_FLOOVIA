import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/lstm_prediction_model.dart';
import '../services/geo_service.dart';
import 'road_status_provider.dart';
import '../services/lstm_service.dart';

class FloodDataProvider with ChangeNotifier {
  // === STATE MANAGEMENT ===
  bool _isLoadingDetails = false;
  bool _isLoadingPrediction = false;
  bool _isDemo = false;

  String _floodStatus = "Pilih lokasi...";
  double? _currentWaterLevel;
  double? _maxWaterLevel;
  List<double> _waterLevelData = [];
  List<Map<String, dynamic>> _xyLevelData = [];

  LSTMPredictionResponse? _lstmPrediction;
  String? _detailsError;
  String? _predictionError;

  // === CACHING ===
  String? _lastFetchedLocationKey;
  DateTime? _lastDetailsFetchTime;
  DateTime? _lastPredictionFetchTime;
  String? _inflightLocationKey; // Duplicate request prevention
  
  static const Duration _detailsCacheDuration = Duration(minutes: 1);
  static const Duration _predictionCacheDuration = Duration(minutes: 1);

  // === SERVICES ===
  final _geoService = GeoService();
  final _statusCache = RoadStatusProvider.instance;
  final _lstmService = LSTMService();
  
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  // === GETTERS ===
  bool get isLoadingDetails => _isLoadingDetails;
  bool get isLoadingPrediction => _isLoadingPrediction;
  bool get isLoading => _isLoadingDetails || _isLoadingPrediction;
  bool get isDemo => _isDemo;
  String get floodStatus => _floodStatus;
  double? get currentWaterLevel => _currentWaterLevel;
  double? get maxWaterLevel => _maxWaterLevel;
  List<double> get waterLevelData => List.unmodifiable(_waterLevelData);
  List<Map<String, dynamic>> get xyLevelData => _xyLevelData;
  LSTMPredictionResponse? get lstmPrediction => _lstmPrediction;
  String? get detailsError => _detailsError;
  String? get predictionError => _predictionError;
  bool get hasDetailsData => _currentWaterLevel != null;
  bool get hasPredictionData => _lstmPrediction != null;

  bool _isDisposed = false;

  // === MAIN FETCH METHOD ===
  Future<void> fetchFloodDetails(LatLng location, {bool forceRefresh = false}) async {
    final locationKey = '${location.latitude.toStringAsFixed(6)},${location.longitude.toStringAsFixed(6)}';

    // Prevent duplicate requests
    if (_inflightLocationKey == locationKey) {
      debugPrint('🚫 Already fetching $locationKey');
      return;
    }

    // Check cache
    if (!forceRefresh && _isCacheValid(locationKey)) {
      debugPrint('📦 Using cached data for $locationKey');
      return;
    }

    _startLoading(locationKey);

    try {
      // Step 1: Get segment ID
      final segmentId = await _getSegmentId(locationKey);
      if (segmentId == null) {
        _handleNoSegment();
        return;
      }

      // Step 2: Get sensor ID from Firestore
      final sensorId = await _getSensorId(segmentId);
      
      // Step 3: Handle sensor data
      if (sensorId == null || sensorId == 'unknown') {
        await _loadDemoData(locationKey);
      } else {
        await _loadRealData(sensorId, segmentId, locationKey);
      }

    } on TimeoutException catch (e) {
      _handleError("Timeout: Koneksi terlalu lama", e);
    } on FirebaseException catch (e) {
      _handleError("Error Firebase: ${e.message}", e);
    } catch (e) {
      _handleError("Terjadi kesalahan: ${e.toString()}", e);
    } finally {
      _finishLoading();
    }
  }

  // === HELPER: GET SEGMENT ID ===
  Future<String?> _getSegmentId(String locationKey) async {
    final segMap = await _geoService
        .batchGetSegments({locationKey})
        .timeout(const Duration(seconds: 60));

    final segString = segMap.values.isNotEmpty ? segMap.values.first : "";
    
    if (segString.isEmpty) return null;
    
    final parts = segString.split("::");
    if (parts.length < 2) return null;
    
    return parts[1];
  }

  // === HELPER: GET SENSOR ID ===
  Future<String?> _getSensorId(String segmentId) async {
    final doc = await _firestore
        .collection('segments')
        .doc(segmentId)
        .get()
        .timeout(const Duration(seconds: 120));

    if (!doc.exists) return null;
    
    final docData = doc.data();
    return docData?['sensor_id'];
  }

  // === HELPER: LOAD DEMO DATA ===
  Future<void> _loadDemoData(String locationKey) async {
    debugPrint('📊 Loading demo data for $locationKey');
    
    _isDemo = true;
    _floodStatus = "Data tidak tersedia. Menampilkan data simulasi.";
    _currentWaterLevel = 5.0;
    _maxWaterLevel = 110.0;
    _waterLevelData = [110.0, 100.0, 90.0, 80.0, 70.0, 60.0, 50.0, 40.0, 30.0, 20.0, 10.0, 5.0];
    _xyLevelData = [
      {'curah_hujan': 0, 'suhu': 29.07},
      {'curah_hujan': 0, 'suhu': 29.1},
      {'curah_hujan': 0, 'suhu': 29.7},
      {'curah_hujan': 0, 'suhu': 29.4},
      {'curah_hujan': 0, 'suhu': 29.3},
    ];
    
    _updateCache(locationKey);
    _notifySafely();
    
    // Auto-fetch prediction
    await _fetchPrediction();
  }

  // === HELPER: LOAD REAL DATA ===
  Future<void> _loadRealData(String sensorId, String segmentId, String locationKey) async {
    debugPrint('📡 Loading real data for sensor: $sensorId');
    
    final doc = await _firestore.collection('segments').doc(segmentId).get();
    final kecamatanId = doc.data()?['kecamatan_id'] ?? 'MedanKota';
    
    final floodData = await _statusCache.getBatchStatus(sensorId, kecamatanId);
    
    _isDemo = floodData['isDemo'] ?? false;
    _currentWaterLevel = floodData['current_value'];
    _maxWaterLevel = floodData['max_value'];
    _waterLevelData = List<double>.from(
      floodData['batch_data'] ?? [10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60, 65]
    );
    _xyLevelData = List<Map<String, dynamic>>.from(
      floodData['batch_data_xy'] ?? [
        {'curah_hujan': 0, 'suhu': 29.07},
        {'curah_hujan': 0, 'suhu': 29.1},
        {'curah_hujan': 0, 'suhu': 29.7},
        {'curah_hujan': 0, 'suhu': 29.4},
        {'curah_hujan': 0, 'suhu': 29.3},
      ]
    );
    
    _floodStatus = _isDemo 
        ? 'Data tidak tersedia. Menampilkan data simulasi.'
        : _determineFloodStatus(_currentWaterLevel);
    
    _updateCache(locationKey);
    _notifySafely();
    
    debugPrint('✅ Data loaded: $_floodStatus');
    
    // Auto-fetch prediction
    await _fetchPrediction();
  }

  // === HELPER: FETCH PREDICTION ===
  Future<void> _fetchPrediction() async {
    if (_isDisposed) return;
    
    final data = {
      'batch_data': _waterLevelData,
      'batch_data_xy': _xyLevelData,
    };
    
    unawaited(fetchLSTMPrediction(customData: data));
  }

  // === LSTM PREDICTION ===
  Future<void> fetchLSTMPrediction({
    Map<String, dynamic>? customData,
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _isCacheValid(null, isForPrediction: true)) {
      debugPrint('📦 Using cached LSTM prediction');
      return;
    }

    _isLoadingPrediction = true;
    _predictionError = null;
    _notifySafely();

    try {
      final prediction = await _lstmService.fetchPredictionWithRetry(
        requestData: customData
      );

      if (prediction != null && prediction.success) {
        _lstmPrediction = prediction;
        _predictionError = null;
        _lastPredictionFetchTime = DateTime.now();
      } else {
        _predictionError = "Data prediksi tidak tersedia";
        _lstmPrediction = null;
      }
    } on TimeoutException {
      _predictionError = "Timeout: Gagal memuat prediksi";
    } catch (e) {
      _predictionError = "Error: ${e.toString()}";
    } finally {
      _isLoadingPrediction = false;
      _notifySafely();
    }
  }

  // === STATE MANAGEMENT HELPERS ===
  void _startLoading(String locationKey) {
    _isLoadingDetails = true;
    _detailsError = null;
    _inflightLocationKey = locationKey;
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notifySafely();
    });
  }

  void _finishLoading() {
    _isLoadingDetails = false;
    _inflightLocationKey = null;
    _notifySafely();
  }

  void _handleNoSegment() {
    _floodStatus = "Lokasi tidak terdaftar";
    _currentWaterLevel = null;
    _maxWaterLevel = null;
    _waterLevelData = [];
    _detailsError = "Lokasi tidak terdaftar";
    _finishLoading();
  }

  void _handleError(String message, dynamic error) {
    _floodStatus = message;
    _detailsError = message;
    _currentWaterLevel = null;
    _maxWaterLevel = null;
    _waterLevelData = [];
    debugPrint('❌ Error: $error');
  }

  void _updateCache(String locationKey) {
    _lastFetchedLocationKey = locationKey;
    _lastDetailsFetchTime = DateTime.now();
    _detailsError = null;
  }

  void _notifySafely() {
    if (!_isDisposed) notifyListeners();
  }

  // === CACHE VALIDATION ===
  bool _isCacheValid(String? locationKey, {bool isForPrediction = false}) {
    final lastFetchTime = isForPrediction 
        ? _lastPredictionFetchTime 
        : _lastDetailsFetchTime;
    
    final cacheDuration = isForPrediction 
        ? _predictionCacheDuration 
        : _detailsCacheDuration;

    if (lastFetchTime == null) return false;

    final isExpired = DateTime.now().difference(lastFetchTime) > cacheDuration;
    if (isExpired) return false;

    // Check location change (only for details, not prediction)
    if (!isForPrediction && locationKey != null && _lastFetchedLocationKey != locationKey) {
      return false;
    }

    return true;
  }

  // === FLOOD STATUS DETERMINATION ===
  String _determineFloodStatus(double? waterLevel) {
    if (waterLevel == null) return "Data tidak tersedia";
    if (waterLevel >= 40) return "Banjir Besar";
    if (waterLevel >= 30) return "Banjir Sedang";
    if (waterLevel >= 20) return "Banjir Ringan";
    if (waterLevel >= 10 || waterLevel > 0) return "Siaga";
    return "Aman";
  }

  // === PUBLIC METHODS ===
  Future<void> refreshAll(LatLng location) async {
    _inflightLocationKey = null;
    await Future.wait([
      fetchFloodDetails(location, forceRefresh: true),
      fetchLSTMPrediction(forceRefresh: true),
    ]);
  }

  void clearCache() {
    _lastFetchedLocationKey = null;
    _lastDetailsFetchTime = null;
    _lastPredictionFetchTime = null;
    _inflightLocationKey = null;
    _resetAllData();
    _notifySafely();
  }

  void _resetAllData() {
    _currentWaterLevel = null;
    _maxWaterLevel = null;
    _waterLevelData = [];
    _xyLevelData = [];
    _floodStatus = "Pilih lokasi...";
    _detailsError = null;
    _lstmPrediction = null;
    _predictionError = null;
  }

  @override
  void dispose() {
    _isDisposed = true;
    _inflightLocationKey = null;
    super.dispose();
  }
}

// Helper function for unawaited futures
void unawaited(Future<void> future) {
  future.catchError((error) {
    debugPrint('⚠️ Unawaited future error: $error');
  });
}