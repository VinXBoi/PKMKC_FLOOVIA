// Pastikan Anda mengimpor package yang menyediakan LatLng
import 'package:google_maps_flutter/google_maps_flutter.dart';

class RouteModel {
  final int id;
  final String name;
  final String distance;
  final String duration;
  final String floodStatus;
  final String floodRisk;
  final String description;
  final List<RouteSegment> segments;
  final String polyline; // Tetap berguna untuk menggambar rute di dalam aplikasi Anda

  // --- PROPERTI TAMBAHAN YANG DIPERLUKAN ---
  final LatLng startLocation;
  final LatLng destinationLocation;
  final List<LatLng> waypoints;

  RouteModel({
    required this.id,
    required this.name,
    required this.distance,
    required this.duration,
    required this.floodStatus,
    required this.floodRisk,
    required this.description,
    required this.segments,
    required this.polyline,
    // --- TAMBAHKAN DI CONSTRUCTOR ---
    required this.startLocation,
    required this.destinationLocation,
    required this.waypoints,
  });
}

// --- CLASS INI SUDAH BENAR, TIDAK PERLU DIUBAH ---
class RouteSegment {
  final String name;
  final String status;
  final String id;
  final String range;
  final int? distanceMeters; 
  RouteSegment({
    required this.name,
    required this.status,
    required this.id,
    required this.range,
    this.distanceMeters,
  });

  @override
  bool operator ==(Object other) {
    return other is RouteSegment && other.name == name;
  }

  @override
  int get hashCode => name.hashCode;
}