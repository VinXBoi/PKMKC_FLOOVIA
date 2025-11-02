// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import '../models/route_model.dart';
import '../utils/route_utils.dart';

class RouteResults extends StatelessWidget {
  final List<RouteModel> routes;

  const RouteResults({super.key, required this.routes});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Available Routes',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.blue[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${routes.where((r) => r.floodStatus == 'Aman').length} Safe Routes',
                style: TextStyle(
                  color: Colors.blue[800],
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...routes.map((route) => _buildRouteCard(route)),
        _buildQuickActions(),
      ],
    );
  }

  Widget _buildRouteCard(RouteModel route) {
    Color borderColor = RouteUtils.getStatusColor(route.floodStatus);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: borderColor, width: 4),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildRouteHeader(route),
                const SizedBox(height: 12),
                _buildRouteSegments(route.segments),
                const SizedBox(height: 12),
                _buildNavigationButton(route),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRouteHeader(RouteModel route) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      route.name,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[800],
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: RouteUtils.getStatusColor(route.floodStatus).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: RouteUtils.getStatusColor(route.floodStatus).withOpacity(0.3),
                      ),
                    ),
                    child: Text(
                      '${route.floodRisk} Risk',
                      style: TextStyle(
                        color: RouteUtils.getStatusColor(route.floodStatus),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                route.description,
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.access_time, size: 16, color: Colors.grey[500]),
                  const SizedBox(width: 4),
                  Text(
                    route.duration,
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Icon(Icons.navigation, size: 16, color: Colors.grey[500]),
                  const SizedBox(width: 4),
                  Text(
                    route.distance,
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRouteSegments(List<RouteSegment> segments) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ROUTE SEGMENTS',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.grey[700],
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        Column(
          children: segments.map((segment) => _buildSegmentItem(segment)).toList(),
        ),
      ],
    );
  }

  Widget _buildSegmentItem(RouteSegment segment) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            segment.name,
            style: TextStyle(
              color: Colors.grey[700],
              fontSize: 14,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: RouteUtils.getStatusColor(segment.status).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: RouteUtils.getStatusColor(segment.status).withOpacity(0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  RouteUtils.getStatusIcon(segment.status),
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(width: 4),
                Text(
                  segment.status.toUpperCase(),
                  style: TextStyle(
                    color: RouteUtils.getStatusColor(segment.status),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationButton(RouteModel route) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: route.floodStatus == 'Banjir' ? null : () {},
        icon: const Icon(Icons.navigation),
        label: Text(
          route.floodStatus == 'Banjir' ? 'Route Blocked' : 'Mulai Navigasi',
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: route.floodStatus == 'Aman'
              ? Colors.green[600]
              : route.floodStatus == 'Ringan'
                  ? Colors.orange[600]
                  : Colors.grey[400],
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  Widget _buildQuickActions() {
    return Card(
      color: Colors.blue[50],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Quick Actions',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.blue[800],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.notifications, size: 16),
                    label: const Text('Route Alerts'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blue[600],
                      side: BorderSide(color: Colors.blue[300]!),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.location_on, size: 16),
                    label: const Text('Save Route'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blue[600],
                      side: BorderSide(color: Colors.blue[300]!),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}