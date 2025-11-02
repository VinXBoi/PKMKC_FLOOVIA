import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import '../providers/user_location_provider.dart';
import '../providers/flood_data_provider.dart';
import '../widgets/water_level_details.dart';
import '../widgets/water_level_chart.dart';
import '../widgets/location_search_bar.dart';
import 'dart:math';

class DetailsPage extends StatefulWidget {
  const DetailsPage({super.key});

  @override
  State<DetailsPage> createState() => _DetailsPageState();
}

class _DetailsPageState extends State<DetailsPage> {
  LatLng? _lastFetchedLocation;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final locationProvider = Provider.of<UserLocationProvider>(context);
    final activeLocation = locationProvider.activeLocation;

    // Hanya fetch data jika lokasi aktif berubah
    if (activeLocation != _lastFetchedLocation) {
      context.read<FloodDataProvider>().fetchFloodDetails(activeLocation);
      _lastFetchedLocation = activeLocation;
    }
  }

  @override
  Widget build(BuildContext context) {
    final floodProvider = context.watch<FloodDataProvider>();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LocationSearchBar(),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('Info Banjir',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                      Expanded(
                        child: Text(''),
                      )
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (floodProvider.isLoadingDetails)
                    const Center(
                        child: Padding(
                            padding: EdgeInsets.all(8.0),
                            child: CircularProgressIndicator(color: Colors.blue,)))
                  else
                    Text('Status : ${floodProvider.floodStatus}',
                        style: const TextStyle(fontSize: 16)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          WaterLevelDetails(
              currentWaterLevel: max(floodProvider.currentWaterLevel ?? 0, 0.0),
              maxWaterLevel: floodProvider.maxWaterLevel ?? 0,
              waterLevelData: floodProvider.waterLevelData,
              floodDataProvider: floodProvider),
          // Flood Prediction Card
          const SizedBox(height: 16),
          WaterLevelChart(waterLevelData: floodProvider.waterLevelData, floodDataProvider: floodProvider,),
        ],
      ),
    );
  }
}