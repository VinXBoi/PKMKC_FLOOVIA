// lib/widgets/location_search_bar.dart
// FIXED VERSION - Updates search bar after processing

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import '../providers/user_location_provider.dart';
import '../providers/flood_data_provider.dart';
import '../providers/map_data_provider.dart';
import '../services/place_services.dart';

class LocationSearchBar extends StatefulWidget {
  const LocationSearchBar({super.key});

  @override
  State<LocationSearchBar> createState() => _LocationSearchBarState();
}

class _LocationSearchBarState extends State<LocationSearchBar> {
  final TextEditingController _searchController = TextEditingController();
  final PlaceServices _placeServices = PlaceServices();
  final FocusNode _focusNode = FocusNode();
  
  Timer? _debounce;
  List<dynamic> _placePredictions = [];
  String _lastKnownAddress = '';
  bool _isProcessing = false;
  bool _isFetchingSuggestions = false;

  @override
  void initState() {
    super.initState();
    // Initialize with current location
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final provider = context.read<UserLocationProvider>();
        _searchController.text = provider.activeAddress;
        _lastKnownAddress = provider.activeAddress;
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    
    // Sync with provider changes (only when not processing)
    final provider = context.watch<UserLocationProvider>();
    if (provider.activeAddress != _lastKnownAddress && !_isProcessing) {
      _updateSearchBarText(provider.activeAddress);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _updateSearchBarText(String address) {
    _searchController.text = address;
    _lastKnownAddress = address;
    _searchController.selection = TextSelection.fromPosition(
      TextPosition(offset: _searchController.text.length),
    );
  }

  void _onTextChanged(String value) {
    _debounce?.cancel();
    
    if (value.length <= 2) {
      if (mounted) {
        setState(() {
          _placePredictions = [];
          _isFetchingSuggestions = false;
        });
      }
      return;
    }

    setState(() => _isFetchingSuggestions = true);

    _debounce = Timer(const Duration(milliseconds: 500), () {
      _getPlaceSuggestions(value);
    });
  }

  Future<void> _getPlaceSuggestions(String input) async {
    try {
      final suggestions = await _placeServices.getPlaceSuggestions(input);
      if (mounted) {
        setState(() {
          _placePredictions = suggestions;
          _isFetchingSuggestions = false;
        });
      }
    } catch (e) {
      debugPrint("❌ Error fetching place suggestions: $e");
      if (mounted) {
        setState(() {
          _placePredictions = [];
          _isFetchingSuggestions = false;
        });
      }
    }
  }

  Future<void> _onSuggestionTapped(Map<String, dynamic> prediction) async {
    if (_isProcessing) {
      debugPrint('⚠️ Already processing, ignoring tap');
      return;
    }

    // Immediate UI feedback
    setState(() {
      _isProcessing = true;
      _placePredictions = [];
    });
    _focusNode.unfocus();

    final placeId = prediction['place_id'];
    final address = prediction['structured_formatting']?['main_text'] ?? '';

    // Validate data
    if (placeId == null || placeId.isEmpty) {
      debugPrint('❌ Invalid placeId');
      setState(() => _isProcessing = false);
      _showErrorSnackBar('Data lokasi tidak valid');
      return;
    }

    // Show loading
    _showLoadingSnackBar('Memuat data untuk $address...');

    try {
      // 1. Update location provider
      final locationProvider = context.read<UserLocationProvider>();
      await locationProvider.setActiveLocationFromSearch(placeId, address);
      
      // Get new coordinates
      final newLocation = locationProvider.activeLocation;
      
      // 2. Update providers in parallel
      final floodProvider = context.read<FloodDataProvider>();
      final mapProvider = context.read<MapDataProvider>();
      
      // Clear map cache
      mapProvider.clearCache();
      
      // Calculate bounds
      const double radiusKm = 1.0;
      final latDelta = radiusKm / 111.0;
      final lngDelta = radiusKm / (111.0 * (newLocation.latitude * 3.14159 / 180).abs());
      
      final bounds = LatLngBounds(
        southwest: LatLng(
          newLocation.latitude - latDelta,
          newLocation.longitude - lngDelta,
        ),
        northeast: LatLng(
          newLocation.latitude + latDelta,
          newLocation.longitude + lngDelta,
        ),
      );

      // Fetch data in parallel with timeout
      await Future.wait([
        floodProvider.fetchFloodDetails(newLocation, forceRefresh: true),
        mapProvider.loadSegments(bounds, forceRefresh: true),
      ]).timeout(const Duration(seconds: 60));

      debugPrint('✅ All providers updated for: $address');
      
      if (mounted) {
        // 🆕 UPDATE: Sync search bar with provider AFTER processing
        _updateSearchBarText(locationProvider.activeAddress);
        _showSuccessSnackBar('Data berhasil dimuat untuk $address');
      }

    } on TimeoutException catch (e) {
      debugPrint('⏱️ Timeout: $e');
      if (mounted) {
        _showErrorSnackBar('⏱️ Waktu habis, silakan coba lagi');
      }
      
    } catch (e) {
      debugPrint('❌ Error updating providers: $e');
      if (mounted) {
        _showErrorSnackBar('⚠️ Gagal memuat data: ${e.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _onGpsButtonPressed() async {
    if (_isProcessing) {
      debugPrint('⚠️ Already processing, ignoring GPS tap');
      return;
    }

    setState(() => _isProcessing = true);
    _focusNode.unfocus();

    _showLoadingSnackBar('Mencari lokasi Anda...');

    try {
      // 1. Refresh GPS location
      final locationProvider = context.read<UserLocationProvider>();
      await locationProvider.refreshGpsLocation();
      
      final gpsLocation = locationProvider.activeLocation;
      
      // 2. Update providers
      final floodProvider = context.read<FloodDataProvider>();
      final mapProvider = context.read<MapDataProvider>();
      
      mapProvider.clearCache();

      // Calculate bounds
      const double radiusKm = 1.0;
      final latDelta = radiusKm / 111.0;
      final lngDelta = radiusKm / (111.0 * (gpsLocation.latitude * 3.14159 / 180).abs());
      
      final bounds = LatLngBounds(
        southwest: LatLng(
          gpsLocation.latitude - latDelta,
          gpsLocation.longitude - lngDelta,
        ),
        northeast: LatLng(
          gpsLocation.latitude + latDelta,
          gpsLocation.longitude + lngDelta,
        ),
      );

      // Fetch data with timeout
      await Future.wait([
        floodProvider.fetchFloodDetails(gpsLocation, forceRefresh: true),
        mapProvider.loadSegments(bounds, forceRefresh: true),
      ]).timeout(const Duration(seconds: 30));

      debugPrint('✅ GPS location updated successfully');
      
      if (mounted) {
        // 🆕 UPDATE: Sync search bar with provider AFTER processing
        _updateSearchBarText(locationProvider.activeAddress);
        _showSuccessSnackBar('✅ Lokasi GPS berhasil dimuat');
      }

    } on TimeoutException catch (e) {
      debugPrint('⏱️ GPS timeout: $e');
      if (mounted) {
        _showErrorSnackBar('⏱️ Waktu habis mencari GPS');
      }
      
    } catch (e) {
      debugPrint('❌ GPS error: $e');
      if (mounted) {
        _showErrorSnackBar('⚠️ Gagal memuat lokasi GPS: ${e.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  void _showLoadingSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: _searchController,
          focusNode: _focusNode,
          onChanged: _onTextChanged,
          enabled: !_isProcessing,
          decoration: InputDecoration(
            hintText: "Cari lokasi...",
            filled: true,
            fillColor: Colors.white,
            prefixIcon: _isProcessing
                ? const Padding(
                    padding: EdgeInsets.all(14.0),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.my_location, color: Colors.blue),
                    onPressed: _onGpsButtonPressed,
                  ),
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: _isProcessing
                        ? null
                        : () {
                            _searchController.clear();
                            setState(() => _placePredictions = []);
                          },
                  )
                : null,
            contentPadding: const EdgeInsets.symmetric(vertical: 15.0),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.blue, width: 2),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.blue, width: 2),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.blue, width: 2),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey[300]!, width: 2),
            ),
          ),
        ),
        if (_isFetchingSuggestions || _placePredictions.isNotEmpty)
          _buildSuggestionList(),
      ],
    );
  }

  Widget _buildSuggestionList() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: _isFetchingSuggestions
          ? const Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _placePredictions.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, indent: 16, endIndent: 16),
              itemBuilder: (context, index) {
                final prediction = _placePredictions[index];
                final mainText =
                    prediction['structured_formatting']?['main_text'] ?? '';
                final secondaryText =
                    prediction['structured_formatting']?['secondary_text'] ?? '';

                return ListTile(
                  enabled: !_isProcessing,
                  leading: Icon(
                    Icons.location_on_outlined,
                    color: _isProcessing ? Colors.grey : Colors.blue[600],
                  ),
                  title: Text(
                    mainText,
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: _isProcessing ? Colors.grey : Colors.black,
                    ),
                  ),
                  subtitle: Text(
                    secondaryText,
                    style: TextStyle(
                      color: _isProcessing ? Colors.grey : Colors.black54,
                      fontSize: 12,
                    ),
                  ),
                  onTap: _isProcessing ? null : () => _onSuggestionTapped(prediction),
                  dense: true,
                );
              },
            ),
    );
  }
}