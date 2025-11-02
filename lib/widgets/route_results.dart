// lib/widgets/route_results.dart

import 'package:flutter/material.dart';
import '../models/route_model.dart';
import '../utils/route_utils.dart';
import '../widgets/risk_pill.dart';
import 'package:url_launcher/url_launcher.dart';

class RouteResults extends StatelessWidget {
  final List<RouteModel> routes;

  const RouteResults({super.key, required this.routes});

  @override
  Widget build(BuildContext context) {
    if (routes.isEmpty) {
      return _buildEmptyState(context);
    }

    // Sort routes: Safe routes first
    final sortedRoutes = List<RouteModel>.from(routes)
      ..sort((a, b) {
        final priorityA = _getRoutePriority(a.floodStatus);
        final priorityB = _getRoutePriority(b.floodStatus);
        return priorityA.compareTo(priorityB);
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(context),
        const SizedBox(height: 12),
        ...sortedRoutes.map((route) => _RouteCard(route: route)),
        const SizedBox(height: 8),
        _buildQuickActions(context),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    final safeCount = routes.where((r) => r.floodStatus == 'Aman').length;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Rute Tersedia',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: Colors.grey[800],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: safeCount > 0 ? Colors.green[50] : Colors.orange[50],
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: safeCount > 0 ? Colors.green[200]! : Colors.orange[200]!,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                safeCount > 0 ? Icons.check_circle : Icons.warning_amber,
                size: 16,
                color: safeCount > 0 ? Colors.green[700] : Colors.orange[700],
              ),
              const SizedBox(width: 6),
              Text(
                '$safeCount Rute Aman',
                style: TextStyle(
                  color: safeCount > 0 ? Colors.green[700] : Colors.orange[700],
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    return Card(
      color: Colors.blue[50],
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.flash_on, color: Colors.blue[700], size: 22),
                const SizedBox(width: 8),
                Text(
                  'Aksi Cepat',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue[800],
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildActionButton(
                  icon: Icons.notifications_outlined,
                  label: 'Periksa Peringatan',
                  onPressed: () {
                    // TODO: Implement check warnings
                  },
                ),
                _buildActionButton(
                  icon: Icons.bookmark_outline,
                  label: 'Simpan Rute',
                  onPressed: () {
                    // TODO: Implement save route
                  },
                ),
                _buildActionButton(
                  icon: Icons.share_outlined,
                  label: 'Bagikan',
                  onPressed: () {
                    // TODO: Implement share route
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.blue[700],
        side: BorderSide(color: Colors.blue[300]!),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          children: [
            Icon(Icons.route_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'Tidak Ada Rute',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.grey[700],
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Silakan cari rute untuk melihat hasil',
              style: TextStyle(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  int _getRoutePriority(String status) {
    switch (status) {
      case 'Aman':
        return 0;
      case 'Ringan':
        return 1;
      case 'Banjir':
        return 2;
      default:
        return 3;
    }
  }
}

// Stateful widget for individual route card with expandable segments
class _RouteCard extends StatefulWidget {
  final RouteModel route;

  const _RouteCard({required this.route});

  @override
  State<_RouteCard> createState() => _RouteCardState();
}

class _RouteCardState extends State<_RouteCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final borderColor = RouteUtils.getStatusColor(widget.route.floodStatus);
    final isRecommended = widget.route.floodStatus == 'Aman';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Card(
        elevation: isRecommended ? 4 : 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: borderColor.withOpacity(0.3),
            width: isRecommended ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Recommended badge
            if (isRecommended) _buildRecommendedBadge(),

            // Route content
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildRouteHeader(widget.route),
                  const SizedBox(height: 16),
                  _buildRouteSegments(widget.route.segments),
                  const SizedBox(height: 16),
                  _buildNavigationButton(context, widget.route),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecommendedBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.green[50],
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star, color: Colors.green[700], size: 16),
          const SizedBox(width: 6),
          Text(
            'RUTE DIREKOMENDASIKAN',
            style: TextStyle(
              color: Colors.green[700],
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRouteHeader(RouteModel route) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                route.name,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: Colors.black87,
                ),
              ),
            ),
            RiskPill(
              label: 'Risiko ${route.floodRisk}',
              status: route.floodStatus,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          route.description,
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 12),
        _buildRouteMetrics(route),
      ],
    );
  }

  Widget _buildRouteMetrics(RouteModel route) {
    return Row(
      children: [
        _buildMetricChip(
          icon: Icons.access_time,
          label: route.duration,
          color: Colors.blue,
        ),
        const SizedBox(width: 12),
        _buildMetricChip(
          icon: Icons.straighten,
          label: route.distance,
          color: Colors.purple,
        ),
      ],
    );
  }

  Widget _buildMetricChip({
    required IconData icon,
    required String label,
    required MaterialColor color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color[50],
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color[200]!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color[700]),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color[700],
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRouteSegments(List<RouteSegment> segments) {
    if (segments.isEmpty) {
      return _buildNoSegmentsInfo();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'DETAIL JALUR RUTE',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.grey[700],
                letterSpacing: 0.5,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${segments.length} segmen',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[700],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Show first 5 segments or all if expanded
        ...(_isExpanded ? segments : segments.take(5))
            .map((segment) => _buildSegmentItem(segment)),
        // Show more/less button if there are more than 5 segments
        if (segments.length > 5) _buildToggleButton(segments.length),
      ],
    );
  }

  Widget _buildNoSegmentsInfo() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 20, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Detail segmen tidak tersedia',
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentItem(RouteSegment segment) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          // Segment info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  segment.name.isEmpty ? "Jalan Tidak Dikenal" : segment.name,
                  style: const TextStyle(
                    color: Colors.black87,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _formatSegmentId(segment.id),
                        style: const TextStyle(
                          color: Colors.blue,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.straighten, size: 12, color: Colors.grey[500]),
                    const SizedBox(width: 4),
                    Text(
                      segment.range,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Status badge
          _buildStatusBadge(segment.status),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    final statusColor = RouteUtils.getStatusColor(status);
    final statusIcon = RouteUtils.getStatusIcon(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: statusColor.withOpacity(0.3),
          width: 1.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            statusIcon,
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(width: 4),
          Text(
            status.toUpperCase(),
            style: TextStyle(
              color: statusColor,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleButton(int totalSegments) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: TextButton.icon(
        onPressed: () {
          setState(() {
            _isExpanded = !_isExpanded;
          });
        },
        icon: Icon(
          _isExpanded ? Icons.expand_less : Icons.expand_more,
          size: 18,
        ),
        label: Text(
          _isExpanded
              ? 'Sembunyikan segmen'
              : 'Lihat ${totalSegments - 5} segmen lainnya',
        ),
        style: TextButton.styleFrom(
          foregroundColor: Colors.blue[700],
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
      ),
    );
  }

  // Di dalam class _RouteCardState

  Widget _buildNavigationButton(BuildContext context, RouteModel route) {
    final buttonColor = RouteUtils.getStatusColor(route.floodStatus);

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        // --- LOGIKA BARU DIMULAI DI SINI ---
        onPressed: () async {
          // 1. Ambil data geografis dari objek 'route' yang spesifik ini
          final String origin =
              '${route.startLocation.latitude},${route.startLocation.longitude}';
          final String destination =
              '${route.destinationLocation.latitude},${route.destinationLocation.longitude}';

          // 2. Format waypoints unik milik rute ini, gabungkan dengan karakter '|'
          final String waypointsString = route.waypoints
              .map((point) => '${point.latitude},${point.longitude}')
              .join('|');

          // 3. Buat URL Google Maps dengan mode perjalanan mengemudi (driving)
          // Format URL ini paling kompatibel di berbagai platform
          String url = 'https://www.google.com/maps/dir/?api=1'
              '&origin=$origin'
              '&destination=$destination'
              '&travelmode=driving';

          // Tambahkan waypoints ke URL hanya jika list-nya tidak kosong
          if (waypointsString.isNotEmpty) {
            url += '&waypoints=$waypointsString';
          }

          final Uri googleMapsUrl = Uri.parse(url);

          // 4. Buka URL menggunakan url_launcher
          if (await canLaunchUrl(googleMapsUrl)) {
            await launchUrl(googleMapsUrl);
          } else {
            // Tampilkan pesan error jika Google Maps tidak bisa dibuka
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Tidak dapat membuka aplikasi Google Maps.')),
            );
          }
        },
        // --- AKHIR LOGIKA BARU ---
        icon: const Icon(Icons.navigation, size: 20),
        label: const Text(
          'Mulai Navigasi',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: buttonColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          elevation: 2,
        ),
      ),
    );
  }

  String _formatSegmentId(String id) {
    final raw = id.replaceFirst("seg_", "");
    final parts = raw.split("_");

    if (parts.length == 2 && parts[0].length >= 2 && parts[1].length >= 2) {
      final left = parts[0].substring(0, 2);
      final right = parts[1].substring(0, 2);
      return "ID $left$right";
    }

    return "ID ${raw.substring(0, 4)}";
  }
}
