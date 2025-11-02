import 'package:floovia/providers/flood_data_provider.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Model untuk data point chart
class WaterLevelDataPoint {
  final DateTime timestamp;
  final double level;

  const WaterLevelDataPoint({
    required this.timestamp,
    required this.level,
  });
}

/// Production-ready Water Level Chart Widget
class WaterLevelChart extends StatelessWidget {
  final FloodDataProvider floodDataProvider;
  final List<double> waterLevelData;

  // Optional: custom timestamps, jika null akan di-generate otomatis
  final List<DateTime>? timestamps;

  const WaterLevelChart({
    super.key,
    required this.waterLevelData,
    required this.floodDataProvider,
    this.timestamps,
  });

  /// Generate data points dengan timestamp
  List<WaterLevelDataPoint> get _dataPoints {
    final now = DateTime.now();
    final List<WaterLevelDataPoint> points = [];

    for (int i = 0; i < waterLevelData.length; i++) {
      final timestamp = timestamps != null && i < timestamps!.length
          ? timestamps![i]
          : now.subtract(Duration(hours: waterLevelData.length - 1 - i));

      points.add(WaterLevelDataPoint(
        timestamp: timestamp,
        level: waterLevelData[i],
      ));
    }

    return points;
  }

  /// Check apakah tidak ada data banjir
  bool get _hasNoFloodData {
    return waterLevelData.isEmpty ||
        waterLevelData.every((level) => level == 0.0);
  }

  /// Get max level untuk scaling
  double get _maxLevel {
    if (waterLevelData.isEmpty) return 100.0;
    final max = waterLevelData.reduce((a, b) => a > b ? a : b);
    return max > 100 ? max : 100.0;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 20),
            if (floodDataProvider.isLoading)
              _buildLoadingState()
            else if (_hasNoFloodData)
              _buildNoFloodState()
            else
              _buildChartContent(context),
          ],
        ),
      ),
    );
  }

  /// Header dengan icon dan title
  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.blue[50],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.waves,
            color: Colors.blue[700],
            size: 24,
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Grafik Ketinggian Air',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Monitoring 12 jam terakhir',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
        _buildLegendButton(),
      ],
    );
  }

  /// Tombol legend info
  Widget _buildLegendButton() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.info_outline, size: 16, color: Colors.grey[600]),
          const SizedBox(width: 4),
          Text(
            'Info',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[700],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// Loading state
  Widget _buildLoadingState() {
    return Container(
      height: 220,
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(
            strokeWidth: 3,
          ),
          const SizedBox(height: 16),
          Text(
            'Memuat data...',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  /// No flood state dengan desain lebih baik
  Widget _buildNoFloodState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.green[50]!,
            Colors.green[100]!.withOpacity(0.3),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green[200]!, width: 2),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.green[200]!.withOpacity(0.5),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(
              Icons.check_circle,
              size: 48,
              color: Colors.green[600],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Kondisi Aman',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.green[800],
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tidak ada banjir terdeteksi dalam 12 jam terakhir',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.green[700],
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  /// Main chart content
  Widget _buildChartContent(BuildContext context) {
    final dataPoints = _dataPoints;

    return Column(
      children: [
        // Legend
        _buildLegend(),
        const SizedBox(height: 20),

        // Chart area
        _buildChart(dataPoints),

        const SizedBox(height: 12),

        // Time labels
        _buildTimeLabels(dataPoints),

        const SizedBox(height: 16),

        // Current status
        _buildCurrentStatus(),
      ],
    );
  }

  /// Legend untuk level warna
  Widget _buildLegend() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildLegendItem('Aman', Colors.green[500]!, '0 cm'),
          _buildLegendItem('Ringan', Colors.blue[500]!, ' < 10 cm'),
          _buildLegendItem('Sedang', Colors.yellow[700]!, '10-19 cm'),
          _buildLegendItem('Siaga', Colors.orange[600]!, '20-30 cm'),
          _buildLegendItem('Bahaya', Colors.red[600]!, '≥ 30 cm'),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color, String range) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              range,
              style: TextStyle(
                fontSize: 9,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Chart bars
  Widget _buildChart(List<WaterLevelDataPoint> dataPoints) {
    return Container(
      height: 200,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: Colors.grey[300]!, width: 1.5),
          bottom: BorderSide(color: Colors.grey[300]!, width: 1.5),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: dataPoints.asMap().entries.map((entry) {
          return _buildBar(entry.value, entry.key == dataPoints.length - 1);
        }).toList(),
      ),
    );
  }

  /// Individual bar
  Widget _buildBar(WaterLevelDataPoint dataPoint, bool isLatest) {
    final height = dataPoint.level;
    final displayHeight = (height / _maxLevel) * 180;
    final color = _getBarColor(height);
    final timeFormatter = DateFormat('HH:mm');

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Tooltip(
          message:
              '${timeFormatter.format(dataPoint.timestamp)}\n${height.toStringAsFixed(1)} cm',
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // Bar
              Container(
                height: displayHeight < 4 && height > 0 ? 4 : displayHeight,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(4),
                  ),
                  boxShadow: isLatest
                      ? [
                          BoxShadow(
                            color: color.withOpacity(0.4),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Time labels di bawah chart
  Widget _buildTimeLabels(List<WaterLevelDataPoint> dataPoints) {
    if (dataPoints.isEmpty) return const SizedBox.shrink();

    final now = DateTime.now();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 11 jam yang lalu (first)
          _buildTimeLabel(
            '11 jam lalu',
            false,
          ),

          // 6 jam yang lalu (middle)
          _buildTimeLabel(
            '6 jam lalu',
            false,
          ),

          // Sekarang (current)
          _buildTimeLabel(
            'Sekarang',
            true,
          ),
        ],
      ),
    );
  }

  Widget _buildTimeLabel(String time, bool isCurrent) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isCurrent ? Colors.blue[50] : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: isCurrent ? Border.all(color: Colors.blue[200]!) : null,
          ),
          child: Text(
            time,
            style: TextStyle(
              fontSize: 11,
              color: isCurrent ? Colors.blue[800] : Colors.grey[600],
              fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ),
        if (isCurrent) ...[
          const SizedBox(height: 2),
          Text(
            'Sekarang',
            style: TextStyle(
              fontSize: 9,
              color: Colors.blue[700],
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }

  /// Current status badge
  Widget _buildCurrentStatus() {
    if (waterLevelData.isEmpty) return const SizedBox.shrink();

    final currentLevel = waterLevelData.last;
    final status = _getStatusInfo(currentLevel);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: status.color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: status.color.withOpacity(0.3), width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: status.color,
              shape: BoxShape.circle,
            ),
            child: Icon(
              status.icon,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Status Saat Ini: ${status.label}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: status.color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  status.description,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ),
          ),
          // Text(
          //   '${currentLevel.toStringAsFixed(1)} cm',
          //   style: TextStyle(
          //     fontSize: 20,
          //     fontWeight: FontWeight.bold,
          //     color: status.color,
          //   ),
          // ),
        ],
      ),
    );
  }

  /// Get bar color berdasarkan level
  Color _getBarColor(double height) {
    if (height >= 30) {
      return Colors.red[600]!;
    } else if (height >= 20) {
      return Colors.orange[600]!;
    } else if (height >= 10) {
      return Colors.yellow[700]!;
    } else if (height < 10) {
      return Colors.blue[500]!;
    } else {
      return Colors.green[500]!;
    }
  }

  /// Get status info
  _StatusInfo _getStatusInfo(double level) {
    if (level >= 30) {
      return _StatusInfo(
        label: 'Bahaya',
        description: 'Segera evakuasi ke tempat aman',
        color: Colors.red[600]!,
        icon: Icons.warning,
      );
    } else if (level >= 20) {
      return _StatusInfo(
        label: 'Siaga',
        description: 'Bersiap untuk evakuasi',
        color: Colors.orange[600]!,
        icon: Icons.error_outline,
      );
    } else if (level >= 10) {
      return _StatusInfo(
        label: 'Waspada',
        description: 'Pantau kondisi secara berkala',
        color: Colors.yellow[700]!,
        icon: Icons.info_outline,
      );
    } else if (level < 10) {
      return _StatusInfo(
        label: 'Ringan',
        description: 'Kondisi air dalam keadaan waspada',
        color: Colors.blue[500]!,
        icon: Icons.check_circle_outline,
      );
    } else {
      return _StatusInfo(
          label: 'Aman',
          description: 'Kondisi air dalam keadaan aman',
          color: Colors.green[500]!,
          icon: Icons.check_circle_outline);
    }
  }
}

/// Helper class untuk status info
class _StatusInfo {
  final String label;
  final String description;
  final Color color;
  final IconData icon;

  _StatusInfo({
    required this.label,
    required this.description,
    required this.color,
    required this.icon,
  });
}
