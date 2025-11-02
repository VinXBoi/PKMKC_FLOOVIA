import '../providers/flood_data_provider.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:floovia/providers/user_location_provider.dart';
import 'package:floovia/widgets/alternative_route_card.dart';
import 'package:flutter/material.dart';
import '../widgets/alert_banner.dart';
import '../widgets/flood_map_card.dart';
import '../widgets/flood_prediction_card.dart';
import 'package:provider/provider.dart';
import '../widgets/location_search_bar.dart';
import '../providers/map_data_provider.dart';

class HomePage extends StatelessWidget {
  final VoidCallback onNavigateToMap;
  final VoidCallback onNavigateToDetails;
  final VoidCallback onNavigateToRoutes;

  const HomePage({
    super.key,
    required this.onNavigateToMap,
    required this.onNavigateToDetails,
    required this.onNavigateToRoutes,
  });

  @override
  Widget build(BuildContext context) {
    return Selector<UserLocationProvider, bool>(
      selector: (_, provider) => provider.hasError,
      builder: (context, hasLocationError, _) {
        if (hasLocationError) {
          return _buildErrorState(context);
        }
        return _buildContent(context);
      },
    );
  }

  Widget _buildContent(BuildContext context) {
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: () => _handleRefresh(context),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const LocationSearchBar(),
                const SizedBox(height: 16),
                Selector<MapDataProvider, bool>(
                  selector: (_, provider) => provider.hasAlertSegments,
                  builder: (context, hasRedSegments, _) {
                    return AlertBanner(hasRedSegments: hasRedSegments);
                  },
                ),
                const SizedBox(height: 16),
                FloodMapCard(onTap: onNavigateToMap),
                const SizedBox(height: 16),
                FloodPredictionCard(onTap: onNavigateToDetails),
                const SizedBox(height: 16),
                AlternativeRouteCard(onTap: onNavigateToRoutes),
              ],
            ),
          ),
        ),
        _buildLoadingOverlay(context),
      ],
    );
  }

  Widget _buildLoadingOverlay(BuildContext context) {
    return Selector2<MapDataProvider, UserLocationProvider, bool>(
      selector: (_, mapProvider, locationProvider) =>
          mapProvider.isLoading || locationProvider.isLoading,
      builder: (context, isLoading, _) {
        if (!isLoading) return const SizedBox.shrink();

        return Container(
          color: Colors.black.withOpacity(0.3),
          child: Center(
            child: Card(
              elevation: 8,
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      'Memuat data...',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Mohon tunggu sebentar',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey[600],
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildErrorState(BuildContext context) {
    final locationProvider = context.read<UserLocationProvider>();

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red[300],
            ),
            const SizedBox(height: 16),
            Text(
              'Terjadi Kesalahan',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              locationProvider.errorMessage ?? 'Gagal memuat data',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _handleRefresh(context),
              icon: const Icon(Icons.refresh),
              label: const Text('Coba Lagi'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleRefresh(BuildContext context) async {
    final locationProvider = context.read<UserLocationProvider>();
    final mapProvider = context.read<MapDataProvider>();
    // Tambahkan floodProvider
    final floodProvider = context.read<FloodDataProvider>();

    final bool isCurrentlyGps = !locationProvider.isUsingDefaultLocation;

    if (isCurrentlyGps) {
      await locationProvider.refreshGpsLocation();
    }

    final activeLocation = locationProvider.activeLocation;

    const double radiusKm = 1.0;
    final latDelta = radiusKm / 111.0;
    final lngDelta =
        radiusKm / (111.0 * (activeLocation.latitude * 3.14159 / 180).abs());

    final bounds = LatLngBounds(
      southwest: LatLng(
        activeLocation.latitude - latDelta,
        activeLocation.longitude - lngDelta,
      ),
      northeast: LatLng(
        activeLocation.latitude + latDelta,
        activeLocation.longitude + lngDelta,
      ),
    );

    await Future.wait([
      floodProvider.fetchFloodDetails(activeLocation, forceRefresh: true),
      mapProvider.loadSegments(bounds, forceRefresh: true),
    ]);
  }
}
