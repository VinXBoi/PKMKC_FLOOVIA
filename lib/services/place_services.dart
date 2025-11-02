import 'dart:convert';
import 'package:floovia/config/config.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';

class PlaceServices {
  final String baseUrl = AppConfig.baseUrl;

  Future<dynamic> getPlaceSuggestions(String input) async {
    final url = Uri.parse('$baseUrl/place_suggestions?input=$input&country=ID');
    
    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['status'] == 'OK') {
          // Extract predictions and return the top 3
          return List<dynamic>.from(data['predictions']).take(3).toList();
        } else {
          throw Exception(
              'Error fetching place suggestions: ${data['status']}');
        }
      } else {
        throw Exception(
            'Failed to load place suggestions, Status Code: ${response.statusCode}');
      }
    } catch (e) {
      // Handle any errors
      debugPrint("Error fetching place suggestions: $e");
      throw Exception('Error fetching place suggestions');
    }
  }

  Future<LatLng> convertId(String placeId) async {
    final url = Uri.parse("$baseUrl/convert_id?place_id=$placeId");

    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final lat = data['lat'];
        final lng = data['lng'];

        if (lat != null && lng != null) {
          // Return the location as LatLng
          return LatLng(lat, lng);
        } else {
          throw Exception('Latitude or longitude data is missing');
        }
      } else {
        throw Exception('Failed to fetch place details: ${response.body}');
      }
    } catch (e) {
      debugPrint("Error fetching place details: $e");
      throw Exception('Error fetching place details');
    }
  }

  Future<String> getAddressFromLatLng(double lat, double lng) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(lat, lng);

      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];

        final addressParts = [
          place.street,
          place.subLocality,
          place.locality,
          place.postalCode,
          place.country
        ];
        final String address = addressParts
            .where((part) => part != null && part.isNotEmpty)
            .join(', ');

        // ✅ KUNCI #1: Mengembalikan string alamat jika berhasil
        return address.isNotEmpty ? address : 'Detail alamat tidak tersedia';
      } else {
        // ✅ KUNCI #2: Mengembalikan string pesan jika alamat tidak ditemukan
        return "Alamat tidak ditemukan";
      }
    } catch (e) {
      debugPrint('Error getting address from coordinates: $e');
      // ✅ KUNCI #3: Mengembalikan string pesan jika terjadi error
      return 'Gagal mendapatkan lokasi';
    }
  }
}
