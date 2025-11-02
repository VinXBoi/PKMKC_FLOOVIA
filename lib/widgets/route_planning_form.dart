// lib/widgets/route_planning_form.dart

import 'package:flutter/material.dart';
import 'dart:async';
import '../services/place_services.dart';

class RoutePlanningForm extends StatefulWidget {
  final String fromLocation;
  final String toLocation;
  final Function(String value, String placeId) onFromLocationChanged;
  final Function(String value, String placeId) onToLocationChanged;
  final VoidCallback? onFindRoutes;
  final bool isLoading;

  const RoutePlanningForm({
    super.key,
    required this.fromLocation,
    required this.toLocation,
    required this.onFromLocationChanged,
    required this.onToLocationChanged,
    required this.onFindRoutes,
    this.isLoading = false,
  });

  @override
  State<RoutePlanningForm> createState() => _RoutePlanningFormState();
}

class _RoutePlanningFormState extends State<RoutePlanningForm> {
  // Controllers
  final TextEditingController _originController = TextEditingController();
  final TextEditingController _destinationController = TextEditingController();

  // Focus nodes for better UX
  final FocusNode _originFocus = FocusNode();
  final FocusNode _destinationFocus = FocusNode();

  // Services
  final PlaceServices _placeServices = PlaceServices();

  // State
  List<dynamic> _placePredictions = [];
  String _activeField = ''; // 'origin' or 'destination'
  bool _isLoadingSuggestions = false;
  String? _suggestionsError;

  // Debounce timer
  Timer? _debounceTimer;
  static const Duration _debounceDelay = Duration(milliseconds: 500);

  @override
  void initState() {
    super.initState();
    _originController.text = widget.fromLocation;
    _destinationController.text = widget.toLocation;
  }

  @override
  void didUpdateWidget(RoutePlanningForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Perbarui controller jika teks dari parent (widget) berubah
    if (widget.fromLocation != oldWidget.fromLocation) {
      _originController.text = widget.fromLocation;
    }
    if (widget.toLocation != oldWidget.toLocation) {
      _destinationController.text = widget.toLocation;
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _originController.dispose();
    _destinationController.dispose();
    _originFocus.dispose();
    _destinationFocus.dispose();
    super.dispose();
  }

  /// Handle text field changes with debouncing
  void _onTextChanged(String value, String fieldType) {
    setState(() {
      _activeField = fieldType;
      _suggestionsError = null;
    });

    // Cancel previous timer
    _debounceTimer?.cancel();

    if (value.isEmpty) {
      setState(() {
        _placePredictions.clear();
        _isLoadingSuggestions = false;
      });
      return;
    }

    // Start loading state immediately for better UX
    setState(() {
      _isLoadingSuggestions = true;
    });

    // Debounce the API call
    _debounceTimer = Timer(_debounceDelay, () {
      if (mounted) {
        _fetchPlaceSuggestions(value);
      }
    });
  }

  /// Fetch place suggestions from API
  Future<void> _fetchPlaceSuggestions(String input) async {
    if (input.isEmpty) {
      setState(() {
        _placePredictions.clear();
        _isLoadingSuggestions = false;
      });
      return;
    }

    try {
      final suggestions = await _placeServices
          .getPlaceSuggestions(input)
          .timeout(const Duration(seconds: 60));

      if (mounted) {
        setState(() {
          _placePredictions = suggestions;
          _isLoadingSuggestions = false;
          _suggestionsError = null;
        });
      }

      debugPrint('✅ Loaded ${suggestions.length} place suggestions');
    } on TimeoutException catch (e) {
      if (mounted) {
        setState(() {
          _placePredictions.clear();
          _isLoadingSuggestions = false;
          _suggestionsError = 'Timeout mencari lokasi';
        });
      }
      debugPrint('⏱️ Timeout fetching suggestions: $e');
    } catch (e) {
      if (mounted) {
        setState(() {
          _placePredictions.clear();
          _isLoadingSuggestions = false;
          _suggestionsError = 'Gagal mencari lokasi';
        });
      }
      debugPrint('❌ Error fetching suggestions: $e');
    }
  }

  /// Handle place selection
  void _onPlaceSelected(Map<String, dynamic> place) {
    final mainText = place['structured_formatting']?['main_text'] ?? '';
    final placeId = place['place_id'] ?? '';

    setState(() {
      _placePredictions.clear();
      _isLoadingSuggestions = false;
      _suggestionsError = null;

      if (_activeField == 'origin') {
        _originController.text = mainText;
        widget.onFromLocationChanged(mainText, placeId);
        // Move focus to destination
        _destinationFocus.requestFocus();
      } else {
        _destinationController.text = mainText;
        widget.onToLocationChanged(mainText, placeId);
        // Dismiss keyboard
        FocusScope.of(context).unfocus();
      }
    });

    debugPrint('📍 Selected place: $mainText');
  }

  /// Clear origin field
  void _clearOrigin() {
    _originController.clear();
    _placePredictions.clear();
    widget.onFromLocationChanged('', '');
    setState(() {});
  }

  /// Clear destination field
  void _clearDestination() {
    _destinationController.clear();
    _placePredictions.clear();
    widget.onToLocationChanged('', '');
    setState(() {});
  }

  /// Swap origin and destination
  void _swapLocations() {
    final tempText = _originController.text;
    _originController.text = _destinationController.text;
    _destinationController.text = tempText;

    // Trigger callbacks to update parent state
    widget.onFromLocationChanged(_originController.text, '');
    widget.onToLocationChanged(_destinationController.text, '');

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final canSearch = widget.fromLocation.isNotEmpty &&
        widget.toLocation.isNotEmpty &&
        !widget.isLoading;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            const SizedBox(height: 20),
            _buildLocationFields(),
            if (_placePredictions.isNotEmpty ||
                _isLoadingSuggestions ||
                _suggestionsError != null)
              _buildSuggestionsPanel(),
            const SizedBox(height: 20),
            _buildSearchButton(canSearch),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.blue[50],
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.route, color: Colors.blue[700], size: 24),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Perencanaan Rute',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Temukan jalur bebas banjir',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLocationFields() {
    return Stack(
      children: [
        Column(
          children: [
            _buildLocationField(
              controller: _originController,
              focusNode: _originFocus,
              label: 'Lokasi Awal',
              hint: 'Pilih titik keberangkatan',
              icon: Icons.trip_origin,
              iconColor: Colors.blue[700]!,
              onChanged: (value) => _onTextChanged(value, 'origin'),
              onClear: _clearOrigin,
            ),
            const SizedBox(height: 16),
            _buildLocationField(
              controller: _destinationController,
              focusNode: _destinationFocus,
              label: 'Tujuan',
              hint: 'Pilih lokasi tujuan',
              icon: Icons.location_on,
              iconColor: Colors.red[600]!,
              onChanged: (value) => _onTextChanged(value, 'destination'),
              onClear: _clearDestination,
            ),
          ],
        ),
        // Swap button positioned between fields
        // Positioned(
        //   right: 8,
        //   top: 56,
        //   child: _buildSwapButton(),
        // ),
      ],
    );
  }

  Widget _buildLocationField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String label,
    required String hint,
    required IconData icon,
    required Color iconColor,
    required Function(String) onChanged,
    required VoidCallback onClear,
  }) {
    final hasText = controller.text.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: Colors.grey[700],
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          focusNode: focusNode,
          onChanged: onChanged,
          style: const TextStyle(fontSize: 15),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey[400]),
            prefixIcon: Icon(icon, color: iconColor, size: 22),
            suffixIcon: hasText
                ? IconButton(
                    icon: Icon(Icons.clear, size: 20, color: Colors.grey[600]),
                    onPressed: onClear,
                  )
                : null,
            filled: true,
            fillColor: Colors.grey[50],
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey[300]!, width: 1.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.blue[400]!, width: 2),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSwapButton() {
    return Material(
      color: Colors.white,
      elevation: 2,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: _swapLocations,
        customBorder: const CircleBorder(),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.grey[300]!, width: 1),
          ),
          child: Icon(
            Icons.swap_vert,
            color: Colors.blue[700],
            size: 20,
          ),
        ),
      ),
    );
  }

  Widget _buildSuggestionsPanel() {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      constraints: const BoxConstraints(maxHeight: 300),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.search, size: 18, color: Colors.grey[600]),
                const SizedBox(width: 8),
                Text(
                  'Hasil Pencarian',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Content
          if (_isLoadingSuggestions)
            _buildLoadingState()
          else if (_suggestionsError != null)
            _buildErrorState()
          else if (_placePredictions.isEmpty)
            _buildEmptyState()
          else
            _buildSuggestionsList(),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Padding(
      padding: EdgeInsets.all(24.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          SizedBox(height: 12),
          Text(
            'Mencari lokasi...',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, color: Colors.red[300], size: 40),
          const SizedBox(height: 12),
          Text(
            _suggestionsError!,
            style: TextStyle(color: Colors.red[700], fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.location_off, color: Colors.grey[400], size: 40),
          const SizedBox(height: 12),
          Text(
            'Tidak ada hasil ditemukan',
            style: TextStyle(color: Colors.grey[600], fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestionsList() {
    return Flexible(
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: _placePredictions.length,
        separatorBuilder: (_, __) => Divider(
          height: 1,
          indent: 56,
          color: Colors.grey[200],
        ),
        itemBuilder: (context, index) {
          final place = _placePredictions[index];
          final mainText = place['structured_formatting']?['main_text'] ?? '';
          final secondaryText =
              place['structured_formatting']?['secondary_text'] ?? '';

          return ListTile(
            dense: true,
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.location_on,
                color: Colors.blue[700],
                size: 20,
              ),
            ),
            title: Text(
              mainText,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: secondaryText.isNotEmpty
                ? Text(
                    secondaryText,
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  )
                : null,
            onTap: () => _onPlaceSelected(place),
          );
        },
      ),
    );
  }

  Widget _buildSearchButton(bool canSearch) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: canSearch ? widget.onFindRoutes : null,
        icon: widget.isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Icon(Icons.search, size: 22),
        label: Text(
          widget.isLoading ? 'Mencari Rute...' : 'Cari Rute Aman',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          backgroundColor: canSearch ? Colors.blue[700] : Colors.grey[400],
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: canSearch ? 3 : 0,
          disabledBackgroundColor: Colors.grey[300],
          disabledForegroundColor: Colors.grey[500],
        ),
      ),
    );
  }
}
