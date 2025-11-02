import 'dart:async';
import 'package:floovia/providers/routes_provider.dart';
import 'package:floovia/providers/user_location_provider.dart';
import 'package:floovia/services/place_services.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import '../widgets/route_planning_form.dart';
import '../widgets/route_results.dart';
import '../widgets/emergency_routes_card.dart';

class RoutesPage extends StatefulWidget {
  const RoutesPage({super.key});

  @override
  State<RoutesPage> createState() => _RoutesPageState();
}

class _RoutesPageState extends State<RoutesPage>
    with AutomaticKeepAliveClientMixin {
  // Form state
  String _fromLocation = '';
  String _toLocation = '';
  LatLng? _origin;
  LatLng? _destination;
  
  // Flag untuk tracking apakah user location sudah digunakan
  bool _hasUsedUserLocation = false;

  // Services
  final _placeServices = PlaceServices();

  // Loading state for place conversion
  bool _isConvertingOrigin = false;
  bool _isConvertingDestination = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // Set lokasi user sebagai origin saat pertama kali load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeUserLocation();
    });
  }

  /// Inisialisasi lokasi user sebagai titik awal
  void _initializeUserLocation() {
    final locationProvider = context.read<UserLocationProvider>();
    
    if (!_hasUsedUserLocation && locationProvider.hasInitialized) {
      setState(() {
        _origin = locationProvider.activeLocation;
        _fromLocation = locationProvider.activeAddress;
        _hasUsedUserLocation = true;
      });
      
      debugPrint('✅ User location set as origin: ${locationProvider.activeAddress}');
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  /// Handle place ID conversion to LatLng
  Future<void> _convertPlaceIdToLatLng(String placeId, String type) async {
    if (placeId.isEmpty) return;

    setState(() {
      if (type == 'origin') {
        _isConvertingOrigin = true;
      } else {
        _isConvertingDestination = true;
      }
    });

    try {
      final location = await _placeServices
          .convertId(placeId)
          .timeout(const Duration(seconds: 10));

      if (mounted) {
        setState(() {
          if (type == 'origin') {
            _origin = location;
            _isConvertingOrigin = false;
          } else {
            _destination = location;
            _isConvertingDestination = false;
          }
        });
        debugPrint('✅ Converted $type to: $location');
      }
    } on TimeoutException catch (e) {
      if (mounted) {
        _showErrorSnackbar('Timeout mengkonversi lokasi');
        setState(() {
          if (type == 'origin') {
            _isConvertingOrigin = false;
          } else {
            _isConvertingDestination = false;
          }
        });
      }
      debugPrint('⏱️ Timeout converting place ID: $e');
    } catch (e) {
      if (mounted) {
        _showErrorSnackbar('Gagal mengkonversi lokasi: ${e.toString()}');
        setState(() {
          if (type == 'origin') {
            _isConvertingOrigin = false;
          } else {
            _isConvertingDestination = false;
          }
        });
      }
      debugPrint('❌ Error converting place ID: $e');
    }
  }

  /// Gunakan lokasi user saat ini sebagai origin
  void _useCurrentLocation() async {
    final locationProvider = context.read<UserLocationProvider>();
    
    // Refresh lokasi jika diperlukan
    if (locationProvider.isLocationStale || !locationProvider.hasInitialized) {
      _showInfoSnackbar('Mengambil lokasi Anda...');
      await locationProvider.refreshGpsLocation();
    }
    
    if (mounted) {
      setState(() {
        _origin = (locationProvider.userLocation == null) ? locationProvider.activeLocation : locationProvider.userLocation;
        _fromLocation = ((locationProvider.userAddress == null) ? locationProvider.activeAddress : locationProvider.userAddress)!;
      });
      
      _showSuccessSnackbar('Lokasi Anda telah diatur sebagai titik awal');
      debugPrint('✅ Current location set: ${locationProvider.activeAddress}');
    }
  }

  /// Handle route search
  Future<void> _handleFindRoutes() async {
    if (_origin == null || _destination == null) {
      _showWarningSnackbar('Pilih lokasi asal dan tujuan terlebih dahulu');
      return;
    }

    // Dismiss keyboard
    FocusScope.of(context).unfocus();

    final routesProvider = context.read<RoutesProvider>();

    try {
      await routesProvider.fetchRoutes(
        origin: _origin!,
        destination: _destination!,
      );

      // Show success or error message
      if (mounted) {
        if (routesProvider.error != null) {
          _showErrorSnackbar(routesProvider.error!);
        } else if (routesProvider.hasRoutes) {
          _showSuccessSnackbar(
            '${routesProvider.routes.length} rute ditemukan '
            '(${routesProvider.safeRoutesCount} aman)',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackbar('Terjadi kesalahan: ${e.toString()}');
      }
    }
  }

  /// Clear all routes
  void _handleClearRoutes() {
    context.read<RoutesProvider>().clearRoutes();
    _showInfoSnackbar('Rute dibersihkan');
  }

  /// Show error snackbar
  void _showErrorSnackbar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red[700],
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Tutup',
          textColor: Colors.white,
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
  }

  /// Show success snackbar
  void _showSuccessSnackbar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.white),
            const SizedBox(width: 8),
            Text(message),
          ],
        ),
        backgroundColor: Colors.green[700],
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Show warning snackbar
  void _showWarningSnackbar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.warning_amber_outlined, color: Colors.white),
            const SizedBox(width: 8),
            Text(message),
          ],
        ),
        backgroundColor: Colors.orange[700],
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Show info snackbar
  void _showInfoSnackbar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.white),
            const SizedBox(width: 8),
            Text(message),
          ],
        ),
        backgroundColor: Colors.blue[700],
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin

    return Consumer2<RoutesProvider, UserLocationProvider>(
      builder: (context, routesProvider, locationProvider, _) {
        final isProcessing = routesProvider.isLoading ||
            _isConvertingOrigin ||
            _isConvertingDestination;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Location Status Card (jika ada error)
              if (locationProvider.hasError)
                _buildLocationErrorCard(locationProvider),

              // Planning Form
              RoutePlanningForm(
                fromLocation: _fromLocation,
                toLocation: _toLocation,
                onFromLocationChanged: (value, placeId) {
                  setState(() => _fromLocation = value);
                  _convertPlaceIdToLatLng(placeId, 'origin');
                },
                onToLocationChanged: (value, placeId) {
                  setState(() => _toLocation = value);
                  _convertPlaceIdToLatLng(placeId, 'destination');
                },
                onFindRoutes: isProcessing ? null : _handleFindRoutes,
                isLoading: isProcessing,
              ),

              const SizedBox(height: 12),

              // Tombol gunakan lokasi saat ini
              _buildUseCurrentLocationButton(locationProvider),

              const SizedBox(height: 16),

              // Loading Indicator
              if (routesProvider.isLoading) _buildLoadingCard(),

              // Error State
              if (routesProvider.error != null && !routesProvider.isLoading)
                _buildErrorCard(routesProvider.error!),

              // Empty State
              if (!routesProvider.hasRoutes &&
                  !routesProvider.isLoading &&
                  routesProvider.error == null &&
                  (_origin != null || _destination != null))
                _buildEmptyState(),

              // Results
              if (routesProvider.hasRoutes) ...[
                _buildResultsHeader(routesProvider),
                const SizedBox(height: 12),
                RouteResults(routes: routesProvider.routes),
                const SizedBox(height: 16),
              ],

              // Emergency Routes
              const EmergencyRoutesCard(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLocationErrorCard(UserLocationProvider provider) {
    return Card(
      color: Colors.orange[50],
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            Icon(Icons.location_off, color: Colors.orange[700]),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Lokasi Tidak Tersedia',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.orange[900],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    provider.errorMessage ?? 'Gagal mendapatkan lokasi',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.orange[800],
                    ),
                  ),
                ],
              ),
            ),
            if (provider.status == LocationStatus.permissionDenied)
              TextButton(
                onPressed: () => provider.openSettings(),
                child: const Text('Buka Settings'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildUseCurrentLocationButton(UserLocationProvider provider) {
    return OutlinedButton.icon(
      onPressed: provider.isLoading ? null : _useCurrentLocation,
      icon: provider.isLoading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.my_location),
      label: Text(
        provider.isLoading
            ? 'Mengambil lokasi...'
            : 'Gunakan Lokasi Saya Sekarang',
      ),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
    );
  }

  Widget _buildLoadingCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Mencari rute terbaik...',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Mohon tunggu, ini mungkin memakan waktu hingga 1 menit',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard(String error) {
    return Card(
      color: Colors.red[50],
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red[700]),
            const SizedBox(height: 12),
            Text(
              'Gagal Mencari Rute',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.red[900],
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              style: TextStyle(color: Colors.red[700]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _handleFindRoutes,
              icon: const Icon(Icons.refresh),
              label: const Text('Coba Lagi'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red[700],
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          children: [
            Icon(Icons.route, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'Belum Ada Rute',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.grey[700],
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Masukkan lokasi asal dan tujuan,\nlalu tekan "Cari Rute"',
              style: TextStyle(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultsHeader(RoutesProvider provider) {
    return Card(
      color: Colors.blue[50],
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green[700]),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${provider.routes.length} Rute Ditemukan',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${provider.safeRoutesCount} rute aman dari banjir',
                    style: TextStyle(
                      color: Colors.grey[700],
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: _handleClearRoutes,
              icon: const Icon(Icons.clear),
              tooltip: 'Hapus Hasil',
              color: Colors.grey[700],
            ),
          ],
        ),
      ),
    );
  }

  
}