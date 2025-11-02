import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:floovia/services/place_services.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

/// Location status enumeration for clear state management
enum LocationStatus {
  initial,
  loading,
  success,
  error,
  permissionDenied,
  serviceDisabled,
}

/// Immutable location data model with value equality
@immutable
class LocationData {
  final LatLng coordinates;
  final String address;
  final DateTime timestamp;
  final bool isGpsLocation;

  const LocationData({
    required this.coordinates,
    required this.address,
    required this.timestamp,
    this.isGpsLocation = false,
  });

  LocationData copyWith({
    LatLng? coordinates,
    String? address,
    DateTime? timestamp,
    bool? isGpsLocation,
  }) {
    return LocationData(
      coordinates: coordinates ?? this.coordinates,
      address: address ?? this.address,
      timestamp: timestamp ?? this.timestamp,
      isGpsLocation: isGpsLocation ?? this.isGpsLocation,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LocationData &&
          runtimeType == other.runtimeType &&
          coordinates.latitude == other.coordinates.latitude &&
          coordinates.longitude == other.coordinates.longitude &&
          address == other.address &&
          isGpsLocation == other.isGpsLocation;

  @override
  int get hashCode =>
      coordinates.latitude.hashCode ^
      coordinates.longitude.hashCode ^
      address.hashCode ^
      isGpsLocation.hashCode;
}

/// High-performance location provider with caching, debouncing, and optimized rebuilds
class UserLocationProvider with ChangeNotifier {
  // ==================== CONSTANTS ====================
  static const LatLng _defaultLocation = LatLng(3.587, 98.691);
  static const String _defaultAddress = "Medan, Sumatera Utara";
  static const Duration _locationTimeout = Duration(seconds: 15);
  static const Duration _cacheExpiration = Duration(minutes: 5);
  static const Duration _debounceDelay = Duration(milliseconds: 300);

  // ==================== PRIVATE STATE ====================
  LocationData _currentLocation = LocationData(
    coordinates: _defaultLocation,
    address: _defaultAddress,
    timestamp: DateTime.now(),
    isGpsLocation: false,
  );

  LocationStatus _status = LocationStatus.initial;
  String? _errorMessage;
  bool _hasInitialized = false;
  bool _isDisposed = false;

  // Performance optimizations
  Timer? _debounceTimer;
  StreamSubscription<Position>? _positionStreamSubscription;
  Completer<void>? _initCompleter;
  LatLng? userLocation;
  String? userAddress;
  final PlaceServices _placeServices = PlaceServices();

  // ==================== PUBLIC GETTERS ====================
  
  /// Current location data (immutable)
  LocationData get currentLocation => _currentLocation;
  
  /// Active coordinates
  LatLng get activeLocation => _currentLocation.coordinates;
  
  /// Active address string
  String get activeAddress => _currentLocation.address;
  
  /// Current status
  LocationStatus get status => _status;
  
  /// Error message if any
  String? get errorMessage => _errorMessage;
  
  /// Loading state
  bool get isLoading => _status == LocationStatus.loading;
  
  /// Initialization state
  bool get hasInitialized => _hasInitialized;
  
  /// Error state
  bool get hasError =>
      _status == LocationStatus.error ||
      _status == LocationStatus.permissionDenied ||
      _status == LocationStatus.serviceDisabled;
  
  /// Check if using default location
  bool get isUsingDefaultLocation => !_currentLocation.isGpsLocation;
  
  /// Check if location is stale
  bool get isLocationStale {
    final age = DateTime.now().difference(_currentLocation.timestamp);
    return age > _cacheExpiration;
  }

  // ==================== CACHE VALIDATION ====================
  
  bool get _isCacheValid {
    return !isLocationStale && _currentLocation.isGpsLocation;
  }

  // ==================== PUBLIC METHODS ====================

  /// Initialize location on app startup (idempotent)
  Future<void> initializeLocation() async {
    // Prevent multiple simultaneous initializations
    if (_initCompleter != null && !_initCompleter!.isCompleted) {
      return _initCompleter!.future;
    }

    if (_hasInitialized) {
      debugPrint('✓ Location already initialized');
      return;
    }

    _initCompleter = Completer<void>();
    debugPrint('→ Initializing location...');

    try {
      await refreshGpsLocation();
      _hasInitialized = true;
      debugPrint('✓ Location initialized successfully');
    } catch (e) {
      debugPrint('✗ Location initialization failed: $e');
      // Still mark as initialized to prevent retry loops
      _hasInitialized = true;
    } finally {
      _initCompleter?.complete();
      _initCompleter = null;
    }
  }

  /// Refresh GPS location with smart caching
  Future<void> refreshGpsLocation() async {
    if (_isDisposed) return;

    // Use cache if still valid
    if (_isCacheValid) {
      debugPrint('✓ Using cached GPS location (age: ${DateTime.now().difference(_currentLocation.timestamp).inSeconds}s)');
      return;
    }

    _setLoadingState();

    try {
      // Check permissions first (fast operation)
      final hasPermission = await _checkAndRequestPermissions();
      if (!hasPermission) {
        _setPermissionDeniedState();
        return;
      }

      // Check service status
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _setServiceDisabledState();
        return;
      }

      // Get position with timeout and fallback
      final position = await _getCurrentPositionWithFallback();
      if (_isDisposed) return;

      final coordinates = LatLng(position.latitude, position.longitude);

      // Fetch address asynchronously (don't block on this)
      _fetchAddressAsync(position.latitude, position.longitude, coordinates);

      debugPrint('✓ GPS Location: ${coordinates.latitude.toStringAsFixed(4)}, ${coordinates.longitude.toStringAsFixed(4)}');
    } on PermissionDeniedException catch (e) {
      _setPermissionDeniedState(e.message);
    } on LocationServiceDisabledException catch (e) {
      _setServiceDisabledState(e.message);
    } on TimeoutException {
      _setErrorState('Waktu habis mencari lokasi. Coba lagi.');
      _fallbackToDefaultLocation();
    } catch (e) {
      _setErrorState('Gagal mendapatkan lokasi: ${e.toString()}');
      _fallbackToDefaultLocation();
    }
  }

  /// Set location from search with debouncing
  Future<void> setActiveLocationFromSearch(String placeId, String address) async {
    if (_isDisposed) return;
    
    if (placeId.isEmpty) {
      debugPrint('✗ Invalid placeId');
      return;
    }

    // Debounce rapid search selections
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDelay, () async {
      await _setLocationFromSearchInternal(placeId, address);
    });
  }

  /// Enable continuous location tracking (battery intensive)
  Future<void> startLocationTracking() async {
    if (_positionStreamSubscription != null) {
      debugPrint('✓ Location tracking already active');
      return;
    }

    try {
      final hasPermission = await _checkAndRequestPermissions();
      if (!hasPermission) return;

      const locationSettings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // Update every 10 meters
      );

      _positionStreamSubscription = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen(
        _handlePositionUpdate,
        onError: _handlePositionError,
      );

      debugPrint('✓ Location tracking started');
    } catch (e) {
      debugPrint('✗ Failed to start location tracking: $e');
    }
  }

  /// Stop continuous location tracking
  void stopLocationTracking() {
    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;
    debugPrint('✓ Location tracking stopped');
  }

  /// Request location permission
  Future<bool> requestPermission() async {
    try {
      final permission = await Geolocator.requestPermission();
      final granted = permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always;

      if (granted) {
        await refreshGpsLocation();
      }
      return granted;
    } catch (e) {
      debugPrint('✗ Permission request failed: $e');
      return false;
    }
  }

  /// Open app settings
  Future<void> openSettings() async {
    try {
      await ph.openAppSettings();
    } catch (e) {
      debugPrint('✗ Failed to open settings: $e');
    }
  }

  /// Reset to default location
  void resetToDefault() {
    if (_isDisposed) return;

    _currentLocation = LocationData(
      coordinates: _defaultLocation,
      address: _defaultAddress,
      timestamp: DateTime.now(),
      isGpsLocation: false,
    );
    _status = LocationStatus.success;
    _errorMessage = null;
    
    _notifyListenersSafely();
    debugPrint('✓ Location reset to default');
  }

  /// Clear error state
  void clearError() {
    if (hasError && !_isDisposed) {
      _errorMessage = null;
      _status = LocationStatus.success;
      _notifyListenersSafely();
    }
  }

  // ==================== PRIVATE METHODS ====================

  Future<void> _setLocationFromSearchInternal(String placeId, String address) async {
    if (_isDisposed) return;

    _setLoadingState();

    try {
      final coordinates = await _placeServices.convertId(placeId);
      if (_isDisposed) return;

      _currentLocation = LocationData(
        coordinates: coordinates,
        address: address,
        timestamp: DateTime.now(),
        isGpsLocation: false,
      );

      _setSuccessState();
      debugPrint('✓ Search location set: ${coordinates.latitude.toStringAsFixed(4)}, ${coordinates.longitude.toStringAsFixed(4)}');
    } catch (e) {
      _setErrorState('Gagal mengatur lokasi: ${e.toString()}');
      debugPrint('✗ Search location error: $e');
    }
  }

  Future<bool> _checkAndRequestPermissions() async {
    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw PermissionDeniedException('Izin lokasi ditolak');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw PermissionDeniedException(
        'Izin lokasi ditolak permanen. Aktifkan di pengaturan.',
      );
    }

    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
  }

  Future<Position> _getCurrentPositionWithFallback() async {
    try {
      // Try high accuracy first
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: _locationTimeout,
        ),
      );
      // .timeout(_locationTimeout)
    } on TimeoutException {
      debugPrint('⚠ High accuracy timeout, trying medium accuracy...');
      // Fallback to medium accuracy
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 10),
        ),
      ).timeout(const Duration(seconds: 10));
    }
  }

  Future<void> _fetchAddressAsync(double lat, double lng, LatLng coordinates) async {
    // Update location immediately with coordinates
    _currentLocation = LocationData(
      coordinates: coordinates,
      address: 'Memuat alamat...',
      timestamp: DateTime.now(),
      isGpsLocation: true,
    );
    _setSuccessState();

    // Fetch address in background
    try {
      final address = await _placeServices.getAddressFromLatLng(lat, lng);
      if (_isDisposed) return;
      if(userLocation == null) {
        userLocation = LatLng(lat, lng);
        userAddress = address;
      }
      // Only update if location hasn't changed
      if (_currentLocation.coordinates == coordinates) {
        _currentLocation = _currentLocation.copyWith(address: address);
        _notifyListenersSafely();
        debugPrint('✓ Address resolved: $address');
      }
    } catch (e) {
      debugPrint('⚠ Address fetch failed: $e');
      // Use coordinate fallback
      final fallbackAddress = 'Lat: ${lat.toStringAsFixed(4)}, Lng: ${lng.toStringAsFixed(4)}';
      if (_isDisposed) return;
      
      if (_currentLocation.coordinates == coordinates) {
        _currentLocation = _currentLocation.copyWith(address: fallbackAddress);
        _notifyListenersSafely();
      }
    }
  }

  void _handlePositionUpdate(Position position) {
    if (_isDisposed) return;

    final coordinates = LatLng(position.latitude, position.longitude);
    
    // Only update if position changed significantly (>10 meters)
    final distance = Geolocator.distanceBetween(
      _currentLocation.coordinates.latitude,
      _currentLocation.coordinates.longitude,
      position.latitude,
      position.longitude,
    );

    if (distance > 10) {
      _fetchAddressAsync(position.latitude, position.longitude, coordinates);
      debugPrint('✓ Position updated (moved ${distance.toStringAsFixed(0)}m)');
    }
  }

  void _handlePositionError(dynamic error) {
    debugPrint('✗ Position stream error: $error');
    stopLocationTracking();
  }

  void _fallbackToDefaultLocation() {
    _currentLocation = LocationData(
      coordinates: _defaultLocation,
      address: _defaultAddress,
      timestamp: DateTime.now(),
      isGpsLocation: false,
    );
    debugPrint('⚠ Using default location');
  }

  // ==================== STATE MANAGEMENT ====================

  void _setLoadingState() {
    if (_isDisposed) return;
    _status = LocationStatus.loading;
    _errorMessage = null;
    _notifyListenersSafely();
  }

  void _setSuccessState() {
    if (_isDisposed) return;
    _status = LocationStatus.success;
    _errorMessage = null;
    _notifyListenersSafely();
  }

  void _setErrorState(String message) {
    if (_isDisposed) return;
    _status = LocationStatus.error;
    _errorMessage = message;
    _notifyListenersSafely();
  }

  void _setPermissionDeniedState([String? customMessage]) {
    if (_isDisposed) return;
    _status = LocationStatus.permissionDenied;
    _errorMessage = customMessage ?? 'Izin lokasi diperlukan untuk menggunakan fitur ini';
    _notifyListenersSafely();
  }

  void _setServiceDisabledState([String? customMessage]) {
    if (_isDisposed) return;
    _status = LocationStatus.serviceDisabled;
    _errorMessage = customMessage ?? 'Layanan lokasi tidak aktif. Aktifkan GPS di pengaturan.';
    _notifyListenersSafely();
  }

  void _notifyListenersSafely() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  // ==================== LIFECYCLE ====================

  @override
  void dispose() {
    _isDisposed = true;
    _debounceTimer?.cancel();
    _positionStreamSubscription?.cancel();
    _initCompleter?.complete();
    debugPrint('✓ UserLocationProvider disposed');
    super.dispose();
  }
}

// ==================== CUSTOM EXCEPTIONS ====================

class PermissionDeniedException implements Exception {
  final String message;
  const PermissionDeniedException(this.message);

  @override
  String toString() => message;
}

class LocationServiceDisabledException implements Exception {
  final String message;
  const LocationServiceDisabledException(this.message);

  @override
  String toString() => message;
}